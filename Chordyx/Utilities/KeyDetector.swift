//
//  KeyDetector.swift
//  Chordyx
//
//  Infers song key from live-played chord symbols (heuristic layer).
//  Session code should prefer AdaptiveKeyLearningEngine for fused AI detection.
//

import Foundation

/// Infers the song key from a sequence of live-played chord symbols.
enum KeyDetector {
    struct Result: Equatable {
        let key: MusicalKey
        /// 0…1 — higher means the best key fits the chords much better than the runner-up.
        let confidence: Double
    }

    private enum Quality {
        case major
        case minor
        case dominant
        case diminished
        case other
    }

    /// Minimum unique chord observations before returning a result.
    private static let minimumSymbols = 3

    static func detect(from symbols: [String]) -> Result? {
        let normalized = symbols.map { LiveRing.normalize($0) }.filter { !$0.isEmpty }
        guard normalized.count >= minimumSymbols else { return nil }

        var scores = [MusicalKey: Double]()
        for key in MusicalKey.allCases {
            scores[key] = score(symbols: normalized, for: key)
        }

        let ksScores = KeyChordAnalysis.krumhanselSchmuckler(from: normalized)
        for key in MusicalKey.allCases {
            scores[key, default: 0] += (ksScores[key] ?? 0) * 2.8
        }

        let ranked = scores.sorted { $0.value > $1.value }
        guard let best = ranked.first, best.value > 0,
              ranked.count >= 2 else { return nil }

        let runnerUp = ranked[1].value
        let margin = best.value - runnerUp
        let confidence = min(1, max(0, margin / max(best.value, 1)))

        guard confidence >= 0.16 || best.value >= 3.8 else { return nil }

        return Result(key: best.key, confidence: confidence)
    }

    private static func score(symbols: [String], for key: MusicalKey) -> Double {
        var total = 0.0
        for (index, symbol) in symbols.enumerated() {
            guard let parsed = Transposer.parse(symbol),
                  let rootPC = Transposer.pitchClass(ofRoot: parsed.root) else { continue }

            let degree = (rootPC - key.pitchClass + 12) % 12
            let quality = Self.quality(of: parsed.suffix)
            let recency = 1.0 + (Double(index) / Double(max(symbols.count, 1))) * 0.35
            let isLast = index == symbols.count - 1
            let isFirst = index == 0
            total += recency * degreeScore(degree: degree, quality: quality, isLast: isLast, isFirst: isFirst)
        }
        return total
    }

    private static func degreeScore(degree: Int, quality: Quality, isLast: Bool, isFirst: Bool) -> Double {
        switch degree {
        case 0:
            switch quality {
            case .major:
                if isLast { return 2.65 }
                if isFirst { return 2.75 }
                return 2.4
            case .minor:
                if isLast { return 2.55 }
                if isFirst { return 2.65 }
                return 2.35
            default: return 0.6
            }
        case 2, 4, 9:
            return quality == .minor ? 2.2 : 0.55
        case 5:
            return quality == .major ? 2.1 : (quality == .minor ? 1.8 : 0.65)
        case 7:
            switch quality {
            case .major: return 2.0
            case .dominant: return 2.35
            case .minor: return 1.5
            default: return 0.7
            }
        case 11:
            return quality == .diminished ? 1.6 : 0.35
        case 10:
            return quality == .minor || quality == .major ? 1.1 : 0.45
        case 3:
            return quality == .major ? 1.0 : (quality == .minor ? 1.3 : 0.4)
        case 8:
            return quality == .minor ? 0.9 : 0.35
        default:
            return 0.25
        }
    }

    private static func quality(of suffix: String) -> Quality {
        let s = suffix.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if s.isEmpty || s.hasPrefix("maj") || s == "6" || s == "6/9" || s.hasPrefix("add")
            || s.contains("sus") || s == "5" {
            return .major
        }
        if s.hasPrefix("m") && !s.hasPrefix("maj") {
            return .minor
        }
        if s.contains("dim") || s == "m7b5" || s.contains("ø") {
            return .diminished
        }
        if s.hasPrefix("7") || s.hasSuffix("9") || s.contains("11") || s.contains("13") {
            return .dominant
        }
        return .other
    }
}
