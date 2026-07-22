//
//  ChordyxTests.swift
//  ChordyxTests
//

import Testing
@testable import Chordyx

struct BeginnerPianoTriadTests {

    @Test func maj9CollapsesToMajorTriadSymbol() {
        #expect(ChordTheory.beginnerTriadSymbol(for: "Cmaj9", preferFlats: false) == "C")
        #expect(ChordTheory.beginnerMajorMinorTriad(for: "Cmaj9")?.isMinor == false)
    }

    @Test func min9CollapsesToMinorTriadSymbol() {
        #expect(ChordTheory.beginnerTriadSymbol(for: "Cm9", preferFlats: false) == "Cm")
        #expect(ChordTheory.beginnerTriadSymbol(for: "Cmin9", preferFlats: false) == "Cm")
        #expect(ChordTheory.beginnerMajorMinorTriad(for: "Cm9")?.isMinor == true)
    }

    @Test func highlightsCMajorTriadNotes() {
        // Host plays a Cmaj9 voicing around C3 (MIDI-ish internal: C3=36)
        let host = [36, 40, 43, 47, 50] // C E G B D
        let notes = ChordTheory.beginnerTriadNotes(from: host, symbol: "Cmaj9")
        #expect(notes == [36, 40, 43]) // C E G
    }

    @Test func highlightsCMinorTriadNotes() {
        let host = [36, 39, 43, 46, 50] // C Eb G Bb D
        let notes = ChordTheory.beginnerTriadNotes(from: host, symbol: "Cm9")
        #expect(notes == [36, 39, 43]) // C Eb G
    }

    @Test func leavesSusUnchanged() {
        #expect(ChordTheory.beginnerMajorMinorTriad(for: "Csus4") == nil)
        #expect(ChordTheory.beginnerTriadNotes(from: [36, 41, 43], symbol: "Csus4") == nil)
    }
}
