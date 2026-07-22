//
//  KeyChordAnalysis.swift
//  Chordyx
//
//  Pure key/chord analysis helpers — safe to call from any isolation domain.
//

import Foundation

enum KeyChordAnalysis: Sendable {
    private static let majorProfile: [Double] = [
        6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88
    ]
    private static let minorProfile: [Double] = [
        6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17
    ]

    static func krumhanselSchmuckler(from symbols: [String]) -> [MusicalKey: Double] {
        var histogram = [Double](repeating: 0, count: 12)
        for (index, symbol) in symbols.enumerated() {
            guard let parsed = Transposer.parse(symbol),
                  let pc = Transposer.pitchClass(ofRoot: parsed.root) else { continue }
            let recency = 1.0 + Double(index) / Double(max(symbols.count, 1)) * 0.5
            let qualityWeight = qualityWeight(for: parsed.suffix)
            histogram[pc] += recency * qualityWeight
        }
        let sum = histogram.reduce(0, +)
        guard sum > 0 else { return [:] }
        for index in 0..<12 { histogram[index] /= sum }

        var keyScores = [MusicalKey: Double]()
        for key in MusicalKey.allCases {
            let tonic = key.pitchClass
            var majorCorr = 0.0
            var minorCorr = 0.0
            for pc in 0..<12 {
                let rotatedMajor = majorProfile[(pc - tonic + 12) % 12]
                let rotatedMinor = minorProfile[(pc - tonic + 12) % 12]
                majorCorr += histogram[pc] * rotatedMajor
                minorCorr += histogram[pc] * rotatedMinor
            }
            keyScores[key] = max(majorCorr, minorCorr) / 6.35
        }
        return keyScores
    }

    static func fingerprint(from symbols: [String]) -> String {
        var tokens: [String] = []
        for symbol in symbols {
            guard let parsed = Transposer.parse(symbol),
                  let pc = Transposer.pitchClass(ofRoot: parsed.root) else { continue }
            let q = qualityToken(parsed.suffix)
            tokens.append("\(pc):\(q)")
        }
        return tokens.sorted().joined(separator: "|")
    }

    /// Ordered root+quality tokens (keeps sequence for progression matching).
    static func orderedTokens(from symbols: [String]) -> [String] {
        symbols.compactMap { symbol -> String? in
            guard let parsed = Transposer.parse(symbol),
                  let pc = Transposer.pitchClass(ofRoot: parsed.root) else { return nil }
            return "\(pc):\(qualityToken(parsed.suffix))"
        }
    }

    /// How well `live` matches a known library progression (0…1).
    /// Prefers ordered contiguous runs, then unique-chord overlap.
    static func progressionSimilarity(live: [String], library: [String]) -> Double {
        let liveTokens = orderedTokens(from: live)
        let libraryTokens = orderedTokens(from: library)
        guard liveTokens.count >= 3, libraryTokens.count >= 3 else { return 0 }

        let liveWindow = Array(liveTokens.suffix(min(16, liveTokens.count)))
        let absolute = absoluteSimilarity(liveWindow: liveWindow, libraryTokens: libraryTokens)
        let relative = bestRelativeMatch(liveWindow: liveWindow, libraryTokens: libraryTokens).score
        return max(absolute, relative)
    }

    /// Best library progression key for the live sequence, if similarity is strong enough.
    /// When the match is transpose-related, returns the live key (library key + interval).
    static func bestLibraryKeyMatch(
        liveSymbols: [String],
        library: [(name: String, key: MusicalKey, symbols: [String])]
    ) -> (key: MusicalKey, confidence: Double, name: String, similarity: Double)? {
        var best: (key: MusicalKey, confidence: Double, name: String, similarity: Double)?
        for entry in library {
            let liveTokens = orderedTokens(from: liveSymbols)
            let libraryTokens = orderedTokens(from: entry.symbols)
            guard liveTokens.count >= 3, libraryTokens.count >= 3 else { continue }

            let liveWindow = Array(liveTokens.suffix(min(16, liveTokens.count)))
            let absolute = absoluteSimilarity(liveWindow: liveWindow, libraryTokens: libraryTokens)
            let relative = bestRelativeMatch(liveWindow: liveWindow, libraryTokens: libraryTokens)
            let similarity = max(absolute, relative.score)
            guard similarity >= 0.58 else { continue }

            let liveFP = fingerprint(from: Array(liveSymbols.suffix(12)))
            let libFP = fingerprint(from: entry.symbols)
            let exactBoost = liveFP == libFP ? 0.12 : 0
            let confidence = min(0.96, 0.55 + similarity * 0.40 + exactBoost)

            let resolvedKey: MusicalKey
            if absolute >= relative.score - 0.02 {
                resolvedKey = entry.key
            } else {
                let livePC = (entry.key.pitchClass + relative.shift) % 12
                resolvedKey = MusicalKey.allCases.first { $0.pitchClass == livePC } ?? entry.key
            }

            if best == nil || similarity > best!.similarity {
                best = (resolvedKey, confidence, entry.name, similarity)
            }
        }
        return best
    }

    private static func absoluteSimilarity(liveWindow: [String], libraryTokens: [String]) -> Double {
        let liveSet = Set(liveWindow)
        let librarySet = Set(libraryTokens)
        let intersection = liveSet.intersection(librarySet).count
        let union = liveSet.union(librarySet).count
        let jaccard = union == 0 ? 0.0 : Double(intersection) / Double(union)
        let contiguous = maxContiguousOverlap(liveWindow, libraryTokens)
        let contiguousScore = Double(contiguous) / Double(min(liveWindow.count, libraryTokens.count, 8))
        return min(1, jaccard * 0.45 + contiguousScore * 0.55)
    }

    private static func bestRelativeMatch(
        liveWindow: [String],
        libraryTokens: [String]
    ) -> (score: Double, shift: Int) {
        var bestScore = 0.0
        var bestShift = 0
        for shift in 0..<12 {
            let shiftedLive = liveWindow.map { token -> String in
                let parts = token.split(separator: ":")
                guard parts.count == 2, let pc = Int(parts[0]) else { return token }
                return "\((pc - shift + 12) % 12):\(parts[1])"
            }
            let score = absoluteSimilarity(liveWindow: shiftedLive, libraryTokens: libraryTokens)
            if score > bestScore {
                bestScore = score
                bestShift = shift
            }
        }
        return (bestScore, bestShift)
    }

    private static func maxContiguousOverlap(_ a: [String], _ b: [String]) -> Int {
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        var best = 0
        let doubled = b + b
        for startA in 0..<a.count {
            for startB in 0..<b.count {
                var length = 0
                while startA + length < a.count,
                      startB + length < doubled.count,
                      a[startA + length] == doubled[startB + length] {
                    length += 1
                }
                best = max(best, length)
            }
        }
        return best
    }

    private static func qualityWeight(for suffix: String) -> Double {
        let s = suffix.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if s.isEmpty || s.hasPrefix("maj") || s == "6" || s.hasPrefix("add") || s.contains("sus") { return 1.0 }
        if s.hasPrefix("m") && !s.hasPrefix("maj") { return 1.15 }
        if s.hasPrefix("7") || s.contains("9") || s.contains("13") { return 1.05 }
        if s.contains("dim") || s == "m7b5" { return 0.85 }
        return 0.95
    }

    private static func qualityToken(_ suffix: String) -> String {
        let s = suffix.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if s.hasPrefix("m") && !s.hasPrefix("maj") { return "m" }
        if s.hasPrefix("7") || s.contains("9") { return "7" }
        if s.contains("dim") { return "d" }
        return "M"
    }
}
