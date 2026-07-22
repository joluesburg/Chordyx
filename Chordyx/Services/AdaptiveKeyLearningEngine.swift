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
        case ensemble
        case heuristic
    }
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

    private init() {
        // Fast local load only — iCloud resolution is async (ubiquity APIs can stall launch on Mac).
        applyStore(from: localStoreURL, startDownloadIfNeeded: false)
        ensureNeuralInitialized()
        resolveCloudStoreIfNeeded()
    }

    // MARK: - Public API

    func detect(from symbols: [String], sessionName: String?) -> AdaptiveKeyDetection? {
        let normalized = normalizedSymbols(symbols)
        guard normalized.count >= Self.minimumSymbols else { return nil }

        let fingerprint = KeyChordAnalysis.fingerprint(from: normalized)

        if let memoryHit = recallMemory(fingerprint: fingerprint, sessionName: sessionName) {
            return AdaptiveKeyDetection(key: memoryHit, confidence: 0.92, source: .memory)
        }

        let heuristic = KeyDetector.detect(from: normalized)
        let ks = KeyChordAnalysis.krumhanselSchmuckler(from: normalized)
        let neural = neuralScores(from: normalized)

        var blended = [MusicalKey: Double]()
        for key in MusicalKey.allCases {
            let h = heuristic?.key == key ? (heuristic?.confidence ?? 0) * 0.45 : 0
            let k = ks[key] ?? 0
            let n = neural[key] ?? 0
            blended[key] = h + k * 0.38 + n * 0.22
        }

        if let heuristic, blended[heuristic.key, default: 0] < 0.12 {
            blended[heuristic.key, default: 0] += heuristic.confidence * 0.28
        }

        let ranked = blended.sorted { $0.value > $1.value }
        guard let best = ranked.first, best.value > 0.22,
              ranked.count >= 2 else { return heuristic.map {
            AdaptiveKeyDetection(key: $0.key, confidence: $0.confidence, source: .heuristic)
        }}

        let runnerUp = ranked[1].value
        let margin = best.value - runnerUp
        let confidence = min(1, max(0.15, margin / max(best.value, 0.01)))

        guard confidence >= 0.14 || best.value >= 0.55 else {
            return heuristic.map {
                AdaptiveKeyDetection(key: $0.key, confidence: $0.confidence, source: .heuristic)
            }
        }

        return AdaptiveKeyDetection(key: best.key, confidence: confidence, source: .ensemble)
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
        if let exact = memory.first(where: { $0.fingerprint == fingerprint && $0.hitCount >= 1 }),
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

    // MARK: - Neural online learner

    private func ensureNeuralInitialized() {
        guard neuralWeights.isEmpty else { return }
        neuralWeights = (0..<12).map { row in
            (0..<24).map { col in
                let seed = sin(Float(row * 24 + col) * 0.37) * 0.08
                return row == col % 12 ? seed + 0.12 : seed
            }
        }
        neuralBias = [Float](repeating: 0, count: 12)
    }

    private func featureVector(from symbols: [String]) -> [Float] {
        var pcMajor = [Float](repeating: 0, count: 12)
        var pcMinor = [Float](repeating: 0, count: 12)
        for (index, symbol) in symbols.enumerated() {
            guard let parsed = Transposer.parse(symbol),
                  let pc = Transposer.pitchClass(ofRoot: parsed.root) else { continue }
            let weight = Float(1.0 + Double(index) / Double(max(symbols.count, 1)) * 0.4)
            let s = parsed.suffix.lowercased()
            if s.hasPrefix("m") && !s.hasPrefix("maj") {
                pcMinor[pc] += weight
            } else {
                pcMajor[pc] += weight
            }
        }
        let total = pcMajor.reduce(0, +) + pcMinor.reduce(0, +)
        if total > 0 {
            for i in 0..<12 {
                pcMajor[i] /= total
                pcMinor[i] /= total
            }
        }
        return pcMajor + pcMinor
    }

    private func neuralScores(from symbols: [String]) -> [MusicalKey: Double] {
        let features = featureVector(from: symbols)
        var logits = [Float](repeating: 0, count: 12)
        for row in 0..<12 {
            var sum = neuralBias[row]
            for col in 0..<24 {
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
        var logits = [Float](repeating: 0, count: 12)
        for row in 0..<12 {
            var sum = neuralBias[row]
            for col in 0..<24 {
                sum += neuralWeights[row][col] * features[col]
            }
            logits[row] = sum
        }
        let probs = softmax(logits)
        let target = targetKey.pitchClass
        for row in 0..<12 {
            let error = probs[row] - (row == target ? 1 : 0)
            neuralBias[row] -= learningRate * error
            for col in 0..<24 {
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
        neuralWeights = payload.neuralWeights
        neuralBias = payload.neuralBias
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
