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

nonisolated enum MusicalKey: String, Codable, CaseIterable, Identifiable, Sendable {
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
    /// Short notes keyed by GuestViewRole raw value for live display.
    var roleNotes: [String: String]
    /// Named arrangement layouts (Sunday A, acoustic, etc.).
    var arrangementVariants: [ArrangementVariant]

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
        rehearsalNotes: String = "",
        roleNotes: [String: String] = [:],
        arrangementVariants: [ArrangementVariant] = []
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
        self.roleNotes = roleNotes
        self.arrangementVariants = arrangementVariants
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
        case lyricsLines, pdfFileName, rehearsalNotes, roleNotes, arrangementVariants
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
        roleNotes = try container.decodeIfPresent([String: String].self, forKey: .roleNotes) ?? [:]
        arrangementVariants = try container.decodeIfPresent([ArrangementVariant].self, forKey: .arrangementVariants) ?? []
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
    /// True when a repeating live loop was auto-applied to `chords` (synced to guests).
    var hasInferredLiveProgression: Bool = false
    /// Unique chords on the current live ring (most-used first, capped for display).
    var freestyleChordSymbols: [String] = []
    /// Play counts keyed by normalized chord symbol (host builds the ring from these).
    var liveRingUsageCounts: [String: Int] = [:]
    /// Normalized symbols in order of last performance (oldest first).
    var liveRingRecentOrder: [String] = []
    /// Latest display spelling per normalized chord symbol.
    var liveRingCanonicalSymbols: [String: String] = [:]
    /// Completed live rings from earlier songs in this session (each list is unique chords, oldest first).
    var liveRingSegments: [[String]] = []
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
    /// Host listens to live chords and picks the key automatically.
    var autoDetectKey: Bool = true
    /// True when the current key was chosen by auto-detection (shown in the UI).
    var isKeyAutoDetected: Bool = false
    /// Internet backup via iCloud — works over cellular when local Wi‑Fi fails.
    var isRemoteBackupEnabled: Bool = true
    /// Short code guests can enter to follow the session over the Internet.
    var remoteJoinCode: String?
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
    /// Host assigns display presets per connected musician name.
    var guestRoleAssignments: [String: GuestViewRole] = [:]
    /// Projector / confidence-monitor layout — controls hidden on guest devices.
    var isStageDisplayOnly: Bool = false
    /// When live piano disagrees with the chart (e.g. "Played Am · chart A").
    var pianoChartMismatch: String?
    /// Timeline capture active for rehearsal replay.
    var isRecordingRehearsal: Bool = false
    /// Peer name the host invited to take over hosting duties.
    var pendingHostHandoffPeer: String?
    /// Count-in beats left — synced for lock screen / widgets.
    var countInBeatsRemaining: Int = 0
    /// Send MIDI program changes on cues (host).
    var isMIDICueOutEnabled: Bool = false
    /// Beats remaining before the next section jump.
    var sectionCountdownBeats: Int = 0
    var sectionCountdownLabel: String?
    /// Positive = ahead of metronome, negative = behind.
    var tempoDriftBPM: Double = 0
    var quickMessages: [SessionQuickMessage] = []
    /// Shared band chat log (host + guests). Synced on full state only — not live bursts.
    var bandChatMessages: [SessionQuickMessage] = []
    var peerPresence: [String: PeerPresenceInfo] = [:]
    var handoffCountdown: Int?
    var handoffFromPeer: String?
    var isGhostBandReplayActive: Bool = false
    var vocalTargetKeyName: String?
    var syncedRoleNotes: [String: String] = [:]
    var nextSetlistSongTitle: String?
    var isSectionMapLocked: Bool = false
    var tempoRampTargetBPM: Double?
    var tempoRampBarsRemaining: Int = 0
    var clickTrackLanes: [String: String] = [:]
    var chartDeliveryModes: [String: String] = [:]
    var peerChordPositions: [String: UUID] = [:]
    var serviceTimelineStartEpoch: Double?
    var voicingHintsEnabled: Bool = false
    var readinessScore: Int?
    var isCongregationModeActive: Bool = false
    var congregationJoinToken: String?
    var sectionLoopCountInBars: Int = 1
    var broadcastSilentNudge: SilentNudgeKind?
    var silentNudgeSequence: Int = 0
    /// Mac host: live groove (solo drums) is enabled — guests show tempo & genre.
    var hostLiveGrooveActive: Bool = false
    /// Detected or locked BPM from the host's piano analysis.
    var hostLiveGrooveBPM: Double?
    /// `LiveMusicStyle.rawValue` for guest genre display.
    var hostLiveGrooveStyleRaw: String?
    /// `SoloDrumWorkflowPhase.rawValue` for guest status.
    var hostLiveGroovePhaseRaw: String?
    /// Worldwide genre id from `GlobalMusicGenreCatalog` (guest display).
    var hostGlobalGenreID: String?
    /// Localized genre label for guests without catalog lookup.
    var hostGlobalGenreLabel: String?
    /// `GlobalMusicRegion.rawValue` for guest region badge.
    var hostGlobalGenreRegionRaw: String?

    /// `SoloDrumInstrumentCategory.rawValue` for guest / sync display.
    var hostSoloInstrumentCategoryRaw: String?

    static let empty = SessionSyncPayload(
        sessionName: "",
        key: .C,
        notation: .symbol,
        chords: [],
        activeChordID: nil,
        isHost: false
    )

    /// Strips host-only / bulky fields for high-frequency live MIDI broadcasts.
    func forHighFrequencyPeerSync() -> SessionSyncPayload {
        var copy = self
        copy.quickMessages = []
        copy.bandChatMessages = []
        copy.readinessScore = nil
        copy.chartDeliveryModes = [:]
        copy.clickTrackLanes = [:]
        copy.syncedRoleNotes = [:]
        copy.rehearsalNotes = ""
        copy.pianoChartMismatch = nil
        copy.chords = []
        copy.lyrics = ""
        copy.lyricsLines = []
        copy.sections = []
        copy.setlistSongTitles = []
        copy.peerChordPositions = [:]
        return copy
    }

    /// True when this payload looks like a stripped high-frequency cloud publish.
    func looksLikeHighFrequencyPeerSyncStrip(comparedTo prior: SessionSyncPayload) -> Bool {
        sessionToken == prior.sessionToken
            && chords.isEmpty
            && sections.isEmpty
            && bandChatMessages.isEmpty
            && quickMessages.isEmpty
            && (!prior.chords.isEmpty || !prior.sections.isEmpty || !prior.bandChatMessages.isEmpty)
    }

    /// Minimal live-chord packet for sub-10ms peer sync (guest merges into existing state).
    func liveChordWire(revision: UInt64) -> LiveChordWire {
        LiveChordWire(
            sessionToken: sessionToken,
            revision: revision,
            liveChordSymbol: liveChordSymbol,
            pianoNotes: pianoNotes,
            freestyleChordSymbols: freestyleChordSymbols,
            key: key,
            isKeyAutoDetected: isKeyAutoDetected,
            isPianoActive: isPianoActive
        )
    }

    func applyingLiveWire(_ wire: LiveChordWire) -> SessionSyncPayload {
        var merged = self
        merged.pianoNotes = wire.pianoNotes
        merged.liveChordSymbol = wire.liveChordSymbol
        merged.freestyleChordSymbols = wire.freestyleChordSymbols
        merged.key = wire.key
        merged.isKeyAutoDetected = wire.isKeyAutoDetected
        merged.isPianoActive = wire.isPianoActive
        return merged
    }

    func hostLiveGrooveGuestSignature() -> String {
        [
            hostLiveGrooveActive ? "1" : "0",
            hostLiveGroovePhaseRaw ?? "",
            hostLiveGrooveStyleRaw ?? "",
            hostLiveGrooveBPM.map { String(format: "%.1f", $0) } ?? "",
            hostGlobalGenreID ?? "",
            hostGlobalGenreLabel ?? ""
        ].joined(separator: "|")
    }

    func metronomeSyncSignature() -> MetronomeSyncSignature {
        MetronomeSyncSignature(
            tempoBPM: tempoBPM,
            beatsPerBar: beatsPerBar,
            beatUnit: beatUnit,
            isMetronomePlaying: isMetronomePlaying,
            metronomeStartEpoch: metronomeStartEpoch,
            countInBars: countInBars,
            isCountingIn: isCountingIn,
            countInStartEpoch: countInStartEpoch,
            countInBeatsRemaining: countInBeatsRemaining
        )
    }

    /// True when only live piano / chord fields changed — avoids full payload replacement on guests.
    func isLiveChordBurst(comparedTo prior: SessionSyncPayload) -> Bool {
        sessionToken == prior.sessionToken
            && chords == prior.chords
            && activeChordID == prior.activeChordID
            && hasInferredLiveProgression == prior.hasInferredLiveProgression
            && activeCue?.sentAt == prior.activeCue?.sentAt
            && metronomeSyncSignature() == prior.metronomeSyncSignature()
            && silentNudgeSequence == prior.silentNudgeSequence
            && guestRoleAssignments == prior.guestRoleAssignments
            && pendingHostHandoffPeer == prior.pendingHostHandoffPeer
            && coHostPeerName == prior.coHostPeerName
            // Chat / quick messages must take the full-merge path, not live-burst merge.
            && bandChatMessages == prior.bandChatMessages
            && quickMessages == prior.quickMessages
    }

    func applyingLiveBurst(from received: SessionSyncPayload) -> SessionSyncPayload {
        var merged = self
        merged.pianoNotes = received.pianoNotes
        merged.liveChordSymbol = received.liveChordSymbol
        merged.freestyleChordSymbols = received.freestyleChordSymbols
        merged.liveRingUsageCounts = received.liveRingUsageCounts
        merged.liveRingRecentOrder = received.liveRingRecentOrder
        merged.liveRingCanonicalSymbols = received.liveRingCanonicalSymbols
        merged.liveRingSegments = received.liveRingSegments
        merged.key = received.key
        merged.isKeyAutoDetected = received.isKeyAutoDetected
        merged.beatsOnActiveChord = received.beatsOnActiveChord
        merged.isPianoActive = received.isPianoActive
        merged.hasInferredLiveProgression = received.hasInferredLiveProgression
        return merged
    }
}

/// Fields that drive local metronome playback on guests.
struct MetronomeSyncSignature: Equatable, Sendable {
    var tempoBPM: Double
    var beatsPerBar: Int
    var beatUnit: Int
    var isMetronomePlaying: Bool
    var metronomeStartEpoch: Double?
    var countInBars: Int
    var isCountingIn: Bool
    var countInStartEpoch: Double?
    var countInBeatsRemaining: Int
}

enum SessionMessageCodec {
    static func encode(_ message: SessionMessage) -> Data? {
        try? JSONEncoder().encode(message)
    }

    static func decode(_ data: Data) -> SessionMessage? {
        try? JSONDecoder().decode(SessionMessage.self, from: data)
    }
}

/// One round-trip sample used to estimate the clock offset between a guest and
/// the host, NTP-style.
struct TimeSyncPing: Codable, Sendable {
    let id: UUID
    let clientSendEpoch: Double
    var hostEpoch: Double?
}

/// Ultra-compact live chord update — avoids encoding the full session payload on every MIDI event.
struct LiveChordWire: Codable, Sendable, Equatable {
    var sessionToken: UUID
    var revision: UInt64
    var liveChordSymbol: String?
    var pianoNotes: [Int]
    var freestyleChordSymbols: [String]
    var key: MusicalKey
    var isKeyAutoDetected: Bool
    var isPianoActive: Bool
}

/// Everything that travels over the peer connection.
enum SessionMessage: Codable, Sendable {
    case state(SessionSyncPayload)
    case liveChord(LiveChordWire)
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
        chords.map { ($0.symbol, latinName(forSymbol: $0.symbol)) }
    }

    /// Converts a letter-name chord (e.g. "C#m7") into its configured Latin spelling ("Do#m7").
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
        guard let split = splitLetterRoot(from: symbol) else { return symbol }
        let toneNames = GuestDisplaySettings.chromaticToneNames
        let mappedRoot: String
        if let custom = toneNames.name(forLetterRoot: split.root) {
            mappedRoot = custom
        } else if let first = split.root.first {
            let letter = Character(first.uppercased())
            guard let solfege = solfegeForLetter[letter] else { return symbol }
            let accidental = String(split.root.dropFirst())
                .replacingOccurrences(of: "#", with: "♯")
                .replacingOccurrences(of: "b", with: "♭")
            mappedRoot = solfege + accidental
        } else {
            return symbol
        }
        let quality = split.quality
            .replacingOccurrences(of: "#", with: "♯")
            .replacingOccurrences(of: "b", with: "♭")
        return mappedRoot + quality
    }

    /// Splits `C#m7` → root `C#`, quality `m7`; `Bb` → `Bb` / ``; `9` → nil.
    private static func splitLetterRoot(from symbol: String) -> (root: String, quality: String)? {
        guard let first = symbol.first else { return nil }
        let letter = Character(first.uppercased())
        guard solfegeForLetter[letter] != nil else { return nil }
        var rootEnd = symbol.index(after: symbol.startIndex)
        while rootEnd < symbol.endIndex {
            let ch = symbol[rootEnd]
            if ch == "#" || ch == "♯" || ch == "＃" || ch == "b" || ch == "♭" {
                rootEnd = symbol.index(after: rootEnd)
            } else {
                break
            }
        }
        let root = String(symbol[..<rootEnd])
        let quality = String(symbol[rootEnd...])
        return (root, quality)
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
        let trimmed = symbol.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Accept Latin solfège roots used in display (La, Lam7, …) as well as letter names.
        let latinRoots = ["Sol", "Do", "Re", "Mi", "Fa", "La", "Si"]
        for latin in latinRoots {
            if trimmed.hasPrefix(latin) || trimmed.hasPrefix(latin.lowercased()) {
                let rootLength = latin.count
                var end = rootLength
                let chars = Array(trimmed)
                if chars.count > rootLength {
                    switch chars[rootLength] {
                    case "#", "♯", "b", "♭": end = rootLength + 1
                    default: break
                    }
                }
                return (String(chars[0..<end]), String(chars[end...]))
            }
        }

        let chars = Array(trimmed)
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
        let normalized = root
            .replacingOccurrences(of: "♯", with: "#")
            .replacingOccurrences(of: "♭", with: "b")
        let latinMap: [String: Int] = [
            "Do": 0, "Re": 2, "Mi": 4, "Fa": 5, "Sol": 7, "La": 9, "Si": 11
        ]
        for (latin, base) in latinMap {
            if normalized.hasPrefix(latin) || normalized.lowercased().hasPrefix(latin.lowercased()) {
                var value = base
                let accidentalIndex = latin.count
                let chars = Array(normalized)
                if chars.count > accidentalIndex {
                    switch chars[accidentalIndex] {
                    case "#": value += 1
                    case "b": value -= 1
                    default: break
                    }
                }
                return ((value % 12) + 12) % 12
            }
        }

        let chars = Array(normalized)
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

struct TimeSignature: Identifiable, Equatable, Hashable, Sendable {
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

    /// Guest beginner piano: collapse extended chords to a major or minor triad only.
    /// Returns `nil` for sus / dim / aug / power / unparseable symbols (show host notes unchanged).
    static func beginnerMajorMinorTriad(
        for symbol: String
    ) -> (root: Int, isMinor: Bool)? {
        let base = symbol.split(separator: "/").first.map(String.init) ?? symbol
        guard let (root, suffix) = Transposer.parse(base),
              let rootPC = Transposer.pitchClass(ofRoot: root),
              let isMinor = beginnerIsMinorTriad(suffix: suffix) else { return nil }
        return (rootPC, isMinor)
    }

    /// Simplified label for beginners — e.g. `Cmaj9` → `C`, `Cm9` → `Cm`.
    static func beginnerTriadSymbol(for symbol: String, preferFlats: Bool) -> String? {
        guard let triad = beginnerMajorMinorTriad(for: symbol) else { return nil }
        let rootName = (preferFlats ? Transposer.flatNames : Transposer.sharpNames)[triad.root]
        return triad.isMinor ? rootName + "m" : rootName
    }

    /// Piano keys to highlight for a beginner: root–3–5 near the host's right hand.
    static func beginnerTriadNotes(
        from hostNotes: [Int],
        symbol: String?
    ) -> [Int]? {
        guard let symbol,
              let triad = beginnerMajorMinorTriad(for: symbol) else { return nil }

        let thirdInterval = triad.isMinor ? 3 : 4
        // Prefer the right-hand register so the guest sees one clean treble triad.
        let split = PianoNote.upperKeyboardRange.lowerBound
        let rightHand = hostNotes.filter { $0 >= split }
        let anchor = rightHand.min() ?? hostNotes.max() ?? PianoNote.middleC
        let rootNote = nearestKeyboardNote(pitchClass: triad.root, near: anchor)
        let candidates = [rootNote, rootNote + thirdInterval, rootNote + 7]
            .filter { PianoNote.keyboardRange.contains($0) }
        return candidates.isEmpty ? nil : candidates
    }

    /// `true` = minor triad family, `false` = major/dominant family, `nil` = not a maj/min teaching triad.
    private static func beginnerIsMinorTriad(suffix: String) -> Bool? {
        let s = suffix.lowercased()
        if s.contains("sus") { return nil }
        if s.contains("dim") || s.contains("°") || s.contains("ø") || s.contains("m7b5") { return nil }
        if s.hasPrefix("aug") || s.hasPrefix("+") { return nil }
        if s == "5" { return nil }

        let isMinor = (s.hasPrefix("m") && !s.hasPrefix("maj")) || s.hasPrefix("min")
        return isMinor
    }

    private static func nearestKeyboardNote(pitchClass: Int, near target: Int) -> Int {
        let pc = ((pitchClass % 12) + 12) % 12
        let base = target - ((target % 12 - pc + 12) % 12)
        let options = [base - 12, base, base + 12]
            .filter { PianoNote.keyboardRange.contains($0) }
        return options.min(by: { abs($0 - target) < abs($1 - target) }) ?? max(
            PianoNote.keyboardRange.lowerBound,
            min(PianoNote.keyboardRange.upperBound, base)
        )
    }
}

/// Normalizes live-played chord symbols so duplicates and inversions collapse to one bubble.
enum LiveRing {
    /// Chords shown on the live ring (keeps the UI readable).
    static let maxDisplayChords = 6
    static let maxChordsPerRing = maxDisplayChords
    static let maxStoredRings = 6
    static let maxLiveProgressionChords = 16

    /// Ranks normalized symbols by play count, then recency; returns display spellings.
    static func rankedDisplaySymbols(
        counts: [String: Int],
        recentOrder: [String],
        canonicalByNormalized: [String: String],
        maxCount: Int = maxDisplayChords
    ) -> [String] {
        guard !counts.isEmpty else { return [] }
        let ranked = counts.keys.sorted { lhs, rhs in
            let leftCount = counts[lhs] ?? 0
            let rightCount = counts[rhs] ?? 0
            if leftCount != rightCount { return leftCount > rightCount }
            let leftRecency = recentOrder.lastIndex(of: lhs) ?? -1
            let rightRecency = recentOrder.lastIndex(of: rhs) ?? -1
            return leftRecency > rightRecency
        }
        return ranked.prefix(maxCount).map { canonicalByNormalized[$0] ?? $0 }
    }

    /// Compares chord symbols for ring deduplication (ignores slash bass and spacing).
    static func matches(_ a: String, _ b: String) -> Bool {
        normalize(a) == normalize(b)
    }

    static func contains(_ symbol: String, in ring: [String]) -> Bool {
        ring.contains { matches($0, symbol) }
    }

    static func normalize(_ symbol: String) -> String {
        let trimmed = symbol.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        let base = trimmed.split(separator: "/", maxSplits: 1).first.map(String.init) ?? trimmed
        return base
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

    /// Split between left-hand (below C3) and right-hand (C3+) registers.
    static var handSplitIndex: Int { PianoNote.upperKeyboardRange.lowerBound }

    /// Learns from both hands: LH chord or bass root + RH quality.
    /// Example: LH Sol (G) + RH Fa major → `G` for beginner/live labeling.
    /// Example: LH La octaves + RH Am7 (or C–E–G over A) → `Am`, not `A`.
    static func symbolConsideringBothHands(
        notes: [Int],
        preferFlats: Bool
    ) -> String? {
        let normalized = notes
            .map { PianoNote.normalizeToInternal($0) }
            .filter { PianoNote.keyboardRange.contains($0) }
            .sorted()
        guard !normalized.isEmpty else { return nil }

        let split = handSplitIndex
        // Bass-octave twins that sit on/above C3 still belong to LH analysis
        // (Do2+Do3 under an upper structure must not look like RH-only C + G triad).
        let (left, right) = PianoNote.analysisHandGroups(for: normalized, split: split)

        let leftPCs = Set(left.map { PianoNote.pitchClass(of: $0) })
        let rightPCs = Set(right.map { PianoNote.pitchClass(of: $0) })
        let leftBass = left.min().map { PianoNote.pitchClass(of: $0) }
        let rightBass = right.min().map { PianoNote.pitchClass(of: $0) }

        let leftSymbol = symbol(forPitchClasses: leftPCs, bassPitchClass: leftBass, preferFlats: preferFlats)
        let rightSymbol = symbol(forPitchClasses: rightPCs, bassPitchClass: rightBass, preferFlats: preferFlats)
        let allPCs = Set(normalized.map { PianoNote.pitchClass(of: $0) })
        let overallBass = normalized.min().map { PianoNote.pitchClass(of: $0) }
        let combinedSymbol = symbol(
            forPitchClasses: allPCs,
            bassPitchClass: overallBass,
            preferFlats: preferFlats
        )

        // Lower board through B3 — catches LH triads whose top note sits just above C3 (e.g. D3).
        let lowerRegister = normalized.filter { $0 < PianoNote.middleC }
        let lowerPCs = Set(lowerRegister.map { PianoNote.pitchClass(of: $0) })
        let lowerBass = lowerRegister.min().map { PianoNote.pitchClass(of: $0) }
        let lowerSymbol = symbol(
            forPitchClasses: lowerPCs,
            bassPitchClass: lowerBass,
            preferFlats: preferFlats
        )

        let resolved: String?
        // 1) Full left-hand chord below C3 (e.g. G–B–D with D below C3).
        if let leftSymbol, leftPCs.count >= 3 {
            resolved = stripSlashBass(leftSymbol)
        }
        // 1a) Octave bass shell + combined chord on that bass wins over a misleading
        //     lower-register partial (C+G+B below C4 can false-match Gadd11 via omit-fifth).
        else if PianoNote.hasSoundingBassOctaveShell(normalized),
                let overallBass,
                let combinedSymbol,
                let combinedTriad = ChordTheory.beginnerMajorMinorTriad(for: combinedSymbol),
                combinedTriad.root == overallBass {
            resolved = stripSlashBass(combinedSymbol)
        }
        // 1b) Full triad in the lower register (< C4), even if the 5th sits on D3/E3.
        //     Require the triad root to match the lower bass so partial upper tones don't steal the label.
        else if let lowerSymbol,
                lowerPCs.count >= 3,
                let lowerBass,
                let lowerTriad = ChordTheory.beginnerMajorMinorTriad(for: lowerSymbol),
                lowerTriad.root == lowerBass {
            resolved = stripSlashBass(lowerSymbol)
        }
        // 2) Sparse LH (octaves/root) + combined chord rooted on that bass → keep quality.
        //    La+La + Am7 / C–E–G → Am7 (beginner shows Am), never plain A major.
        //    Also: Do+Do + Sol–Si–Re–Mi → Cmaj9, never plain G from the upper structure alone.
        else if leftPCs.count <= 2,
                let leftBass,
                let combinedSymbol,
                let combinedTriad = ChordTheory.beginnerMajorMinorTriad(for: combinedSymbol),
                combinedTriad.root == leftBass {
            resolved = stripSlashBass(combinedSymbol)
        }
        // 3) LH bass + different RH maj/min color → root from LH, quality from RH.
        //    Sol in LH + Fa major in RH → G (not F).
        else if let leftBass,
                let rightSymbol,
                let rhTriad = ChordTheory.beginnerMajorMinorTriad(for: rightSymbol),
                rhTriad.root != leftBass {
            let names = preferFlats ? Transposer.flatNames : Transposer.sharpNames
            // Prefer combined bass-rooted quality when RH looks like an upper structure of that bass.
            if let combinedSymbol,
               let combinedTriad = ChordTheory.beginnerMajorMinorTriad(for: combinedSymbol),
               combinedTriad.root == leftBass {
                resolved = stripSlashBass(combinedSymbol)
            } else {
                resolved = rhTriad.isMinor ? names[leftBass] + "m" : names[leftBass]
            }
        } else if let rightSymbol,
                  let overallBass,
                  let rhTriad = ChordTheory.beginnerMajorMinorTriad(for: rightSymbol),
                  rhTriad.root != overallBass,
                  PianoNote.hasSoundingBassOctaveShell(normalized) {
            // Never let RH-only labeling win over a clear LH octave shell.
            if let combinedSymbol,
               let combinedTriad = ChordTheory.beginnerMajorMinorTriad(for: combinedSymbol),
               combinedTriad.root == overallBass {
                resolved = stripSlashBass(combinedSymbol)
            } else {
                let names = preferFlats ? Transposer.flatNames : Transposer.sharpNames
                resolved = rhTriad.isMinor ? names[overallBass] + "m" : names[overallBass]
            }
        } else if let rightSymbol {
            resolved = stripSlashBass(rightSymbol)
        } else if let leftSymbol {
            resolved = stripSlashBass(leftSymbol)
        } else {
            resolved = combinedSymbol.map { stripSlashBass($0) }
        }

        if let resolved {
            TwoHandChordMemory.shared.remember(notes: normalized, symbol: resolved)
        } else if let remembered = TwoHandChordMemory.shared.recall(notes: normalized) {
            return remembered
        }
        return resolved
    }

    /// When a live label disagrees with the sounding bass octave shell, prefer the bass-rooted symbol.
    /// Feeds TwoHandChordMemory so the next pass of the same voicing stays stable.
    static func reconcileSymbolWithVoicing(
        notes: [Int],
        chordSymbol: String?,
        preferFlats: Bool
    ) -> String? {
        let normalized = notes
            .map { PianoNote.normalizeToInternal($0) }
            .filter { PianoNote.keyboardRange.contains($0) }
            .sorted()
        guard !normalized.isEmpty else { return chordSymbol }

        let voicingSymbol = symbolConsideringBothHands(notes: normalized, preferFlats: preferFlats)
        guard let chordSymbol, !chordSymbol.isEmpty else { return voicingSymbol }

        guard PianoNote.symbolConflictsWithSoundingBass(chordSymbol: chordSymbol, notes: normalized) else {
            return chordSymbol
        }

        if let voicingSymbol {
            TwoHandChordMemory.shared.remember(notes: normalized, symbol: voicingSymbol)
            return voicingSymbol
        }
        // Drop the conflicting label rather than keep a root that tears hand roles apart.
        return nil
    }

    /// Pure string helper — safe outside the main actor (Swift 6 Optional.map).
    nonisolated private static func stripSlashBass(_ symbol: String) -> String {
        symbol.split(separator: "/").first.map(String.init) ?? symbol
    }
}

// MARK: - Fast two-hand chord memory (learns live voicings quickly)

/// Remembers recent left/right-hand note fingerprints → chord symbol so live
/// two-hand voicings (LH root + RH triad) stabilize after one or two plays.
final class TwoHandChordMemory: @unchecked Sendable {
    static let shared = TwoHandChordMemory()

    private let lock = NSLock()
    private var hits: [String: (symbol: String, count: Int)] = [:]
    private let limit = 80

    func recall(notes: [Int]) -> String? {
        let key = fingerprint(notes)
        lock.lock()
        defer { lock.unlock() }
        guard let entry = hits[key], entry.count >= 1 else { return nil }
        return entry.symbol
    }

    func remember(notes: [Int], symbol: String) {
        let key = fingerprint(notes)
        lock.lock()
        defer { lock.unlock() }
        if var entry = hits[key], entry.symbol == symbol {
            entry.count += 1
            hits[key] = entry
        } else {
            hits[key] = (symbol, 1)
        }
        if hits.count > limit {
            let sorted = hits.sorted { $0.value.count < $1.value.count }
            for item in sorted.prefix(hits.count - limit) {
                hits.removeValue(forKey: item.key)
            }
        }
    }

    private func fingerprint(_ notes: [Int]) -> String {
        // v3: bass-octave twins on/above C3 count as LH (Do2+Do3 under upper structure).
        let split = ChordRecognizer.handSplitIndex
        let (leftNotes, rightNotes) = PianoNote.analysisHandGroups(for: notes, split: split)
        let left = Set(leftNotes.map { PianoNote.pitchClass(of: $0) }).sorted()
        let right = Set(rightNotes.map { PianoNote.pitchClass(of: $0) }).sorted()
        let leftPart = left.map(String.init).joined(separator: ",")
        let rightPart = right.map(String.init).joined(separator: ",")
        return "v3|L\(leftPart)|R\(rightPart)"
    }
}

/// Helpers for naming piano keys by absolute semitone index (0 = C0).
enum PianoNote {
    /// MIDI note number offset (MIDI 12 = internal index 0 = C0).
    static let midiOffset = 12

    static func fromMIDINote(_ midi: Int) -> Int { midi - midiOffset }

    /// Internal index range: A0 (9) through C8 (96) — full 88-key piano.
    static let keyboardRange = 9...96

    /// On-screen live keyboard shows the full 88-key span (scrollable on all platforms).
    static let liveKeyboardRange = keyboardRange

    /// Dual-row lower board: A0 (9) … B3 (47) — fixed window; LH notes light here.
    static let lowerKeyboardRange = 9...47

    /// Dual-row upper board: C3 (36) … C8 (96) — fixed window; RH notes light here.
    /// Overlaps LH through B3 so neither hand feels cut off; lighting stays exclusive per hand.
    static let upperKeyboardRange = 36...96

    /// Classic C3 register boundary used when assigning bass vs treble roles.
    static let handRegisterSplit = 36

    /// MIDI note numbers for the 88-key span (A0=21 … C8=108).
    static let keyboardMIDIRange = 21...108

    /// Default scroll anchor when no notes are held (middle C / C4).
    static let middleC = 48

    /// Default scroll anchor for the lower (bass) dual-row keyboard (C2).
    static let lowerMiddleC = 24

    /// Narrowest white key that stays usable for tap/click without stacking rows.
    /// ~26pt still tracks well with a pointer; touch platforms fall back to dual-row sooner via width.
    static let minComfortableWhiteKeyWidth: CGFloat = 26

    /// Preferred white-key width when scrolling a partial viewport.
    static let preferredWhiteKeyWidth: CGFloat = 46

    /// Musical left / right-hand division for dual piano boards.
    /// Uses fixed board windows and role-based assignment (bass/root vs chord body).
    struct HandDivision: Equatable, Sendable {
        let leftNotes: [Int]
        let rightNotes: [Int]
        /// Keys shown on the lower (LH) board — always `lowerKeyboardRange` for dual layouts.
        let lowerRange: ClosedRange<Int>
        /// Keys shown on the upper (RH) board — always `upperKeyboardRange` for dual layouts.
        let upperRange: ClosedRange<Int>

        var usesBothHands: Bool { !leftNotes.isEmpty && !rightNotes.isEmpty }

        var leftScrollTarget: Int {
            let mid = ((leftNotes.min() ?? PianoNote.lowerMiddleC) + (leftNotes.max() ?? PianoNote.lowerMiddleC)) / 2
            return mid
        }

        var rightScrollTarget: Int {
            let mid = ((rightNotes.min() ?? PianoNote.middleC) + (rightNotes.max() ?? PianoNote.middleC)) / 2
            return mid
        }
    }

    /// How Piano Keys presents the live keyboard.
    enum KeysLayoutMode: String, CaseIterable, Identifiable, Sendable {
        case auto
        case alwaysDual
        case single

        var id: String { rawValue }

        var label: String {
            switch self {
            case .auto: String(localized: "Auto")
            case .alwaysDual: String(localized: "2 hands")
            case .single: String(localized: "1 keyboard")
            }
        }
    }

    /// Split a live voicing into LH / RH for dual-board display.
    /// - LH: bass / root (+ octave or fifth below the treble cluster)
    /// - RH: remaining chord tones
    /// Board ranges stay fixed so the UI does not jump when voicings change.
    /// When `chordSymbol` root conflicts with the sounding bass octave shell, the symbol
    /// is ignored for hand-role fifths so a bad live label cannot tear octaves apart.
    static func handDivision(for notes: [Int], chordSymbol: String? = nil) -> HandDivision? {
        let sorted = Array(Set(notes.map { normalizeToInternal($0) }.filter { keyboardRange.contains($0) })).sorted()
        guard sorted.count >= 2 else { return nil }

        let roleRootPC = handRoleRootPitchClass(sorted: sorted, chordSymbol: chordSymbol)

        // Pure octaves / unisons of one pitch class → one bass board.
        let pitchClasses = Set(sorted.map { pitchClass(of: $0) })
        if pitchClasses.count == 1 {
            return lowerOnlyDivision(leftNotes: sorted)
        }

        let (left, right) = assignHandsByMusicalRole(sorted: sorted, rootPitchClass: roleRootPC)

        if right.isEmpty {
            return lowerOnlyDivision(leftNotes: left)
        }
        if left.isEmpty {
            // Treble-only cluster — single scrolling board.
            return nil
        }

        return HandDivision(
            leftNotes: left,
            rightNotes: right,
            lowerRange: lowerKeyboardRange,
            upperRange: upperKeyboardRange
        )
    }

    /// Groups notes for two-hand chord analysis (not dual-board lighting).
    /// Bass-octave twins through B3 stay with the left-hand group even at/above C3.
    static func analysisHandGroups(for sorted: [Int], split: Int) -> (left: [Int], right: [Int]) {
        guard let lowest = sorted.first else { return ([], []) }
        let bassPC = pitchClass(of: lowest)
        var left: [Int] = []
        var right: [Int] = []
        for note in sorted {
            let isBassTwin = pitchClass(of: note) == bassPC
                && note <= lowerKeyboardRange.upperBound
                && (note < split || note - lowest <= 12)
            if note < split || isBassTwin {
                left.append(note)
            } else {
                right.append(note)
            }
        }
        return (left, right)
    }

    /// True when the lowest pitch class is doubled as a low octave shell (e.g. Do2+Do3).
    static func hasSoundingBassOctaveShell(_ notes: [Int]) -> Bool {
        let sorted = Array(Set(notes.map { normalizeToInternal($0) }.filter { keyboardRange.contains($0) })).sorted()
        guard let lowest = sorted.first else { return false }
        let bassPC = pitchClass(of: lowest)
        guard sorted.contains(where: { pitchClass(of: $0) == bassPC && $0 < handRegisterSplit }) else {
            return false
        }
        return sorted.contains {
            pitchClass(of: $0) == bassPC
                && $0 > lowest
                && $0 <= lowerKeyboardRange.upperBound
                && $0 - lowest <= 12
        }
    }

    /// Live chord label root disagrees with an octave bass shell in the MIDI voicing.
    static func symbolConflictsWithSoundingBass(chordSymbol: String?, notes: [Int]) -> Bool {
        guard let chordSymbol,
              let symbolRoot = ChordTheory.tones(for: chordSymbol)?.root,
              hasSoundingBassOctaveShell(notes),
              let bassPC = notes
                .map({ normalizeToInternal($0) })
                .filter({ keyboardRange.contains($0) })
                .min()
                .map({ pitchClass(of: $0) })
        else { return false }
        return symbolRoot != bassPC
    }

    /// Root used only for optional LH fifth shells. Prefer sounding bass; drop conflicting symbols.
    static func handRoleRootPitchClass(sorted: [Int], chordSymbol: String?) -> Int? {
        guard let symbolRoot = chordSymbol.flatMap({ ChordTheory.tones(for: $0)?.root }) else {
            return nil
        }
        guard let bassPC = sorted.first.map({ pitchClass(of: $0) }) else { return symbolRoot }
        if symbolRoot == bassPC { return symbolRoot }
        // Octave bass under a mismatched label (C octaves labeled G) → ignore symbol root.
        if hasSoundingBassOctaveShell(sorted) { return nil }
        // True slash / alternate bass (single low tone) may keep chord-root fifth cues.
        return symbolRoot
    }

    /// Assign notes to LH/RH using bass register + root/fifth roles.
    private static func assignHandsByMusicalRole(
        sorted: [Int],
        rootPitchClass: Int?
    ) -> (left: [Int], right: [Int]) {
        guard let lowest = sorted.first else { return ([], []) }

        // Pure treble cluster (nothing below C3) → one scrolling keyboard.
        guard sorted.contains(where: { $0 < handRegisterSplit }) else {
            return ([], [])
        }

        // LH octaves follow the *sounding* bass note, not the chord-symbol root.
        // Otherwise C2+C3 under a G-ish recognition (Sol–Si–Re–Mi on top) leaves only one Do on LH.
        let playedBassPC = pitchClass(of: lowest)
        let fifthOfBassPC = (playedBassPC + 7) % 12
        // Optional: also treat chord-root fifth as LH shell when it matches a low dyad.
        let chordFifthPC = rootPitchClass.map { ($0 + 7) % 12 }

        var leftSet = Set<Int>()
        for note in sorted {
            let pc = pitchClass(of: note)
            if note < handRegisterSplit {
                leftSet.insert(note)
                continue
            }
            guard note <= lowerKeyboardRange.upperBound else { continue }

            // Keep every octave of the sounding bass on LH through B3 (Do+Do).
            if pc == playedBassPC {
                let hasLowerTwin = sorted.contains { pitchClass(of: $0) == pc && $0 < handRegisterSplit }
                if hasLowerTwin || note - lowest <= 12 {
                    leftSet.insert(note)
                }
                continue
            }

            // Low fifth shells (G2+D3, or C2+G2) stay on LH.
            let isBassFifth = pc == fifthOfBassPC
            let isChordFifth = chordFifthPC == pc
            if isBassFifth || isChordFifth {
                let hasLowerTwin = sorted.contains { pitchClass(of: $0) == pc && $0 < handRegisterSplit }
                if hasLowerTwin || note - lowest <= 7 {
                    leftSet.insert(note)
                }
            }
        }

        // Always keep the lowest bass tone + its octaves on LH through B3.
        leftSet.insert(lowest)
        for note in sorted where pitchClass(of: note) == playedBassPC && note <= lowerKeyboardRange.upperBound {
            let hasLowerTwin = sorted.contains { pitchClass(of: $0) == playedBassPC && $0 < handRegisterSplit }
            if hasLowerTwin || note == lowest || note - lowest <= 12 {
                leftSet.insert(note)
            }
        }

        var left = sorted.filter { leftSet.contains($0) }
        var right = sorted.filter { !leftSet.contains($0) }

        // If everything landed on LH but there is a clear treble gap, move upper non-bass tones to RH.
        if right.isEmpty, left.count >= 3, let gapSplit = firstWideGapSplit(in: left) {
            let newLeft = Array(left[0...gapSplit])
            let leftFinal = Set(newLeft)
            left = newLeft
            right = sorted.filter { !leftFinal.contains($0) }
        }

        // Fold RH that only doubles LH pitch classes back into lower-only.
        if !left.isEmpty, !right.isEmpty {
            let leftPCs = Set(left.map { pitchClass(of: $0) })
            let rightPCs = Set(right.map { pitchClass(of: $0) })
            if rightPCs.isSubset(of: leftPCs) {
                return (sorted, [])
            }
        }

        return (left, right)
    }

    private static func firstWideGapSplit(in sorted: [Int]) -> Int? {
        guard sorted.count >= 2 else { return nil }
        var bestIndex: Int?
        var bestGap = 0
        for index in 0..<(sorted.count - 1) {
            let low = sorted[index]
            let high = sorted[index + 1]
            let gap = high - low
            if pitchClass(of: low) == pitchClass(of: high), (11...13).contains(gap) {
                continue
            }
            if gap >= 7, gap > bestGap {
                bestGap = gap
                bestIndex = index
            }
        }
        return bestIndex
    }

    private static func lowerOnlyDivision(leftNotes: [Int]) -> HandDivision? {
        guard !leftNotes.isEmpty else { return nil }
        return HandDivision(
            leftNotes: leftNotes,
            rightNotes: [],
            lowerRange: lowerKeyboardRange,
            upperRange: upperKeyboardRange
        )
    }

    /// True when a voicing should use stacked LH/RH boards.
    static func spansBothHands(_ notes: [Int], chordSymbol: String? = nil) -> Bool {
        handDivision(for: notes, chordSymbol: chordSymbol)?.usesBothHands ?? false
    }

    /// Bass-only voicing (e.g. Sol2+Sol3) that should use one extended lower board.
    static func lowerBoardOnly(for notes: [Int], chordSymbol: String? = nil) -> HandDivision? {
        guard let division = handDivision(for: notes, chordSymbol: chordSymbol),
              !division.leftNotes.isEmpty,
              division.rightNotes.isEmpty else { return nil }
        return division
    }

    /// Remap live notes onto a previous hand shape (same chord) so boards don't flip-flop.
    static func stickyHandDivision(
        for notes: [Int],
        previous: HandDivision,
        chordSymbol: String? = nil
    ) -> HandDivision {
        let sorted = Array(Set(notes.map { normalizeToInternal($0) }.filter { keyboardRange.contains($0) })).sorted()
        guard !sorted.isEmpty else { return previous }

        if previous.rightNotes.isEmpty {
            return lowerOnlyDivision(leftNotes: sorted) ?? previous
        }

        let leftPCs = Set(previous.leftNotes.map { pitchClass(of: $0) })
        let rightPCs = Set(previous.rightNotes.map { pitchClass(of: $0) })
        let playedBassPC = sorted.first.map { pitchClass(of: $0) }

        var left: [Int] = []
        var right: [Int] = []
        for note in sorted {
            let pc = pitchClass(of: note)
            if leftPCs.contains(pc), note <= lowerKeyboardRange.upperBound {
                left.append(note)
            } else if let playedBassPC, pc == playedBassPC, note <= lowerKeyboardRange.upperBound {
                // Keep sounding-bass octaves on LH even if a prior split missed them.
                left.append(note)
            } else if rightPCs.contains(pc) {
                right.append(note)
            } else if note < handRegisterSplit {
                left.append(note)
            } else {
                right.append(note)
            }
        }

        if left.isEmpty, let lowest = sorted.first {
            left = [lowest]
            right = sorted.filter { $0 != lowest }
        }
        if right.isEmpty {
            return lowerOnlyDivision(leftNotes: left.isEmpty ? sorted : left) ?? previous
        }

        return HandDivision(
            leftNotes: left,
            rightNotes: right,
            lowerRange: lowerKeyboardRange,
            upperRange: upperKeyboardRange
        )
    }

    static func whiteKeyCount(in range: ClosedRange<Int>) -> Int {
        range.filter { !isBlack($0) }.count
    }

    /// True when the full note range can fit in `availableWidth` without uncomfortable key shrink.
    static func canFitComfortably(range: ClosedRange<Int>, in availableWidth: CGFloat) -> Bool {
        let count = max(1, whiteKeyCount(in: range))
        return availableWidth / CGFloat(count) >= minComfortableWhiteKeyWidth
    }

    /// Convert incoming value (legacy MIDI storage or internal) to internal index.
    /// Internal indices occupy 9…96; MIDI occupies 21…108. Prefer internal when the
    /// value already sits in the 88-key index span so A3 (45) is not mistaken for MIDI.
    static func normalizeToInternal(_ value: Int) -> Int {
        if keyboardRange.contains(value) { return value }
        if value > keyboardRange.upperBound, keyboardMIDIRange.contains(value) {
            return fromMIDINote(value)
        }
        if value < keyboardRange.lowerBound, keyboardMIDIRange.contains(value) {
            return fromMIDINote(value)
        }
        return value
    }

    static func toMIDI(_ internalIndex: Int) -> Int { internalIndex + midiOffset }

    static func pitchClass(of index: Int) -> Int { ((index % 12) + 12) % 12 }

    static func pitchClass(forStored value: Int) -> Int {
        pitchClass(of: normalizeToInternal(value))
    }

    static func octave(of index: Int) -> Int { index / 12 }
    static func isBlack(_ index: Int) -> Bool { [1, 3, 6, 8, 10].contains(pitchClass(of: index)) }

    static func isBlackMIDI(_ midi: Int) -> Bool { isBlack(fromMIDINote(midi)) }

    static func name(of index: Int, preferFlats: Bool, includeOctave: Bool = false) -> String {
        let names = preferFlats ? Transposer.flatNames : Transposer.sharpNames
        let base = names[pitchClass(of: index)]
        return includeOctave ? "\(base)\(octave(of: index))" : base
    }

    static func name(forStored value: Int, preferFlats: Bool, includeOctave: Bool = false) -> String {
        name(of: normalizeToInternal(value), preferFlats: preferFlats, includeOctave: includeOctave)
    }

    static func latinName(of index: Int, preferFlats: Bool) -> String {
        _ = preferFlats
        return GuestDisplaySettings.chromaticToneNames.name(forPitchClass: pitchClass(of: index))
    }

    static func latinName(forStored value: Int, preferFlats: Bool) -> String {
        latinName(of: normalizeToInternal(value), preferFlats: preferFlats)
    }

    static func keyboardLabel(for index: Int, preferFlats: Bool) -> String {
        _ = preferFlats
        let pc = pitchClass(of: index)
        let base = GuestDisplaySettings.chromaticToneNames.name(forPitchClass: pc)
        let showOctave = pc == 0 || isBlack(index)
        return showOctave ? "\(base)\(octave(of: index))" : base
    }
}

// MARK: - Live hand-split stabilizer (hysteresis)

/// Keeps LH/RH assignment stable while the same chord is held so boards don't flip in live play.
/// Integrates voicing fingerprints + confidence so a flickering/wrong `liveChordSymbol`
/// cannot tear a held octave bass + upper-structure split apart.
@MainActor
final class PianoHandSplitStabilizer {
    private var lastSymbol: String?
    private var lastVoicingKey: String?
    private var lastDivision: PianoNote.HandDivision?
    private var lockedAt: Date = .distantPast
    /// Hold the previous split this long after notes change under the same chord / voicing.
    var lockDuration: TimeInterval = 0.45

    func reset() {
        lastSymbol = nil
        lastVoicingKey = nil
        lastDivision = nil
        lockedAt = .distantPast
    }

    func division(for notes: [Int], chordSymbol: String?) -> PianoNote.HandDivision? {
        // Ignore conflicting labels for hand roles (Do+Do labeled as G, etc.).
        let roleSymbol: String?
        if PianoNote.symbolConflictsWithSoundingBass(chordSymbol: chordSymbol, notes: notes) {
            roleSymbol = nil
            // Teach two-hand memory the bass-rooted reading so the next recognition pass is stable.
            _ = ChordRecognizer.reconcileSymbolWithVoicing(
                notes: notes,
                chordSymbol: chordSymbol,
                preferFlats: false
            )
        } else {
            roleSymbol = chordSymbol
        }

        let fresh = PianoNote.handDivision(for: notes, chordSymbol: roleSymbol)
        let normalizedSymbol = chordSymbol?.trimmingCharacters(in: .whitespacesAndNewlines)
        let symbolKey = (normalizedSymbol?.isEmpty == false) ? normalizedSymbol : nil
        let voicingKey = Self.voicingFingerprint(notes)
        let now = Date()

        // Symbol flicker on the same held voicing is NOT a chord change.
        let symbolChanged = symbolKey != lastSymbol
        let voicingHeld = lastVoicingKey != nil && voicingKey == lastVoicingKey
        if symbolChanged && !voicingHeld {
            lastSymbol = symbolKey
            lastVoicingKey = voicingKey
            lastDivision = fresh
            lockedAt = now
            return fresh
        }

        lastSymbol = symbolKey
        lastVoicingKey = voicingKey

        guard let previous = lastDivision else {
            lastDivision = fresh
            lockedAt = now
            return fresh
        }

        let withinLock = now.timeIntervalSince(lockedAt) < lockDuration
        let stickyPreferred = withinLock || previous.usesBothHands || previous.rightNotes.isEmpty || voicingHeld

        if stickyPreferred {
            let sticky = PianoNote.stickyHandDivision(for: notes, previous: previous, chordSymbol: roleSymbol)
            // Only leave sticky when fresh evidence is strong and does not tear the bass shell.
            if !withinLock, shouldAdoptFresh(fresh, over: sticky, notes: notes) {
                lastDivision = fresh
                lockedAt = now
                return fresh
            }
            lastDivision = sticky
            return sticky
        }

        if shouldAdoptFresh(fresh, over: previous, notes: notes) {
            lastDivision = fresh
            lockedAt = now
            return fresh
        }

        let sticky = PianoNote.stickyHandDivision(for: notes, previous: previous, chordSymbol: roleSymbol)
        lastDivision = sticky
        return sticky
    }

    /// Bass PC + pitch-class set — stable while the same voicing is held.
    private static func voicingFingerprint(_ notes: [Int]) -> String {
        let sorted = Array(
            Set(notes.map { PianoNote.normalizeToInternal($0) }.filter { PianoNote.keyboardRange.contains($0) })
        ).sorted()
        let bass = sorted.first.map { PianoNote.pitchClass(of: $0) } ?? -1
        let pcs = Set(sorted.map { PianoNote.pitchClass(of: $0) }).sorted().map(String.init).joined(separator: ",")
        return "\(bass)|\(pcs)"
    }

    /// Adopt a new split only when it keeps the sounding bass shell and is a clear dual/lower shape.
    private func shouldAdoptFresh(
        _ fresh: PianoNote.HandDivision?,
        over previous: PianoNote.HandDivision,
        notes: [Int]
    ) -> Bool {
        guard let fresh else { return false }
        if fresh == previous { return true }

        let sorted = Array(
            Set(notes.map { PianoNote.normalizeToInternal($0) }.filter { PianoNote.keyboardRange.contains($0) })
        ).sorted()
        guard let lowest = sorted.first else { return true }
        let bassPC = PianoNote.pitchClass(of: lowest)
        let bassShell = sorted.filter {
            PianoNote.pitchClass(of: $0) == bassPC && $0 <= PianoNote.lowerKeyboardRange.upperBound
        }
        let freshKeepsBass = Set(bassShell).isSubset(of: Set(fresh.leftNotes))
        let previousKeepsBass = Set(bassShell).isSubset(of: Set(previous.leftNotes))

        // Never flip to a split that tears a previously intact octave bass.
        if previousKeepsBass && !freshKeepsBass { return false }
        if !freshKeepsBass { return false }

        // Same hand shape (dual vs lower-only) with remapped notes is fine.
        if fresh.usesBothHands == previous.usesBothHands { return true }
        // Switching dual ↔ single needs a clear dual gap or a pure lower board.
        if fresh.usesBothHands {
            return !fresh.rightNotes.isEmpty && fresh.leftNotes.count >= 1
        }
        return fresh.rightNotes.isEmpty
    }
}
