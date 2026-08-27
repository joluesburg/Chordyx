//
//  LivePerformanceFusionEngine.swift
//  Chordyx
//
//  Fuses MIDI harmonic analysis with live audio AI (tempo + style).
//

#if os(macOS) || os(iOS)
import Foundation

enum PerformanceAnalysisSource: String, Sendable {
    case fused
    case midi
    case audio
}

@MainActor
final class LivePerformanceFusionEngine {
    private lazy var midiAnalyzer = LivePerformanceAnalyzer()
    private lazy var audioAnalyzer = AudioPerformanceAnalyzer()

    var audioAIEnabled = true
    /// When true, tempo is locked and drums must not react to new chord/MIDI analysis.
    var grooveLocked = false
    var onFusionUpdated: (() -> Void)?

    private lazy var driftMidiAnalyzer = LivePerformanceAnalyzer()
    private(set) var driftEstimatedBPM: Double?
    private(set) var driftTempoConfidence: Double = 0

    init() {}

    func bindAudioCallbacksIfNeeded() {
        guard audioAnalyzer.onAnalysisUpdated == nil else { return }
        audioAnalyzer.onAnalysisUpdated = { [weak self] in
            Task { @MainActor in
                self?.fuse()
            }
        }
    }

    private(set) var estimatedBPM: Double?
    private(set) var tempoConfidence: Double = 0
    private(set) var detectedStyle: LiveMusicStyle = .unknown
    private(set) var styleConfidence: Double = 0
    private(set) var suggestedStyle: LiveMusicStyle?
    private(set) var syncopationIndex: Double = 0
    private(set) var chordChangesPerMinute: Double = 0
    private(set) var isTracking = false
    private(set) var primaryTempoSource: PerformanceAnalysisSource = .midi
    private(set) var primaryStyleSource: PerformanceAnalysisSource = .midi

    private(set) var midiTempoConfidence: Double = 0
    private(set) var audioTempoConfidence: Double = 0
    private(set) var midiStyleConfidence: Double = 0
    private(set) var audioStyleConfidence: Double = 0
    private(set) var audioInputLevel: Float = 0
    private(set) var isAudioListening = false
    private(set) var audioLastError: String?
    private(set) var latinRhythmAnalysis: LatinRhythmAnalysis = .empty
    private(set) var detectedClave: ClaveOrientation = .unknown
    private(set) var montunoStrength: Double = 0
    private(set) var matchedRhythmPatternLabel: String?
    private(set) var globalGenreAnalysis: GlobalGenreAnalysis = .empty
    private(set) var estimatedAudioKey: MusicalKey?
    private(set) var estimatedAudioScale: MusicalScaleQuality = .major
    private(set) var audioKeyConfidence: Double = 0
    private(set) var audioKeyScores: [MusicalKey: Double] = [:]
    private(set) var estimatedAudioRelativeKey: MusicalKey?
    /// True when mic is open specifically to assist Auto-key.
    private var keyAssistRequested = false

    var detectedGlobalGenre: GlobalMusicGenre? { globalGenreAnalysis.primary }
    var detectedGlobalGenreConfidence: Double { globalGenreAnalysis.confidence }

    var availableAudioInputDevices: [AudioInputDevice] {
        audioAnalyzer.availableInputDevices
    }

    func registerMIDIPerformance(
        chordSymbol: String?,
        activeNoteCount: Int,
        newNotesAdded: Bool
    ) {
        bindAudioCallbacksIfNeeded()
        midiAnalyzer.registerPerformance(
            chordSymbol: chordSymbol,
            activeNoteCount: activeNoteCount,
            newNotesAdded: newNotesAdded,
            learnTempo: !grooveLocked
        )
        if grooveLocked {
            if chordSymbol != nil {
                driftMidiAnalyzer.registerPerformance(
                    chordSymbol: chordSymbol,
                    activeNoteCount: activeNoteCount,
                    newNotesAdded: newNotesAdded,
                    learnTempo: true
                )
                updateDriftEstimate()
            }
        }
        fuse()
    }

    func startAudioAI() {
        bindAudioCallbacksIfNeeded()
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.audioAnalyzer.startListening()
            self.isAudioListening = self.audioAnalyzer.isListening
            self.audioLastError = self.audioAnalyzer.lastError
            self.fuse()
        }
    }

    func stopAudioAI() {
        // Style path asked to stop — keep mic if Auto-key chroma still needs it.
        if keyAssistRequested {
            isAudioListening = audioAnalyzer.isListening
            fuse()
            return
        }
        audioAnalyzer.stopListening()
        isAudioListening = false
        clearAudioKeyEstimate()
        fuse()
    }

    /// Host Auto-key: keep mic open for chroma key MIR.
    func setAudioKeyAssistEnabled(_ enabled: Bool) {
        keyAssistRequested = enabled
        if enabled {
            Task { @MainActor [weak self] in
                guard let self else { return }
                if !self.audioAnalyzer.isListening {
                    await self.audioAnalyzer.startListening()
                }
                self.isAudioListening = self.audioAnalyzer.isListening
                self.audioLastError = self.audioAnalyzer.lastError
                self.fuse()
            }
            return
        }
        fuse()
    }

    /// Unified mic teardown when Auto-key assist no longer needs capture.
    func stopAllAudioCapture() {
        keyAssistRequested = false
        audioAnalyzer.stopListening()
        isAudioListening = false
        clearAudioKeyEstimate()
        fuse()
    }

    private func clearAudioKeyEstimate() {
        estimatedAudioKey = nil
        estimatedAudioScale = .major
        audioKeyConfidence = 0
        audioKeyScores = [:]
        estimatedAudioRelativeKey = nil
    }

    /// Soft reset of mic chroma only — keeps capture running for Auto-key Re-listen.
    func resetAudioKeyListening() {
        audioAnalyzer.resetAudioKeyEstimate()
        clearAudioKeyEstimate()
    }

    func refreshAudioDevices() {
        audioAnalyzer.refreshDevices()
    }

    func selectAudioInputDevice(_ device: AudioInputDevice?) {
        audioAnalyzer.selectInputDevice(device)
    }

    func reset() {
        grooveLocked = false
        keyAssistRequested = false
        midiAnalyzer.reset()
        driftMidiAnalyzer.reset()
        driftEstimatedBPM = nil
        driftTempoConfidence = 0
        audioAnalyzer.stopListening()
        audioAnalyzer.resetAnalysis()
        isAudioListening = false
        clearAudioKeyEstimate()
        fuse()
    }

    func resetDriftAnalysis() {
        driftMidiAnalyzer.reset()
        driftEstimatedBPM = nil
        driftTempoConfidence = 0
    }

    private func fuse() {
        midiStyleConfidence = midiAnalyzer.styleConfidence
        audioStyleConfidence = audioAnalyzer.styleConfidence
        audioInputLevel = audioAnalyzer.inputLevel
        isAudioListening = audioAnalyzer.isListening
        audioLastError = audioAnalyzer.lastError

        chordChangesPerMinute = midiAnalyzer.chordChangesPerMinute
        isTracking = midiAnalyzer.isTracking || audioAnalyzer.isTracking

        let (style, styleSource, styleConf, syncopation) = fuseStyle()
        detectedStyle = style
        primaryStyleSource = styleSource
        styleConfidence = styleConf
        syncopationIndex = syncopation
        suggestedStyle = style == .unknown ? nil : style
        latinRhythmAnalysis = fuseLatinAnalysis()
        detectedClave = latinRhythmAnalysis.clave
        montunoStrength = max(midiAnalyzer.montunoStrength, audioAnalyzer.latinRhythmAnalysis.montunoOstinatoStrength)
        matchedRhythmPatternLabel = latinRhythmAnalysis.matchedPatternLabel
        globalGenreAnalysis = classifyGlobalGenre(
            grooveStyle: style,
            grooveConfidence: styleConf
        )

        if let key = audioAnalyzer.estimatedAudioKey {
            estimatedAudioKey = key
            estimatedAudioScale = audioAnalyzer.estimatedAudioScale
            audioKeyConfidence = audioAnalyzer.audioKeyConfidence
            audioKeyScores = audioAnalyzer.audioKeyScores
            estimatedAudioRelativeKey = audioAnalyzer.estimatedAudioRelativeKey
        }

        guard !grooveLocked else {
            updateDriftEstimate()
            onFusionUpdated?()
            return
        }

        midiTempoConfidence = midiAnalyzer.tempoConfidence
        audioTempoConfidence = audioAnalyzer.tempoConfidence

        let (bpm, tempoSource) = fuseTempo()
        estimatedBPM = bpm
        primaryTempoSource = tempoSource

        tempoConfidence = max(
            weightedConfidence(midi: midiTempoConfidence, audio: audioTempoConfidence, audioEnabled: audioAIEnabled),
            0
        )
        onFusionUpdated?()
    }

    private func fuseTempo() -> (Double?, PerformanceAnalysisSource) {
        let midiBPM = midiAnalyzer.estimatedBPM
        let audioBPM = audioAnalyzer.estimatedBPM

        switch (midiBPM, audioBPM, audioAIEnabled) {
        case let (m?, a?, true):
            if midiTempoConfidence >= 0.35, midiTempoConfidence >= audioTempoConfidence {
                return (m, .midi)
            }
            if audioTempoConfidence >= 0.35, audioTempoConfidence > midiTempoConfidence + 0.15 {
                return (a, .audio)
            }
            let wAudio = midiTempoConfidence + audioTempoConfidence > 0
                ? audioTempoConfidence / (midiTempoConfidence + audioTempoConfidence)
                : 0.5
            let fused = m * (1 - wAudio) + a * wAudio
            return (fused, .fused)
        case let (nil, a?, true):
            return (a, .audio)
        case let (m?, _, _):
            return (m, .midi)
        default:
            return (nil, .midi)
        }
    }

    private func fuseStyle() -> (LiveMusicStyle, PerformanceAnalysisSource, Double, Double) {
        let midiStyle = midiAnalyzer.detectedStyle
        let audioStyle = audioAnalyzer.detectedStyle
        let midiLatin = midiAnalyzer.latinRhythmAnalysis
        let audioLatin = audioAnalyzer.latinRhythmAnalysis

        let midiSync = midiAnalyzer.syncopationIndex
        let audioSync = audioAnalyzer.syncopationIndex

        func boostLatinIfNeeded(
            _ style: LiveMusicStyle,
            source: PerformanceAnalysisSource,
            confidence: Double,
            syncopation: Double
        ) -> (LiveMusicStyle, PerformanceAnalysisSource, Double, Double) {
            let latin = fuseLatinAnalysis()
            guard latin.confidence >= 0.3, let patternStyle = latin.bestStyle else {
                return (style, source, confidence, syncopation)
            }
            if patternStyle.category == .latin || patternStyle == .montuno {
                let boosted = max(confidence, latin.confidence * 0.94)
                if latin.confidence > confidence * 0.9 || style == .unknown {
                    return (patternStyle, .fused, boosted, syncopation)
                }
            }
            if latin.montunoOstinatoStrength >= 0.48, confidence < 0.45 {
                return (.montuno, .fused, max(confidence, latin.montunoOstinatoStrength * 0.9), syncopation)
            }
            return (style, source, confidence, syncopation)
        }

        guard audioAIEnabled, audioStyle != .unknown, audioStyleConfidence >= 0.2 else {
            let base = (midiStyle, PerformanceAnalysisSource.midi, midiStyleConfidence, midiSync)
            return boostLatinIfNeeded(base.0, source: base.1, confidence: base.2, syncopation: base.3)
        }

        guard midiStyle != .unknown, midiStyleConfidence >= 0.2 else {
            let base = (audioStyle, PerformanceAnalysisSource.audio, audioStyleConfidence, audioSync)
            return boostLatinIfNeeded(base.0, source: base.1, confidence: base.2, syncopation: base.3)
        }

        if midiStyle == audioStyle {
            let conf = min(1.0, (midiStyleConfidence + audioStyleConfidence) * 0.55 + 0.15)
            let latinBonus = max(midiLatin.confidence, audioLatin.confidence)
            let adjusted = min(1.0, conf + latinBonus * 0.12)
            return boostLatinIfNeeded(midiStyle, source: .fused, confidence: adjusted, syncopation: (midiSync + audioSync) / 2)
        }

        if midiLatin.bestStyle == audioLatin.bestStyle,
           let agreed = midiLatin.bestStyle,
           max(midiLatin.confidence, audioLatin.confidence) >= 0.34 {
            let conf = min(1.0, max(midiStyleConfidence, audioStyleConfidence) + 0.18)
            return (agreed, .fused, conf, (midiSync + audioSync) / 2)
        }

        if audioStyleConfidence > midiStyleConfidence + 0.12 {
            return boostLatinIfNeeded(audioStyle, source: .audio, confidence: audioStyleConfidence, syncopation: audioSync)
        }
        if midiStyleConfidence > audioStyleConfidence + 0.12 {
            return boostLatinIfNeeded(midiStyle, source: .midi, confidence: midiStyleConfidence, syncopation: midiSync)
        }

        return boostLatinIfNeeded(
            audioStyle,
            source: .fused,
            confidence: (midiStyleConfidence + audioStyleConfidence) / 2,
            syncopation: (midiSync + audioSync) / 2
        )
    }

    private func fuseLatinAnalysis() -> LatinRhythmAnalysis {
        let midi = midiAnalyzer.latinRhythmAnalysis
        let audio = audioAnalyzer.latinRhythmAnalysis
        guard midi.confidence > 0.1 || audio.confidence > 0.1 else {
            return midi.confidence >= audio.confidence ? midi : audio
        }
        if midi.bestStyle == audio.bestStyle, midi.bestStyle != nil {
            var merged = midi.confidence >= audio.confidence ? midi : audio
            merged.confidence = min(1.0, max(midi.confidence, audio.confidence) + 0.12)
            merged.montunoOstinatoStrength = max(midi.montunoOstinatoStrength, audio.montunoOstinatoStrength)
            if midi.claveConfidence >= audio.claveConfidence {
                merged.clave = midi.clave
                merged.claveConfidence = midi.claveConfidence
            } else {
                merged.clave = audio.clave
                merged.claveConfidence = audio.claveConfidence
            }
            return merged
        }
        return midi.confidence >= audio.confidence ? midi : audio
    }

    private func classifyGlobalGenre(
        grooveStyle: LiveMusicStyle,
        grooveConfidence: Double
    ) -> GlobalGenreAnalysis {
        let spectral = audioAnalyzer.spectralProfile()

        let snapshot = midiAnalyzer.buildGenreSnapshot(
            audioProbabilities: audioAnalyzer.lastStyleProbabilities,
            onsetDensity: audioAnalyzer.onsetDensityPerSecond,
            spectralBrightness: spectral.brightness,
            lowEnergyRatio: spectral.lowRatio
        )

        var analysis = GlobalGenreClassifier.classify(snapshot)

        if analysis.primary == nil, grooveStyle != .unknown {
            if let match = GlobalMusicGenreCatalog.all.first(where: { $0.closestGroove == grooveStyle }) {
                analysis.primary = match
                analysis.confidence = max(analysis.confidence, grooveConfidence * 0.72)
                analysis.region = match.region
            }
        }

        return analysis
    }

    private func weightedConfidence(midi: Double, audio: Double, audioEnabled: Bool) -> Double {
        if audioEnabled, audio > 0.1 {
            return min(1.0, midi * 0.45 + audio * 0.55)
        }
        return midi
    }

    private func updateDriftEstimate() {
        let midiBPM = driftMidiAnalyzer.estimatedBPM
        let audioBPM = audioAIEnabled ? audioAnalyzer.estimatedBPM : nil
        let midiConf = driftMidiAnalyzer.tempoConfidence
        let audioConf = audioAnalyzer.tempoConfidence

        switch (midiBPM, audioBPM, audioAIEnabled) {
        case let (_, a?, true) where audioConf >= 0.3 && audioConf > midiConf + 0.1:
            driftEstimatedBPM = a
            driftTempoConfidence = audioConf
        case let (m?, _, _):
            driftEstimatedBPM = m
            driftTempoConfidence = midiConf
        case let (nil, a?, true):
            driftEstimatedBPM = a
            driftTempoConfidence = audioConf
        default:
            driftEstimatedBPM = nil
            driftTempoConfidence = 0
        }
    }
}
#endif
