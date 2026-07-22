//
//  LiveMusicStyle.swift
//  Chordyx
//
//  Live style inference from harmonic + rhythmic performance cues.
//

import Foundation

enum LiveMusicStyle: String, CaseIterable, Identifiable, Sendable {
    case unknown
    // Worship & ballad
    case worshipBallad
    case softPulse
    case gospelGroove
    case brushWaltz
    // Pop, rock & dance
    case popRock
    case rockDrive
    case funkGroove
    case rbSoul
    case edmPulse
    // Jazz & blues
    case jazzSwing
    case bluesShuffle
    // Latin & Caribbean
    case montuno
    case merengue
    case salsa
    case songo
    case bossaNova
    case bolero
    // World & folk
    case reggaeOneDrop
    case countryTrain

    var id: String { rawValue }

    /// Styles the live analyzers can classify (excludes `.unknown`).
    static let detectableStyles: [LiveMusicStyle] = [
        .worshipBallad, .softPulse, .gospelGroove, .brushWaltz,
        .popRock, .rockDrive, .funkGroove, .rbSoul, .edmPulse,
        .jazzSwing, .bluesShuffle,
        .merengue, .montuno, .salsa, .songo, .bossaNova, .bolero,
        .reggaeOneDrop, .countryTrain
    ]

    enum Category: String, Sendable {
        case worship
        case popRock
        case jazzBlues
        case latin
        case world
    }

    var category: Category {
        switch self {
        case .unknown: .popRock
        case .worshipBallad, .softPulse, .gospelGroove, .brushWaltz: .worship
        case .popRock, .rockDrive, .funkGroove, .rbSoul, .edmPulse: .popRock
        case .jazzSwing, .bluesShuffle: .jazzBlues
        case .merengue, .montuno, .salsa, .songo, .bossaNova, .bolero: .latin
        case .reggaeOneDrop, .countryTrain: .world
        }
    }

    var label: String {
        switch self {
        case .unknown: String(localized: "Listening…")
        case .worshipBallad: String(localized: "Worship ballad")
        case .softPulse: String(localized: "Soft pulse")
        case .gospelGroove: String(localized: "Gospel groove")
        case .brushWaltz: String(localized: "Brush waltz")
        case .popRock: String(localized: "Pop / rock")
        case .rockDrive: String(localized: "Rock drive")
        case .funkGroove: String(localized: "Funk groove")
        case .rbSoul: String(localized: "R&B / soul")
        case .edmPulse: String(localized: "EDM / four-on-the-floor")
        case .jazzSwing: String(localized: "Jazz swing")
        case .bluesShuffle: String(localized: "Blues shuffle")
        case .merengue: String(localized: "Merengue")
        case .montuno: String(localized: "Montuno")
        case .salsa: String(localized: "Salsa")
        case .songo: String(localized: "Songó")
        case .bossaNova: String(localized: "Bossa nova")
        case .bolero: String(localized: "Bolero")
        case .reggaeOneDrop: String(localized: "Reggae one-drop")
        case .countryTrain: String(localized: "Country train")
        }
    }

    var suggestedDrumPattern: DrumPattern? {
        switch self {
        case .unknown: nil
        case .worshipBallad: .worshipBallad
        case .softPulse: .softPulse
        case .gospelGroove: .gospelGroove
        case .brushWaltz: .brushWaltz
        case .popRock: .popRock
        case .rockDrive: .rockDrive
        case .funkGroove: .funkGroove
        case .rbSoul: .rbSoul
        case .edmPulse: .edmPulse
        case .jazzSwing: .jazzSwing
        case .bluesShuffle: .bluesShuffle
        case .merengue: .merengue
        case .montuno: .salsa
        case .salsa: .salsa
        case .songo: .songo
        case .bossaNova: .bossaNova
        case .bolero: .bolero
        case .reggaeOneDrop: .reggaeOneDrop
        case .countryTrain: .countryTrain
        }
    }
}

enum ChordQualityHint: Sendable {
    case major
    case minor
    case dominant
    case major7
    case minor7
    case suspended
    case diminished
    case halfDiminished
    case extended
    case power
    case unknown
}

struct ChordSymbolAnalysis: Sendable {
    let quality: ChordQualityHint
    let complexity: Int
    let isSuspended: Bool
    let isDominantFamily: Bool
    let extensionCount: Int

    static func analyze(_ symbol: String) -> ChordSymbolAnalysis {
        let trimmed = symbol.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ChordSymbolAnalysis(
                quality: .unknown,
                complexity: 0,
                isSuspended: false,
                isDominantFamily: false,
                extensionCount: 0
            )
        }

        let base = trimmed.split(separator: "/").first.map(String.init) ?? trimmed
        let lower = base.lowercased()

        let suffix: String = {
            if base.count >= 2, let second = base.dropFirst().first, second == "#" || second == "b" {
                return String(base.dropFirst(2))
            }
            return String(base.dropFirst())
        }()
        let suffixLower = suffix.lowercased()

        var complexity = 1
        var extensions = 0
        let isSuspended = lower.contains("sus")
        let isDim = lower.contains("dim") || lower.contains("°")
        let isHalfDim = lower.contains("m7b5") || lower.contains("ø")
        let isMinor = suffixLower.hasPrefix("m") && !suffixLower.hasPrefix("maj")
        let hasMaj7 = lower.contains("maj7") || lower.contains("maj9") || lower.contains("mmaj")
        let hasMin7 = lower.contains("m7") && isMinor && !isHalfDim
        let hasDom7 = lower.contains("7") && !hasMaj7 && !hasMin7 && !isHalfDim
        let hasExtended = lower.contains("9") || lower.contains("11") || lower.contains("13")
            || lower.contains("add")
        let isPower = suffixLower == "5" || lower.hasSuffix("5")

        if hasExtended { extensions += 1; complexity += 2 }
        if hasMaj7 || hasMin7 || hasDom7 { extensions += 1; complexity += 1 }
        if isSuspended { complexity += 1 }
        if isDim || isHalfDim { complexity += 2 }
        if isPower { complexity = 1 }

        let quality: ChordQualityHint = {
            if isSuspended { return .suspended }
            if isHalfDim { return .halfDiminished }
            if isDim { return .diminished }
            if isPower { return .power }
            if hasExtended { return .extended }
            if hasMaj7 { return .major7 }
            if hasMin7 { return .minor7 }
            if hasDom7 { return .dominant }
            if isMinor { return .minor }
            if base.first?.isLetter == true { return .major }
            return .unknown
        }()

        let dominantFamily = hasDom7 || isSuspended || quality == .dominant

        return ChordSymbolAnalysis(
            quality: quality,
            complexity: min(5, complexity),
            isSuspended: isSuspended,
            isDominantFamily: dominantFamily,
            extensionCount: extensions
        )
    }
}

struct ChordPerformanceEvent: Sendable {
    let symbol: String
    let time: TimeInterval
    let analysis: ChordSymbolAnalysis
    let noteCount: Int
}

struct RhythmOnsetEvent: Sendable {
    let time: TimeInterval
    let strength: Double
    let isChordChange: Bool
}
