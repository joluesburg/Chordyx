//
//  FeatureModels.swift
//  Chordyx
//

import Foundation

// MARK: - Rehearsal timeline

enum RehearsalEventKind: String, Codable, Sendable {
    case chordChange
    case tempoChange
    case cue
    case sectionJump
    case metronomeToggle
    case setlistAdvance
    case errorMarker
}

struct RehearsalEvent: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var kind: RehearsalEventKind
    var timestamp: TimeInterval
    var chordID: UUID?
    var tempoBPM: Double?
    var cueText: String?
    var sectionID: UUID?
    var songTitle: String?

    init(
        id: UUID = UUID(),
        kind: RehearsalEventKind,
        timestamp: TimeInterval,
        chordID: UUID? = nil,
        tempoBPM: Double? = nil,
        cueText: String? = nil,
        sectionID: UUID? = nil,
        songTitle: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.timestamp = timestamp
        self.chordID = chordID
        self.tempoBPM = tempoBPM
        self.cueText = cueText
        self.sectionID = sectionID
        self.songTitle = songTitle
    }
}

struct RehearsalRecording: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var name: String
    var sessionName: String
    var recordedAt: Date
    var duration: TimeInterval
    var events: [RehearsalEvent]
    var initialPayload: SessionSyncPayload?

    init(
        id: UUID = UUID(),
        name: String,
        sessionName: String,
        recordedAt: Date = Date(),
        duration: TimeInterval = 0,
        events: [RehearsalEvent] = [],
        initialPayload: SessionSyncPayload? = nil
    ) {
        self.id = id
        self.name = name
        self.sessionName = sessionName
        self.recordedAt = recordedAt
        self.duration = duration
        self.events = events
        self.initialPayload = initialPayload
    }
}

// MARK: - Practice stats

struct PracticeSessionRecord: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var date: Date
    var durationSeconds: TimeInterval
    var songsPlayed: Int
    var sessionName: String
    var holdCueCount: Int
    var vampCueCount: Int

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        durationSeconds: TimeInterval,
        songsPlayed: Int,
        sessionName: String,
        holdCueCount: Int = 0,
        vampCueCount: Int = 0
    ) {
        self.id = id
        self.date = date
        self.durationSeconds = durationSeconds
        self.songsPlayed = songsPlayed
        self.sessionName = sessionName
        self.holdCueCount = holdCueCount
        self.vampCueCount = vampCueCount
    }
}

struct PracticeStatsSummary: Codable, Equatable, Sendable {
    var sessions: [PracticeSessionRecord]

    var totalMinutes: Double {
        sessions.reduce(0) { $0 + $1.durationSeconds } / 60
    }

    var totalSongs: Int {
        sessions.reduce(0) { $0 + $1.songsPlayed }
    }
}

// MARK: - Service templates

struct ServiceTemplate: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var name: String
    var setlistID: UUID?
    var performanceMode: SessionPerformanceMode
    var countInBars: Int
    var defaultTempoBPM: Double
    var checklistItems: [String]
    var internetBackupEnabled: Bool
    var timelineBlocks: [ServiceTimelineBlock]

    init(
        id: UUID = UUID(),
        name: String,
        setlistID: UUID? = nil,
        performanceMode: SessionPerformanceMode = .live,
        countInBars: Int = 1,
        defaultTempoBPM: Double = 100,
        checklistItems: [String] = ServiceTemplate.defaultChecklist,
        internetBackupEnabled: Bool = true,
        timelineBlocks: [ServiceTimelineBlock] = []
    ) {
        self.id = id
        self.name = name
        self.setlistID = setlistID
        self.performanceMode = performanceMode
        self.countInBars = countInBars
        self.defaultTempoBPM = defaultTempoBPM
        self.checklistItems = checklistItems
        self.internetBackupEnabled = internetBackupEnabled
        self.timelineBlocks = timelineBlocks
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, setlistID, performanceMode, countInBars, defaultTempoBPM
        case checklistItems, internetBackupEnabled, timelineBlocks
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        setlistID = try container.decodeIfPresent(UUID.self, forKey: .setlistID)
        performanceMode = try container.decodeIfPresent(SessionPerformanceMode.self, forKey: .performanceMode) ?? .live
        countInBars = try container.decodeIfPresent(Int.self, forKey: .countInBars) ?? 1
        defaultTempoBPM = try container.decodeIfPresent(Double.self, forKey: .defaultTempoBPM) ?? 100
        checklistItems = try container.decodeIfPresent([String].self, forKey: .checklistItems) ?? ServiceTemplate.defaultChecklist
        internetBackupEnabled = try container.decodeIfPresent(Bool.self, forKey: .internetBackupEnabled) ?? true
        timelineBlocks = try container.decodeIfPresent([ServiceTimelineBlock].self, forKey: .timelineBlocks) ?? []
    }

    static let defaultChecklist = [
        String(localized: "Sound check complete"),
        String(localized: "Band connected"),
        String(localized: "Metronome tempo set"),
        String(localized: "Count-in configured"),
    ]
}

// MARK: - Guest role presets (host-assigned)

struct GuestRolePreset: Codable, Equatable, Sendable {
    var role: GuestViewRole
    var transposeSemitones: Int
    var capoFret: Int
    var notation: ChordNotation?
    var liveNote: String

    init(
        role: GuestViewRole,
        transposeSemitones: Int,
        capoFret: Int,
        notation: ChordNotation? = nil,
        liveNote: String = ""
    ) {
        self.role = role
        self.transposeSemitones = transposeSemitones
        self.capoFret = capoFret
        self.notation = notation
        self.liveNote = liveNote
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        role = try container.decode(GuestViewRole.self, forKey: .role)
        transposeSemitones = try container.decodeIfPresent(Int.self, forKey: .transposeSemitones) ?? 0
        capoFret = try container.decodeIfPresent(Int.self, forKey: .capoFret) ?? 0
        notation = try container.decodeIfPresent(ChordNotation.self, forKey: .notation)
        liveNote = try container.decodeIfPresent(String.self, forKey: .liveNote) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case role, transposeSemitones, capoFret, notation, liveNote
    }

    static func preset(for role: GuestViewRole) -> GuestRolePreset {
        switch role {
        case .auto:
            return GuestRolePreset(role: .auto, transposeSemitones: 0, capoFret: 0, notation: nil)
        case .vocal:
            return GuestRolePreset(role: .vocal, transposeSemitones: 0, capoFret: 0, notation: .symbol)
        case .bass:
            return GuestRolePreset(role: .bass, transposeSemitones: 0, capoFret: 0, notation: .nashville, liveNote: String(localized: "Root · walkdowns"))
        case .keys:
            return GuestRolePreset(role: .keys, transposeSemitones: 0, capoFret: 0, notation: .symbol, liveNote: String(localized: "Voicing · pad"))
        case .drums:
            return GuestRolePreset(role: .drums, transposeSemitones: 0, capoFret: 0, notation: nil, liveNote: String(localized: "Pattern · fills"))
        case .guitar:
            return GuestRolePreset(role: .guitar, transposeSemitones: 0, capoFret: 0, notation: .symbol, liveNote: String(localized: "Capo · strum"))
        }
    }
}
