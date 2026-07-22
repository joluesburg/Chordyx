//
//  ChordyxTests.swift
//  ChordyxTests
//

import Testing
@testable import Chordyx

struct KeyDetectorTests {

    @Test func detectsKeyOfCFromPopProgression() {
        let result = KeyDetector.detect(from: ["C", "G", "Am", "F"])
        #expect(result?.key == .C)
        #expect((result?.confidence ?? 0) > 0.1)
    }

    @Test func detectsKeyOfGFromWorshipProgression() {
        let result = KeyDetector.detect(from: ["G", "D", "Em", "C"])
        #expect(result?.key == .G)
    }

    @Test func detectsKeyOfDFromProgression() {
        let result = KeyDetector.detect(from: ["D", "A", "Bm", "G"])
        #expect(result?.key == .D)
    }

    @Test func needsAtLeastThreeChords() {
        #expect(KeyDetector.detect(from: ["G", "D"]) == nil)
    }
}

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

    @Test func highlightsAMajorTriadNotes() {
        // A3 C#4 E4 — the voicing guests often miss when scroll targets a black key.
        let host = [45, 49, 52]
        let notes = ChordTheory.beginnerTriadNotes(from: host, symbol: "A")
        #expect(notes == [45, 49, 52])
        #expect(ChordTheory.beginnerTriadSymbol(for: "Amaj9", preferFlats: false) == "A")
        #expect(ChordTheory.tones(for: "La")?.root == 9)
        #expect(ChordTheory.beginnerTriadNotes(from: [PianoNote.middleC], symbol: "La")?.count == 3)
    }

    @Test func highlightsAMinorTriadNotes() {
        let host = [45, 48, 52] // A C E
        let notes = ChordTheory.beginnerTriadNotes(from: host, symbol: "Am")
        #expect(notes == [45, 48, 52])
        #expect(ChordTheory.beginnerMajorMinorTriad(for: "Lam")?.isMinor == true)
        #expect(ChordTheory.beginnerTriadSymbol(for: "Lam7", preferFlats: false) == "Am")
    }
}

struct TwoHandChordRecognitionTests {

    @Test func leftHandBassPlusRightHandMajorUsesLeftRoot() {
        // LH Sol/G2 (31), RH Fa major F3–A3–C4 (41, 45, 48)
        let notes = [31, 41, 45, 48]
        let symbol = ChordRecognizer.symbolConsideringBothHands(notes: notes, preferFlats: false)
        #expect(symbol == "G")
    }

    @Test func leftHandGMajorWinsOverRightHandFMajor() {
        // LH G major G2–B2–D3 (31, 35, 38), RH F major F4–A4–C5 (53, 57, 60)
        let notes = [31, 35, 38, 53, 57, 60]
        let symbol = ChordRecognizer.symbolConsideringBothHands(notes: notes, preferFlats: false)
        #expect(symbol == "G")
    }

    @Test func beginnerTriadAnchorsNearRightHand() {
        let host = [31, 41, 45, 48] // G2 + F major in treble
        let notes = ChordTheory.beginnerTriadNotes(from: host, symbol: "G")
        #expect(notes != nil)
        #expect(notes?.allSatisfy { $0 >= PianoNote.upperKeyboardRange.lowerBound } == true)
    }
}

