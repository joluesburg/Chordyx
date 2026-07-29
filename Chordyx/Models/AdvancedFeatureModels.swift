//
//  AdvancedFeatureModels.swift
//  Chordyx
//

import Foundation

// MARK: - Click track lanes

enum ClickTrackLane: String, Codable, CaseIterable, Identifiable, Sendable {
    case full
    case light
    case mute

    var id: String { rawValue }

    var label: String {
        switch self {
        case .full: String(localized: "Full click")
        case .light: String(localized: "Light pulse")
        case .mute: String(localized: "Muted")
        }
    }

    var volumeMultiplier: Double {
        switch self {
        case .full: 1.0
        case .light: 0.35
        case .mute: 0.0
        }
    }
}

// MARK: - Silent MD nudges

enum SilentNudgeKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case nextSection
    case hold
    case watchMe
    case faster
    case slower

    var id: String { rawValue }

    var label: String {
        switch self {
        case .nextSection: String(localized: "Next section")
        case .hold: String(localized: "Hold")
        case .watchMe: String(localized: "Watch me")
        case .faster: String(localized: "Faster")
        case .slower: String(localized: "Slower")
        }
    }

    var hapticPattern: [Double] {
        switch self {
        case .nextSection: [0, 0.08, 0.08, 0.08]
        case .hold: [0, 0.2]
        case .watchMe: [0, 0.05, 0.05, 0.05, 0.05, 0.05]
        case .faster: [0, 0.06, 0.06]
        case .slower: [0, 0.15, 0.15]
        }
    }
}

// MARK: - Role-based chart delivery

enum ChartDeliveryMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case full
    case chordsOnly
    case lyricsOnly
    case nashville
    case sectionTempo

    var id: String { rawValue }

    var label: String {
        switch self {
        case .full: String(localized: "Full chart")
        case .chordsOnly: String(localized: "Chords only")
        case .lyricsOnly: String(localized: "Lyrics only")
        case .nashville: String(localized: "Nashville numbers")
        case .sectionTempo: String(localized: "Section & tempo")
        }
    }

    var preferredDisplayMode: SessionDisplayMode {
        switch self {
        case .full, .chordsOnly, .nashville: .stage
        case .lyricsOnly: .chart
        case .sectionTempo: .director
        }
    }
}

// MARK: - Arrangement variants

struct ArrangementVariant: Identifiable, Codable, Equatable, Hashable, Sendable {
    let id: UUID
    var name: String
    var key: MusicalKey
    var notation: ChordNotation
    var chords: [ChordEntry]
    var sections: [SectionMarker]
    var capoFret: Int
    var transposeSemitones: Int
    var rehearsalNotes: String

    init(
        id: UUID = UUID(),
        name: String,
        key: MusicalKey,
        notation: ChordNotation = .symbol,
        chords: [ChordEntry],
        sections: [SectionMarker] = [],
        capoFret: Int = 0,
        transposeSemitones: Int = 0,
        rehearsalNotes: String = ""
    ) {
        self.id = id
        self.name = name
        self.key = key
        self.notation = notation
        self.chords = chords
        self.sections = sections
        self.capoFret = capoFret
        self.transposeSemitones = transposeSemitones
        self.rehearsalNotes = rehearsalNotes
    }
}

// MARK: - Practice queue (mistake markers)

struct PracticeQueueItem: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var recordingID: UUID
    var recordingName: String
    var songTitle: String?
    var timestamp: TimeInterval
    var chordID: UUID?
    var sectionID: UUID?
    var isResolved: Bool
    var addedAt: Date

    init(
        id: UUID = UUID(),
        recordingID: UUID,
        recordingName: String,
        songTitle: String? = nil,
        timestamp: TimeInterval,
        chordID: UUID? = nil,
        sectionID: UUID? = nil,
        isResolved: Bool = false,
        addedAt: Date = Date()
    ) {
        self.id = id
        self.recordingID = recordingID
        self.recordingName = recordingName
        self.songTitle = songTitle
        self.timestamp = timestamp
        self.chordID = chordID
        self.sectionID = sectionID
        self.isResolved = isResolved
        self.addedAt = addedAt
    }
}

// MARK: - Readiness score

enum ReadinessLevel: String, Sendable {
    case ready
    case caution
    case notReady

    var label: String {
        switch self {
        case .ready: String(localized: "Ready")
        case .caution: String(localized: "Caution")
        case .notReady: String(localized: "Not ready")
        }
    }

    var colorName: String {
        switch self {
        case .ready: "green"
        case .caution: "yellow"
        case .notReady: "red"
        }
    }
}

struct ReadinessReport: Equatable, Sendable {
    var score: Int
    var level: ReadinessLevel
    var items: [SmartChecklistItem]
}

// MARK: - Voicing hints

struct VoicingHint: Equatable, Sendable {
    var role: GuestViewRole
    var chordSymbol: String
    var hint: String
}

// MARK: - Vocal range assistant

struct VocalRangeSuggestion: Equatable, Sendable {
    var currentKey: MusicalKey
    var suggestedKey: MusicalKey
    var capoFret: Int
    var reason: String
    var isHighForCongregation: Bool
}

// MARK: - Team pack subscriptions

struct TeamPackSubscription: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var packName: String
    var teamName: String
    var lastRevisionLabel: String
    var subscribedAt: Date
    var notifyOnUpdate: Bool

    init(
        id: UUID = UUID(),
        packName: String,
        teamName: String,
        lastRevisionLabel: String = "",
        subscribedAt: Date = Date(),
        notifyOnUpdate: Bool = true
    ) {
        self.id = id
        self.packName = packName
        self.teamName = teamName
        self.lastRevisionLabel = lastRevisionLabel
        self.subscribedAt = subscribedAt
        self.notifyOnUpdate = notifyOnUpdate
    }
}

// MARK: - Stage Manager layouts

struct StageLayoutPreset: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var name: String
    var role: GuestViewRole
    var displayMode: SessionDisplayMode
    var showMetronome: Bool
    var showCues: Bool
    var showSectionMap: Bool

    init(
        id: UUID = UUID(),
        name: String,
        role: GuestViewRole = .auto,
        displayMode: SessionDisplayMode = .stage,
        showMetronome: Bool = true,
        showCues: Bool = true,
        showSectionMap: Bool = false
    ) {
        self.id = id
        self.name = name
        self.role = role
        self.displayMode = displayMode
        self.showMetronome = showMetronome
        self.showCues = showCues
        self.showSectionMap = showSectionMap
    }

    static let defaults: [StageLayoutPreset] = [
        StageLayoutPreset(name: String(localized: "Guitarist"), role: .guitar, displayMode: .stage, showMetronome: true, showCues: true),
        StageLayoutPreset(name: String(localized: "Vocalist"), role: .vocal, displayMode: .chart, showMetronome: false, showCues: true),
        StageLayoutPreset(name: String(localized: "Director"), role: .auto, displayMode: .director, showMetronome: true, showCues: true, showSectionMap: true),
    ]
}

// MARK: - Offline Sunday folder

struct SundayFolderEntry: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var setlistName: String
    var progressionIDs: [UUID]
    var songTitles: [String]
    var cachedAt: Date
    var serviceDate: Date?

    init(
        id: UUID = UUID(),
        setlistName: String,
        progressionIDs: [UUID],
        songTitles: [String],
        cachedAt: Date = Date(),
        serviceDate: Date? = nil
    ) {
        self.id = id
        self.setlistName = setlistName
        self.progressionIDs = progressionIDs
        self.songTitles = songTitles
        self.cachedAt = cachedAt
        self.serviceDate = serviceDate
    }
}

// MARK: - Weekly team digest

struct TeamDigestEntry: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var weekStarting: Date
    var totalMinutes: Double
    var sessionsHosted: Int
    var songsPlayed: Int
    var topCues: [String]
    var topHosts: [String]

    init(
        id: UUID = UUID(),
        weekStarting: Date,
        totalMinutes: Double,
        sessionsHosted: Int,
        songsPlayed: Int,
        topCues: [String] = [],
        topHosts: [String] = []
    ) {
        self.id = id
        self.weekStarting = weekStarting
        self.totalMinutes = totalMinutes
        self.sessionsHosted = sessionsHosted
        self.songsPlayed = songsPlayed
        self.topCues = topCues
        self.topHosts = topHosts
    }
}

// MARK: - Multi-language charts

enum ChartLanguage: String, Codable, CaseIterable, Identifiable, Sendable {
    case english
    case spanish
    case solfege

    var id: String { rawValue }

    var label: String {
        switch self {
        case .english: String(localized: "English (C, D, E)")
        case .spanish: String(localized: "Spanish (Do, Re, Mi)")
        case .solfege: String(localized: "Solfège")
        }
    }

    var preferredNotation: ChordNotation {
        switch self {
        case .english: .symbol
        case .spanish, .solfege: .latin
        }
    }
}

// MARK: - ChurchApps / Planning Center API

struct ChurchAppsPlanResponse: Sendable {
    var title: String
    var items: [PlanningCenterPlanItem]
}

// MARK: - Import quality coach extensions

struct ImportQualityCoachTip: Identifiable, Equatable, Sendable {
    let id: String
    var title: String
    var detail: String
    var actionLabel: String?
}

// MARK: - CarPlay rehearsal

struct CarPlayRehearsalItem: Identifiable, Equatable, Sendable {
    let id: UUID
    var title: String
    var chordSummary: String
    var tempoBPM: Double
}
