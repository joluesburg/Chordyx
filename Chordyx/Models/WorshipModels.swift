//
//  WorshipModels.swift
//  Chordyx
//

import Foundation

enum SessionPerformanceMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case rehearsal
    case live

    var id: String { rawValue }

    var label: String {
        switch self {
        case .rehearsal: String(localized: "Rehearsal")
        case .live: String(localized: "Live")
        }
    }

    var subtitle: String {
        switch self {
        case .rehearsal: String(localized: "Full chart, edit-friendly")
        case .live: String(localized: "Minimal stage view")
        }
    }
}

enum SessionDisplayMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case ring
    case stage
    case chart

    var id: String { rawValue }

    var label: String {
        switch self {
        case .ring: String(localized: "Ring")
        case .stage: String(localized: "Stage")
        case .chart: String(localized: "Lyrics Chart")
        }
    }
}

enum WorshipSectionKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case intro, verse, chorus, bridge, preChorus, tag, ending, custom

    var id: String { rawValue }

    var defaultName: String {
        switch self {
        case .intro: String(localized: "Intro")
        case .verse: String(localized: "Verse")
        case .chorus: String(localized: "Chorus")
        case .bridge: String(localized: "Bridge")
        case .preChorus: String(localized: "Pre-Chorus")
        case .tag: String(localized: "Tag")
        case .ending: String(localized: "Ending")
        case .custom: String(localized: "Section")
        }
    }

    var icon: String {
        switch self {
        case .intro: "play.fill"
        case .verse: "text.alignleft"
        case .chorus: "music.mic"
        case .bridge: "arrow.triangle.branch"
        case .preChorus: "arrow.up.right"
        case .tag: "repeat"
        case .ending: "flag.checkered"
        case .custom: "bookmark"
        }
    }
}

struct LyricsLine: Identifiable, Codable, Equatable, Hashable, Sendable {
    let id: UUID
    var text: String
    var chordSymbol: String?

    init(id: UUID = UUID(), text: String, chordSymbol: String? = nil) {
        self.id = id
        self.text = text
        self.chordSymbol = chordSymbol
    }
}

struct LiveCue: Codable, Equatable, Sendable {
    var text: String
    var symbol: String
    var sentAt: Double

    static let presets: [(String, String)] = [
        ("Hold", "hand.raised.fill"),
        ("Build", "arrow.up.circle.fill"),
        ("Break", "pause.circle.fill"),
        ("Repeat", "repeat.circle.fill"),
        ("Tag", "tag.fill"),
        ("Vamp", "infinity.circle.fill"),
        ("Ending", "flag.checkered"),
    ]
}

enum SessionControlAction: Codable, Equatable, Sendable {
    case advanceChord
    case previousChord
    case jumpToSection(UUID)
    case setActiveChord(UUID)
    case sendCue(LiveCue)
    case passControl(String)
}

/// How a guest prefers to view the session (local only).
enum GuestViewRole: String, Codable, CaseIterable, Identifiable, Sendable {
    case auto
    case vocal
    case bass
    case keys
    case drums

    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto: String(localized: "Auto (by instrument)")
        case .vocal: String(localized: "Vocal — lyrics focus")
        case .bass: String(localized: "Bass — Nashville numbers")
        case .keys: String(localized: "Keys — chord ring")
        case .drums: String(localized: "Drums — section & tempo")
        }
    }

    var preferredDisplayMode: SessionDisplayMode? {
        switch self {
        case .auto: nil
        case .vocal: .chart
        case .bass: .stage
        case .keys: .ring
        case .drums: .stage
        }
    }

    var preferredNotation: ChordNotation? {
        switch self {
        case .auto, .vocal, .keys: nil
        case .bass: .nashville
        case .drums: nil
        }
    }
}

enum MusicianInstrument: String, Codable, CaseIterable, Identifiable, Sendable {
    case keys, guitar, bass, vocal, other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .keys: String(localized: "Keys")
        case .guitar: String(localized: "Guitar")
        case .bass: String(localized: "Bass")
        case .vocal: String(localized: "Vocal")
        case .other: String(localized: "Other")
        }
    }
}

struct ChordyxSetlistPack: Codable, Sendable {
    static let currentVersion = 1
    var version: Int
    var name: String
    var progressions: [SavedProgression]
    var setlist: Setlist?

    init(name: String, progressions: [SavedProgression], setlist: Setlist? = nil, version: Int = Self.currentVersion) {
        self.version = version
        self.name = name
        self.progressions = progressions
        self.setlist = setlist
    }
}

enum ChordDisplayHelper {
    static func displayName(
        for chord: ChordEntry,
        notation: ChordNotation,
        songKey: MusicalKey,
        transposeSemitones: Int = 0,
        capoFret: Int = 0
    ) -> String {
        let totalShift = transposeSemitones + capoFret
        if totalShift == 0 {
            return chord.displayName(for: notation, key: songKey)
        }
        let shiftedKey = MusicalKey.allCases.first {
            $0.pitchClass == ((songKey.pitchClass + totalShift) % 12 + 12) % 12
        } ?? songKey
        if notation == .nashville {
            return chord.displayName(for: .nashville, key: songKey)
        }
        let shiftedSymbol = Transposer.transpose(
            symbol: chord.symbolName,
            by: totalShift,
            preferFlats: shiftedKey.prefersFlats
        )
        switch notation {
        case .symbol: return shiftedSymbol
        case .latin: return ChordCatalog.latinName(forSymbol: shiftedSymbol)
        case .nashville: return NashvilleConverter.number(for: shiftedSymbol, in: shiftedKey)
        }
    }
}
