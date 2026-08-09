//
//  SectionDetection.swift
//  Chordyx
//
//  Lightweight section suggestions for imported / saved progressions.
//

import Foundation

enum SectionDetection {
    /// Returns suggested section markers for a progression (keeps existing sections if present).
    static func suggestSections(for progression: SavedProgression) -> [SectionMarker] {
        if !progression.sections.isEmpty { return progression.sections }
        let chords = progression.chords.sorted { $0.order < $1.order }
        guard !chords.isEmpty else { return [] }

        var markers: [SectionMarker] = [
            SectionMarker(name: String(localized: "Verse"), startChordID: chords[0].id, kind: .verse)
        ]

        // Heuristic: add a Chorus marker near the middle when the chart is long enough.
        if chords.count >= 8 {
            let mid = chords[chords.count / 2]
            markers.append(
                SectionMarker(name: String(localized: "Chorus"), startChordID: mid.id, kind: .chorus)
            )
        }
        return markers
    }

    /// Applies `suggestSections` onto a copy of the progression when it has no sections yet.
    static func applySuggestions(to progression: SavedProgression) -> SavedProgression {
        var next = progression
        guard next.sections.isEmpty else { return next }
        next.sections = suggestSections(for: next)
        return next
    }
}
