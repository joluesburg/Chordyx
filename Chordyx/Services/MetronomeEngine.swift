//
//  MetronomeEngine.swift
//  Chordyx
//

import Foundation
import AVFoundation
import Observation

#if os(iOS)
private struct AudioInterruptionSnapshot: Sendable {
    let typeRawValue: UInt
    let optionsRawValue: UInt?
}

private final class AudioInterruptionObserver {
    private var token: NSObjectProtocol?

    func bind(onInterruption: @escaping @MainActor (AudioInterruptionSnapshot) -> Void) {
        token = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { notification in
            guard let typeValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt else { return }
            let snapshot = AudioInterruptionSnapshot(
                typeRawValue: typeValue,
                optionsRawValue: notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt
            )
            Task { @MainActor in
                onInterruption(snapshot)
            }
        }
    }

    deinit {
        if let token {
            NotificationCenter.default.removeObserver(token)
        }
    }
}
#endif

@Observable
@MainActor
final class MetronomeEngine {
    private(set) var currentBeat: Int = -1
    private(set) var isRunning = false
    private(set) var isCountingIn = false
    /// Beats left in the count-in (4, 3, 2, 1…), synced for UI.
    private(set) var countInBeatsRemaining: Int = 0

    var volume: Float = 0.8 {
        didSet { clickPlayer.volume = volume }
    }

    /// When false, timing still runs but no click is heard (guest local mute).
    var localAudioEnabled: Bool = true

    var onBeat: ((Int, Bool, Bool) -> Void)?

    private let engine = AVAudioEngine()
    /// Metronome clicks only — never share this node with the keep-alive loop.
    private let clickPlayer = AVAudioPlayerNode()
    /// Near-silent loop keeps the audio session alive in background without blocking clicks.
    private let keepAlivePlayer = AVAudioPlayerNode()
    private var accentBuffer: AVAudioPCMBuffer?
    private var normalBuffer: AVAudioPCMBuffer?
    private var countInBuffer: AVAudioPCMBuffer?
    private var timer: DispatchSourceTimer?
    private var didConfigureAudio = false
    private var keepAliveActive = false
    private var keepAliveLoopScheduled = false
    #if os(iOS)
    private let audioInterruptionObserver: AudioInterruptionObserver
    #endif

    init() {
        #if os(iOS)
        audioInterruptionObserver = AudioInterruptionObserver()
        audioInterruptionObserver.bind { [weak self] snapshot in
            self?.handleAudioInterruption(snapshot)
        }
        #endif
    }

    private struct Config: Equatable {
        var bpm: Double
        var beatsPerBar: Int
        var beatUnit: Int
        var isPlaying: Bool
        var startEpoch: Double
        var clockOffset: Double
        var countInBars: Int
        var isCountingIn: Bool
        var countInStartEpoch: Double?
    }
    private var lastConfig: Config?

    func apply(
        bpm: Double,
        beatsPerBar: Int,
        beatUnit: Int,
        isPlaying: Bool,
        startEpoch: Double,
        clockOffset: Double,
        countInBars: Int = 0,
        isCountingIn: Bool = false,
        countInStartEpoch: Double? = nil
    ) {
        let config = Config(
            bpm: bpm,
            beatsPerBar: max(1, beatsPerBar),
            beatUnit: max(1, beatUnit),
            isPlaying: isPlaying,
            startEpoch: startEpoch,
            clockOffset: clockOffset,
            countInBars: max(0, countInBars),
            isCountingIn: isCountingIn,
            countInStartEpoch: countInStartEpoch
        )
        guard config != lastConfig else { return }
        lastConfig = config

        stopTimer()
        if isPlaying {
            startTimer(config: config)
        } else {
            isRunning = false
            self.isCountingIn = false
            currentBeat = -1
        }
    }

    func stop() {
        stopTimer()
        lastConfig = nil
        isRunning = false
        isCountingIn = false
        countInBeatsRemaining = 0
        currentBeat = -1
        setSessionKeepAlive(false)
    }

    /// Re-starts audio output after backgrounding or an interruption so the session
    /// keeps running while the phone is locked.
    func reassertBackgroundPlayback() {
        guard keepAliveActive || isRunning else { return }
        configureAudioIfNeeded()
        activateAudioSession()
        guard restartEngineIfNeeded() else { return }
        if keepAliveActive {
            keepAliveLoopScheduled = false
            scheduleKeepAliveLoopIfNeeded()
        }
    }

    /// Keeps the app eligible to run in the background (lock screen) so guests
    /// continue receiving host chord updates and Live Activity refreshes.
    func setSessionKeepAlive(_ enabled: Bool) {
        guard enabled != keepAliveActive else { return }
        keepAliveActive = enabled
        if enabled {
            configureAudioIfNeeded()
            ensureEngineRunning()
            scheduleKeepAliveLoopIfNeeded()
        } else {
            keepAliveLoopScheduled = false
            keepAlivePlayer.stop()
            #if os(iOS)
            if !isRunning {
                clickPlayer.stop()
                engine.stop()
                try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            }
            #endif
        }
    }

    private func startTimer(config: Config) {
        guard config.bpm > 0 else { return }
        configureAudioIfNeeded()
        ensureEngineRunning()
        isRunning = true

        let secondsPerBeat = (60.0 / config.bpm) * (4.0 / Double(config.beatUnit))
        let hostNow = Date().timeIntervalSince1970 + config.clockOffset

        let countingIn = config.isCountingIn && config.countInStartEpoch != nil
        isCountingIn = countingIn
        countInBeatsRemaining = countingIn ? config.countInBars * config.beatsPerBar : 0

        let anchorEpoch: Double
        if countingIn, let countStart = config.countInStartEpoch {
            anchorEpoch = countStart
        } else {
            anchorEpoch = config.startEpoch
        }

        let elapsed = max(0, hostNow - anchorEpoch)
        let beatsElapsed = floor(elapsed / secondsPerBeat)
        let nextBeatTime = anchorEpoch + (beatsElapsed + 1) * secondsPerBeat
        let initialDelay = max(0, nextBeatTime - hostNow)

        let source = DispatchSource.makeTimerSource(queue: .main)
        source.schedule(deadline: .now() + initialDelay, repeating: secondsPerBeat, leeway: .milliseconds(1))
        source.setEventHandler { [weak self] in
            guard let self else { return }
            let hostNowTick = Date().timeIntervalSince1970 + config.clockOffset

            if countingIn, let countStart = config.countInStartEpoch {
                let countElapsed = hostNowTick - countStart
                let countBeatIndex = Int((countElapsed / secondsPerBeat).rounded())
                let totalCountBeats = config.countInBars * config.beatsPerBar
                if countBeatIndex < totalCountBeats {
                    let beatInBar = ((countBeatIndex % config.beatsPerBar) + config.beatsPerBar) % config.beatsPerBar
                    self.countInBeatsRemaining = max(1, totalCountBeats - countBeatIndex)
                    self.clickCountIn(accent: beatInBar == 0)
                    self.currentBeat = beatInBar
                    self.onBeat?(beatInBar, beatInBar == 0, true)
                    return
                }
                self.isCountingIn = false
                self.countInBeatsRemaining = 0
            }

            let elapsedNow = hostNowTick - config.startEpoch
            guard elapsedNow >= 0 else { return }
            let beatIndex = Int((elapsedNow / secondsPerBeat).rounded())
            let beatInBar = ((beatIndex % config.beatsPerBar) + config.beatsPerBar) % config.beatsPerBar
            self.click(accent: beatInBar == 0)
            self.currentBeat = beatInBar
            self.onBeat?(beatInBar, beatInBar == 0, false)
        }
        timer = source
        source.resume()
    }

    private func stopTimer() {
        timer?.cancel()
        timer = nil
    }

    private func configureAudioIfNeeded() {
        guard !didConfigureAudio else { return }
        didConfigureAudio = true

        #if os(iOS)
        configureAudioSessionCategory()
        #endif

        engine.attach(clickPlayer)
        engine.attach(keepAlivePlayer)
        clickPlayer.volume = volume
        keepAlivePlayer.volume = 1
        let format = engine.outputNode.outputFormat(forBus: 0)
        engine.connect(clickPlayer, to: engine.mainMixerNode, format: format)
        engine.connect(keepAlivePlayer, to: engine.mainMixerNode, format: format)

        accentBuffer = makeClick(frequency: 1568, format: format)
        normalBuffer = makeClick(frequency: 988, format: format)
        countInBuffer = makeClick(frequency: 740, format: format)
    }

    private func makeClick(frequency: Double, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let sampleRate = format.sampleRate
        guard sampleRate > 0 else { return nil }
        let duration = 0.05
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }
        buffer.frameLength = frameCount

        let channels = Int(format.channelCount)
        for frame in 0..<Int(frameCount) {
            let t = Double(frame) / sampleRate
            let envelope = exp(-t * 30)
            let sample = Float(sin(2 * .pi * frequency * t) * envelope * 0.6)
            for ch in 0..<channels {
                buffer.floatChannelData?[ch][frame] = sample
            }
        }
        return buffer
    }

    private func ensureEngineRunning() {
        activateAudioSession()
        guard restartEngineIfNeeded() else { return }
        scheduleKeepAliveLoopIfNeeded()
    }

    #if os(iOS)
    private func configureAudioSessionCategory() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(
            .playback,
            mode: .default,
            options: [.mixWithOthers, .allowBluetoothHFP, .allowBluetoothA2DP]
        )
        try? session.setActive(true)
        try? session.overrideOutputAudioPort(.speaker)
    }

    private func activateAudioSession() {
        configureAudioSessionCategory()
    }

    private func handleAudioInterruption(_ snapshot: AudioInterruptionSnapshot) {
        guard keepAliveActive || isRunning,
              let type = AVAudioSession.InterruptionType(rawValue: snapshot.typeRawValue) else { return }

        switch type {
        case .began:
            break
        case .ended:
            let options = snapshot.optionsRawValue.flatMap { AVAudioSession.InterruptionOptions(rawValue: $0) }
            if options?.contains(.shouldResume) ?? true {
                reassertBackgroundPlayback()
            }
        @unknown default:
            reassertBackgroundPlayback()
        }
    }
    #else
    private func activateAudioSession() {}
    #endif

    private func restartEngineIfNeeded() -> Bool {
        if !engine.isRunning {
            do {
                try engine.start()
            } catch {
                keepAliveLoopScheduled = false
                return false
            }
        }
        guard engine.isRunning else { return false }
        if !clickPlayer.isPlaying {
            clickPlayer.play()
        }
        if keepAliveActive, !keepAlivePlayer.isPlaying {
            keepAlivePlayer.play()
        }
        return true
    }

    private func scheduleKeepAliveLoopIfNeeded() {
        guard keepAliveActive, !keepAliveLoopScheduled else { return }
        guard restartEngineIfNeeded() else { return }
        let format = engine.outputNode.outputFormat(forBus: 0)
        guard let buffer = makeSilentBuffer(format: format) else { return }
        keepAliveLoopScheduled = true
        keepAlivePlayer.scheduleBuffer(buffer, at: nil, options: .loops, completionHandler: nil)
        if !keepAlivePlayer.isPlaying {
            keepAlivePlayer.play()
        }
    }

    private func makeSilentBuffer(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let sampleRate = format.sampleRate
        guard sampleRate > 0 else { return nil }
        let duration = 2.0
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }
        buffer.frameLength = frameCount
        let channels = Int(format.channelCount)
        // Near-silent tone — iOS may suspend a fully zero buffer, but this stays inaudible.
        let frequency = 20.0
        let amplitude: Float = 0.00005
        for frame in 0..<Int(frameCount) {
            let t = Double(frame) / sampleRate
            let sample = Float(sin(2 * .pi * frequency * t)) * amplitude
            for ch in 0..<channels {
                buffer.floatChannelData?[ch][frame] = sample
            }
        }
        return buffer
    }

    private func click(accent: Bool) {
        guard localAudioEnabled, engine.isRunning, clickPlayer.isPlaying,
              let buffer = accent ? accentBuffer : normalBuffer else { return }
        clickPlayer.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
    }

    private func clickCountIn(accent: Bool) {
        guard localAudioEnabled, engine.isRunning, clickPlayer.isPlaying else { return }
        let buffer = accent ? accentBuffer : (countInBuffer ?? normalBuffer)
        guard let buffer else { return }
        clickPlayer.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
    }
}
