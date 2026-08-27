//
//  LiveKeyIntelligence.swift
//  Chordyx
//
//  Market-grade live key intelligence for Chordyx.
//  Fuses industry-standard tonal models used in MIR / DAWs / theory tools:
//  - Krumhansl–Schmuckler + Temperley / Aarden–Essen corpus profiles
//  - Harmonic-function & cadence scoring (ii–V–I, V–I, plagal)
//  - Circle-of-fifths proximity
//  - Global pop / worship progression templates (I–V–vi–IV, …)
//  - Lightweight HMM (Viterbi) key tracking over the live sequence
//
//  Pure analysis — safe from any isolation domain. Session code should call
//  AdaptiveKeyLearningEngine, which wraps this ensemble with memory + neural AI.
//

import Foundation

enum LiveKeyIntelligence: Sendable {

    struct Breakdown: Equatable, Sendable {
        let scores: [MusicalKey: Double]
        let bestKey: MusicalKey
        let confidence: Double
        let contributors: [String]
    }

    // MARK: - Corpus key profiles (normalized later by correlation)

    /// Classic Krumhansl–Kessler probe-tone ratings (major / minor).
    private static let krumhanslMajor: [Double] = [
        6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88
    ]
    private static let krumhanslMinor: [Double] = [
        6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17
    ]

    /// Temperley / Essen folk corpus–style profiles (stronger for song corpora / pop).
    private static let temperleyMajor: [Double] = [
        5.0, 2.0, 3.5, 2.0, 4.5, 4.0, 2.0, 4.5, 2.0, 3.5, 1.5, 4.0
    ]
    private static let temperleyMinor: [Double] = [
        5.0, 2.0, 3.5, 4.5, 2.0, 4.0, 2.0, 4.5, 3.5, 2.0, 1.5, 4.0
    ]

    /// Common relative progressions (scale degrees 0…11) seen in worship / pop / jazz.
    private static let templateProgressions: [[Int]] = [
        [0, 7, 9, 5],       // I V vi IV
        [9, 5, 0, 7],       // vi IV I V
        [0, 9, 5, 7],       // I vi IV V
        [0, 5, 7, 0],       // I IV V I
        [2, 7, 0],          // ii V I
        [2, 7, 4, 9],       // ii V iii vi (Am D Bm Em → G)
        [2, 7, 4, 9, 2, 7, 0], // Am D Bm Em Am D G → G
        [0, 7, 0],          // I V I
        [0, 5, 0],          // I IV I (plagal)
        [0, 7, 5, 0],       // I V IV I
        [5, 0, 7, 0],       // IV I V I
        [0, 2, 7, 0],       // I ii V I
        [9, 7, 0],          // vi V I
        [7, 5, 0],          // V IV I (C Bb F → F, not C)
        [5, 7, 0],          // IV V I
        [0, 10, 8, 7],      // Andalusian i–bVII–bVI–V (minor tonic letter)
        [9, 7, 5, 7],       // Am G F G → C
        [0, 10, 5, 7],      // I bVII IV V (mixolydish worship)
        [0, 5, 9, 7],       // I IV vi V
        [7, 0],             // V I
        [5, 0],             // IV I
    ]

    // MARK: - Public API

    /// Full multi-model scorecard for a live chord sequence.
    static func analyze(symbols: [String]) -> Breakdown? {
        let normalized = symbols.map { LiveRing.normalize($0) }.filter { !$0.isEmpty }
        guard normalized.count >= 3 else { return nil }

        var scores = Dictionary(uniqueKeysWithValues: MusicalKey.allCases.map { ($0, 0.0) })
        var contributors: [String] = []

        let ks = profileCorrelation(symbols: normalized, major: krumhanslMajor, minor: krumhanslMinor)
        blend(&scores, ks, weight: 1.15)
        contributors.append("Krumhansl–Schmuckler")

        let temperley = profileCorrelation(symbols: normalized, major: temperleyMajor, minor: temperleyMinor)
        blend(&scores, temperley, weight: 1.05)
        contributors.append("Temperley / corpus profiles")

        let functional = functionalHarmonyScores(symbols: normalized)
        blend(&scores, functional, weight: 1.35)
        contributors.append("Functional harmony + cadences")

        let fifths = circleOfFifthsScores(symbols: normalized)
        blend(&scores, fifths, weight: 0.85)
        contributors.append("Circle of fifths")

        let templates = progressionTemplateScores(symbols: normalized)
        blend(&scores, templates, weight: 1.25)
        contributors.append("Pop / worship templates")

        let hmm = hmmKeyTrackingScores(symbols: normalized)
        blend(&scores, hmm, weight: 1.10)
        contributors.append("HMM key tracking")

        // Phrase-end / last-chord tonic bias (common MIR prior for live locking).
        let phraseEnd = phraseEndTonicScores(symbols: normalized)
        blend(&scores, phraseEnd, weight: 0.75)
        contributors.append("Phrase-end tonic")

        let ranked = scores.sorted { $0.value > $1.value }
        guard let best = ranked.first, best.value > 0.01, ranked.count >= 2 else { return nil }
        let resolvedKey = KeyChordAnalysis.resolveLiveTonalCenter(
            symbols: normalized,
            scores: scores,
            currentBest: best.key
        )
        let runnerUp = ranked.first(where: { $0.key != resolvedKey })?.value ?? ranked[1].value
        let bestValue = max(scores[resolvedKey] ?? 0, best.value)
        let margin = bestValue - runnerUp
        let confidence = min(1, max(0.12, margin / max(bestValue, 0.01)))

        return Breakdown(
            scores: scores,
            bestKey: resolvedKey,
            confidence: confidence,
            contributors: contributors
        )
    }

    /// Convenience: best key only.
    static func detect(from symbols: [String]) -> (key: MusicalKey, confidence: Double)? {
        guard let breakdown = analyze(symbols: symbols) else { return nil }
        return (breakdown.bestKey, breakdown.confidence)
    }

    // MARK: - Profile correlation

    private static func profileCorrelation(
        symbols: [String],
        major: [Double],
        minor: [Double]
    ) -> [MusicalKey: Double] {
        var histogram = [Double](repeating: 0, count: 12)
        for (index, symbol) in symbols.enumerated() {
            guard let parsed = Transposer.parse(symbol),
                  let pc = Transposer.pitchClass(ofRoot: parsed.root) else { continue }
            let recency = 1.0 + Double(index) / Double(max(symbols.count, 1)) * 0.55
            histogram[pc] += recency * qualityWeight(for: parsed.suffix)
        }
        let sum = histogram.reduce(0, +)
        guard sum > 0 else { return [:] }
        for i in 0..<12 { histogram[i] /= sum }

        var scores = [MusicalKey: Double]()
        let majorPeak = major.max() ?? 1
        let minorPeak = minor.max() ?? 1
        for key in MusicalKey.allCases {
            let tonic = key.pitchClass
            var majorCorr = 0.0
            var minorCorr = 0.0
            for pc in 0..<12 {
                majorCorr += histogram[pc] * major[(pc - tonic + 12) % 12]
                minorCorr += histogram[pc] * minor[(pc - tonic + 12) % 12]
            }
            scores[key] = max(majorCorr / majorPeak, minorCorr / minorPeak)
        }
        return scores
    }

    // MARK: - Functional harmony

    private static func functionalHarmonyScores(symbols: [String]) -> [MusicalKey: Double] {
        var scores = Dictionary(uniqueKeysWithValues: MusicalKey.allCases.map { ($0, 0.0) })
        for key in MusicalKey.allCases {
            var total = 0.0
            for (index, symbol) in symbols.enumerated() {
                guard let parsed = Transposer.parse(symbol),
                      let root = Transposer.pitchClass(ofRoot: parsed.root) else { continue }
                let degree = (root - key.pitchClass + 12) % 12
                let quality = qualityClass(parsed.suffix)
                let recency = 1.0 + Double(index) / Double(max(symbols.count, 1)) * 0.4
                total += recency * functionWeight(degree: degree, quality: quality)

                if index > 0,
                   let prev = Transposer.parse(symbols[index - 1]),
                   let prevRoot = Transposer.pitchClass(ofRoot: prev.root) {
                    let prevDeg = (prevRoot - key.pitchClass + 12) % 12
                    total += cadenceBonus(from: prevDeg, to: degree, toQuality: quality) * recency
                }
            }
            scores[key] = total
        }
        return normalizeScores(scores)
    }

    private static func functionWeight(degree: Int, quality: QualityClass) -> Double {
        switch degree {
        case 0: // I / i
            switch quality {
            case .major, .dominant: return 3.2
            case .minor: return 3.0
            default: return 0.8
            }
        case 7: // V
            switch quality {
            case .dominant: return 3.1
            case .major: return 2.7
            case .minor: return 1.4
            default: return 0.9
            }
        case 5: // IV / iv
            return quality == .major ? 2.6 : (quality == .minor ? 2.2 : 0.9)
        case 9: // vi / VI
            return quality == .minor ? 2.5 : 1.2
        case 2: // ii
            return quality == .minor ? 2.4 : 0.8
        case 4: // iii
            return quality == .minor ? 1.6 : 0.7
        case 11: // vii°
            return quality == .diminished ? 2.0 : 0.5
        case 10: // bVII
            return quality == .major ? 1.5 : 0.6
        case 3: // bIII
            return quality == .major ? 1.3 : (quality == .minor ? 1.4 : 0.5)
        case 8: // bVI
            return quality == .major ? 1.2 : 0.5
        default:
            return 0.35
        }
    }

    private static func cadenceBonus(from: Int, to: Int, toQuality: QualityClass) -> Double {
        // Authentic V → I
        if from == 7, to == 0 { return toQuality == .major || toQuality == .minor ? 2.4 : 1.0 }
        // Plagal IV → I
        if from == 5, to == 0 { return 1.8 }
        // ii → V
        if from == 2, to == 7 { return 1.6 }
        // ii → V → (implied) handled pairwise
        // vi → V / vi → IV common in pop
        if from == 9, to == 7 { return 1.1 }
        if from == 9, to == 5 { return 1.0 }
        // V → vi deceptive
        if from == 7, to == 9 { return 1.2 }
        return 0
    }

    // MARK: - Circle of fifths

    /// Keys whose tonic is near the chord roots on the circle score higher.
    private static func circleOfFifthsScores(symbols: [String]) -> [MusicalKey: Double] {
        let roots = symbols.compactMap { symbol -> Int? in
            guard let parsed = Transposer.parse(symbol) else { return nil }
            return Transposer.pitchClass(ofRoot: parsed.root)
        }
        guard !roots.isEmpty else { return [:] }

        var scores = Dictionary(uniqueKeysWithValues: MusicalKey.allCases.map { ($0, 0.0) })
        for key in MusicalKey.allCases {
            let tonic = key.pitchClass
            var total = 0.0
            for (index, root) in roots.enumerated() {
                let fifthSteps = minFifthDistance(root, tonic)
                // 0 steps = tonic, 1 = V/IV, 2 = ii/vi neighborhood, etc.
                let proximity = max(0, 1.0 - Double(fifthSteps) * 0.22)
                let recency = 1.0 + Double(index) / Double(max(roots.count, 1)) * 0.35
                total += proximity * recency
            }
            scores[key] = total
        }
        return normalizeScores(scores)
    }

    private static func minFifthDistance(_ a: Int, _ b: Int) -> Int {
        let alongFifths = [0, 7, 2, 9, 4, 11, 6, 1, 8, 3, 10, 5]
        guard let ia = alongFifths.firstIndex(of: a),
              let ib = alongFifths.firstIndex(of: b) else { return 6 }
        let d = abs(ia - ib)
        return min(d, 12 - d)
    }

    // MARK: - Progression templates

    private static func progressionTemplateScores(symbols: [String]) -> [MusicalKey: Double] {
        let roots = symbols.compactMap { symbol -> Int? in
            guard let parsed = Transposer.parse(symbol) else { return nil }
            return Transposer.pitchClass(ofRoot: parsed.root)
        }
        guard roots.count >= 3 else { return [:] }

        var scores = Dictionary(uniqueKeysWithValues: MusicalKey.allCases.map { ($0, 0.0) })
        for key in MusicalKey.allCases {
            let degrees = roots.map { ($0 - key.pitchClass + 12) % 12 }
            var best = 0.0
            for template in templateProgressions {
                best = max(best, templateMatchScore(degrees: degrees, template: template))
            }
            scores[key] = best
        }
        return normalizeScores(scores)
    }

    private static func templateMatchScore(degrees: [Int], template: [Int]) -> Double {
        guard !template.isEmpty, degrees.count >= template.count else { return 0 }
        var best = 0
        let doubled = degrees + degrees // allow loop wrap
        for start in 0..<degrees.count {
            var length = 0
            while length < template.count,
                  start + length < doubled.count,
                  doubled[start + length] == template[length] {
                length += 1
            }
            best = max(best, length)
        }
        return Double(best) / Double(template.count)
    }

    // MARK: - Phrase-end tonic

    /// Prefer keys whose tonic matches the most recent strong arrival (I / i / V→I).
    private static func phraseEndTonicScores(symbols: [String]) -> [MusicalKey: Double] {
        guard let last = symbols.last,
              let parsed = Transposer.parse(last),
              let root = Transposer.pitchClass(ofRoot: parsed.root) else { return [:] }

        var scores = Dictionary(uniqueKeysWithValues: MusicalKey.allCases.map { ($0, 0.0) })
        let quality = qualityClass(parsed.suffix)
        for key in MusicalKey.allCases {
            let degree = (root - key.pitchClass + 12) % 12
            var score = 0.0
            if degree == 0 {
                score = quality == .minor ? 1.0 : 1.15
            } else if degree == 7 {
                score = 0.55 // lingering on V often precedes I
            } else if degree == 9, quality == .minor {
                // Ending on vi points to the relative MAJOR tonic (Bm → D), not V of Em (E).
                score = 0.35
            }
            // Relative major of a final minor chord (Bm → D gets +0.70).
            if quality == .minor {
                let relativeMajor = MusicalKey.allCases.first { $0.pitchClass == (root + 3) % 12 }
                if relativeMajor == key {
                    score = max(score, 0.70)
                }
            }
            if symbols.count >= 2,
               let prev = Transposer.parse(symbols[symbols.count - 2]),
               let prevRoot = Transposer.pitchClass(ofRoot: prev.root) {
                let prevDeg = (prevRoot - key.pitchClass + 12) % 12
                if prevDeg == 7, degree == 0 { score += 0.85 }
                if prevDeg == 5, degree == 0 { score += 0.55 }
            }
            scores[key] = score
        }
        return normalizeScores(scores)
    }

    // MARK: - HMM / Viterbi-style tracking

    /// Simple key HMM: emission = chord fit in key; transition prefers staying / moving by fifth.
    private static func hmmKeyTrackingScores(symbols: [String]) -> [MusicalKey: Double] {
        let keys = MusicalKey.allCases
        let n = keys.count
        guard symbols.count >= 3 else { return [:] }

        // Viterbi tables
        var vit = [[Double]](repeating: [Double](repeating: -1e9, count: n), count: symbols.count)
        var back = [[Int]](repeating: [Int](repeating: 0, count: n), count: symbols.count)

        for (ki, key) in keys.enumerated() {
            vit[0][ki] = logEmission(symbol: symbols[0], key: key)
        }

        for t in 1..<symbols.count {
            for (kj, keyJ) in keys.enumerated() {
                let emit = logEmission(symbol: symbols[t], key: keyJ)
                var best = -1e9
                var bestI = 0
                for (ki, keyI) in keys.enumerated() {
                    let trans = logTransition(from: keyI, to: keyJ)
                    let score = vit[t - 1][ki] + trans + emit
                    if score > best {
                        best = score
                        bestI = ki
                    }
                }
                vit[t][kj] = best
                back[t][kj] = bestI
            }
        }

        // Path end distribution → soft scores
        let last = vit[symbols.count - 1]
        let maxLog = last.max() ?? 0
        let exps = last.map { exp($0 - maxLog) }
        let sum = exps.reduce(0, +)
        var scores = [MusicalKey: Double]()
        for (i, key) in keys.enumerated() {
            scores[key] = sum > 0 ? exps[i] / sum : 1.0 / Double(n)
        }

        // Also boost the single best path's final key
        if let bestIdx = last.indices.max(by: { last[$0] < last[$1] }) {
            scores[keys[bestIdx], default: 0] += 0.35
        }
        return normalizeScores(scores)
    }

    private static func logEmission(symbol: String, key: MusicalKey) -> Double {
        guard let parsed = Transposer.parse(symbol),
              let root = Transposer.pitchClass(ofRoot: parsed.root) else { return -4 }
        let degree = (root - key.pitchClass + 12) % 12
        let quality = qualityClass(parsed.suffix)
        let weight = functionWeight(degree: degree, quality: quality)
        return log(max(weight, 0.05))
    }

    private static func logTransition(from: MusicalKey, to: MusicalKey) -> Double {
        if from == to { return log(0.72) }
        let d = minFifthDistance(from.pitchClass, to.pitchClass)
        switch d {
        case 1: return log(0.14) // relative / dominant neighborhood
        case 2: return log(0.07)
        default: return log(0.02)
        }
    }

    // MARK: - Helpers

    private enum QualityClass {
        case major, minor, dominant, diminished, other
    }

    private static func qualityClass(_ suffix: String) -> QualityClass {
        let s = suffix.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if s.isEmpty || s.hasPrefix("maj") || s == "6" || s == "6/9" || s.hasPrefix("add")
            || s.contains("sus") || s == "5" {
            return .major
        }
        if s.hasPrefix("m") && !s.hasPrefix("maj") { return .minor }
        if s.contains("dim") || s == "m7b5" || s.contains("ø") { return .diminished }
        if s.hasPrefix("7") || s.contains("9") || s.contains("11") || s.contains("13") {
            return .dominant
        }
        return .other
    }

    private static func qualityWeight(for suffix: String) -> Double {
        switch qualityClass(suffix) {
        case .minor: return 1.15
        case .dominant: return 1.08
        case .diminished: return 0.85
        case .major: return 1.0
        case .other: return 0.95
        }
    }

    private static func blend(
        _ target: inout [MusicalKey: Double],
        _ source: [MusicalKey: Double],
        weight: Double
    ) {
        let normalized = normalizeScores(source)
        for key in MusicalKey.allCases {
            target[key, default: 0] += (normalized[key] ?? 0) * weight
        }
    }

    private static func normalizeScores(_ scores: [MusicalKey: Double]) -> [MusicalKey: Double] {
        let maxValue = scores.values.max() ?? 0
        guard maxValue > 0 else { return scores }
        var out = [MusicalKey: Double]()
        for (key, value) in scores {
            out[key] = value / maxValue
        }
        return out
    }
}
