//
//  TonalScaleIntelligence.swift
//  Chordyx
//
//  Joint tonic + scale/mode detection from chroma and/or chord symbols.
//  Goes beyond “key letter” — major, minor flavors, church modes, pentatonic, blues.
//

import Foundation

nonisolated enum TonalScaleIntelligence: Sendable {

    /// Rank every (tonic × scale) against a normalized 12-bin chroma vector.
    static func detectFromChroma(_ chroma: [Double]) -> DetectedTonalCenter? {
        guard chroma.count == 12 else { return nil }
        let sum = chroma.reduce(0, +)
        guard sum > 0.01 else { return nil }
        let observed = chroma.map { $0 / sum }

        var best: (key: MusicalKey, scale: MusicalScaleQuality, score: Double)?
        var keyMass = Dictionary(uniqueKeysWithValues: MusicalKey.allCases.map { ($0, 0.0) })

        for key in MusicalKey.allCases {
            let tonic = key.pitchClass
            // Prefer tonics that actually ring in the spectrum (Auto-Key style).
            let tonicEnergy = observed[tonic]
            let fifthEnergy = observed[(tonic + 7) % 12]
            let thirdMaj = observed[(tonic + 4) % 12]
            let thirdMin = observed[(tonic + 3) % 12]
            let tonicBias = tonicEnergy * 0.55 + fifthEnergy * 0.28 + max(thirdMaj, thirdMin) * 0.18

            for scale in MusicalScaleQuality.allCases {
                let profile = rotatedProfile(scale.profileWeights, tonic: tonic)
                var corr = pearson(observed, profile)
                // Scale-tone coverage: reward energy inside the scale, penalize outside.
                let coverage = scaleCoverageScore(observed: observed, tonic: tonic, scale: scale)
                corr = corr * 0.72 + coverage * 0.28 + tonicBias * 0.45
                keyMass[key, default: 0] += max(0, corr)
                if best == nil || corr > best!.score {
                    best = (key, scale, corr)
                }
            }
        }

        guard let best, best.score > 0.05 else { return nil }

        let minK = keyMass.values.min() ?? 0
        let maxK = keyMass.values.max() ?? 0
        if maxK > minK {
            for key in MusicalKey.allCases {
                keyMass[key] = ((keyMass[key] ?? 0) - minK) / (maxK - minK)
            }
        }

        var runnerUp = 0.0
        for key in MusicalKey.allCases {
            let tonic = key.pitchClass
            let tonicEnergy = observed[tonic]
            let fifthEnergy = observed[(tonic + 7) % 12]
            let thirdMaj = observed[(tonic + 4) % 12]
            let thirdMin = observed[(tonic + 3) % 12]
            let tonicBias = tonicEnergy * 0.55 + fifthEnergy * 0.28 + max(thirdMaj, thirdMin) * 0.18
            for scale in MusicalScaleQuality.allCases {
                if key == best.key, scale == best.scale { continue }
                let corr = pearson(observed, rotatedProfile(scale.profileWeights, tonic: tonic))
                let coverage = scaleCoverageScore(observed: observed, tonic: tonic, scale: scale)
                let score = corr * 0.72 + coverage * 0.28 + tonicBias * 0.45
                runnerUp = max(runnerUp, score)
            }
        }
        let margin = best.score - runnerUp
        let confidence = min(1, max(0.08, margin * 1.35 + 0.12))

        let pcs = best.scale.intervals.map { ($0 + best.key.pitchClass) % 12 }
        return DetectedTonalCenter(
            key: best.key,
            scale: best.scale,
            confidence: confidence,
            relativeKey: best.scale.relativeKey(of: best.key),
            scalePitchClasses: pcs,
            scores: keyMass
        )
    }

    private static func scaleCoverageScore(
        observed: [Double],
        tonic: Int,
        scale: MusicalScaleQuality
    ) -> Double {
        let inSet = Set(scale.intervals.map { ($0 + tonic) % 12 })
        var inside = 0.0
        var outside = 0.0
        for pc in 0..<12 {
            if inSet.contains(pc) {
                inside += observed[pc]
            } else {
                outside += observed[pc]
            }
        }
        return inside - outside * 0.85
    }

    /// Infer scale/mode for a known tonic from chord symbols (audio can refine later).
    static func inferScale(from symbols: [String], tonic: MusicalKey) -> MusicalScaleQuality {
        let normalized = symbols.map { LiveRing.normalize($0) }.filter { !$0.isEmpty }
        guard !normalized.isEmpty else { return .major }

        var majorish = 0.0
        var minorish = 0.0
        var dominantI = 0.0
        var flatSeven = 0.0
        var sharpFour = 0.0
        var flatTwo = 0.0
        var raisedSeven = 0.0
        var dimish = 0.0

        let tonicPC = tonic.pitchClass
        for (index, symbol) in normalized.enumerated() {
            guard let parsed = Transposer.parse(symbol),
                  let root = Transposer.pitchClass(ofRoot: parsed.root) else { continue }
            let weight = 1.0 + Double(index) / Double(max(normalized.count, 1)) * 0.4
            let deg = (root - tonicPC + 12) % 12
            let s = parsed.suffix.lowercased()
            let isMinor = s.hasPrefix("m") && !s.hasPrefix("maj")
            let isDom = (s.hasPrefix("7") || s.contains("9") || s.contains("11") || s.contains("13"))
                && !s.contains("maj")
            let isMaj = !isMinor && !s.contains("dim") && !s.contains("°")

            if deg == 0 {
                if isDom { dominantI += weight * 2 }
                if isMinor { minorish += weight * 2.2 }
                if isMaj { majorish += weight * 2.0 }
            }
            if deg == 10 { flatSeven += weight }
            if deg == 6 { sharpFour += weight }
            if deg == 1 { flatTwo += weight }
            if deg == 11 {
                if isMaj || isDom { raisedSeven += weight }
            }
            if s.contains("dim") || s.contains("°") { dimish += weight }
            if isMinor { minorish += weight * 0.6 }
            if isMaj { majorish += weight * 0.55 }
            if isDom, deg == 7 { raisedSeven += weight * 0.8 } // V7 → harmonic minor / major
        }

        // Characteristic mode decisions (ordered by specificity).
        if sharpFour >= 1.2, majorish >= minorish { return .lydian }
        if flatTwo >= 1.0, minorish >= majorish { return .phrygian }
        if dominantI >= 1.4 { return .mixolydian }
        if flatSeven >= 1.4, majorish > minorish * 1.05 { return .mixolydian }
        if flatSeven >= 1.2, minorish >= majorish, raisedSeven < 0.8 { return .dorian }
        if raisedSeven >= 1.2, minorish > majorish { return .harmonicMinor }
        if minorish > majorish * 1.15 {
            if dimish >= 0.8 { return .harmonicMinor }
            return .naturalMinor
        }
        if majorish >= minorish { return .major }
        return .naturalMinor
    }

    /// Best joint answer from chords alone (tonic from existing ensemble + scale inference).
    static func detectFromChords(
        symbols: [String],
        preferredKey: MusicalKey,
        keyScores: [MusicalKey: Double] = [:]
    ) -> DetectedTonalCenter {
        let scale = inferScale(from: symbols, tonic: preferredKey)
        let pcs = scale.intervals.map { ($0 + preferredKey.pitchClass) % 12 }
        let conf = max(0.35, keyScores[preferredKey] ?? 0.55)
        return DetectedTonalCenter(
            key: preferredKey,
            scale: scale,
            confidence: min(1, conf),
            relativeKey: scale.relativeKey(of: preferredKey),
            scalePitchClasses: pcs,
            scores: keyScores.isEmpty
                ? [preferredKey: conf]
                : keyScores
        )
    }

    /// Fuse audio scale estimate with chord-inferred scale for the same tonic.
    static func fuse(
        audio: DetectedTonalCenter?,
        chords: DetectedTonalCenter?,
        preferChordTonic: MusicalKey?
    ) -> DetectedTonalCenter? {
        if let prefer = preferChordTonic {
            if let chords, chords.key == prefer { return chords }
            if let audio, audio.key == prefer {
                let scale = chords?.scale ?? audio.scale
                return DetectedTonalCenter(
                    key: prefer,
                    scale: scale,
                    confidence: max(audio.confidence, chords?.confidence ?? 0),
                    relativeKey: scale.relativeKey(of: prefer),
                    scalePitchClasses: scale.intervals.map { ($0 + prefer.pitchClass) % 12 },
                    scores: audio.scores
                )
            }
            if let chords { return chords }
        }
        if let audio, let chords {
            // Same tonic → prefer chord scale if distinctive, else audio.
            if audio.key == chords.key {
                let scale = chords.scale == .major || chords.scale == .naturalMinor
                    ? (audio.scale.confidenceBoosting(over: chords.scale) ? audio.scale : chords.scale)
                    : chords.scale
                return DetectedTonalCenter(
                    key: audio.key,
                    scale: scale,
                    confidence: max(audio.confidence, chords.confidence),
                    relativeKey: scale.relativeKey(of: audio.key),
                    scalePitchClasses: scale.intervals.map { ($0 + audio.key.pitchClass) % 12 },
                    scores: audio.scores
                )
            }
            // Different tonics — trust higher confidence; chords win ties when evidence-rich.
            if chords.confidence + 0.06 >= audio.confidence { return chords }
            return audio
        }
        return audio ?? chords
    }

    // MARK: - Math

    private static func rotatedProfile(_ relative: [Double], tonic: Int) -> [Double] {
        var out = [Double](repeating: 0, count: 12)
        for pc in 0..<12 {
            out[pc] = relative[(pc - tonic + 12) % 12]
        }
        return out
    }

    private static func pearson(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        let n = Double(a.count)
        let meanA = a.reduce(0, +) / n
        let meanB = b.reduce(0, +) / n
        var num = 0.0
        var denA = 0.0
        var denB = 0.0
        for i in 0..<a.count {
            let da = a[i] - meanA
            let db = b[i] - meanB
            num += da * db
            denA += da * da
            denB += db * db
        }
        let den = sqrt(denA * denB)
        return den > 0 ? num / den : 0
    }
}

private nonisolated extension MusicalScaleQuality {
    /// Prefer more specific modes from audio when chords only said major/minor.
    func confidenceBoosting(over other: MusicalScaleQuality) -> Bool {
        let specific: Set<MusicalScaleQuality> = [
            .dorian, .phrygian, .lydian, .mixolydian, .locrian,
            .harmonicMinor, .melodicMinor, .blues, .majorPentatonic, .minorPentatonic
        ]
        return specific.contains(self) && (other == .major || other == .naturalMinor)
    }
}
