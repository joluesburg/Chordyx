//
//  MusicalScaleQuality.swift
//  Chordyx
//
//  Detected scale / mode quality for Auto AI (key + scale, not tonic alone).
//

import Foundation

/// Musical scale or mode identified with the live tonal center.
nonisolated enum MusicalScaleQuality: String, Codable, CaseIterable, Identifiable, Sendable {
    case major
    case naturalMinor
    case harmonicMinor
    case melodicMinor
    case dorian
    case phrygian
    case lydian
    case mixolydian
    case locrian
    case majorPentatonic
    case minorPentatonic
    case blues

    var id: String { rawValue }

    /// Full localized name (“major”, “Dorian”, …).
    var localizedName: String {
        switch self {
        case .major: String(localized: "major")
        case .naturalMinor: String(localized: "natural minor")
        case .harmonicMinor: String(localized: "harmonic minor")
        case .melodicMinor: String(localized: "melodic minor")
        case .dorian: String(localized: "Dorian")
        case .phrygian: String(localized: "Phrygian")
        case .lydian: String(localized: "Lydian")
        case .mixolydian: String(localized: "Mixolydian")
        case .locrian: String(localized: "Locrian")
        case .majorPentatonic: String(localized: "major pentatonic")
        case .minorPentatonic: String(localized: "minor pentatonic")
        case .blues: String(localized: "blues")
        }
    }

    /// Short badge (“maj”, “min”, “dor”…).
    var shortLabel: String {
        switch self {
        case .major: String(localized: "maj")
        case .naturalMinor, .harmonicMinor, .melodicMinor: String(localized: "min")
        case .dorian: "Dor"
        case .phrygian: "Phr"
        case .lydian: "Lyd"
        case .mixolydian: "Mix"
        case .locrian: "Loc"
        case .majorPentatonic: "Maj5"
        case .minorPentatonic: "Min5"
        case .blues: "Blues"
        }
    }

    /// Pitch-class intervals from tonic (0…11).
    var intervals: [Int] {
        switch self {
        case .major: [0, 2, 4, 5, 7, 9, 11]
        case .naturalMinor: [0, 2, 3, 5, 7, 8, 10]
        case .harmonicMinor: [0, 2, 3, 5, 7, 8, 11]
        case .melodicMinor: [0, 2, 3, 5, 7, 9, 11]
        case .dorian: [0, 2, 3, 5, 7, 9, 10]
        case .phrygian: [0, 1, 3, 5, 7, 8, 10]
        case .lydian: [0, 2, 4, 6, 7, 9, 11]
        case .mixolydian: [0, 2, 4, 5, 7, 9, 10]
        case .locrian: [0, 1, 3, 5, 6, 8, 10]
        case .majorPentatonic: [0, 2, 4, 7, 9]
        case .minorPentatonic: [0, 3, 5, 7, 10]
        case .blues: [0, 3, 5, 6, 7, 10]
        }
    }

    /// KS-style probe weights for chroma correlation (length 12, relative to tonic).
    var profileWeights: [Double] {
        var w = [Double](repeating: 0.15, count: 12)
        let core = intervals
        for (index, interval) in core.enumerated() {
            // Emphasize tonic / fifth / third.
            let boost: Double
            switch interval {
            case 0: boost = 6.4
            case 7: boost = 5.2
            case 3, 4: boost = 4.4
            case 5, 9, 10, 11, 2, 1, 6, 8: boost = 3.2 - Double(index) * 0.05
            default: boost = 2.4
            }
            w[interval] = max(w[interval], boost)
        }
        // Characteristic tones get an extra bump so modes separate.
        switch self {
        case .lydian: w[6] = 5.0
        case .mixolydian: w[10] = 4.8
        case .dorian: w[9] = 4.6; w[10] = 3.8
        case .phrygian: w[1] = 5.0
        case .locrian: w[6] = 4.6; w[1] = 4.2
        case .harmonicMinor: w[11] = 5.0; w[8] = 4.2
        case .melodicMinor: w[9] = 4.4; w[11] = 4.6
        case .blues: w[6] = 4.8; w[3] = 4.6
        case .majorPentatonic, .minorPentatonic:
            for i in 0..<12 where !core.contains(i) { w[i] = 0.05 }
        default: break
        }
        return w
    }

    var isMinorFamily: Bool {
        switch self {
        case .naturalMinor, .harmonicMinor, .melodicMinor, .dorian, .phrygian, .locrian, .minorPentatonic, .blues:
            true
        default:
            false
        }
    }

    /// Relative major/minor letter for the same diatonic collection (when applicable).
    func relativeKey(of tonic: MusicalKey) -> MusicalKey? {
        let pc: Int
        switch self {
        case .major, .lydian, .mixolydian, .majorPentatonic:
            pc = (tonic.pitchClass + 9) % 12 // relative minor
        case .naturalMinor, .harmonicMinor, .melodicMinor, .dorian, .phrygian, .minorPentatonic, .blues:
            pc = (tonic.pitchClass + 3) % 12 // relative major
        case .locrian:
            return nil
        }
        return MusicalKey.allCases.first { $0.pitchClass == pc }
    }
}

/// Full Auto AI tonal answer: tonic + scale/mode + confidence.
nonisolated struct DetectedTonalCenter: Equatable, Sendable {
    let key: MusicalKey
    let scale: MusicalScaleQuality
    let confidence: Double
    let relativeKey: MusicalKey?
    let scalePitchClasses: [Int]
    let scores: [MusicalKey: Double]

    var displayScaleName: String { scale.localizedName }

    /// Safe off the main actor (audio / MIR). Uses letter names, not solfège.
    var labeled: String {
        "\(key.displayName) \(scale.localizedName)"
    }
}
