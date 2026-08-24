
//
//  BassAccompanimentEngine.swift
//  Chordyx
//
//  Live bass accompaniment — follows chords or a learned line, synced to drum groove.
//

#if os(macOS) || os(iOS)
import AVFoundation
import AudioToolbox
import Foundation

@MainActor
final class BassAccompanimentEngine {
    private(set) var isPlaying = false
    private(set) var currentBPM: Double = 72
    private(set) var currentStep = 0

    var volume: Float = 0.65 {
        didSet { masterMixer.outputVolume = volume }
    }

    /// Created on first playback — never during SessionViewModel / splash launch.
    private lazy var engine = AVAudioEngine()
    private lazy var masterMixer = AVAudioMixerNode()
    private var samplerUnit: AVAudioUnitSampler?
    private var synthPlayer: AVAudioPlayerNode?
    private var timer: DispatchSourceTimer?
    private var activeSixteenthInterval: Double?

    private var style: BassAccompanimentStyle = .worshipRoot
    private var learnedLine: LearnedBassLine?
    private var currentChordSymbol: String?
    private var beatsPerBar = 4

    private(set) var isGrooveFrozen = false
    private var grooveAnchorTime: CFAbsoluteTime?
    private var lastPlayedAnchorStep = -1
    private var usesSampler = false
    private var noteOffTasks: [Task<Void, Never>] = []
    private var synthBufferCache: [UInt16: AVAudioPCMBuffer] = [:]
    private var prefersStudioSynth = false
    private var reverbUnit: AVAudioUnitReverb?
    /// `mainMixerNode` forces AURemoteIO — defer until first playback (same crash class as drums).
    private var isOutputGraphWired = false
    private var didScheduleInitialBackendLoad = false

    private static let gmSoundBankPath =
        "/System/Library/Components/CoreAudio.component/Contents/Resources/gs_instruments.dls"

    init() {
        // Defer AVAudioEngine attach until first playback — launch must stay light.
    }

    private func ensureOutputGraphWired() {
        guard !isOutputGraphWired else { return }
        isOutputGraphWired = true
        engine.attach(masterMixer)
        masterMixer.outputVolume = volume
        let reverb = AVAudioUnitReverb()
        reverb.loadFactoryPreset(.mediumHall)
        reverb.wetDryMix = 10
        engine.attach(reverb)
        engine.connect(masterMixer, to: reverb, format: nil)
        engine.connect(reverb, to: engine.mainMixerNode, format: nil)
        reverbUnit = reverb
    }

    private func scheduleInitialBackendLoadIfNeeded() {
        guard !didScheduleInitialBackendLoad else { return }
        didScheduleInitialBackendLoad = true
        Task { await loadBackend() }
    }

    func start(
        bpm: Double,
        style: BassAccompanimentStyle,
        chordSymbol: String?,
        learnedLine: LearnedBassLine?,
        beatsPerBar: Int = 4,
        anchorTime: CFAbsoluteTime? = nil
    ) {
        stop(force: true)
        currentBPM = clampBPM(bpm)
        self.style = style
        self.learnedLine = learnedLine
        self.currentChordSymbol = chordSymbol
        self.beatsPerBar = max(1, beatsPerBar)
        currentStep = 0
        lastPlayedAnchorStep = -1

        if let anchorTime {
            grooveAnchorTime = anchorTime
            isGrooveFrozen = true
        } else {
            grooveAnchorTime = CFAbsoluteTimeGetCurrent()
            isGrooveFrozen = true
        }

        configureAudioIfNeeded()
        isPlaying = true
        scheduleStepTimer()
    }

    func stop(force: Bool = false) {
        guard !isGrooveFrozen || force else { return }
        noteOffTasks.forEach { $0.cancel() }
        noteOffTasks.removeAll()
        timer?.cancel()
        timer = nil
        activeSixteenthInterval = nil
        isPlaying = false
        currentStep = 0
        lastPlayedAnchorStep = -1
        isGrooveFrozen = false
        grooveAnchorTime = nil
    }

    func unfreezeGroove() {
        isGrooveFrozen = false
        grooveAnchorTime = nil
        lastPlayedAnchorStep = -1
    }

    func updateChord(_ symbol: String?) {
        guard let symbol, !symbol.isEmpty else { return }
        if currentChordSymbol != symbol {
            synthBufferCache.removeAll()
        }
        currentChordSymbol = symbol
    }

    func setStyle(_ style: BassAccompanimentStyle) {
        self.style = style
    }

    func setLearnedLine(_ line: LearnedBassLine?) {
        learnedLine = line
        if line != nil { style = .learned }
    }

    /// When true, offbeat notes sit a few ms behind the kick grid for a tighter pocket.
    var kickPocketLock = true

    var grooveAnchor: CFAbsoluteTime? { grooveAnchorTime }

    /// Adjust locked bass tempo while preserving musical position on the shared drum grid.
    func retimeLockedGroove(to bpm: Double) {
        guard isPlaying, isGrooveFrozen else { return }
        let clamped = clampBPM(bpm)
        guard abs(clamped - currentBPM) > 0.25 else { return }
        if let anchor = grooveAnchorTime {
            let oldSixteenth = (60.0 / currentBPM) / 4.0
            let newSixteenth = (60.0 / clamped) / 4.0
            if oldSixteenth > 0, newSixteenth > 0 {
                let elapsed = CFAbsoluteTimeGetCurrent() - anchor
                let absoluteStep = elapsed / oldSixteenth
                grooveAnchorTime = CFAbsoluteTimeGetCurrent() - absoluteStep * newSixteenth
            }
        }
        currentBPM = clamped
        scheduleStepTimer()
    }

    private func clampBPM(_ bpm: Double) -> Double {
        min(max(bpm, 48), 200)
    }

    private func configureAudioIfNeeded() {
        ensureOutputGraphWired()
        scheduleInitialBackendLoadIfNeeded()
        #if os(iOS)
        activatePlaybackAudioSession()
        #endif
        if !engine.isRunning {
            engine.prepare()
            try? engine.start()
        }
    }

    #if os(iOS)
    private func activatePlaybackAudioSession() {
        let session = AVAudioSession.sharedInstance()
        let category: AVAudioSession.Category =
            session.category == .playAndRecord ? .playAndRecord : .playback
        try? session.setCategory(
            category,
            mode: .default,
            options: [.mixWithOthers, .defaultToSpeaker, .allowBluetoothHFP, .allowBluetoothA2DP]
        )
        try? session.setActive(true, options: [])
    }
    #endif

    private func loadBackend() async {
        ensureOutputGraphWired()
        didScheduleInitialBackendLoad = true
        if prefersStudioSynth {
            loadStudioSynthBackend()
            return
        }
        guard FileManager.default.fileExists(atPath: Self.gmSoundBankPath) else {
            loadStudioSynthBackend()
            return
        }

        let sampler = AVAudioUnitSampler()
        do {
            try sampler.loadSoundBankInstrument(
                at: URL(fileURLWithPath: Self.gmSoundBankPath),
                program: 34,
                bankMSB: UInt8(kAUSampler_DefaultMelodicBankMSB),
                bankLSB: UInt8(kAUSampler_DefaultBankLSB)
            )
            engine.attach(sampler)
            engine.connect(sampler, to: masterMixer, format: nil)
            samplerUnit = sampler
            usesSampler = true
            if !engine.isRunning { try? engine.start() }
        } catch {
            loadStudioSynthBackend()
        }
    }

    private func loadStudioSynthBackend() {
        let format = engine.outputNode.outputFormat(forBus: 0)
        let player = AVAudioPlayerNode()
        synthPlayer = player
        engine.attach(player)
        engine.connect(player, to: masterMixer, format: format)
        synthBufferCache.removeAll()
        usesSampler = false
        if !engine.isRunning { try? engine.start() }
    }

    private func scheduleStepTimer() {
        guard isPlaying else { return }
        let sixteenth = (60.0 / currentBPM) / 4.0
        if timer != nil,
           let active = activeSixteenthInterval,
           abs(active - sixteenth) < 0.001 {
            return
        }
        activeSixteenthInterval = sixteenth
        timer?.cancel()
        let source = DispatchSource.makeTimerSource(queue: .main)
        source.schedule(deadline: .now(), repeating: sixteenth, leeway: .milliseconds(2))
        source.setEventHandler { [weak self] in
            Task { @MainActor in self?.advanceStep() }
        }
        source.resume()
        timer = source
    }

    private func advanceStep() {
        guard isPlaying else { return }

        let stepToPlay: Int
        if isGrooveFrozen, let anchor = grooveAnchorTime {
            let sixteenth = (60.0 / currentBPM) / 4.0
            guard sixteenth > 0 else { return }
            let elapsed = CFAbsoluteTimeGetCurrent() - anchor
            let absoluteStep = Int(elapsed / sixteenth)
            guard absoluteStep != lastPlayedAnchorStep else { return }
            lastPlayedAnchorStep = absoluteStep
            stepToPlay = absoluteStep % 16
            currentStep = stepToPlay
        } else {
            stepToPlay = currentStep
            currentStep = (currentStep + 1) % 16
        }

        playNotes(for: stepToPlay)
    }

    private func playNotes(for step: Int) {
        let notes = notesForStep(step)
        guard !notes.isEmpty else { return }
        // Kick steps (0 / 8) stay glued; other hits sit slightly behind for pocket.
        let pocketDelayMs: UInt64 = {
            guard kickPocketLock else { return 0 }
            if step == 0 || step == 8 { return 0 }
            if step.isMultiple(of: 4) { return 4 }
            return 8
        }()
        if pocketDelayMs == 0 {
            for note in notes {
                play(midiNote: note.midi, velocity: note.velocity)
            }
            return
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(pocketDelayMs))
            guard let self, self.isPlaying else { return }
            for note in notes {
                self.play(midiNote: note.midi, velocity: note.velocity)
            }
        }
    }

    private struct BassNoteHit {
        let midi: UInt8
        let velocity: UInt8
    }

    private func notesForStep(_ step: Int) -> [BassNoteHit] {
        if style == .learned, let line = learnedLine, !line.isEmpty {
            return line.notes(for: step).map {
                BassNoteHit(
                    midi: UInt8(min(127, max(28, $0.midiNote))),
                    velocity: UInt8(min(127, max(40, $0.velocity)))
                )
            }
        }

        guard let symbol = currentChordSymbol else { return [] }

        switch style {
        case .worshipRoot:
            if step == 0 || step == 8, let root = BassHarmony.bassMidiNote(for: symbol) {
                return [BassNoteHit(midi: root, velocity: 94)]
            }
            if step == 4 || step == 12, let fifth = BassHarmony.fifthMidiNote(for: symbol) {
                return [BassNoteHit(midi: fifth, velocity: 80)]
            }
        case .worshipPocket:
            if step.isMultiple(of: 2), let root = BassHarmony.bassMidiNote(for: symbol) {
                let velocity: UInt8 = [0, 8].contains(step) ? 96 : (step == 4 || step == 12 ? 84 : 76)
                return [BassNoteHit(midi: root, velocity: velocity)]
            }
            if [4, 12].contains(step), let fifth = BassHarmony.fifthMidiNote(for: symbol) {
                return [BassNoteHit(midi: fifth, velocity: 72)]
            }
        case .slowBallad:
            if step == 0, let root = BassHarmony.bassMidiNote(for: symbol) {
                return [BassNoteHit(midi: root, velocity: 84)]
            }
            if step == 8, let fifth = BassHarmony.fifthMidiNote(for: symbol) {
                return [BassNoteHit(midi: fifth, velocity: 66)]
            }
        case .latinTumbao:
            if [0, 8].contains(step), let root = BassHarmony.bassMidiNote(for: symbol) {
                return [BassNoteHit(midi: root, velocity: 98)]
            }
            if [3, 7, 11, 15].contains(step), let fifth = BassHarmony.fifthMidiNote(for: symbol, octave: 3) {
                return [BassNoteHit(midi: fifth, velocity: 86)]
            }
            if step == 14, let root = BassHarmony.bassMidiNote(for: symbol) {
                return [BassNoteHit(midi: root, velocity: 68)]
            }
        case .songoPulse:
            if [0, 8, 13].contains(step), let root = BassHarmony.bassMidiNote(for: symbol) {
                let velocity: UInt8 = [0, 8].contains(step) ? 96 : 78
                return [BassNoteHit(midi: root, velocity: velocity)]
            }
            if [5, 10].contains(step), let fifth = BassHarmony.fifthMidiNote(for: symbol, octave: 3) {
                return [BassNoteHit(midi: fifth, velocity: 86)]
            }
            if step == 11, let root = BassHarmony.bassMidiNote(for: symbol) {
                return [BassNoteHit(midi: root, velocity: 72)]
            }
        case .funkPocket:
            if [0, 8].contains(step), let root = BassHarmony.bassMidiNote(for: symbol) {
                return [BassNoteHit(midi: root, velocity: step == 0 ? 98 : 88)]
            }
            if [3, 11].contains(step), let fifth = BassHarmony.fifthMidiNote(for: symbol) {
                return [BassNoteHit(midi: fifth, velocity: 82)]
            }
            if [5, 13].contains(step), let root = BassHarmony.bassMidiNote(for: symbol) {
                return [BassNoteHit(midi: root, velocity: 74)]
            }
            if [2, 6, 10, 14].contains(step), let fifth = BassHarmony.fifthMidiNote(for: symbol, octave: 3) {
                return [BassNoteHit(midi: fifth, velocity: 58)]
            }
        case .merengueOctave:
            if step.isMultiple(of: 2), let pc = BassHarmony.bassPitchClass(for: symbol) {
                let octaveShift = [4, 12].contains(step) ? 1 : 0
                let midi = 12 + (2 + octaveShift) * 12 + pc
                let velocity: UInt8 = [0, 8].contains(step) ? 98 : 88
                return [BassNoteHit(midi: UInt8(min(127, max(28, midi))), velocity: velocity)]
            }
        case .walkSupport:
            if step.isMultiple(of: 4), let root = BassHarmony.bassMidiNote(for: symbol) {
                let walkOffset: UInt8 = (step / 4) % 2 == 0 ? 0 : 2
                return [BassNoteHit(midi: min(127, root + walkOffset), velocity: 88)]
            }
            if [2, 6, 10, 14].contains(step), let fifth = BassHarmony.fifthMidiNote(for: symbol) {
                return [BassNoteHit(midi: fifth, velocity: 72)]
            }
        case .learned:
            break
        }
        return []
    }

    private func play(midiNote: UInt8, velocity: UInt8) {
        if !engine.isRunning { try? engine.start() }

        if usesSampler, let sampler = samplerUnit {
            sampler.startNote(midiNote, withVelocity: velocity, onChannel: 0)
            let noteDuration = style.noteOffMilliseconds
            let task = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(noteDuration))
                guard let self, self.isPlaying, self.samplerUnit === sampler else { return }
                sampler.stopNote(midiNote, onChannel: 0)
            }
            noteOffTasks.append(task)
            if noteOffTasks.count > 48 {
                noteOffTasks.removeAll { $0.isCancelled }
            }
        } else if let player = synthPlayer {
            let format = engine.outputNode.outputFormat(forBus: 0)
            guard let buffer = synthBuffer(for: midiNote, format: format, velocity: velocity) else { return }
            if !player.isPlaying { player.play() }
            player.scheduleBuffer(buffer, completionHandler: nil)
        }
    }

    private func synthBuffer(for midiNote: UInt8, format: AVAudioFormat, velocity: UInt8) -> AVAudioPCMBuffer? {
        let cacheKey = synthCacheKey(note: midiNote, velocity: velocity)
        if let cached = synthBufferCache[cacheKey] {
            return cached
        }
        guard let rendered = BassSynth.renderElectricBass(
            format: format,
            midiNote: Int(midiNote),
            duration: style == .slowBallad || style == .worshipRoot ? 0.52 : 0.38,
            velocity: velocity
        ) else { return nil }
        synthBufferCache[cacheKey] = rendered
        return rendered
    }

    private func synthCacheKey(note: UInt8, velocity: UInt8) -> UInt16 {
        UInt16(note) << 8 | UInt16(velocity / 12)
    }
}

private enum BassSynth {
    static func renderElectricBass(
        format: AVAudioFormat,
        midiNote: Int,
        duration: Double,
        velocity: UInt8 = 90
    ) -> AVAudioPCMBuffer? {
        let sampleRate = format.sampleRate
        let frameCount = AVAudioFrameCount(duration * sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }
        buffer.frameLength = frameCount
        guard let channel = buffer.floatChannelData?[0] else { return nil }

        let frequency = 440.0 * pow(2.0, (Double(midiNote) - 69.0) / 12.0)
        let velGain = Double(velocity) / 127.0
        let pickGain = 0.58 + velGain * 0.42
        var filterState: Double = 0
        var pickState: Double = 0

        for frame in 0..<Int(frameCount) {
            let t = Double(frame) / sampleRate
            let attack = min(1.0, t * 420.0)
            let decay = exp(-t * (velocity > 80 ? 4.6 : 5.8))
            let env = attack * decay

            let cutoff = frequency * (2.2 + 10.0 * exp(-t * 32.0))
            let alpha = min(0.99, max(0.02, 2 * .pi * cutoff / sampleRate))
            let source = sin(2 * .pi * frequency * t)
                + sin(2 * .pi * frequency * 2.01 * t) * 0.18
                + sin(2 * .pi * frequency * 0.5 * t) * 0.22
                + sin(2 * .pi * frequency * 1.5 * t) * exp(-t * 14) * 0.1
            filterState += alpha * (source - filterState)

            let pickNoise = ((Double(frame * 17 + midiNote * 13) * 0.0001).truncatingRemainder(dividingBy: 1) * 2 - 1)
            pickState = pickState * 0.55 + pickNoise * 0.45
            let pick = pickState * exp(-t * 120) * 0.16 * pickGain

            let sample = (filterState + pick) * env * velGain * 0.72
            channel[frame] = Float(sample / (1 + abs(sample * 0.45)))
        }

        if format.channelCount > 1, let right = buffer.floatChannelData?[1] {
            for frame in 0..<Int(frameCount) {
                right[frame] = channel[frame]
            }
        }
        return buffer
    }

    static func renderNote(format: AVAudioFormat, midiNote: Int, duration: Double) -> AVAudioPCMBuffer? {
        renderElectricBass(format: format, midiNote: midiNote, duration: duration)
    }
}
#endif
