//
//  ScaleHint.swift
//  Chordyx
//

import Foundation

enum ScaleHint {
    /// Suggested scale for soloing over the active chord in the song key.
    static func hint(for chordSymbol: String, songKey: MusicalKey) -> String {
        guard let (root, suffix) = Transposer.parse(chordSymbol),
              let rootPC = Transposer.pitchClass(ofRoot: root) else {
            return pentatonicLabel(for: songKey)
        }

        let s = suffix.lowercased()
        if s.contains("dim") || s.contains("°") {
            return String(format: String(localized: "%@ diminished"), noteName(rootPC, preferFlats: songKey.prefersFlats))
        }
        if s.contains("m7") || (s.hasPrefix("m") && !s.hasPrefix("maj")) {
            return String(format: String(localized: "%@ minor pentatonic"), noteName(rootPC, preferFlats: songKey.prefersFlats))
        }
        if s.contains("7") && !s.contains("maj") {
            return String(format: String(localized: "%@ mixolydian"), noteName(rootPC, preferFlats: songKey.prefersFlats))
        }
        return pentatonicLabel(forPitchClass: rootPC, preferFlats: songKey.prefersFlats)
    }

    private static func pentatonicLabel(for key: MusicalKey) -> String {
        pentatonicLabel(forPitchClass: key.pitchClass, preferFlats: key.prefersFlats)
    }

    private static func pentatonicLabel(forPitchClass pitchClass: Int, preferFlats: Bool) -> String {
        String(format: String(localized: "%@ major pentatonic"), noteName(pitchClass, preferFlats: preferFlats))
    }

    private static func noteName(_ pitchClass: Int, preferFlats: Bool) -> String {
        let names = preferFlats ? Transposer.flatNames : Transposer.sharpNames
        return names[((pitchClass % 12) + 12) % 12]
    }
}
