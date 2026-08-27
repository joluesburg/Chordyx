//
//  AdaptiveKeyLearningEngine.swift
//  Chordyx
//
//  Learns key from live chord sequences — combines music-theory profiles,
//  heuristics, and an online neural scorer that improves when you correct the key.
//

import Foundation

struct AdaptiveKeyDetection: Equatable, Sendable {
    let key: MusicalKey
    /// Detected scale / mode (major, Dorian, blues, …).
    let scale: MusicalScaleQuality
    /// 0…1
    let confidence: Double
    let source: Source
    let relativeKey: MusicalKey?

    enum Source: String, Sendable {
        case memory
        case library
        case ensemble
        case heuristic
        case audio
        case midi
    }

    init(
        key: MusicalKey,
        scale: MusicalScaleQuality = .major,
        confidence: Double,
        source: Source,
        relativeKey: MusicalKey? = nil
    ) {
        self.key = key
        self.scale = scale
        self.confidence = confidence
        self.source = source
        self.relativeKey = relativeKey ?? scale.relativeKey(of: key)
    }
}

/// Soft prior from live mic chroma (HPCP + multi-scale). Cleared when stale.
struct AudioKeyHint: Equatable, Sendable {
    let key: MusicalKey
    let scale: MusicalScaleQuality
    let confidence: Double
    let scores: [MusicalKey: Double]
    let relativeKey: MusicalKey?
    let updatedAt: TimeInterval
}

/// Saved progression snapshot used to ground live Auto-key detection.
struct LibraryKeyHint: Equatable, Sendable {
    let name: String
    let key: MusicalKey
    let symbols: [String]
}

@MainActor
final class AdaptiveKeyLearningEngine {
    static let shared = AdaptiveKeyLearningEngine()

    nonisolated private static let storeFileName = "adaptive_key_learning.json"
    private static let minimumSymbols = 3

    private var memory: [KeyMemoryEntry] = []
    private var corrections: [KeyCorrectionEntry] = []
    private var neuralWeights: [[Float]] = []
    private var neuralBias: [Float] = []
    /// Resolved off the main thread — never call `url(forUbiquityContainerIdentifier:)` on MainActor.
    private var cloudStoreURL: URL?
    private var isResolvingCloudStore = false
    /// Latest library progressions for live sequence matching.
    private(set) var libraryHints: [LibraryKeyHint] = []
    /// Soft prior from live audio chroma (mic/line).
    private var audioKeyHint: AudioKeyHint?
    /// Pitch-class chroma accumulated from the MIDI / piano controller (ground truth when playing).
    private var midiChroma = [Double](repeating: 0, count: 12)
    private var midiChromaUpdatedAt: TimeInterval = 0
    private var midiFrameCount = 0

    private init() {
        // Fast local load only — iCloud resolution is async (ubiquity APIs can stall launch on Mac).
        applyStore(from: localStoreURL, startDownloadIfNeeded: false)
        ensureNeuralInitialized()
        resolveCloudStoreIfNeeded()
    }

    // MARK: - Public API

    func updateLibraryHints(_ hints: [LibraryKeyHint]) {
        libraryHints = hints.filter { $0.symbols.count >= 3 }
    }

    /// Ingest every sounding MIDI pitch class (and bass) into Auto AI chroma.
    /// Call on each settled controller voicing — inversions weight the bass harder.
    func ingestMIDIVoicing(pitchClasses: [Int], bassPitchClass: Int?) {
        guard !pitchClasses.isEmpty else { return }
        for i in 0..<12 {
            midiChroma[i] *= 0.92
        }
        let unique = Set(pitchClasses.map { (($0 % 12) + 12) % 12 })
        for pc in unique {
            midiChroma[pc] += 1.0
        }
        if let bass = bassPitchClass {
            let b = ((bass % 12) + 12) % 12
            midiChroma[b] += 1.25
        }
        midiFrameCount += 1
        midiChromaUpdatedAt = Date().timeIntervalSince1970
    }

    func clearMIDIChroma() {
        midiChroma = [Double](repeating: 0, count: 12)
        midiFrameCount = 0
        midiChromaUpdatedAt = 0
    }

    private func freshMIDIDetection() -> DetectedTonalCenter? {
        guard midiFrameCount >= 2 else { return nil }
        guard Date().timeIntervalSince1970 - midiChromaUpdatedAt <= 6 else {
            clearMIDIChroma()
            return nil
        }
        return TonalScaleIntelligence.detectFromChroma(midiChroma)
    }

    /// Feed HPCP multi-scale audio estimate from the live mic pipeline (primary Auto AI signal).
    func updateAudioKeyHint(
        key: MusicalKey,
        scale: MusicalScaleQuality = .major,
        confidence: Double,
        scores: [MusicalKey: Double],
        relativeKey: MusicalKey? = nil
    ) {
        guard confidence >= 0.08 else { return }
        audioKeyHint = AudioKeyHint(
            key: key,
            scale: scale,
            confidence: min(1, confidence),
            scores: scores,
            relativeKey: relativeKey ?? scale.relativeKey(of: key),
            updatedAt: Date().timeIntervalSince1970
        )
    }

    func clearAudioKeyHint() {
        audioKeyHint = nil
    }

    /// MIDI-controller-first Auto AI: voicings + inversions + pitch chroma lead;
    /// mic reinforces; clear chord-family anchors can still override a wrong letter.
    func detect(from symbols: [String], sessionName: String?) -> AdaptiveKeyDetection? {
        let normalized = normalizedSymbols(symbols)
        let audio = freshAudioHint()
        let midi = freshMIDIDetection()

        // Hard chord anchors — progression names the tonic; infer scale from the chords.
        if let anchored = strongChordAnchorDetection(from: normalized) {
            return anchored
        }

        let chordBlend = softChordScores(from: normalized, sessionName: sessionName)
        let hasChordEvidence = KeyChordAnalysis.hasProgressionEvidence(normalized)

        // ── Primary when controller is active: MIDI pitch chroma + scale ───────
        if let midi, midi.confidence >= 0.12, midiFrameCount >= 2 {
            if hasChordEvidence,
               KeyChordAnalysis.isImplausibleLiveKeyCandidate(symbols: normalized, candidate: midi.key),
               let chordOnly = resolveSoftChordDetection(
                scores: chordBlend,
                symbols: normalized,
                preferSource: .ensemble
               ) {
                return chordOnly
            }

            var blended = [MusicalKey: Double]()
            for key in MusicalKey.allCases {
                let m = midi.scores[key] ?? 0
                let a = audio?.scores[key] ?? 0
                let c = chordBlend[key] ?? 0
                // MIDI controller is ground truth; audio soft; chords reinforce.
                blended[key] = m * 0.58 + a * 0.22 + c * 0.20
            }
            blended[midi.key, default: 0] += midi.confidence * 0.20
            if let audio {
                blended[audio.key, default: 0] += audio.confidence * 0.08
            }
            if !normalized.isEmpty {
                WorshipAutoKeyRules.applyScoreBoost(symbols: normalized, into: &blended)
            }

            let ranked = blended.sorted { $0.value > $1.value }
            let plausible = ranked.first { candidate in
                guard hasChordEvidence else { return true }
                return !KeyChordAnalysis.isImplausibleLiveKeyCandidate(
                    symbols: normalized,
                    candidate: candidate.key
                )
            }
            if let best = plausible, best.value > 0.12 {
                let scale: MusicalScaleQuality = {
                    if best.key == midi.key {
                        let chordScale = TonalScaleIntelligence.inferScale(from: normalized, tonic: best.key)
                        if chordScale != .major && chordScale != .naturalMinor { return chordScale }
                        return midi.scale
                    }
                    return TonalScaleIntelligence.inferScale(from: normalized, tonic: best.key)
                }()
                return AdaptiveKeyDetection(
                    key: best.key,
                    scale: scale,
                    confidence: max(midi.confidence, min(1, best.value)),
                    source: best.key == midi.key ? .midi : .ensemble
                )
            }
            return AdaptiveKeyDetection(
                key: midi.key,
                scale: midi.scale,
                confidence: midi.confidence,
                source: .midi,
                relativeKey: midi.relativeKey
            )
        }

        // ── Mic chroma when no / weak MIDI ─────────────────────────────────────
        if let audio, audio.confidence >= 0.14 {
            if hasChordEvidence,
               KeyChordAnalysis.isImplausibleLiveKeyCandidate(symbols: normalized, candidate: audio.key),
               let chordOnly = resolveSoftChordDetection(
                scores: chordBlend,
                symbols: normalized,
                preferSource: .ensemble
               ) {
                return chordOnly
            }

            var blended = [MusicalKey: Double]()
            for key in MusicalKey.allCases {
                let a = audio.scores[key] ?? 0
                let c = chordBlend[key] ?? 0
                blended[key] = a * 0.70 + c * 0.30
            }
            blended[audio.key, default: 0] += audio.confidence * 0.18
            if !normalized.isEmpty {
                WorshipAutoKeyRules.applyScoreBoost(symbols: normalized, into: &blended)
            }

            let ranked = blended.sorted { $0.value > $1.value }
            let plausible = ranked.first { candidate in
                guard hasChordEvidence else { return true }
                return !KeyChordAnalysis.isImplausibleLiveKeyCandidate(
                    symbols: normalized,
                    candidate: candidate.key
                )
            }
            if let best = plausible, best.value > 0.12 {
                var confidence = max(audio.confidence, min(1, best.value))
                if best.key == audio.key {
                    confidence = max(confidence, audio.confidence)
                }
                let scale: MusicalScaleQuality
                if best.key == audio.key {
                    let chordScale = TonalScaleIntelligence.inferScale(from: normalized, tonic: best.key)
                    scale = (chordScale == .major || chordScale == .naturalMinor)
                        ? audio.scale
                        : chordScale
                } else {
                    scale = TonalScaleIntelligence.inferScale(from: normalized, tonic: best.key)
                }
                let source: AdaptiveKeyDetection.Source =
                    best.key == audio.key ? .audio : .ensemble
                return AdaptiveKeyDetection(
                    key: best.key,
                    scale: scale,
                    confidence: confidence,
                    source: source
                )
            }

            return AdaptiveKeyDetection(
                key: audio.key,
                scale: audio.scale,
                confidence: audio.confidence,
                source: .audio,
                relativeKey: audio.relativeKey
            )
        }

        // ── Fallback: chords only (pad / no mic / no MIDI chroma yet) ──────────
        guard normalized.count >= Self.minimumSymbols else { return nil }
        return resolveSoftChordDetection(
            scores: chordBlend,
            symbols: normalized,
            preferSource: .ensemble
        )
    }

    /// Explicit theory anchors from the live chord window — override audio when present.
    private func strongChordAnchorDetection(from normalized: [String]) -> AdaptiveKeyDetection? {
        guard normalized.count >= 3 else { return nil }

        func pack(_ key: MusicalKey, confidence: Double) -> AdaptiveKeyDetection {
            let scale = TonalScaleIntelligence.inferScale(from: normalized, tonic: key)
            return AdaptiveKeyDetection(
                key: key,
                scale: scale,
                confidence: confidence,
                source: .ensemble
            )
        }

        if WorshipAutoKeyRules.hasTwoLoopEvidence(normalized),
           let worshipKey = WorshipAutoKeyRules.resolveKey(from: normalized),
           !KeyChordAnalysis.isImplausibleLiveKeyCandidate(symbols: normalized, candidate: worshipKey) {
            return pack(worshipKey, confidence: 0.90)
        }
        if let tonicPC = KeyChordAnalysis.establishedMajorFamilyTonic(in: normalized),
           let tonicKey = MusicalKey.allCases.first(where: { $0.pitchClass == tonicPC }) {
            return pack(tonicKey, confidence: 0.88)
        }
        if let tonicPC = KeyChordAnalysis.establishedMajorTonicFromIAndV7(in: normalized),
           let tonicKey = MusicalKey.allCases.first(where: { $0.pitchClass == tonicPC }) {
            return pack(tonicKey, confidence: 0.86)
        }
        if let tonicPC = KeyChordAnalysis.authenticDominantCadenceDestination(in: normalized),
           let tonicKey = MusicalKey.allCases.first(where: { $0.pitchClass == tonicPC }) {
            return pack(tonicKey, confidence: 0.84)
        }
        if let tonicPC = KeyChordAnalysis.establishedMinorTonic(in: normalized),
           let tonicKey = MusicalKey.allCases.first(where: { $0.pitchClass == tonicPC }) {
            return pack(tonicKey, confidence: 0.82)
        }
        return nil
    }

    private func softChordScores(from normalized: [String], sessionName: String?) -> [MusicalKey: Double] {
        guard normalized.count >= 3 else { return [:] }

        let memoryHit = recallMemory(
            fingerprint: KeyChordAnalysis.fingerprint(from: normalized),
            sessionName: sessionName
        )
        let libraryHit = KeyChordAnalysis.bestLibraryKeyMatch(
            liveSymbols: normalized,
            library: libraryHints.map { ($0.name, $0.key, $0.symbols) }
        )
        let intelligence = LiveKeyIntelligence.analyze(symbols: normalized)
        let heuristic = KeyDetector.detect(from: normalized)
        let neural = neuralScores(from: normalized)

        var blended = [MusicalKey: Double]()
        for key in MusicalKey.allCases {
            let intel = intelligence?.scores[key] ?? 0
            let h = heuristic?.key == key ? (heuristic?.confidence ?? 0) : 0
            let n = neural[key] ?? 0
            blended[key] = intel * 0.62 + h * 0.22 + n * 0.16
        }
        WorshipAutoKeyRules.applyScoreBoost(symbols: normalized, into: &blended)

        if let libraryHit,
           !KeyChordAnalysis.isImplausibleLiveKeyCandidate(symbols: normalized, candidate: libraryHit.key) {
            blended[libraryHit.key, default: 0] += libraryHit.similarity * 0.18
        }
        if let memoryHit,
           !KeyChordAnalysis.isImplausibleLiveKeyCandidate(symbols: normalized, candidate: memoryHit) {
            blended[memoryHit, default: 0] += 0.12
        }
        return blended
    }

    private func resolveSoftChordDetection(
        scores: [MusicalKey: Double],
        symbols: [String],
        preferSource: AdaptiveKeyDetection.Source
    ) -> AdaptiveKeyDetection? {
        func detection(for key: MusicalKey, confidence: Double, source: AdaptiveKeyDetection.Source) -> AdaptiveKeyDetection {
            let scale = TonalScaleIntelligence.inferScale(from: symbols, tonic: key)
            return AdaptiveKeyDetection(key: key, scale: scale, confidence: confidence, source: source)
        }

        guard !scores.isEmpty else {
            let intelligence = LiveKeyIntelligence.analyze(symbols: symbols)
            if let intelligence,
               !KeyChordAnalysis.isImplausibleLiveKeyCandidate(symbols: symbols, candidate: intelligence.bestKey),
               intelligence.confidence >= 0.14 {
                return detection(for: intelligence.bestKey, confidence: intelligence.confidence, source: preferSource)
            }
            return KeyDetector.detect(from: symbols).flatMap { result -> AdaptiveKeyDetection? in
                guard !KeyChordAnalysis.isImplausibleLiveKeyCandidate(symbols: symbols, candidate: result.key) else {
                    return nil
                }
                return detection(for: result.key, confidence: result.confidence, source: .heuristic)
            }
        }

        let ranked = scores.sorted { $0.value > $1.value }
        let plausible = ranked.first {
            !KeyChordAnalysis.isImplausibleLiveKeyCandidate(symbols: symbols, candidate: $0.key)
        }
        guard let best = plausible, best.value > 0.18, ranked.count >= 2 else {
            let intelligence = LiveKeyIntelligence.analyze(symbols: symbols)
            if let intelligence,
               !KeyChordAnalysis.isImplausibleLiveKeyCandidate(symbols: symbols, candidate: intelligence.bestKey),
               intelligence.confidence >= 0.14 {
                return detection(for: intelligence.bestKey, confidence: intelligence.confidence, source: preferSource)
            }
            return KeyDetector.detect(from: symbols).flatMap { result -> AdaptiveKeyDetection? in
                guard !KeyChordAnalysis.isImplausibleLiveKeyCandidate(symbols: symbols, candidate: result.key) else {
                    return nil
                }
                return detection(for: result.key, confidence: result.confidence, source: .heuristic)
            }
        }

        let resolved = KeyChordAnalysis.resolveLiveTonalCenter(
            symbols: symbols,
            scores: scores,
            currentBest: best.key
        )
        guard !KeyChordAnalysis.isImplausibleLiveKeyCandidate(symbols: symbols, candidate: resolved) else {
            return nil
        }

        let resolvedValue = scores[resolved] ?? best.value
        let runnerUp = ranked.first(where: { $0.key != resolved })?.value ?? ranked[1].value
        let margin = resolvedValue - runnerUp
        var confidence = min(1, max(0.15, margin / max(resolvedValue, 0.01)))
        if let intelligence = LiveKeyIntelligence.analyze(symbols: symbols),
           intelligence.bestKey == resolved {
            confidence = max(confidence, intelligence.confidence * 0.92)
        }

        guard confidence >= 0.14 || resolvedValue >= 0.48 else {
            return KeyDetector.detect(from: symbols).flatMap { result -> AdaptiveKeyDetection? in
                guard !KeyChordAnalysis.isImplausibleLiveKeyCandidate(symbols: symbols, candidate: result.key) else {
                    return nil
                }
                return detection(for: result.key, confidence: result.confidence, source: .heuristic)
            }
        }

        return detection(for: resolved, confidence: confidence, source: preferSource)
    }

    private func freshAudioHint() -> AudioKeyHint? {
        guard let hint = audioKeyHint else { return nil }
        guard Date().timeIntervalSince1970 - hint.updatedAt <= 5 else {
            audioKeyHint = nil
            return nil
        }
        return hint
    }

    func confirmDetection(symbols: [String], key: MusicalKey, sessionName: String?) {
        let normalized = normalizedSymbols(symbols)
        guard !normalized.isEmpty else { return }
        reinforceMemory(fingerprint: KeyChordAnalysis.fingerprint(from: normalized), key: key, sessionName: sessionName)
        trainNeural(symbols: normalized, targetKey: key, learningRate: 0.06)
        save()
    }

    func recordCorrection(
        symbols: [String],
        detectedKey: MusicalKey,
        correctedKey: MusicalKey,
        sessionName: String?
    ) {
        let normalized = normalizedSymbols(symbols)
        guard !normalized.isEmpty, detectedKey != correctedKey else { return }

        corrections.append(KeyCorrectionEntry(
            symbols: normalized,
            detectedKeyRaw: detectedKey.rawValue,
            correctedKeyRaw: correctedKey.rawValue,
            sessionName: sessionName,
            recordedAt: Date()
        ))
        if corrections.count > 120 {
            corrections.removeFirst(corrections.count - 120)
        }

        reinforceMemory(fingerprint: KeyChordAnalysis.fingerprint(from: normalized), key: correctedKey, sessionName: sessionName)
        trainNeural(symbols: normalized, targetKey: correctedKey, learningRate: 0.14)

        for entry in corrections.suffix(24) where entry.correctedKeyRaw == correctedKey.rawValue {
            trainNeural(symbols: entry.symbols, targetKey: correctedKey, learningRate: 0.04)
        }

        save()
    }

    var learnedSongCount: Int {
        memory.count
    }

    var correctionCount: Int {
        corrections.count
    }

    // MARK: - Memory

    private func recallMemory(fingerprint: String, sessionName: String?) -> MusicalKey? {
        if let exact = memory.first(where: { $0.fingerprint == fingerprint && $0.hitCount >= 2 }),
           let key = MusicalKey(rawValue: exact.keyRaw) {
            return key
        }

        if let title = sessionName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !title.isEmpty,
           let byTitle = memory
            .filter({ $0.sessionTitles.contains(where: { $0.caseInsensitiveCompare(title) == .orderedSame }) })
            .max(by: { $0.hitCount < $1.hitCount }),
           byTitle.hitCount >= 2,
           let key = MusicalKey(rawValue: byTitle.keyRaw) {
            return key
        }

        let queryTokens = Set(fingerprint.split(separator: "|").map(String.init))
        var bestMatch: (entry: KeyMemoryEntry, score: Double)?
        for entry in memory where entry.hitCount >= 2 {
            let storedTokens = Set(entry.fingerprint.split(separator: "|").map(String.init))
            guard !storedTokens.isEmpty else { continue }
            let intersection = Double(queryTokens.intersection(storedTokens).count)
            let union = Double(queryTokens.union(storedTokens).count)
            let jaccard = intersection / max(union, 1)
            if jaccard >= 0.72, bestMatch == nil || jaccard > bestMatch!.score {
                bestMatch = (entry, jaccard)
            }
        }
        if let bestMatch, let key = MusicalKey(rawValue: bestMatch.entry.keyRaw) {
            return key
        }
        return nil
    }

    private func reinforceMemory(fingerprint: String, key: MusicalKey, sessionName: String?) {
        if let index = memory.firstIndex(where: { $0.fingerprint == fingerprint }) {
            memory[index].hitCount += 1
            memory[index].keyRaw = key.rawValue
            memory[index].lastConfirmed = Date()
            if let title = sessionName?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty,
               !memory[index].sessionTitles.contains(where: { $0.caseInsensitiveCompare(title) == .orderedSame }) {
                memory[index].sessionTitles.append(title)
            }
        } else {
            memory.append(KeyMemoryEntry(
                fingerprint: fingerprint,
                keyRaw: key.rawValue,
                hitCount: 1,
                lastConfirmed: Date(),
                sessionTitles: sessionName.map { [$0] } ?? []
            ))
        }
        if memory.count > 200 {
            memory.sort { $0.hitCount > $1.hitCount }
            memory = Array(memory.prefix(200))
        }
    }

    // MARK: - Neural online learner (36-D: major / minor / dominant pitch-class mass)

    private func ensureNeuralInitialized() {
        guard neuralWeights.isEmpty else { return }
        neuralWeights = (0..<12).map { row in
            (0..<36).map { col in
                let seed = sin(Float(row * 36 + col) * 0.37) * 0.08
                return row == col % 12 ? seed + 0.12 : seed
            }
        }
        neuralBias = [Float](repeating: 0, count: 12)
    }

    private func featureVector(from symbols: [String]) -> [Float] {
        var pcMajor = [Float](repeating: 0, count: 12)
        var pcMinor = [Float](repeating: 0, count: 12)
        var pcDominant = [Float](repeating: 0, count: 12)
        for (index, symbol) in symbols.enumerated() {
            guard let parsed = Transposer.parse(symbol),
                  let pc = Transposer.pitchClass(ofRoot: parsed.root) else { continue }
            let weight = Float(1.0 + Double(index) / Double(max(symbols.count, 1)) * 0.45)
            let s = parsed.suffix.lowercased()
            if s.hasPrefix("m") && !s.hasPrefix("maj") {
                pcMinor[pc] += weight
            } else if s.hasPrefix("7") || s.contains("9") || s.contains("11") || s.contains("13") {
                pcDominant[pc] += weight
            } else {
                pcMajor[pc] += weight
            }
        }
        let total = pcMajor.reduce(0, +) + pcMinor.reduce(0, +) + pcDominant.reduce(0, +)
        if total > 0 {
            for i in 0..<12 {
                pcMajor[i] /= total
                pcMinor[i] /= total
                pcDominant[i] /= total
            }
        }
        return pcMajor + pcMinor + pcDominant
    }

    private func neuralScores(from symbols: [String]) -> [MusicalKey: Double] {
        ensureNeuralInitialized()
        if neuralWeights.first?.count != 36 {
            neuralWeights = []
            ensureNeuralInitialized()
        }
        let features = featureVector(from: symbols)
        guard features.count == 36, neuralWeights.first?.count == 36 else {
            return [:]
        }
        var logits = [Float](repeating: 0, count: 12)
        for row in 0..<12 {
            var sum = neuralBias[row]
            for col in 0..<36 {
                sum += neuralWeights[row][col] * features[col]
            }
            logits[row] = sum
        }
        let probs = softmax(logits)
        var scores = [MusicalKey: Double]()
        for key in MusicalKey.allCases {
            scores[key] = Double(probs[key.pitchClass])
        }
        return scores
    }

    private func trainNeural(symbols: [String], targetKey: MusicalKey, learningRate: Float) {
        let features = featureVector(from: symbols)
        guard features.count == 36 else { return }
        if neuralWeights.first?.count != 36 {
            neuralWeights = []
            ensureNeuralInitialized()
        }
        var logits = [Float](repeating: 0, count: 12)
        for row in 0..<12 {
            var sum = neuralBias[row]
            for col in 0..<36 {
                sum += neuralWeights[row][col] * features[col]
            }
            logits[row] = sum
        }
        let probs = softmax(logits)
        let target = targetKey.pitchClass
        for row in 0..<12 {
            let error = probs[row] - (row == target ? 1 : 0)
            neuralBias[row] -= learningRate * error
            for col in 0..<36 {
                neuralWeights[row][col] -= learningRate * error * features[col]
            }
        }
    }

    private func softmax(_ logits: [Float]) -> [Float] {
        guard let maxLogit = logits.max() else { return [] }
        let exps = logits.map { expf($0 - maxLogit) }
        let sum = exps.reduce(0, +)
        guard sum > 0 else { return logits.map { _ in 1 / Float(logits.count) } }
        return exps.map { $0 / sum }
    }

    private func normalizedSymbols(_ symbols: [String]) -> [String] {
        // Keep slash-bass inversions (C/E) — theory helpers strip when they need the chord body.
        symbols
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    // MARK: - Persistence

    /// Prefers iCloud Drive when resolved; otherwise Application Support (never blocks launch).
    private var storeURL: URL {
        cloudStoreURL ?? localStoreURL
    }

    private var localStoreURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("Chordyx", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(Self.storeFileName)
    }

    private struct StorePayload: Codable {
        var memory: [KeyMemoryEntry]
        var corrections: [KeyCorrectionEntry]
        var neuralWeights: [[Float]]
        var neuralBias: [Float]
    }

    private func applyStore(from url: URL, startDownloadIfNeeded: Bool) {
        if startDownloadIfNeeded, FileManager.default.isUbiquitousItem(at: url) {
            try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        }
        guard let data = try? Data(contentsOf: url),
              let payload = try? JSONDecoder().decode(StorePayload.self, from: data) else { return }
        memory = payload.memory
        corrections = payload.corrections
        // Drop legacy 24-D nets so the 36-D MIR feature space can re-init cleanly.
        if payload.neuralWeights.first?.count == 36, payload.neuralBias.count == 12 {
            neuralWeights = payload.neuralWeights
            neuralBias = payload.neuralBias
        } else {
            neuralWeights = []
            neuralBias = []
        }
    }

    /// Call when the app becomes active so iCloud updates from other devices are picked up.
    func reloadFromDisk() {
        applyStore(from: storeURL, startDownloadIfNeeded: cloudStoreURL != nil)
        ensureNeuralInitialized()
        resolveCloudStoreIfNeeded()
    }

    private func resolveCloudStoreIfNeeded() {
        guard cloudStoreURL == nil, !isResolvingCloudStore else { return }
        isResolvingCloudStore = true
        let local = localStoreURL
        let fileName = Self.storeFileName
        Task.detached(priority: .utility) {
            // Apple: do not call ubiquity container APIs on the main thread.
            let cloudRoot = FileManager.default.url(forUbiquityContainerIdentifier: nil)
            let cloudURL: URL? = {
                guard let cloudRoot else { return nil }
                let dir = cloudRoot
                    .appendingPathComponent("Documents", isDirectory: true)
                    .appendingPathComponent("Chordyx", isDirectory: true)
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                return dir.appendingPathComponent(fileName)
            }()

            if let cloudURL,
               FileManager.default.fileExists(atPath: local.path),
               !FileManager.default.fileExists(atPath: cloudURL.path) {
                try? FileManager.default.copyItem(at: local, to: cloudURL)
            }

            await MainActor.run {
                self.cloudStoreURL = cloudURL
                self.isResolvingCloudStore = false
                if let cloudURL {
                    self.applyStore(from: cloudURL, startDownloadIfNeeded: true)
                    self.ensureNeuralInitialized()
                }
            }
        }
    }

    private func save() {
        let payload = StorePayload(
            memory: memory,
            corrections: corrections,
            neuralWeights: neuralWeights,
            neuralBias: neuralBias
        )
        guard let data = try? JSONEncoder().encode(payload) else { return }
        let url = storeURL
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            // Fall back to on-device memory if iCloud is unavailable.
            try? data.write(to: localStoreURL, options: .atomic)
        }
        if cloudStoreURL == nil {
            resolveCloudStoreIfNeeded()
        }
    }
}

private struct KeyMemoryEntry: Codable {
    var fingerprint: String
    var keyRaw: String
    var hitCount: Int
    var lastConfirmed: Date
    var sessionTitles: [String]
}

private struct KeyCorrectionEntry: Codable {
    var symbols: [String]
    var detectedKeyRaw: String
    var correctedKeyRaw: String
    var sessionName: String?
    var recordedAt: Date
}
