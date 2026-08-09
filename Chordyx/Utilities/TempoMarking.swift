//
//  TempoMarking.swift
//  Chordyx
//
//  Classical tempo names for display (guest metronome, live groove sync).
//

import Foundation

enum TempoMarking: String, CaseIterable, Sendable {
    case grave
    case adagio
    case andante
    case moderato
    case allegretto
    case allegro
    case vivace
    case presto
    case prestissimo

    /// Nearest marking for a metronome BPM.
    static func forBPM(_ bpm: Double) -> TempoMarking {
        let value = Int(bpm.rounded())
        switch value {
        case ..<56: return .grave
        case 56..<72: return .adagio
        case 72..<92: return .andante
        case 92..<108: return .moderato
        case 108..<120: return .allegretto
        case 120..<168: return .allegro
        case 168..<184: return .vivace
        case 184..<208: return .presto
        default: return .prestissimo
        }
    }

    var label: String {
        switch self {
        case .grave: String(localized: "Grave")
        case .adagio: String(localized: "Adagio")
        case .andante: String(localized: "Andante")
        case .moderato: String(localized: "Moderato")
        case .allegretto: String(localized: "Allegretto")
        case .allegro: String(localized: "Allegro")
        case .vivace: String(localized: "Vivace")
        case .presto: String(localized: "Presto")
        case .prestissimo: String(localized: "Prestissimo")
        }
    }

    var bpmRangeLabel: String {
        switch self {
        case .grave: "40–56"
        case .adagio: "56–72"
        case .andante: "72–92"
        case .moderato: "92–108"
        case .allegretto: "108–120"
        case .allegro: "120–168"
        case .vivace: "168–184"
        case .presto: "184–208"
        case .prestissimo: "208+"
        }
    }
}

extension TempoMarking {
    static func caption(for bpm: Double) -> String {
        let marking = forBPM(bpm)
        return "\(marking.label) · \(Int(bpm.rounded())) BPM"
    }
}
