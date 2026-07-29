//
//  ExtendedFeatureModels.swift
//  Chordyx
//

import Foundation

// MARK: - Section auto-cues

struct SectionCueRule: Codable, Equatable, Hashable, Sendable {
    var cueText: String
    var cueSymbol: String
    var trigger: SectionCueTrigger

    static func hold() -> SectionCueRule {
        SectionCueRule(cueText: "Hold", cueSymbol: "hand.raised.fill", trigger: .onEnter)
    }
}

enum SectionCueTrigger: String, Codable, CaseIterable, Sendable {
    case onEnter
    case onLastChord
}

// MARK: - Role notes (per musician)

struct RoleChartNote: Codable, Equatable, Hashable, Sendable {
    var role: GuestViewRole
    var text: String

    init(role: GuestViewRole, text: String) {
        self.role = role
        self.text = text
    }

    init?(dictionaryKey key: String, text: String) {
        guard let role = GuestViewRole(rawValue: key) else { return nil }
        self.role = role
        self.text = text
    }
}

// MARK: - Quick band messages

struct SessionQuickMessage: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var senderName: String
    var text: String
    var symbol: String
    var sentAt: Double

    init(
        id: UUID = UUID(),
        senderName: String,
        text: String,
        symbol: String = "bubble.left.fill",
        sentAt: Double = Date().timeIntervalSince1970
    ) {
        self.id = id
        self.senderName = senderName
        self.text = text
        self.symbol = symbol
        self.sentAt = sentAt
    }

    static let presets: [(String, String)] = [
        (String(localized: "Again"), "arrow.counterclockwise"),
        (String(localized: "Slower"), "tortoise.fill"),
        (String(localized: "Guitar in"), "guitars.fill"),
        (String(localized: "Ready"), "hand.thumbsup.fill"),
    ]

    /// Short chips for the band chat sheet (kept separate from director quick messages).
    static let chatPresets: [(String, String)] = [
        (String(localized: "Ready"), "hand.thumbsup.fill"),
        (String(localized: "Wait"), "hand.raised.fill"),
        (String(localized: "Again"), "arrow.counterclockwise"),
        (String(localized: "Coming in"), "arrow.right.circle.fill"),
        (String(localized: "Louder"), "speaker.wave.2.fill"),
        (String(localized: "Quieter"), "speaker.fill"),
        (String(localized: "All good"), "checkmark.circle.fill"),
    ]
}

enum BandChatLimits {
    static let maxMessages = 50
    static let maxTextLength = 240
    static let pendingTimeoutSeconds: TimeInterval = 20
}

// MARK: - Peer presence

struct PeerPresenceInfo: Codable, Equatable, Sendable {
    var instrument: MusicianInstrument
    var syncQuality: SyncQuality
    var isLagging: Bool
    var reportedChordID: UUID?
    var isOnCurrentChord: Bool

    init(
        instrument: MusicianInstrument = .other,
        syncQuality: SyncQuality = .unknown,
        isLagging: Bool = false,
        reportedChordID: UUID? = nil,
        isOnCurrentChord: Bool = false
    ) {
        self.instrument = instrument
        self.syncQuality = syncQuality
        self.isLagging = isLagging
        self.reportedChordID = reportedChordID
        self.isOnCurrentChord = isOnCurrentChord
    }
}

// MARK: - Service timeline

struct ServiceTimelineBlock: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var title: String
    var offsetMinutes: Int
    var estimatedMinutes: Int

    init(
        id: UUID = UUID(),
        title: String,
        offsetMinutes: Int,
        estimatedMinutes: Int = 15
    ) {
        self.id = id
        self.title = title
        self.offsetMinutes = offsetMinutes
        self.estimatedMinutes = estimatedMinutes
    }
}

// MARK: - Capo / chart intelligence

struct CapoSuggestion: Equatable, Sendable {
    var chartKey: MusicalKey
    var vocalKey: MusicalKey
    var capoFret: Int
    var transposeSemitones: Int

    var summary: String {
        if capoFret > 0 {
            return String(
                format: String(localized: "Chart in %@ · sing in %@ · capo %lld"),
                chartKey.displayName,
                vocalKey.displayName,
                capoFret
            )
        }
        return String(
            format: String(localized: "Transpose chart %@ → %@"),
            chartKey.displayName,
            vocalKey.displayName
        )
    }
}

struct ChartDiffLine: Identifiable, Equatable, Sendable {
    let id = UUID()
    var sectionName: String?
    var left: String
    var right: String
    var kind: ChartDiffKind
}

enum ChartDiffKind: String, Sendable {
    case same
    case changed
    case added
    case removed
}

struct ChartDiffResult: Equatable, Sendable {
    var lines: [ChartDiffLine]

    var hasDifferences: Bool {
        lines.contains { $0.kind != .same }
    }
}

// MARK: - Smart checklist

struct SmartChecklistItem: Identifiable, Equatable, Sendable {
    let id: String
    var title: String
    var detail: String
    var icon: String
    var isAutoSatisfied: Bool
    var severity: SmartChecklistSeverity
}

enum SmartChecklistSeverity: Sendable {
    case info
    case warning
    case critical
}

// MARK: - Service stats

struct ServiceSessionStats: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var sessionName: String
    var endedAt: Date
    var durationSeconds: TimeInterval
    var songsPlayed: Int
    var cueCount: Int
    var transposeCount: Int
    var sectionJumps: Int
    var averageTempoBPM: Double

    init(
        id: UUID = UUID(),
        sessionName: String,
        endedAt: Date = Date(),
        durationSeconds: TimeInterval,
        songsPlayed: Int,
        cueCount: Int,
        transposeCount: Int,
        sectionJumps: Int,
        averageTempoBPM: Double
    ) {
        self.id = id
        self.sessionName = sessionName
        self.endedAt = endedAt
        self.durationSeconds = durationSeconds
        self.songsPlayed = songsPlayed
        self.cueCount = cueCount
        self.transposeCount = transposeCount
        self.sectionJumps = sectionJumps
        self.averageTempoBPM = averageTempoBPM
    }
}

// MARK: - Team library

struct TeamLibraryRevision: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var packName: String
    var updatedAt: Date
    var songCount: Int
    var revisionLabel: String

    init(
        id: UUID = UUID(),
        packName: String,
        updatedAt: Date = Date(),
        songCount: Int,
        revisionLabel: String
    ) {
        self.id = id
        self.packName = packName
        self.updatedAt = updatedAt
        self.songCount = songCount
        self.revisionLabel = revisionLabel
    }
}

// MARK: - Planning Center stub

struct PlanningCenterPlanItem: Identifiable, Equatable, Sendable {
    let id = UUID()
    var title: String
    var sequence: Int
    var keyName: String?
}

struct PlanningCenterImportDraft: Equatable, Sendable {
    var planTitle: String
    var items: [PlanningCenterPlanItem]
}

// MARK: - Audio chord stub

struct AudioChordDetectionDraft: Equatable, Sendable {
    var suggestedSymbols: [String]
    var confidence: Double
    var note: String

    static let unavailable = AudioChordDetectionDraft(
        suggestedSymbols: [],
        confidence: 0,
        note: String(localized: "Record a short clip during rehearsal to suggest chords. Full audio analysis ships in a future update.")
    )
}
