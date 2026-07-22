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
