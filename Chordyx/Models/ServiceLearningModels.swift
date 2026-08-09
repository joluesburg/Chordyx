//
//  ServiceLearningModels.swift
//  Chordyx
//
//  Local library of how your church band plays — tempo, groove, chords, style.
//

import Foundation

enum ServiceLearningCaptureSource: String, Codable, Sendable {
    case manual
    case autoDrumLock
}

/// A snapshot captured during worship, rehearsal, or solo practice.
struct ServiceLearningRecord: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var profileName: String
    var songTitle: String
    var serviceSessionName: String
    var tempoBPM: Double
    var drumPatternRaw: String
    var detectedStyleRaw: String
    var styleConfidence: Double
    var syncopationIndex: Double
    var key: MusicalKey
    var notation: ChordNotation
    var beatsPerBar: Int
    var chordSymbols: [String]
    var chords: [ChordEntry]
    var recordedAt: Date
    var captureSource: ServiceLearningCaptureSource
    // Phase 3 — learned stems + auto band
    var learnedDrumPattern: LearnedDrumPattern?
    var learnedBassLine: LearnedBassLine?
    var bassStyleRaw: String
    var autoBandModeRaw: String

    init(
        id: UUID = UUID(),
        profileName: String,
        songTitle: String,
        serviceSessionName: String,
        tempoBPM: Double,
        drumPatternRaw: String,
        detectedStyleRaw: String,
        styleConfidence: Double,
        syncopationIndex: Double,
        key: MusicalKey,
        notation: ChordNotation,
        beatsPerBar: Int,
        chordSymbols: [String],
        chords: [ChordEntry],
        recordedAt: Date = Date(),
        captureSource: ServiceLearningCaptureSource,
        learnedDrumPattern: LearnedDrumPattern? = nil,
        learnedBassLine: LearnedBassLine? = nil,
        bassStyleRaw: String = BassAccompanimentStyle.worshipRoot.rawValue,
        autoBandModeRaw: String = AutoBandMode.fullBand.rawValue
    ) {
        self.id = id
        self.profileName = profileName
        self.songTitle = songTitle
        self.serviceSessionName = serviceSessionName
        self.tempoBPM = tempoBPM
        self.drumPatternRaw = drumPatternRaw
        self.detectedStyleRaw = detectedStyleRaw
        self.styleConfidence = styleConfidence
        self.syncopationIndex = syncopationIndex
        self.key = key
        self.notation = notation
        self.beatsPerBar = beatsPerBar
        self.chordSymbols = chordSymbols
        self.chords = chords
        self.recordedAt = recordedAt
        self.captureSource = captureSource
        self.learnedDrumPattern = learnedDrumPattern
        self.learnedBassLine = learnedBassLine
        self.bassStyleRaw = bassStyleRaw
        self.autoBandModeRaw = autoBandModeRaw
    }

    enum CodingKeys: String, CodingKey {
        case id, profileName, songTitle, serviceSessionName, tempoBPM, drumPatternRaw
        case detectedStyleRaw, styleConfidence, syncopationIndex, key, notation, beatsPerBar
        case chordSymbols, chords, recordedAt, captureSource
        case learnedDrumPattern, learnedBassLine, bassStyleRaw, autoBandModeRaw
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        profileName = try c.decode(String.self, forKey: .profileName)
        songTitle = try c.decode(String.self, forKey: .songTitle)
        serviceSessionName = try c.decode(String.self, forKey: .serviceSessionName)
        tempoBPM = try c.decode(Double.self, forKey: .tempoBPM)
        drumPatternRaw = try c.decode(String.self, forKey: .drumPatternRaw)
        detectedStyleRaw = try c.decode(String.self, forKey: .detectedStyleRaw)
        styleConfidence = try c.decode(Double.self, forKey: .styleConfidence)
        syncopationIndex = try c.decode(Double.self, forKey: .syncopationIndex)
        key = try c.decode(MusicalKey.self, forKey: .key)
        notation = try c.decode(ChordNotation.self, forKey: .notation)
        beatsPerBar = try c.decode(Int.self, forKey: .beatsPerBar)
        chordSymbols = try c.decode([String].self, forKey: .chordSymbols)
        chords = try c.decode([ChordEntry].self, forKey: .chords)
        recordedAt = try c.decode(Date.self, forKey: .recordedAt)
        captureSource = try c.decode(ServiceLearningCaptureSource.self, forKey: .captureSource)
        learnedDrumPattern = try c.decodeIfPresent(LearnedDrumPattern.self, forKey: .learnedDrumPattern)
        learnedBassLine = try c.decodeIfPresent(LearnedBassLine.self, forKey: .learnedBassLine)
        bassStyleRaw = try c.decodeIfPresent(String.self, forKey: .bassStyleRaw) ?? BassAccompanimentStyle.worshipRoot.rawValue
        autoBandModeRaw = try c.decodeIfPresent(String.self, forKey: .autoBandModeRaw) ?? AutoBandMode.fullBand.rawValue
    }

    var drumPattern: DrumPattern {
        DrumPattern(rawValue: drumPatternRaw) ?? .worshipBallad
    }

    var detectedStyle: LiveMusicStyle {
        LiveMusicStyle(rawValue: detectedStyleRaw) ?? .unknown
    }

    var bassStyle: BassAccompanimentStyle {
        BassAccompanimentStyle(rawValue: bassStyleRaw) ?? .worshipRoot
    }

    var autoBandMode: AutoBandMode {
        AutoBandMode(rawValue: autoBandModeRaw) ?? .fullBand
    }

    var hasLearnedDrums: Bool {
        learnedDrumPattern.map { !$0.isEmpty } ?? false
    }

    var hasLearnedBass: Bool {
        learnedBassLine.map { !$0.isEmpty } ?? false
    }

    var bandSummary: String {
        var parts: [String] = []
        if hasLearnedDrums { parts.append(String(localized: "Learned drums")) }
        if hasLearnedBass { parts.append(String(localized: "Learned bass")) }
        if parts.isEmpty { parts.append(autoBandMode.label) }
        return parts.joined(separator: " · ")
    }

    var chordSummary: String {
        if chordSymbols.isEmpty { return String(localized: "No chords captured") }
        let preview = chordSymbols.prefix(6).joined(separator: " · ")
        if chordSymbols.count > 6 {
            return "\(preview)…"
        }
        return preview
    }

    var recordedAtLabel: String {
        recordedAt.formatted(date: .abbreviated, time: .shortened)
    }
}
