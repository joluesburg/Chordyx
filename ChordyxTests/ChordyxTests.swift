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

struct LibraryKeyMatchTests {

    @Test func matchesSavedProgressionAbsoluteKey() {
        let library = [(name: "Sunday", key: MusicalKey.G, symbols: ["G", "D", "Em", "C"])]
        let match = KeyChordAnalysis.bestLibraryKeyMatch(
            liveSymbols: ["G", "D", "Em", "C", "G"],
            library: library
        )
        #expect(match?.key == .G)
        #expect((match?.similarity ?? 0) >= 0.58)
    }

    @Test func matchesTransposedLibraryProgressionToLiveKey() {
        // Library in C; live plays the same relative progression in G.
        let library = [(name: "Pop", key: MusicalKey.C, symbols: ["C", "G", "Am", "F"])]
        let match = KeyChordAnalysis.bestLibraryKeyMatch(
            liveSymbols: ["G", "D", "Em", "C"],
            library: library
        )
        #expect(match?.key == .G)
        #expect((match?.similarity ?? 0) >= 0.58)
    }

    @Test func ignoresUnrelatedProgressions() {
        let library = [(name: "Blues", key: MusicalKey.A, symbols: ["A7", "D7", "E7"])]
        let match = KeyChordAnalysis.bestLibraryKeyMatch(
            liveSymbols: ["C", "G", "Am", "F"],
            library: library
        )
        #expect(match == nil || (match?.similarity ?? 1) < 0.58)
    }
}

struct LiveKeyIntelligenceTests {

    @Test func detectsPopProgressionInC() {
        let result = LiveKeyIntelligence.detect(from: ["C", "G", "Am", "F", "C"])
        #expect(result?.key == .C)
        #expect((result?.confidence ?? 0) > 0.12)
    }

    @Test func detectsWorshipProgressionInG() {
        let result = LiveKeyIntelligence.detect(from: ["G", "D", "Em", "C", "G"])
        #expect(result?.key == .G)
    }

    @Test func detectsTwoFiveOneInF() {
        let result = LiveKeyIntelligence.detect(from: ["Gm", "C7", "F", "F"])
        #expect(result?.key == .F)
    }

    @Test func reportsMIRContributors() {
        let breakdown = LiveKeyIntelligence.analyze(symbols: ["D", "A", "Bm", "G"])
        #expect(breakdown?.bestKey == .D)
        #expect((breakdown?.contributors.count ?? 0) >= 5)
    }

    @Test func needsAtLeastThreeChords() {
        #expect(LiveKeyIntelligence.detect(from: ["C", "G"]) == nil)
    }
}

#if os(macOS) || os(iOS)
struct AudioChromaKeyEstimatorTests {

    @Test func estimatesCFromMajorTriadChroma() {
        let estimator = AudioChromaKeyEstimator()
        // Sparse C-major template (tonic / third / fifth only).
        var frame = [Float](repeating: 0, count: 12)
        frame[0] = 1.0   // C
        frame[4] = 0.7   // E
        frame[7] = 0.85  // G
        for _ in 0..<32 {
            estimator.ingest(frameChroma: frame, rms: 0.05)
        }
        let estimate = estimator.estimate()
        #expect(estimate?.key == .C)
        #expect((estimate?.confidence ?? 0) > 0.08)
    }

    @Test func estimatesGFromDominantFamilyChroma() {
        let estimator = AudioChromaKeyEstimator()
        var frame = [Float](repeating: 0, count: 12)
        frame[7] = 1.0   // G
        frame[11] = 0.65 // B
        frame[2] = 0.8   // D
        for _ in 0..<32 {
            estimator.ingest(frameChroma: frame, rms: 0.05)
        }
        let estimate = estimator.estimate()
        #expect(estimate?.key == .G)
        #expect((estimate?.confidence ?? 0) > 0.08)
    }

    @Test func ignoresSilence() {
        let estimator = AudioChromaKeyEstimator()
        var frame = [Float](repeating: 0, count: 12)
        frame[0] = 1
        for _ in 0..<24 {
            estimator.ingest(frameChroma: frame, rms: 0.001)
        }
        #expect(estimator.estimate() == nil)
    }
}
#endif

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

    @Test func leftHandAOctavesPlusRightHandAm7IsMinor() {
        // LH La octaves A1–A2 (21, 33), RH Am7 A3–C4–E4–G4 (45, 48, 52, 55)
        let notes = [21, 33, 45, 48, 52, 55]
        let symbol = ChordRecognizer.symbolConsideringBothHands(notes: notes, preferFlats: false)
        #expect(symbol == "Am7" || symbol == "Am")
        #expect(ChordTheory.beginnerTriadSymbol(for: symbol ?? "", preferFlats: false) == "Am")
    }

    @Test func leftHandAPlusRightHandCEGIsAmNotAMajor() {
        // Common Am7 voicing: LH root A2 (33), RH upper structure C4–E4–G4 (48, 52, 55)
        let notes = [33, 48, 52, 55]
        let symbol = ChordRecognizer.symbolConsideringBothHands(notes: notes, preferFlats: false)
        #expect(symbol == "Am7" || symbol == "Am")
        #expect(ChordTheory.beginnerTriadSymbol(for: symbol ?? "", preferFlats: false) == "Am")
    }

    @Test func beginnerTriadAnchorsNearRightHand() {
        let host = [31, 41, 45, 48] // G2 + F major in treble
        let notes = ChordTheory.beginnerTriadNotes(from: host, symbol: "G")
        #expect(notes != nil)
        #expect(notes?.allSatisfy { $0 >= PianoNote.upperKeyboardRange.lowerBound } == true)
    }
}

struct PianoHandDivisionTests {

    @Test func cmaj9OctaveBassKeepsBothCsOnLeftHand() {
        // C2 + C3 octave, RH upper structure B3–D4–E4–G4 (user Domaj9 voicing).
        let notes = [24, 36, 47, 50, 52, 55]
        let division = PianoNote.handDivision(for: notes)
        #expect(division?.leftNotes == [24, 36])
        #expect(division?.rightNotes == [47, 50, 52, 55])
        #expect(division?.lowerRange.contains(24) == true)
        #expect(division?.lowerRange.contains(36) == true)
        #expect(division?.upperRange.contains(36) == false)
        #expect(division?.upperRange.contains(47) == true)
    }

    @Test func closePositionCTriadOverBassUsesClassicC3Split() {
        // C2 + close C3–E3–G3 — C3 stays with the right-hand triad.
        let notes = [24, 36, 40, 43]
        let division = PianoNote.handDivision(for: notes)
        #expect(division?.leftNotes == [24])
        #expect(division?.rightNotes == [36, 40, 43])
        #expect(division?.lowerRange.upperBound == PianoNote.lowerKeyboardRange.upperBound)
    }

    @Test func spansBothHandsForOctavePlusUpperStructure() {
        #expect(PianoNote.spansBothHands([24, 36, 47, 50, 52, 55]))
        #expect(!PianoNote.spansBothHands([36, 40, 43]))
    }
}

