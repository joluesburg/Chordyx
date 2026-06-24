//
//  SongImportQuality.swift
//  Chordyx
//

import Foundation

enum SongImportReadiness: String, Sendable {
    case ready
    case review
    case incomplete

    var label: String {
        switch self {
        case .ready: String(localized: "Ready to play")
        case .review: String(localized: "Review recommended")
        case .incomplete: String(localized: "Needs work")
        }
    }

    var icon: String {
        switch self {
        case .ready: "checkmark.seal.fill"
        case .review: "exclamationmark.triangle.fill"
        case .incomplete: "xmark.seal.fill"
        }
    }
}

struct SongImportQuality: Sendable, Equatable {
    var readiness: SongImportReadiness
    var score: Int
    var checks: [SongImportQualityCheck]

    static func assess(_ draft: SongImportDraft) -> SongImportQuality {
        var checks: [SongImportQualityCheck] = []
        var score = 0

        if draft.chords.count >= 2 {
            checks.append(.init(id: "chords", title: String(localized: "Chords parsed"), passed: true, detail: "\(draft.chords.count)"))
            score += 25
        } else {
            checks.append(.init(id: "chords", title: String(localized: "Chords parsed"), passed: false, detail: String(localized: "Too few chords")))
        }

        let hasSections = draft.sections.count >= 2
        let hasVerse = draft.sections.contains { $0.kind == .verse }
        if hasSections {
            checks.append(.init(
                id: "sections",
                title: String(localized: "Song structure"),
                passed: true,
                detail: SongSectionAnalyzer.sectionSummary(draft.sections)
            ))
            score += hasVerse ? 30 : 20
        } else {
            checks.append(.init(
                id: "sections",
                title: String(localized: "Song structure"),
                passed: false,
                detail: String(localized: "No sections detected")
            ))
        }

        let linkedLyrics = draft.lyricsLines.filter { $0.chordSymbol != nil }.count
        let lyricRatio = draft.lyricsLines.isEmpty ? 0 : Double(linkedLyrics) / Double(draft.lyricsLines.count)
        if draft.lyricsLines.isEmpty {
            checks.append(.init(id: "lyrics", title: String(localized: "Lyrics linked"), passed: false, detail: String(localized: "No lyrics")))
        } else if lyricRatio >= 0.4 {
            checks.append(.init(id: "lyrics", title: String(localized: "Lyrics linked"), passed: true, detail: "\(linkedLyrics)/\(draft.lyricsLines.count)"))
            score += 20
        } else {
            checks.append(.init(
                id: "lyrics",
                title: String(localized: "Lyrics linked"),
                passed: false,
                detail: String(localized: "Many lines missing chords")
            ))
            score += 5
        }

        if let tempo = draft.tempoBPM {
            checks.append(.init(id: "tempo", title: String(localized: "Tempo found"), passed: true, detail: "\(Int(tempo)) BPM"))
            score += 10
        } else {
            checks.append(.init(id: "tempo", title: String(localized: "Tempo found"), passed: false, detail: String(localized: "Default 100 BPM")))
            score += 3
        }

        let bracketLyrics = draft.lyricsLines.filter { $0.text.contains("[") && $0.text.contains("]") }.count
        if bracketLyrics == 0 {
            checks.append(.init(id: "clean", title: String(localized: "Clean chart"), passed: true, detail: String(localized: "Chords separated")))
            score += 15
        } else {
            checks.append(.init(
                id: "clean",
                title: String(localized: "Clean chart"),
                passed: false,
                detail: String(localized: "Some chords still in lyric text")
            ))
        }

        let readiness: SongImportReadiness
        if score >= 75 && hasSections && hasVerse { readiness = .ready }
        else if score >= 45 { readiness = .review }
        else { readiness = .incomplete }

        return SongImportQuality(readiness: readiness, score: min(100, score), checks: checks)
    }
}

struct SongImportQualityCheck: Identifiable, Sendable, Equatable {
    let id: String
    let title: String
    let passed: Bool
    let detail: String
}

extension SongImportDraft {
    func makeSavedProgression(
        title overrideTitle: String? = nil,
        key overrideKey: MusicalKey? = nil,
        tempoBPM overrideTempo: Double? = nil,
        existingID: UUID? = nil
    ) -> SavedProgression {
        SongImportParser.sanitizeProgression(
            SavedProgression(
                id: existingID ?? UUID(),
                name: overrideTitle ?? title,
                key: overrideKey ?? key,
                notation: .symbol,
                chords: chords,
                tempoBPM: overrideTempo ?? tempoBPM ?? 100,
                beatsPerBar: beatsPerBar,
                beatUnit: beatUnit,
                sections: sections,
                lyrics: plainLyrics,
                lyricsLines: lyricsLines
            )
        )
    }
}
