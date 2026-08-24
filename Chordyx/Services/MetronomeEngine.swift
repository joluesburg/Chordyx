//
//  MetronomeEngine.swift
//  Chordyx
//

import AVFoundation
import Combine
import Foundation

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

/// Pure beat-grid math shared by the click engine (and tests).
enum MetronomePhaseMath {
    static func secondsPerBeat(bpm: Double, beatUnit: Int) -> Double {
        (60.0 / max(1, bpm)) * (4.0 / Double(max(1, beatUnit)))
    }

    static func absoluteBeatIndex(elapsed: Double, secondsPerBeat: Double) -> Int {
        guard secondsPerBeat > 0, elapsed >= 0 else { return 0 }
        return Int(floor(elapsed / secondsPerBeat))
    }

    static func beatInBar(absoluteBeat: Int, beatsPerBar: Int) -> Int {
        let bars = max(1, beatsPerBar)
        return ((absoluteBeat % bars) + bars) % bars
    }

    /// True when a drum 16th-grid downbeat (step 0 of a 16-step bar) lines up with a click accent.
    static func drumDownbeatMatchesClickAccent(
        elapsed: Double,
        bpm: Double,
        beatsPerBar: Int = 4,
        beatUnit: Int = 4
    ) -> Bool {
        let spb = secondsPerBeat(bpm: bpm, beatUnit: beatUnit)
        let beat = absoluteBeatIndex(elapsed: elapsed, secondsPerBeat: spb)
        guard beatInBar(absoluteBeat: beat, beatsPerBar: beatsPerBar) == 0 else { return false }
        let sixteenth = spb / 4.0
        guard sixteenth > 0 else { return false }
        let step = Int(floor(elapsed / sixteenth))
        return step % 16 == 0
    }
}

@MainActor
final class MetronomeEngine: ObservableObject {
    @Published private(set) var currentBeat: Int = -1
    @Published private(set) var isRunning = false
    @Published private(set) var isCountingIn = false
    /// Beats left in the count-in (4, 3, 2, 1…), synced for UI.
    @Published private(set) var countInBeatsRemaining: Int = 0

    @Published var volume: Float = 0.8 {
        didSet { clickPlayer.volume = volume }
    }

    /// When false, wall-clock phase / `onBeat` still run but no local click is scheduled
    /// (guest mute, acoustic room mode, etc.).
    @Published var localAudioEnabled: Bool = true

    /// Convenience for mute / silent phase tracking.
    func setLocalAudioEnabled(_ enabled: Bool) {
        localAudioEnabled = enabled
    }

    /// Route metronome to headphones when plugged in instead of forcing the speaker.
    @Published var preferHeadphoneOutput: Bool = false {
        didSet {
            #if os(iOS)
            configureAudioSessionCategory()
            #endif
        }
    }

    var onBeat: ((Int, Bool, Bool) -> Void)?

    /// Created when the click first starts — never during SessionViewModel / splash launch.
    private lazy var engine = AVAudioEngine()
    /// Metronome clicks only — never share this node with the keep-alive loop.
    private lazy var clickPlayer = AVAudioPlayerNode()
    /// Near-silent loop keeps the audio session alive in background without blocking clicks.
    private lazy var keepAlivePlayer = AVAudioPlayerNode()
    private var accentBuffer: AVAudioPCMBuffer?
    private var normalBuffer: AVAudioPCMBuffer?
    private var countInBuffer: AVAudioPCMBuffer?
    private var timer: DispatchSourceTimer?
    private var didConfigureAudio = false
    private var keepAliveActive = false
    private var keepAliveLoopScheduled = false
    private var audioSessionIsActive = false
    /// Last absolute beat index fired from the wall-clock grid (avoids DispatchSource drift).
    private var lastFiredAbsoluteBeat = -1
    #if os(iOS)
    private lazy var audioInterruptionObserver = AudioInterruptionObserver()
    private var didBindInterruption = false
    #endif

    init() {}

    private func bindInterruptionIfNeeded() {
        #if os(iOS)
        guard !didBindInterruption else { return }
        didBindInterruption = true
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
            #if os(iOS)
            if localAudioEnabled {
                activateAudioSession(audible: false)
            }
            #endif
            releaseAudioSessionIfIdle()
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
        releaseAudioSessionIfIdle()
    }

    /// Re-starts audio output after backgrounding or an interruption so the session
    /// keeps running while the phone is locked.
    func reassertBackgroundPlayback() {
        guard keepAliveActive || isRunning else { return }
        guard !engine.isRunning else { return }
        configureAudioIfNeeded()
        activateAudioSession(audible: isRunning && localAudioEnabled)
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
            releaseAudioSessionIfIdle()
        }
    }

    private func releaseAudioSessionIfIdle() {
        #if os(iOS)
        if !isRunning {
            clickPlayer.stop()
            if engine.isRunning {
                engine.stop()
            }
            if audioSessionIsActive {
                try? AVAudioSession.sharedInstance().setActive(
                    false,
                    options: .notifyOthersOnDeactivation
                )
                audioSessionIsActive = false
            }
        }
        #else
        if !isRunning, engine.isRunning {
            clickPlayer.stop()
            engine.stop()
        }
        #endif
    }

    private func startTimer(config: Config) {
        guard config.bpm > 0 else { return }
        configureAudioIfNeeded()
        activateAudioSession(audible: localAudioEnabled)
        ensureEngineRunning()
        isRunning = true
        lastFiredAbsoluteBeat = -1

        let secondsPerBeat = MetronomePhaseMath.secondsPerBeat(bpm: config.bpm, beatUnit: config.beatUnit)
        guard secondsPerBeat > 0 else { return }

        let countingIn = config.isCountingIn && config.countInStartEpoch != nil
        isCountingIn = countingIn
        countInBeatsRemaining = countingIn ? config.countInBars * config.beatsPerBar : 0

        // Seed to the current absolute beat so we only fire on upcoming boundaries
        // (keeps Solo Drums phase lock tight when the click is armed mid-bar).
        let hostNow = Date().timeIntervalSince1970 + config.clockOffset
        let seedAnchor = countingIn ? (config.countInStartEpoch ?? config.startEpoch) : config.startEpoch
        let seedElapsed = max(0, hostNow - seedAnchor)
        lastFiredAbsoluteBeat = MetronomePhaseMath.absoluteBeatIndex(
            elapsed: seedElapsed,
            secondsPerBeat: secondsPerBeat
        )

        // Poll wall-clock like Solo Drums — a repeating beat timer drifts vs the groove grid.
        let source = DispatchSource.makeTimerSource(queue: .main)
        source.schedule(deadline: .now(), repeating: .milliseconds(8), leeway: .milliseconds(2))
        source.setEventHandler { [weak self] in
            guard let self else { return }
            self.tickWallClock(config: config, secondsPerBeat: secondsPerBeat)
        }
        timer = source
        source.resume()
    }

    private func tickWallClock(config: Config, secondsPerBeat: Double) {
        let hostNow = Date().timeIntervalSince1970 + config.clockOffset
        let countingInConfigured = config.isCountingIn && config.countInStartEpoch != nil

        if countingInConfigured, let countStart = config.countInStartEpoch, isCountingIn {
            let countElapsed = hostNow - countStart
            guard countElapsed >= 0 else { return }
            let countBeatIndex = MetronomePhaseMath.absoluteBeatIndex(
                elapsed: countElapsed,
                secondsPerBeat: secondsPerBeat
            )
            let totalCountBeats = config.countInBars * config.beatsPerBar
            if countBeatIndex < totalCountBeats {
                guard countBeatIndex > lastFiredAbsoluteBeat else { return }
                lastFiredAbsoluteBeat = countBeatIndex
                let beatInBar = MetronomePhaseMath.beatInBar(
                    absoluteBeat: countBeatIndex,
                    beatsPerBar: config.beatsPerBar
                )
                countInBeatsRemaining = max(1, totalCountBeats - countBeatIndex)
                clickCountIn(accent: beatInBar == 0)
                currentBeat = beatInBar
                onBeat?(beatInBar, beatInBar == 0, true)
                return
            }
            // Hand off to the groove epoch without dumping a burst of clicks.
            isCountingIn = false
            countInBeatsRemaining = 0
            let grooveElapsed = max(0, hostNow - config.startEpoch)
            lastFiredAbsoluteBeat = MetronomePhaseMath.absoluteBeatIndex(
                elapsed: grooveElapsed,
                secondsPerBeat: secondsPerBeat
            )
            return
        }

        let elapsedNow = hostNow - config.startEpoch
        guard elapsedNow >= 0 else { return }
        let beatIndex = MetronomePhaseMath.absoluteBeatIndex(
            elapsed: elapsedNow,
            secondsPerBeat: secondsPerBeat
        )
        guard beatIndex > lastFiredAbsoluteBeat else { return }
        // Limit catch-up so a long stall doesn't machine-gun clicks.
        let from = max(lastFiredAbsoluteBeat + 1, beatIndex - 1)
        for index in from...beatIndex {
            let beatInBar = MetronomePhaseMath.beatInBar(
                absoluteBeat: index,
                beatsPerBar: config.beatsPerBar
            )
            click(accent: beatInBar == 0)
            currentBeat = beatInBar
            onBeat?(beatInBar, beatInBar == 0, false)
        }
        lastFiredAbsoluteBeat = beatIndex
    }

    private func stopTimer() {
        timer?.cancel()
        timer = nil
        lastFiredAbsoluteBeat = -1
    }

    private func configureAudioIfNeeded() {
        guard !didConfigureAudio else { return }
        didConfigureAudio = true
        bindInterruptionIfNeeded()

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
        activateAudioSession(audible: isRunning && localAudioEnabled)
        guard restartEngineIfNeeded() else { return }
        scheduleKeepAliveLoopIfNeeded()
    }

    #if os(iOS)
    private func configureAudioSessionCategory() {
        let session = AVAudioSession.sharedInstance()
        // Preserve playAndRecord when Solo Audio AI / key assist owns the mic.
        if session.category == .playAndRecord {
            try? session.setCategory(
                .playAndRecord,
                mode: .default,
                options: [.mixWithOthers, .defaultToSpeaker, .allowBluetoothHFP, .allowBluetoothA2DP]
            )
        } else {
            try? session.setCategory(
                .playback,
                mode: .default,
                options: [.mixWithOthers, .allowBluetoothHFP, .allowBluetoothA2DP]
            )
        }
    }

    /// Activates the audio session only when needed. Never forces speaker routing unless
    /// the metronome is audibly playing — preserves USB / headphone audio from a connected keyboard.
    private func activateAudioSession(audible: Bool) {
        configureAudioSessionCategory()
        guard keepAliveActive || isRunning else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(true)
        audioSessionIsActive = true
        if audible {
            if preferHeadphoneOutput {
                try? session.overrideOutputAudioPort(.none)
            } else {
                try? session.overrideOutputAudioPort(.speaker)
            }
        } else {
            try? session.overrideOutputAudioPort(.none)
        }
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
    private func activateAudioSession(audible: Bool = false) {}
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
