//
//  ChordModels.swift
//  Chordyx
//

import Foundation

enum ChordNotation: String, Codable, CaseIterable, Identifiable, Sendable {
    case symbol
    case latin
    case nashville

    var id: String { rawValue }

    /// Full professional name shown in menus and setup screens.
    var label: String {
        switch self {
        case .symbol: String(localized: "Chord Symbols")
        case .latin: String(localized: "Solfège")
        case .nashville: String(localized: "Nashville Numbers")
        }
    }

    /// Compact label for tight control chips at the bottom of the session screen.
    var chipLabel: String {
        switch self {
        case .symbol: String(localized: "Chord Symbols")
        case .latin: String(localized: "Solfège")
        case .nashville: String(localized: "Nashville")
        }
    }

    /// Label for the floating notation cycle button — shows the session key in the active notation.
    func cycleGlyph(for key: MusicalKey) -> String {
        switch self {
        case .symbol: key.displayName
        case .latin: ChordCatalog.latinName(forSymbol: key.rootSymbol)
        case .nashville: "1"
        }
    }

    func nextInCycle() -> ChordNotation {
        let all = ChordNotation.allCases
        guard let index = all.firstIndex(of: self) else { return .symbol }
        return all[(index + 1) % all.count]
    }

    var subtitle: String {
        switch self {
        case .symbol: "C · Am · G7"
        case .latin: "Do · Re · Sol7"
        case .nashville: "1 · 6m · 5⁷"
        }
    }
}

enum MusicalKey: String, Codable, CaseIterable, Identifiable, Sendable {
    case C, Cs, D, Eb, E, F, Fs, G, Ab, A, Bb, B

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .Cs: "C♯"
        case .Eb: "E♭"
        case .Fs: "F♯"
        case .Ab: "A♭"
        case .Bb: "B♭"
        default: rawValue
        }
    }

    /// Semitone offset above C (0–11).
    var pitchClass: Int {
        switch self {
        case .C: 0
        case .Cs: 1
        case .D: 2
        case .Eb: 3
        case .E: 4
        case .F: 5
        case .Fs: 6
        case .G: 7
        case .Ab: 8
        case .A: 9
        case .Bb: 10
        case .B: 11
        }
    }

    /// Flat/sharp spelling for chord symbols (used by solfège conversion).
    var rootSymbol: String {
        switch self {
        case .C: "C"
        case .Cs: "C#"
        case .D: "D"
        case .Eb: "Eb"
        case .E: "E"
        case .F: "F"
        case .Fs: "F#"
        case .G: "G"
        case .Ab: "Ab"
        case .A: "A"
        case .Bb: "Bb"
        case .B: "B"
        }
    }

    /// Flat keys spell accidentals with flats; the rest use sharps.
    var prefersFlats: Bool {
        switch self {
        case .Eb, .F, .Ab, .Bb: true
        default: false
        }
    }
}

struct ChordEntry: Identifiable, Codable, Equatable, Hashable, Sendable {
    let id: UUID
    let symbolName: String
    let latinName: String
    let order: Int
    /// How many beats to stay on this chord before auto-advancing (host only).
    var durationBeats: Double?
    var lyrics: String?

    init(
        id: UUID = UUID(),
        symbolName: String,
        latinName: String,
        order: Int,
        durationBeats: Double? = nil,
        lyrics: String? = nil
    ) {
        self.id = id
        self.symbolName = symbolName
        self.latinName = latinName
        self.order = order
        self.durationBeats = durationBeats
        self.lyrics = lyrics
    }

    func displayName(for notation: ChordNotation, key: MusicalKey = .C) -> String {
        switch notation {
        case .symbol: symbolName
        case .latin: latinName
        case .nashville: NashvilleConverter.number(for: symbolName, in: key)
        }
    }

    func copying(
        symbolName: String? = nil,
        latinName: String? = nil,
        order: Int? = nil,
        durationBeats: Double?? = nil,
        lyrics: String?? = nil
    ) -> ChordEntry {
        ChordEntry(
            id: id,
            symbolName: symbolName ?? self.symbolName,
            latinName: latinName ?? self.latinName,
            order: order ?? self.order,
            durationBeats: durationBeats ?? self.durationBeats,
            lyrics: lyrics ?? self.lyrics
        )
    }

    /// Ephemeral entry for live MIDI / freestyle chords shown on the guest ring.
    static func freestyle(symbol: String, order: Int) -> ChordEntry {
        ChordEntry(
            id: freestyleID(symbol: symbol, order: order),
            symbolName: symbol,
            latinName: ChordCatalog.latinName(forSymbol: symbol),
            order: order
        )
    }

    private static func freestyleID(symbol: String, order: Int) -> UUID {
        let seed = "freestyle.\(order).\(symbol)"
        var bytes = [UInt8](repeating: 0, count: 16)
        for (index, byte) in seed.utf8.enumerated() where index < 16 {
            bytes[index] = byte
        }
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}

struct SavedProgression: Identifiable, Codable, Equatable, Hashable, Sendable {
    let id: UUID
    var name: String
    var key: MusicalKey
    var notation: ChordNotation
    var chords: [ChordEntry]
    var tempoBPM: Double
    var beatsPerBar: Int
    var beatUnit: Int
    var savedAt: Date
    var sections: [SectionMarker]
    var lyrics: String
    var loopStartChordID: UUID?
    var loopEndChordID: UUID?
    var isLoopEnabled: Bool
    var lyricsLines: [LyricsLine]
    var pdfFileName: String?
    /// Band notes visible in rehearsal mode (capo reminders, dynamics, etc.).
    var rehearsalNotes: String

    init(
        id: UUID = UUID(),
        name: String,
        key: MusicalKey,
        notation: ChordNotation,
        chords: [ChordEntry],
        tempoBPM: Double = 100,
        beatsPerBar: Int = 4,
        beatUnit: Int = 4,
        savedAt: Date = Date(),
        sections: [SectionMarker] = [],
        lyrics: String = "",
        loopStartChordID: UUID? = nil,
        loopEndChordID: UUID? = nil,
        isLoopEnabled: Bool = false,
        lyricsLines: [LyricsLine] = [],
        pdfFileName: String? = nil,
        rehearsalNotes: String = ""
    ) {
        self.id = id
        self.name = name
        self.key = key
        self.notation = notation
        self.chords = chords
        self.tempoBPM = tempoBPM
        self.beatsPerBar = beatsPerBar
        self.beatUnit = beatUnit
        self.savedAt = savedAt
        self.sections = sections
        self.lyrics = lyrics
        self.loopStartChordID = loopStartChordID
        self.loopEndChordID = loopEndChordID
        self.isLoopEnabled = isLoopEnabled
        self.lyricsLines = lyricsLines
        self.pdfFileName = pdfFileName
        self.rehearsalNotes = rehearsalNotes
    }

    var summary: String {
        chords
            .sorted { $0.order < $1.order }
            .map { $0.displayName(for: notation, key: key) }
            .joined(separator: " · ")
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, key, notation, chords, tempoBPM, beatsPerBar, beatUnit, savedAt
        case sections, lyrics, loopStartChordID, loopEndChordID, isLoopEnabled
        case lyricsLines, pdfFileName, rehearsalNotes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        key = try container.decode(MusicalKey.self, forKey: .key)
        notation = try container.decode(ChordNotation.self, forKey: .notation)
        chords = try container.decode([ChordEntry].self, forKey: .chords)
        tempoBPM = try container.decodeIfPresent(Double.self, forKey: .tempoBPM) ?? 100
        beatsPerBar = try container.decodeIfPresent(Int.self, forKey: .beatsPerBar) ?? 4
        beatUnit = try container.decodeIfPresent(Int.self, forKey: .beatUnit) ?? 4
        savedAt = try container.decode(Date.self, forKey: .savedAt)
        sections = try container.decodeIfPresent([SectionMarker].self, forKey: .sections) ?? []
        lyrics = try container.decodeIfPresent(String.self, forKey: .lyrics) ?? ""
        loopStartChordID = try container.decodeIfPresent(UUID.self, forKey: .loopStartChordID)
        loopEndChordID = try container.decodeIfPresent(UUID.self, forKey: .loopEndChordID)
        isLoopEnabled = try container.decodeIfPresent(Bool.self, forKey: .isLoopEnabled) ?? false
        lyricsLines = try container.decodeIfPresent([LyricsLine].self, forKey: .lyricsLines) ?? []
        pdfFileName = try container.decodeIfPresent(String.self, forKey: .pdfFileName)
        rehearsalNotes = try container.decodeIfPresent(String.self, forKey: .rehearsalNotes) ?? ""
    }
}

struct SessionSyncPayload: Codable, Equatable, Sendable {
    var sessionName: String
    var key: MusicalKey
    var notation: ChordNotation
    var chords: [ChordEntry]
    var activeChordID: UUID?
    var isHost: Bool
    var tempoBPM: Double = 100
    var beatsPerBar: Int = 4
    var beatUnit: Int = 4
    var isMetronomePlaying: Bool = false
    var metronomeStartEpoch: Double?
    var isPianoActive: Bool = false
    /// Absolute semitone indices of the keys the host is currently highlighting.
    var pianoNotes: [Int] = []
    /// Chord symbol recognized from the host's current piano/MIDI notes.
    var liveChordSymbol: String?
    /// Recent chords the host played freestyle (MIDI / piano), oldest first.
    var freestyleChordSymbols: [String] = []
    var isFretboardActive: Bool = false
    var fretInstrument: FretInstrument = .acoustic
    var bassStrings: Int = 4
    /// The chord (from `chords`) currently shown on the fretboard.
    var fretChordID: UUID?
    var sections: [SectionMarker] = []
    var lyrics: String = ""
    var loopStartChordID: UUID?
    var loopEndChordID: UUID?
    var isLoopEnabled: Bool = false
    var countInBars: Int = 0
    var isCountingIn: Bool = false
    var countInStartEpoch: Double?
    var setlistName: String?
    var setlistSongIndex: Int?
    var setlistSongCount: Int?
    var activeSectionID: UUID?
    var beatsOnActiveChord: Int = 0
    var performanceMode: SessionPerformanceMode = .live
    var displayMode: SessionDisplayMode = .ring
    var coHostPeerName: String?
    var activeCue: LiveCue?
    var lyricsLines: [LyricsLine] = []
    var transitionTitle: String?
    var transitionCountdown: Int?
    var autoAdvanceSetlist: Bool = false
    /// When true, the ring shows live-played chords instead of the saved progression.
    var ringShowsLiveChords: Bool = false
    /// Freestyle session: broadcast the current live chord only (no progression, no next chord).
    var isLiveChordsOnly: Bool = false
    /// Stable ID for reconnecting to the same session.
    var sessionToken: UUID = UUID()
    /// Repeat the active section until the host turns it off.
    var isSectionLoopEnabled: Bool = false
    /// Band notes shown in rehearsal mode.
    var rehearsalNotes: String = ""
    /// Song titles for setlist timeline (guests).
    var setlistSongTitles: [String] = []
    /// Brief pulse when the last chord of a song is reached.
    var isSongEnding: Bool = false
    /// Pulse chord bubbles on beat when a chord change is due.
    var showBeatSyncHints: Bool = false
    /// Hold cue — pauses metronome-driven auto-advance.
    var isAutoAdvancePaused: Bool = false
    /// Vamp cue — repeats the current chord instead of advancing.
    var isVampActive: Bool = false
    /// Reference track title shown to the band (host plays locally).
    var backingTrackDisplayName: String = ""
    var isBackingTrackPlaying: Bool = false

    static let empty = SessionSyncPayload(
        sessionName: "",
        key: .C,
        notation: .symbol,
        chords: [],
        activeChordID: nil,
        isHost: false
    )
}

/// One round-trip sample used to estimate the clock offset between a guest and
/// the host, NTP-style.
struct TimeSyncPing: Codable, Sendable {
    let id: UUID
    let clientSendEpoch: Double
    var hostEpoch: Double?
}

/// Everything that travels over the peer connection.
enum SessionMessage: Codable, Sendable {
    case state(SessionSyncPayload)
    case timeSyncRequest(TimeSyncPing)
    case timeSyncResponse(TimeSyncPing)
    case controlRequest(SessionControlAction)
}

enum ChordCatalog {
    /// Maps the letter name of a root note to its solfège (Latin) equivalent.
    static let solfegeForLetter: [Character: String] = [
        "C": "Do", "D": "Re", "E": "Mi", "F": "Fa",
        "G": "Sol", "A": "La", "B": "Si"
    ]

    /// Each chord is stored once with both naming systems so the two notations
    /// describe the exact same chord, e.g. ("Am7", "Lam7").
    static let chords: [(symbol: String, latin: String)] = [
        ("C", "Do"), ("Cm", "Dom"), ("C7", "Do7"),
        ("D", "Re"), ("Dm", "Rem"), ("D7", "Re7"),
        ("E", "Mi"), ("Em", "Mim"), ("E7", "Mi7"),
        ("F", "Fa"), ("Fm", "Fam"), ("F7", "Fa7"),
        ("G", "Sol"), ("Gm", "Solm"), ("G7", "Sol7"),
        ("A", "La"), ("Am", "Lam"), ("A7", "La7"),
        ("B", "Si"), ("Bm", "Sim"), ("B7", "Si7"),
        ("Cmaj7", "Domaj7"), ("Dm7", "Rem7"), ("Em7", "Mim7"),
        ("Fmaj7", "Famaj7"), ("Gmaj7", "Solmaj7"), ("Am7", "Lam7"),
        ("Bb", "Si♭"), ("Eb", "Mi♭"), ("Ab", "La♭"),
    ]

    static func chords(for notation: ChordNotation) -> [(symbol: String, latin: String)] {
        chords
    }

    /// Converts a letter-name chord (e.g. "C#m7") into its solfège form ("Do♯m7").
    /// Slash chords convert both sides ("C/E" → "Do/Mi"); numeric slashes like
    /// "C6/9" are preserved since "9" has no root letter to convert.
    static func latinName(forSymbol symbol: String) -> String {
        let parts = symbol.split(separator: "/", omittingEmptySubsequences: false)
        if parts.count == 2 {
            return convertRoot(String(parts[0])) + "/" + convertRoot(String(parts[1]))
        }
        return convertRoot(symbol)
    }

    private static func convertRoot(_ symbol: String) -> String {
        guard let first = symbol.first, let solfege = solfegeForLetter[first] else {
            return symbol
        }
        let rest = symbol.dropFirst()
            .replacingOccurrences(of: "#", with: "♯")
            .replacingOccurrences(of: "b", with: "♭")
        return solfege + rest
    }
}

/// Transposes chord symbols by a number of semitones while preserving the
/// chord quality (the suffix after the root, e.g. "m7", "maj7", "7b5").
enum Transposer {
    static let sharpNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    static let flatNames = ["C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"]

    private static let naturalPitchClass: [Character: Int] = [
        "C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11
    ]

    /// Splits a chord symbol into its root (with accidental) and the remaining quality.
    static func parse(_ symbol: String) -> (root: String, suffix: String)? {
        let chars = Array(symbol)
        guard let first = chars.first,
              "ABCDEFGabcdefg".contains(first) else { return nil }

        var rootLength = 1
        if chars.count > 1 {
            switch chars[1] {
            case "#", "♯", "b", "♭": rootLength = 2
            default: break
            }
        }
        return (String(chars[0..<rootLength]), String(chars[rootLength...]))
    }

    static func pitchClass(ofRoot root: String) -> Int? {
        let chars = Array(root)
        guard let letter = chars.first,
              let base = naturalPitchClass[Character(letter.uppercased())] else { return nil }
        var value = base
        if chars.count > 1 {
            switch chars[1] {
            case "#", "♯": value += 1
            case "b", "♭": value -= 1
            default: break
            }
        }
        return ((value % 12) + 12) % 12
    }

    static func transpose(symbol: String, by semitones: Int, preferFlats: Bool) -> String {
        guard let (root, suffix) = parse(symbol),
              let pitch = pitchClass(ofRoot: root) else { return symbol }
        let newPitch = ((pitch + semitones) % 12 + 12) % 12
        let newRoot = (preferFlats ? flatNames : sharpNames)[newPitch]
        return newRoot + suffix
    }

    static func semitones(from: MusicalKey, to: MusicalKey) -> Int {
        ((to.pitchClass - from.pitchClass) % 12 + 12) % 12
    }
}

struct TimeSignature: Identifiable, Equatable, Sendable {
    let beats: Int
    let unit: Int

    var id: String { "\(beats)/\(unit)" }
    var label: String { "\(beats)/\(unit)" }

    /// Beat length relative to a quarter note (used to scale the click rate).
    var beatLengthMultiplier: Double { 4.0 / Double(unit) }

    static let presets: [TimeSignature] = [
        .init(beats: 2, unit: 4),
        .init(beats: 3, unit: 4),
        .init(beats: 4, unit: 4),
        .init(beats: 5, unit: 4),
        .init(beats: 6, unit: 4),
        .init(beats: 7, unit: 4),
        .init(beats: 2, unit: 2),
        .init(beats: 3, unit: 2),
        .init(beats: 3, unit: 8),
        .init(beats: 5, unit: 8),
        .init(beats: 6, unit: 8),
        .init(beats: 7, unit: 8),
        .init(beats: 9, unit: 8),
        .init(beats: 12, unit: 8)
    ]
}

enum FretInstrument: String, Codable, CaseIterable, Sendable, Identifiable {
    case acoustic
    case electric
    case bass

    var id: String { rawValue }

    var label: String {
        switch self {
        case .acoustic: String(localized: "Acoustic")
        case .electric: String(localized: "Electric")
        case .bass: String(localized: "Bass")
        }
    }

    var isBass: Bool { self == .bass }
}

/// How a viewer chooses to render shared notes locally (independent of the host).
enum ViewInstrument: String, CaseIterable, Identifiable, Sendable {
    case piano
    case acoustic
    case electric
    case bass

    var id: String { rawValue }

    var label: String {
        switch self {
        case .piano: String(localized: "Piano")
        case .acoustic: String(localized: "Acoustic")
        case .electric: String(localized: "Electric")
        case .bass: String(localized: "Bass")
        }
    }

    var fretInstrument: FretInstrument? {
        switch self {
        case .piano: nil
        case .acoustic: .acoustic
        case .electric: .electric
        case .bass: .bass
        }
    }
}

/// String tunings as pitch classes, ordered from lowest string to highest.
enum InstrumentTuning {
    static func pitchClasses(for instrument: FretInstrument, bassStrings: Int) -> [Int] {
        switch instrument {
        case .acoustic, .electric:
            // E A D G B E
            return [4, 9, 2, 7, 11, 4]
        case .bass:
            switch bassStrings {
            case 5: return [11, 4, 9, 2, 7]        // B E A D G
            case 6: return [11, 4, 9, 2, 7, 0]     // B E A D G C
            default: return [4, 9, 2, 7]           // E A D G
            }
        }
    }

    /// Open-string note labels (with octave omitted) for display, low to high.
    static func openNames(for instrument: FretInstrument, bassStrings: Int, preferFlats: Bool) -> [String] {
        pitchClasses(for: instrument, bassStrings: bassStrings).map {
            (preferFlats ? Transposer.flatNames : Transposer.sharpNames)[$0]
        }
    }
}

/// Derives the pitch classes that make up a chord from its symbol.
enum ChordTheory {
    static func intervals(forSuffix raw: String) -> [Int] {
        let s = raw.lowercased()

        if s.contains("dim7") { return [0, 3, 6, 9] }
        if s.hasPrefix("dim") || s.contains("°") { return [0, 3, 6] }
        if s.contains("m7b5") || s.contains("ø") { return [0, 3, 6, 10] }
        if s.hasPrefix("aug") || s.hasPrefix("+") { return [0, 4, 8] }
        if s.hasPrefix("sus2") { return [0, 2, 7] }
        if s.hasPrefix("sus4") || s == "sus" { return [0, 5, 7] }

        let isMinor = (s.hasPrefix("m") && !s.hasPrefix("maj")) || s.hasPrefix("min")
        var tones: Set<Int> = [0, 7]
        tones.insert(isMinor ? 3 : 4)

        if s.contains("maj7") || s.contains("M7") {
            tones.insert(11)
        } else if s.contains("7") {
            tones.insert(10)
        }
        if s.contains("6") { tones.insert(9) }
        if s.contains("9") {
            tones.insert(2)
            if !s.contains("maj") { tones.insert(10) }
        }
        return Array(tones).sorted()
    }

    /// Returns the root pitch class and the set of chord-tone pitch classes.
    static func tones(for symbol: String) -> (root: Int, pitchClasses: Set<Int>)? {
        guard let (root, suffix) = Transposer.parse(symbol),
              let rootPC = Transposer.pitchClass(ofRoot: root) else { return nil }
        let pcs = intervals(forSuffix: suffix).map { ((rootPC + $0) % 12 + 12) % 12 }
        return (rootPC, Set(pcs))
    }
}

/// Guesses a chord name from a set of sounding pitch classes (e.g. live MIDI input).
enum ChordRecognizer {
    /// Chord templates as intervals above the root. Ordered larger-first so the
    /// richest exact match wins; ties between equal-size sets are resolved by
    /// root preference (the bass note is tried first).
    private static let qualities: [(name: String, intervals: Set<Int>)] = [
        // 6-note extensions
        ("13", [0, 2, 4, 7, 9, 10]),
        ("m13", [0, 2, 3, 7, 9, 10]),
        ("maj13", [0, 2, 4, 7, 9, 11]),
        ("11", [0, 2, 4, 5, 7, 10]),
        ("m11", [0, 2, 3, 5, 7, 10]),
        // 5-note
        ("9", [0, 2, 4, 7, 10]),
        ("maj9", [0, 2, 4, 7, 11]),
        ("m9", [0, 2, 3, 7, 10]),
        ("mMaj9", [0, 2, 3, 7, 11]),
        ("6/9", [0, 2, 4, 7, 9]),
        ("m6/9", [0, 2, 3, 7, 9]),
        ("7b9", [0, 1, 4, 7, 10]),
        ("7#9", [0, 3, 4, 7, 10]),
        ("7#11", [0, 4, 6, 7, 10]),
        ("7b13", [0, 4, 7, 8, 10]),
        ("9sus4", [0, 2, 5, 7, 10]),
        ("maj7#11", [0, 4, 6, 7, 11]),
        // 4-note
        ("maj7", [0, 4, 7, 11]),
        ("7", [0, 4, 7, 10]),
        ("m7", [0, 3, 7, 10]),
        ("mMaj7", [0, 3, 7, 11]),
        ("dim7", [0, 3, 6, 9]),
        ("m7b5", [0, 3, 6, 10]),
        ("aug7", [0, 4, 8, 10]),
        ("augMaj7", [0, 4, 8, 11]),
        ("7b5", [0, 4, 6, 10]),
        ("6", [0, 4, 7, 9]),
        ("m6", [0, 3, 7, 9]),
        ("7sus4", [0, 5, 7, 10]),
        ("7sus2", [0, 2, 7, 10]),
        ("add9", [0, 2, 4, 7]),
        ("madd9", [0, 2, 3, 7]),
        ("add11", [0, 4, 5, 7]),
        // triads
        ("", [0, 4, 7]),
        ("m", [0, 3, 7]),
        ("dim", [0, 3, 6]),
        ("aug", [0, 4, 8]),
        ("sus4", [0, 5, 7]),
        ("sus2", [0, 2, 7]),
        // dyad
        ("5", [0, 7])
    ]

    /// Returns a chord symbol (letter-based, with slash bass for inversions)
    /// or nil if the notes don't form a recognizable chord.
    static func symbol(forPitchClasses pcs: Set<Int>, bassPitchClass: Int?, preferFlats: Bool) -> String? {
        guard pcs.count >= 2 else { return nil }
        let names = preferFlats ? Transposer.flatNames : Transposer.sharpNames

        // The root is almost always one of the sounding notes; try the bass first.
        var roots = (0..<12).filter { pcs.contains($0) }
        if let bass = bassPitchClass, pcs.contains(bass) {
            roots.removeAll { $0 == bass }
            roots.insert(bass, at: 0)
        }

        // Second pass tolerates a missing fifth, which is common in real voicings.
        for omitFifth in [false, true] {
            for root in roots {
                let relative = Set(pcs.map { (($0 - root) % 12 + 12) % 12 })
                for quality in qualities {
                    var target = quality.intervals
                    if omitFifth {
                        guard target.count >= 4, target.contains(7) else { continue }
                        target.remove(7)
                    }
                    if relative == target {
                        var symbol = names[root] + quality.name
                        if let bass = bassPitchClass, bass != root, pcs.contains(bass) {
                            symbol += "/" + names[bass]
                        }
                        return symbol
                    }
                }
            }
        }
        return nil
    }
}

/// Helpers for naming piano keys by absolute semitone index (0 = C0).
enum PianoNote {
    static func pitchClass(of index: Int) -> Int { ((index % 12) + 12) % 12 }
    static func octave(of index: Int) -> Int { index / 12 }
    static func isBlack(_ index: Int) -> Bool { [1, 3, 6, 8, 10].contains(pitchClass(of: index)) }

    static func name(of index: Int, preferFlats: Bool, includeOctave: Bool = false) -> String {
        let names = preferFlats ? Transposer.flatNames : Transposer.sharpNames
        let base = names[pitchClass(of: index)]
        return includeOctave ? "\(base)\(octave(of: index))" : base
    }

    static func latinName(of index: Int, preferFlats: Bool) -> String {
        let symbol = (preferFlats ? Transposer.flatNames : Transposer.sharpNames)[pitchClass(of: index)]
        return ChordCatalog.latinName(forSymbol: symbol)
    }
}
