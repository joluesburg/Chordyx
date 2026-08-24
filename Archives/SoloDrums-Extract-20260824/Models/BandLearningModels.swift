//
//  BandLearningModels.swift
//  Chordyx
//
//  Phase 3 — learned drum grids, bass lines, and auto-band playback.
//

import Foundation

enum AutoBandMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case off
    case drumsOnly
    case bassOnly
    case fullBand

    var id: String { rawValue }

    var label: String {
        switch self {
        case .off: String(localized: "Off")
        case .drumsOnly: String(localized: "Drums only")
        case .bassOnly: String(localized: "Bass only")
        case .fullBand: String(localized: "Drums + bass")
        }
    }

    var includesDrums: Bool {
        self == .drumsOnly || self == .fullBand
    }

    var includesBass: Bool {
        self == .bassOnly || self == .fullBand
    }
}

enum BassAccompanimentStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case worshipRoot
    case worshipPocket
    case slowBallad
    case latinTumbao
    case songoPulse
    case funkPocket
    case merengueOctave
    case walkSupport
    case learned

    var id: String { rawValue }

    var label: String {
        switch self {
        case .worshipRoot: String(localized: "Worship root (half notes)")
        case .worshipPocket: String(localized: "Worship pocket (8ths)")
        case .slowBallad: String(localized: "Slow ballad")
        case .latinTumbao: String(localized: "Latin tumbao")
        case .songoPulse: String(localized: "Songó tumbao")
        case .funkPocket: String(localized: "Funk pocket")
        case .merengueOctave: String(localized: "Merengue drive")
        case .walkSupport: String(localized: "Walk / support")
        case .learned: String(localized: "Learned line")
        }
    }

    var subtitle: String {
        switch self {
        case .worshipRoot: String(localized: "Root on 1 & 3, fifth on 2 & 4 — ballads")
        case .worshipPocket: String(localized: "Steady 8th-note pulse locked to the kick")
        case .slowBallad: String(localized: "Long root on 1, fifth on 3 — very slow songs")
        case .latinTumbao: String(localized: "2-3 tumbao with root and fifth")
        case .songoPulse: String(localized: "Syncopated Cuban bass locked to songó kick")
        case .funkPocket: String(localized: "On-the-one root with syncopated 16th pushes")
        case .merengueOctave: String(localized: "Driving merengue with octave jumps")
        case .walkSupport: String(localized: "Quarter-note walk for jazz and funk")
        case .learned: String(localized: "Captured from your bass send")
        }
    }

    var noteOffMilliseconds: UInt64 {
        switch self {
        case .slowBallad, .worshipRoot: 420
        case .songoPulse, .latinTumbao, .funkPocket: 240
        default: 220
        }
    }
}

/// One bar of drum hits learned from a live drum send (16 sixteenth steps).
struct LearnedDrumPattern: Codable, Equatable, Sendable {
    /// Index 0…15 → voice storage keys (`kick`, `snare`, …).
    var stepVoices: [[String]]
    var capturedAt: Date
    var barsAnalyzed: Int

    init(stepVoices: [[String]] = Array(repeating: [], count: 16), capturedAt: Date = Date(), barsAnalyzed: Int = 0) {
        self.stepVoices = stepVoices.count == 16 ? stepVoices : Self.emptyGrid()
        self.capturedAt = capturedAt
        self.barsAnalyzed = barsAnalyzed
    }

    static func emptyGrid() -> [[String]] {
        Array(repeating: [], count: 16)
    }

    func hits(for step: Int) -> Set<DrumVoice> {
        let index = ((step % 16) + 16) % 16
        guard stepVoices.indices.contains(index) else { return [] }
        return Set(stepVoices[index].compactMap { DrumVoice(storageKey: $0) })
    }

    func events(for step: Int) -> [DrumStepEvent] {
        hits(for: step).map { DrumStepEvent($0) }
    }

    var isEmpty: Bool {
        stepVoices.allSatisfy(\.isEmpty)
    }
}

/// One-bar bass template learned from a bass send or derived from chord roots.
struct LearnedBassLine: Codable, Equatable, Sendable {
    struct Event: Codable, Equatable, Sendable {
        var sixteenthStep: Int
        var midiNote: Int
        var velocity: Int
    }

    var events: [Event]
    var capturedAt: Date

    init(events: [Event] = [], capturedAt: Date = Date()) {
        self.events = events
        self.capturedAt = capturedAt
    }

    func notes(for step: Int) -> [Event] {
        let index = ((step % 16) + 16) % 16
        return events.filter { $0.sixteenthStep == index }
    }

    var isEmpty: Bool { events.isEmpty }
}

extension DrumVoice {
    var storageKey: String {
        switch self {
        case .kick: "kick"
        case .snare: "snare"
        case .hihatClosed: "hihat"
        case .hihatOpen: "hihatOpen"
        case .rim: "rim"
        case .ride: "ride"
        case .cowbell: "cowbell"
        case .conga: "conga"
        case .shaker: "shaker"
        case .tambourine: "tambourine"
        case .bongo: "bongo"
        }
    }

    init?(storageKey: String) {
        switch storageKey {
        case "kick": self = .kick
        case "snare": self = .snare
        case "hihat": self = .hihatClosed
        case "hihatOpen": self = .hihatOpen
        case "rim": self = .rim
        case "ride": self = .ride
        case "cowbell": self = .cowbell
        case "conga": self = .conga
        case "shaker": self = .shaker
        case "tambourine": self = .tambourine
        case "bongo": self = .bongo
        default: return nil
        }
    }
}

enum BassHarmony {
    /// Pitch class for the bass note (slash bass wins over root).
    static func bassPitchClass(for symbol: String) -> Int? {
        let trimmed = symbol.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.contains("/") {
            let parts = trimmed.split(separator: "/", maxSplits: 1).map(String.init)
            if parts.count == 2 {
                let bassToken = parts[1].trimmingCharacters(in: .whitespaces)
                if let pc = pitchClassFromToken(bassToken) { return pc }
            }
        }

        guard let parsed = Transposer.parse(trimmed) else { return nil }
        return Transposer.pitchClass(ofRoot: parsed.root)
    }

    static func bassMidiNote(for symbol: String, octave: Int = 2) -> UInt8? {
        guard let pc = bassPitchClass(for: symbol) else { return nil }
        let midi = 12 + octave * 12 + pc
        return UInt8(min(127, max(28, midi)))
    }

    static func fifthMidiNote(for symbol: String, octave: Int = 2) -> UInt8? {
        guard let root = bassPitchClass(for: symbol) else { return nil }
        let fifth = (root + 7) % 12
        let midi = 12 + octave * 12 + fifth
        return UInt8(min(127, max(28, midi)))
    }

    private static func pitchClassFromToken(_ token: String) -> Int? {
        if let parsed = Transposer.parse(token + "maj") {
            return Transposer.pitchClass(ofRoot: parsed.root)
        }
        if let parsed = Transposer.parse(token) {
            return Transposer.pitchClass(ofRoot: parsed.root)
        }
        return nil
    }
}
