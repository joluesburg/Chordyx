//
//  LiveChordPadDefaults.swift
//  Chordyx
//
//  Default diatonic chords for the host live tap pad when no chart is loaded.
//

import Foundation

enum LiveChordPadDefaults {
    /// I – ii – iii – IV – V – vi – vii° in the session key (worship-friendly triads).
    static func diatonicChords(in key: MusicalKey) -> [String] {
        let t = key.pitchClass
        let names = key.prefersFlats ? Transposer.flatNames : Transposer.sharpNames
        func sym(_ degree: Int, minor: Bool = false) -> String {
            let root = names[(t + degree) % 12]
            return minor ? root + "m" : root
        }
        return [
            sym(0),
            sym(2, minor: true),
            sym(4, minor: true),
            sym(5),
            sym(7),
            sym(9, minor: true),
            sym(11, minor: true)
        ]
    }
}
