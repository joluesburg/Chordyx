//
//  ProgressionInferenceEngine.swift
//  Chordyx
//
//  Infers a repeating chord progression from a live MIDI/piano timeline.
//  Consumes symbols + timestamps only — ready for a future audio chord source.
//

import Foundation

struct TimedChordChange: Equatable, Sendable {
    let symbol: String
    let normalized: String
    let time: TimeInterval
}

struct InferredProgression: Equatable, Sendable {
    /// Display spellings in cycle order (first occurrence spellings).
    let symbols: [String]
    let normalized: [String]
    /// 0…1
    let confidence: Double
    /// How many full cycles matched at the end of the window.
    let repetitions: Int
}

/// Detects repeating chord loops from stabilized live chord changes.
final class ProgressionInferenceEngine: @unchecked Sendable {
    static let applyConfidenceThreshold = 0.75
    static let defaultDebounce: TimeInterval = 0.15
    static let maxWindowSize = 24
    static let minCycleLength = 2
    static let maxCycleLength = 8

    private let debounce: TimeInterval
    private var pending: (symbol: String, normalized: String, time: TimeInterval)?
    private var lastCommittedNormalized: String?
    private var timeline: [TimedChordChange] = []
    private var canonicalByNormalized: [String: String] = [:]

    init(debounce: TimeInterval = ProgressionInferenceEngine.defaultDebounce) {
        self.debounce = debounce
    }

    var committedSymbols: [String] {
        timeline.map(\.symbol)
    }

    var committedNormalized: [String] {
        timeline.map(\.normalized)
    }

    func reset() {
        pending = nil
        lastCommittedNormalized = nil
        timeline.removeAll(keepingCapacity: true)
        canonicalByNormalized.removeAll(keepingCapacity: true)
    }

    /// Observes a live chord symbol at `time`. Returns the best current inference, if any.
    @discardableResult
    func observe(symbol: String, at time: TimeInterval) -> InferredProgression? {
        let trimmed = symbol.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = LiveRing.normalize(trimmed)
        guard !normalized.isEmpty else { return currentInference() }

        if normalized == lastCommittedNormalized {
            pending = nil
            return currentInference()
        }

        if let pending, pending.normalized == normalized {
            if time - pending.time >= debounce {
                commit(symbol: pending.symbol, normalized: pending.normalized, at: time)
                self.pending = nil
            }
            return currentInference()
        }

        pending = (trimmed, normalized, time)
        return currentInference()
    }

    /// Forces a pending candidate to commit (useful in tests / end of hold).
    @discardableResult
    func flush(at time: TimeInterval) -> InferredProgression? {
        guard let pending else { return currentInference() }
        if pending.normalized != lastCommittedNormalized {
            commit(symbol: pending.symbol, normalized: pending.normalized, at: time)
        }
        self.pending = nil
        return currentInference()
    }

    func currentInference() -> InferredProgression? {
        Self.infer(from: timeline, canonicalByNormalized: canonicalByNormalized)
    }

    // MARK: - Internals

    private func commit(symbol: String, normalized: String, at time: TimeInterval) {
        guard normalized != lastCommittedNormalized else { return }
        canonicalByNormalized[normalized] = symbol
        timeline.append(TimedChordChange(symbol: symbol, normalized: normalized, time: time))
        if timeline.count > Self.maxWindowSize {
            timeline.removeFirst(timeline.count - Self.maxWindowSize)
        }
        lastCommittedNormalized = normalized
    }

    static func infer(
        from timeline: [TimedChordChange],
        canonicalByNormalized: [String: String]
    ) -> InferredProgression? {
        let sequence = timeline.map(\.normalized)
        guard sequence.count >= minCycleLength * 2 else { return nil }

        var best: InferredProgression?

        for length in minCycleLength...min(maxCycleLength, sequence.count / 2) {
            if let candidate = exactLoop(in: sequence, length: length, canonical: canonicalByNormalized) {
                if isBetter(candidate, than: best) {
                    best = candidate
                }
            }
            if let candidate = loopAllowingOneSkip(in: sequence, length: length, canonical: canonicalByNormalized) {
                if isBetter(candidate, than: best) {
                    best = candidate
                }
            }
        }

        return best
    }

    private static func isBetter(_ candidate: InferredProgression, than best: InferredProgression?) -> Bool {
        guard let best else { return true }
        if abs(candidate.confidence - best.confidence) < 0.04 {
            // Prefer the smaller cycle when confidence is similar.
            if candidate.normalized.count != best.normalized.count {
                return candidate.normalized.count < best.normalized.count
            }
            return candidate.repetitions > best.repetitions
        }
        return candidate.confidence > best.confidence
    }

    private static func exactLoop(
        in sequence: [String],
        length: Int,
        canonical: [String: String]
    ) -> InferredProgression? {
        let n = sequence.count
        guard n >= length * 2 else { return nil }

        let pattern = Array(sequence[(n - length)..<n])
        var repetitions = 1
        var cursor = n - length
        while cursor >= length {
            let previous = Array(sequence[(cursor - length)..<cursor])
            if previous == pattern {
                repetitions += 1
                cursor -= length
            } else {
                break
            }
        }

        guard repetitions >= 2 else { return nil }
        return makeResult(pattern: pattern, repetitions: repetitions, canonical: canonical, noisePenalty: 0)
    }

    /// Tolerates a single passing chord interrupting an otherwise repeating cycle.
    private static func loopAllowingOneSkip(
        in sequence: [String],
        length: Int,
        canonical: [String: String]
    ) -> InferredProgression? {
        guard sequence.count >= length * 2 + 1 else { return nil }

        var best: InferredProgression?
        for skipIndex in 0..<sequence.count {
            var reduced = sequence
            reduced.remove(at: skipIndex)
            guard let candidate = exactLoop(in: reduced, length: length, canonical: canonical) else { continue }
            let penalized = InferredProgression(
                symbols: candidate.symbols,
                normalized: candidate.normalized,
                confidence: max(0, candidate.confidence - 0.08),
                repetitions: candidate.repetitions
            )
            if isBetter(penalized, than: best) {
                best = penalized
            }
        }
        return best
    }

    private static func makeResult(
        pattern: [String],
        repetitions: Int,
        canonical: [String: String],
        noisePenalty: Double
    ) -> InferredProgression {
        let symbols = pattern.map { canonical[$0] ?? $0 }
        let lengthBonus = min(0.1, Double(pattern.count) * 0.02)
        let repScore = 0.50 + Double(repetitions) * 0.14 + lengthBonus - noisePenalty
        let confidence = min(1.0, max(0, repScore))
        return InferredProgression(
            symbols: symbols,
            normalized: pattern,
            confidence: confidence,
            repetitions: repetitions
        )
    }
}
