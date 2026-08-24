//
//  SoloDrumPolish.swift
//  Chordyx
//
//  Pure helpers for professional Solo Drums: tempo EMA, section dynamics,
//  genre → instrument category, hybrid voice bias.
//

import Foundation

enum SoloDrumPolish {
    /// Exponential blend toward a live tempo estimate (musical follow, not jump cuts).
    static func emaBPM(previous: Double?, sample: Double, alpha: Double = 0.28) -> Double {
        let a = min(1, max(0.05, alpha))
        guard let previous else { return sample }
        return previous * (1 - a) + sample * a
    }

    /// Round to nearest 0.5 BPM for stable UI / metronome sync.
    static func roundHalfBPM(_ bpm: Double) -> Double {
        (bpm * 2).rounded() / 2
    }

    /// Volume scale by chart section — verse softer, chorus more open.
    static func sectionDynamicsScale(for kind: WorshipSectionKind?) -> Float {
        guard let kind else { return 1.0 }
        switch kind {
        case .intro: return 0.78
        case .verse: return 0.86
        case .preChorus: return 0.94
        case .chorus: return 1.08
        case .bridge: return 0.96
        case .tag: return 0.9
        case .ending: return 0.72
        case .custom: return 1.0
        }
    }

    /// Suggest a kit/perc family from detected groove / worldwide genre.
    static func suggestedInstrumentCategory(
        style: LiveMusicStyle,
        globalGenre: GlobalMusicGenre? = nil
    ) -> SoloDrumInstrumentCategory {
        if let region = globalGenre?.region {
            switch region {
            case .latinCaribbean:
                if style == .bolero || style == .bossaNova { return .lightPercussion }
                if style == .songo || style == .salsa || style == .montuno { return .percussion }
                if style == .merengue { return .percussion }
                return .percussion
            case .africa, .middleEast:
                return .cajon
            case .eastAsia, .southAsia:
                return .bellsAndMetals
            case .worshipGospel:
                return style == .brushWaltz ? .brushes : .softKit
            default:
                break
            }
        }

        switch style {
        case .worshipBallad, .softPulse:
            return .softKit
        case .brushWaltz, .jazzSwing:
            return .brushes
        case .gospelGroove, .popRock, .rockDrive, .halfTimeRock, .countryTrain:
            return .drums
        case .funkGroove, .rbSoul, .edmPulse, .discoFour, .hipHopBoomBap, .trapHalftime:
            return .electronic
        case .bluesShuffle:
            return .softKit
        case .bolero, .bossaNova, .bachata:
            return .lightPercussion
        case .merengue, .cumbia, .chaCha, .soca, .dembow:
            return .percussion
        case .montuno, .salsa, .songo:
            return .percussion
        case .reggaeOneDrop, .afrobeat:
            return .cajon
        case .unknown:
            return .drums
        }
    }

    /// Extra body ducking under fills for lighter instrument families.
    static func hybridFillSoftening(for category: SoloDrumInstrumentCategory) -> Float {
        switch category {
        case .drums, .electronic: return 1.0
        case .softKit, .brushes: return 0.85
        case .percussion, .cajon: return 0.9
        case .lightPercussion, .bellsAndMetals: return 0.72
        }
    }

    /// Reverb wet/dry hint (0…100) so categories feel like different rooms.
    static func reverbWetDry(for category: SoloDrumInstrumentCategory) -> Float {
        switch category {
        case .drums: return 16
        case .softKit, .brushes: return 22
        case .electronic: return 10
        case .percussion, .cajon: return 14
        case .lightPercussion: return 18
        case .bellsAndMetals: return 20
        }
    }

    /// Phrases where live tempo nudges should pause (keep the fill intact).
    static func shouldHoldTempoFollow(during phrase: DrumPhraseKind) -> Bool {
        switch phrase {
        case .fill, .intro, .ending, .breakdown:
            return true
        case .grooveA, .grooveB:
            return false
        }
    }
}
