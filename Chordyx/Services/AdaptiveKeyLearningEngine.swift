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
    /// 0…1
    let confidence: Double
    let source: Source

    enum Source: String, Sendable {
        case memory
        case library
        case ensemble
        case heuristic
        case audio
    }
}

/// Soft prior from live mic chroma (HPCP + KS). Cleared when stale.
struct AudioKeyHint: Equatable, Sendable {
    let key: MusicalKey
    let confidence: Double
    let scores: [MusicalKey: Double]
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

    /// Feed HPCP/KS audio key estimate from the live mic pipeline.
    func updateAudioKeyHint(key: MusicalKey, confidence: Double, scores: [MusicalKey: Double]) {
        guard confidence >= 0.12 else { return }
        audioKeyHint = AudioKeyHint(
            key: key,
            confidence: min(1, confidence),
            scores: scores,
            updatedAt: Date().timeIntervalSince1970
        )
    }

    func clearAudioKeyHint() {
        audioKeyHint = nil
    }

    func detect(from symbols: [String], sessionName: String?) -> AdaptiveKeyDetection? {
        let normalized = normalizedSymbols(symbols)
        guard normalized.count >= Self.minimumSymbols else {
            // Never lock Auto-key from mic chroma alone — wait for chord progression evidence.
            return nil
        }

        let fingerprint = KeyChordAnalysis.fingerprint(from: normalized)

        if let memoryHit = recallMemory(fingerprint: fingerprint, sessionName: sessionName),
           !KeyChordAnalysis.isImplausibleLiveKeyCandidate(symbols: normalized, candidate: memoryHit) {
            return AdaptiveKeyDetection(key: memoryHit, confidence: 0.92, source: .memory)
        }

        if let libraryHit = KeyChordAnalysis.bestLibraryKeyMatch(
            liveSymbols: normalized,
            library: libraryHints.map { ($0.name, $0.key, $0.symbols) }
        ), libraryHit.confidence >= 0.72,
           !KeyChordAnalysis.isImplausibleLiveKeyCandidate(symbols: normalized, candidate: libraryHit.key) {
            return AdaptiveKeyDetection(
                key: libraryHit.key,
                confidence: libraryHit.confidence,
                source: .library
            )
        }

        // Market-grade MIR ensemble (KS, Temperley, functions, fifths, templates, HMM).
        let intelligence = LiveKeyIntelligence.analyze(symbols: normalized)
        let heuristic = KeyDetector.detect(from: normalized)
        let neural = neuralScores(from: normalized)
        let audio = freshAudioHint()

        var blended = [MusicalKey: Double]()
        for key in MusicalKey.allCases {
            let intel = intelligence?.scores[key] ?? 0
            let h = heuristic?.key == key ? (heuristic?.confidence ?? 0) : 0
            let n = neural[key] ?? 0
            let a = audio?.scores[key] ?? 0
            // Chord intelligence leads; audio chroma + neural refine live lock.
            blended[key] = intel * 0.58 + h * 0.16 + n * 0.14 + a * 0.12
        }

        if let libraryHit = KeyChordAnalysis.bestLibraryKeyMatch(
            liveSymbols: normalized,
            library: libraryHints.map { ($0.name, $0.key, $0.symbols) }
        ) {
            blended[libraryHit.key, default: 0] += libraryHit.similarity * 0.28
        }

        if let audio {
            blended[audio.key, default: 0] += audio.confidence * 0.10
        }

        let ranked = blended.sorted { $0.value > $1.value }
        let plausible = ranked.first {
            !KeyChordAnalysis.isImplausibleLiveKeyCandidate(symbols: normalized, candidate: $0.key)
        }
        guard let best = plausible ?? ranked.first, best.value > 0.18,
              ranked.count >= 2 else {
            if let intelligence, intelligence.confidence >= 0.14,
               !KeyChordAnalysis.isImplausibleLiveKeyCandidate(symbols: normalized, candidate: intelligence.bestKey) {
                return AdaptiveKeyDetection(
                    key: intelligence.bestKey,
                    confidence: intelligence.confidence,
                    source: .ensemble
                )
            }
            return heuristic.map {
                AdaptiveKeyDetection(key: $0.key, confidence: $0.confidence, source: .heuristic)
            }
        }

        let resolved = KeyChordAnalysis.resolveLiveTonalCenter(
            symbols: normalized,
            scores: blended,
            currentBest: best.key
        )
        let resolvedValue = blended[resolved] ?? best.value
        let runnerUp = ranked.first(where: { $0.key != resolved })?.value ?? ranked[1].value
        let margin = resolvedValue - runnerUp
        var confidence = min(1, max(0.15, margin / max(resolvedValue, 0.01)))
        if let intelligence, intelligence.bestKey == resolved {
            confidence = max(confidence, intelligence.confidence * 0.92)
        }
        if let audio, audio.key == resolved {
            confidence = min(1, confidence + audio.confidence * 0.08)
        }

        guard confidence >= 0.14 || resolvedValue >= 0.48 else {
            return heuristic.map {
                AdaptiveKeyDetection(key: $0.key, confidence: $0.confidence, source: .heuristic)
            }
        }

        if KeyChordAnalysis.isImplausibleLiveKeyCandidate(symbols: normalized, candidate: resolved) {
            return nil
        }

        let source: AdaptiveKeyDetection.Source =
            (audio?.key == resolved && (audio?.confidence ?? 0) >= 0.4 && confidence < 0.5)
            ? .audio
            : .ensemble
        return AdaptiveKeyDetection(key: resolved, confidence: confidence, source: source)
    }

    private func freshAudioHint() -> AudioKeyHint? {
        guard let hint = audioKeyHint else { return nil }
        // Discard stale chroma (>8s) so silent/old audio doesn't poison detection.
        guard Date().timeIntervalSince1970 - hint.updatedAt <= 8 else {
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
        symbols.map { LiveRing.normalize($0) }.filter { !$0.isEmpty }
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
