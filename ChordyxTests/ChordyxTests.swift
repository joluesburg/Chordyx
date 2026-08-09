//
//  ChordyxTests.swift
//  ChordyxTests
//

import Foundation
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

struct SoloAccompanimentHostAvailabilityTests {

    @Test func soloHostGateMatchesPlatformPolicy() {
        #if os(macOS)
        #expect(PlatformDevice.canHostSoloAccompaniment)
        #elseif os(iOS)
        #expect(PlatformDevice.canHostSoloAccompaniment == PlatformDevice.isPad)
        #expect(PlatformDevice.isPhone != PlatformDevice.canHostSoloAccompaniment || !PlatformDevice.isPhone)
        #else
        #expect(!PlatformDevice.canHostSoloAccompaniment)
        #endif
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

    @Test func cOctaveBassPlusGBDEUpperStructureIsCNotG() {
        // Do2+Do3 + Sol–Si–Re–Mi — must not label as G from upper structure / lower partial.
        let notes = [24, 36, 43, 47, 50, 52]
        let symbol = ChordRecognizer.symbolConsideringBothHands(notes: notes, preferFlats: false)
        #expect(symbol != nil)
        if let symbol, let triad = ChordTheory.beginnerMajorMinorTriad(for: symbol) {
            #expect(triad.root == 0)
            #expect(triad.isMinor == false)
        }
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
        let division = PianoNote.handDivision(for: notes, chordSymbol: "Cmaj9")
        #expect(division?.leftNotes == [24, 36])
        #expect(division?.rightNotes == [47, 50, 52, 55])
        #expect(division?.lowerRange == PianoNote.lowerKeyboardRange)
        #expect(division?.upperRange == PianoNote.upperKeyboardRange)
        #expect(division?.lowerRange.contains(24) == true)
        #expect(division?.lowerRange.contains(36) == true)
        #expect(division?.upperRange.contains(47) == true)
    }

    @Test func closePositionCTriadKeepsRootOctaveOnLeftHand() {
        // C2 + close C3–E3–G3 — root octaves stay LH; triad body (E/G) on RH.
        let notes = [24, 36, 40, 43]
        let division = PianoNote.handDivision(for: notes, chordSymbol: "C")
        #expect(division?.leftNotes == [24, 36])
        #expect(division?.rightNotes == [40, 43])
        #expect(division?.usesBothHands == true)
    }

    @Test func spansBothHandsForOctavePlusUpperStructure() {
        #expect(PianoNote.spansBothHands([24, 36, 47, 50, 52, 55], chordSymbol: "Cmaj9"))
        #expect(!PianoNote.spansBothHands([36, 40, 43], chordSymbol: "C"))
    }

    @Test func leftHandGOctaveStaysOnLowerBoardTogether() {
        // Sol2 + Sol3 (31, 43) — must not light one G per board.
        let notes = [31, 43]
        #expect(!PianoNote.spansBothHands(notes, chordSymbol: "G"))
        let division = PianoNote.handDivision(for: notes, chordSymbol: "G")
        #expect(division?.leftNotes == [31, 43])
        #expect(division?.rightNotes.isEmpty == true)
        #expect(division?.lowerRange.contains(31) == true)
        #expect(division?.lowerRange.contains(43) == true)
        #expect(PianoNote.lowerBoardOnly(for: notes, chordSymbol: "G") != nil)
    }

    @Test func leftHandRootFifthRightHandTriad() {
        // G2+D3 shell + B3–D4–G4 triad.
        let notes = [31, 38, 47, 50, 55]
        let division = PianoNote.handDivision(for: notes, chordSymbol: "G")
        #expect(division?.leftNotes == [31, 38])
        #expect(division?.rightNotes == [47, 50, 55])
        #expect(division?.usesBothHands == true)
    }

    @Test func am7LeftOctaveRightUpperStructure() {
        // A1+A2 + C4–E4–G4
        let notes = [21, 33, 48, 52, 55]
        let division = PianoNote.handDivision(for: notes, chordSymbol: "Am7")
        #expect(division?.leftNotes == [21, 33])
        #expect(division?.rightNotes == [48, 52, 55])
    }

    @Test func dualBoardRangesAreFixed() {
        let notes = [24, 36, 47, 50, 52, 55]
        let division = PianoNote.handDivision(for: notes, chordSymbol: "Cmaj9")
        #expect(division?.lowerRange == PianoNote.lowerKeyboardRange)
        #expect(division?.upperRange == PianoNote.upperKeyboardRange)
        #expect(PianoNote.lowerKeyboardRange == 9...47)
        #expect(PianoNote.upperKeyboardRange == 36...96)
    }

    @Test func handLightingStaysOnAssignedBoard() {
        let notes = [24, 36, 47, 50, 52, 55]
        let division = PianoNote.handDivision(for: notes, chordSymbol: "Cmaj9")
        #expect(division != nil)
        if let division {
            for note in division.leftNotes {
                #expect(division.lowerRange.contains(note))
            }
            for note in division.rightNotes {
                #expect(division.upperRange.contains(note))
            }
        }
    }

    @Test func shellVoicingRootSeventhThird() {
        // C2 + Bb2 + E3 shell-ish → LH bass tones, RH guide.
        let notes = [24, 34, 40]
        let division = PianoNote.handDivision(for: notes, chordSymbol: "C7")
        #expect(division?.usesBothHands == true)
        #expect(division?.leftNotes.contains(24) == true)
        #expect(division?.rightNotes.contains(40) == true)
    }

    @Test func stickyDivisionKeepsHandShapeUnderSameChord() {
        let previous = PianoNote.handDivision(for: [24, 36, 47, 50, 52, 55], chordSymbol: "Cmaj9")
        #expect(previous != nil)
        guard let previous else { return }

        // Drop B3 briefly — sticky remap should keep C octaves on LH.
        let sticky = PianoNote.stickyHandDivision(
            for: [24, 36, 50, 52, 55],
            previous: previous,
            chordSymbol: "Cmaj9"
        )
        #expect(sticky.leftNotes == [24, 36])
        #expect(sticky.rightNotes == [50, 52, 55])
        #expect(sticky.lowerRange == PianoNote.lowerKeyboardRange)
        #expect(sticky.upperRange == PianoNote.upperKeyboardRange)
    }

    @Test func beginnerStyleCloseTriadWithoutBassIsSingleBoard() {
        #expect(PianoNote.handDivision(for: [48, 52, 55], chordSymbol: "C") == nil)
        #expect(!PianoNote.spansBothHands([48, 52, 55], chordSymbol: "C"))
    }

    @Test func cOctaveBassStaysTogetherEvenWhenSymbolLooksLikeG() {
        // Live voicing: LH Do+Do (C2+C3), RH Sol+Si+Re+Mi.
        // Chord recognition often labels this as G / Em-ish — LH octaves must still follow the sounding bass.
        let notes = [24, 36, 43, 47, 50, 52]
        let symbols: [String?] = ["G", "Em", "Gmaj7", "Cadd9", nil]
        for symbol in symbols {
            let division = PianoNote.handDivision(for: notes, chordSymbol: symbol)
            #expect(division?.leftNotes == [24, 36], "symbol \(String(describing: symbol))")
            #expect(division?.rightNotes == [43, 47, 50, 52], "symbol \(String(describing: symbol))")
        }
    }

    @Test func conflictingSymbolRootIsIgnoredForHandRoles() {
        let notes = [24, 36, 43, 47, 50, 52]
        #expect(PianoNote.symbolConflictsWithSoundingBass(chordSymbol: "G", notes: notes))
        #expect(!PianoNote.symbolConflictsWithSoundingBass(chordSymbol: "Cmaj9", notes: notes))
        #expect(PianoNote.handRoleRootPitchClass(sorted: notes, chordSymbol: "G") == nil)
        #expect(PianoNote.handRoleRootPitchClass(sorted: notes, chordSymbol: "C") == 0)
    }

    @Test func shellVoicingKeepsRootFifthOnLeftHand() {
        // C2+G2 shell + E4 — LH shell, RH guide tone.
        let notes = [24, 31, 52]
        let division = PianoNote.handDivision(for: notes, chordSymbol: "C")
        #expect(division?.leftNotes == [24, 31])
        #expect(division?.rightNotes == [52])
    }

    @Test func stickyDivisionSurvivesSymbolFlickerOnSameVoicing() {
        let notes = [24, 36, 43, 47, 50, 52]
        let previous = PianoNote.handDivision(for: notes, chordSymbol: "Cmaj9")
        #expect(previous != nil)
        guard let previous else { return }

        // Same MIDI voicing, wrong label — sticky remap must keep Do+Do on LH.
        let sticky = PianoNote.stickyHandDivision(for: notes, previous: previous, chordSymbol: "G")
        #expect(sticky.leftNotes == [24, 36])
        #expect(sticky.rightNotes == [43, 47, 50, 52])
    }

    @MainActor
    @Test func stabilizerIgnoresSymbolFlickerOnHeldVoicing() {
        let notes = [24, 36, 43, 47, 50, 52]
        let stabilizer = PianoHandSplitStabilizer()
        let first = stabilizer.division(for: notes, chordSymbol: "Cmaj9")
        #expect(first?.leftNotes == [24, 36])
        #expect(first?.rightNotes == [43, 47, 50, 52])

        // Wrong live labels for the same held voicing must not re-split the boards.
        for symbol in ["G", "Em", "Gmaj7"] {
            let next = stabilizer.division(for: notes, chordSymbol: symbol)
            #expect(next?.leftNotes == [24, 36], "symbol \(symbol)")
            #expect(next?.rightNotes == [43, 47, 50, 52], "symbol \(symbol)")
        }
    }

    @Test func analysisHandGroupsKeepBassOctaveTwinOnLeft() {
        // C2 below split + C3 at split → both count as LH for recognition.
        let notes = [24, 36, 43, 47, 50, 52]
        let (left, right) = PianoNote.analysisHandGroups(for: notes, split: PianoNote.handRegisterSplit)
        #expect(left == [24, 36])
        #expect(right == [43, 47, 50, 52])
    }

    @Test func reconcilePrefersBassRootedSymbolOverUpperStructure() {
        let notes = [24, 36, 43, 47, 50, 52]
        let reconciled = ChordRecognizer.reconcileSymbolWithVoicing(
            notes: notes,
            chordSymbol: "G",
            preferFlats: false
        )
        #expect(reconciled != nil)
        if let reconciled, let triad = ChordTheory.beginnerMajorMinorTriad(for: reconciled) {
            #expect(triad.root == 0) // C, not G
        }
        let recognized = ChordRecognizer.symbolConsideringBothHands(notes: notes, preferFlats: false)
        #expect(recognized != nil)
        if let recognized, let triad = ChordTheory.beginnerMajorMinorTriad(for: recognized) {
            #expect(triad.root == 0)
        }
    }
}

struct BandChatSyncTests {

    @Test func highFrequencyStripDoesNotCarryChat() {
        var payload = SessionSyncPayload.empty
        payload.sessionToken = UUID()
        payload.chords = [
            ChordEntry(symbolName: "C", latinName: "Do", order: 0)
        ]
        payload.bandChatMessages = [
            SessionQuickMessage(senderName: "Host", text: "Ready")
        ]

        let stripped = payload.forHighFrequencyPeerSync()
        #expect(stripped.bandChatMessages.isEmpty)
        #expect(stripped.looksLikeHighFrequencyPeerSyncStrip(comparedTo: payload))
    }

    @Test func controlActionEncodesBandChat() throws {
        let message = SessionQuickMessage(senderName: "Guest", text: "One more")
        let action = SessionControlAction.postBandChat(message)
        let data = try JSONEncoder().encode(action)
        let decoded = try JSONDecoder().decode(SessionControlAction.self, from: data)
        #expect(decoded == action)
    }

    @Test func chatPresetsCoverLiveBandNeeds() {
        let labels = SessionQuickMessage.chatPresets.map(\.0)
        #expect(labels.contains(where: { $0.localizedCaseInsensitiveContains("Ready") }))
        #expect(labels.contains(where: { $0.localizedCaseInsensitiveContains("Wait") }))
        #expect(SessionQuickMessage.chatPresets.count >= 5)
    }

    @Test func chatOnlyPayloadChangeIsNotTreatedAsLiveBurst() {
        var prior = SessionSyncPayload.empty
        prior.sessionToken = UUID()
        prior.chords = [ChordEntry(symbolName: "C", latinName: "Do", order: 0)]
        prior.bandChatMessages = []

        var next = prior
        next.bandChatMessages = [
            SessionQuickMessage(senderName: "Host", text: "Ready")
        ]

        #expect(!next.isLiveChordBurst(comparedTo: prior))
    }
}

struct ChromaticToneNamesTests {

    @Test func latinMixedPresetMatchesRequestedSpelling() {
        let names = ChromaticToneNames(preset: .latinMixed)
        #expect(names.names == ["Do", "Do#", "Re", "Mi♭", "Mi", "Fa", "Fa#", "Sol", "Sol#", "La", "Si♭", "Si"])
        #expect(names.name(forPitchClass: 0) == "Do")
        #expect(names.name(forPitchClass: 1) == "Do#")
        #expect(names.name(forPitchClass: 3) == "Mi♭")
        #expect(names.name(forPitchClass: 10) == "Si♭")
    }

    @Test func mapsLetterRootsToCustomNames() {
        let names = ChromaticToneNames(preset: .latinMixed)
        #expect(names.name(forLetterRoot: "C#") == "Do#")
        #expect(names.name(forLetterRoot: "Eb") == "Mi♭")
        #expect(names.name(forLetterRoot: "Bb") == "Si♭")
        #expect(names.name(forLetterRoot: "E♭") == "Mi♭")
    }

    @Test func latinChordConversionUsesStoredNames() {
        let previous = GuestDisplaySettings.chromaticToneNames
        defer { GuestDisplaySettings.chromaticToneNames = previous }

        GuestDisplaySettings.chromaticToneNames = ChromaticToneNames(preset: .latinMixed)
        #expect(ChordCatalog.latinName(forSymbol: "C#m7") == "Do#m7")
        #expect(ChordCatalog.latinName(forSymbol: "Ebm") == "Mi♭m")
        #expect(ChordCatalog.latinName(forSymbol: "Bb7") == "Si♭7")
        #expect(ChordCatalog.latinName(forSymbol: "C/E") == "Do/Mi")
        #expect(ChordCatalog.latinName(forSymbol: "C6/9") == "Do6/9")
    }

    @Test func pianoKeyLabelsUseCustomNamesWithOctaveRules() {
        let previous = GuestDisplaySettings.chromaticToneNames
        defer { GuestDisplaySettings.chromaticToneNames = previous }

        GuestDisplaySettings.chromaticToneNames = ChromaticToneNames(preset: .latinMixed)
        // Middle C (index 48) is pitch class 0 → show octave.
        #expect(PianoNote.keyboardLabel(for: 48, preferFlats: false) == "Do4")
        // D4 (50) is white non-C → no octave.
        #expect(PianoNote.keyboardLabel(for: 50, preferFlats: false) == "Re")
        // C#4 (49) is black → show octave.
        #expect(PianoNote.keyboardLabel(for: 49, preferFlats: false) == "Do#4")
        // Eb4 (51) black → Mi♭4
        #expect(PianoNote.keyboardLabel(for: 51, preferFlats: true) == "Mi♭4")
    }
}

struct MetronomeDrumPhaseLockTests {

    @Test func quarterNoteGridKeepsClickAccentOnDrumDownbeats() {
        let bpm = 120.0
        // Sample several bar starts (0, 1, 2 bars of 16 sixteenths).
        for bar in 0..<8 {
            let elapsed = Double(bar * 16) * ((60.0 / bpm) / 4.0)
            #expect(
                MetronomePhaseMath.drumDownbeatMatchesClickAccent(
                    elapsed: elapsed,
                    bpm: bpm,
                    beatsPerBar: 4,
                    beatUnit: 4
                )
            )
        }
    }

    @Test func wrongBeatUnitBreaksDrumLock() {
        let bpm = 120.0
        let elapsed = 0.0
        #expect(
            MetronomePhaseMath.drumDownbeatMatchesClickAccent(
                elapsed: elapsed,
                bpm: bpm,
                beatsPerBar: 4,
                beatUnit: 4
            )
        )
        // beatUnit 8 halves the click period vs the drum quarter grid.
        let spb8 = MetronomePhaseMath.secondsPerBeat(bpm: bpm, beatUnit: 8)
        let spb4 = MetronomePhaseMath.secondsPerBeat(bpm: bpm, beatUnit: 4)
        #expect(abs(spb8 - spb4 / 2) < 0.0001)
    }

    @Test func floorBeatIndexMatchesDrumStyleTruncation() {
        let spb = 0.5 // 120 BPM quarters
        #expect(MetronomePhaseMath.absoluteBeatIndex(elapsed: 0.0, secondsPerBeat: spb) == 0)
        #expect(MetronomePhaseMath.absoluteBeatIndex(elapsed: 0.49, secondsPerBeat: spb) == 0)
        #expect(MetronomePhaseMath.absoluteBeatIndex(elapsed: 0.50, secondsPerBeat: spb) == 1)
        #expect(MetronomePhaseMath.beatInBar(absoluteBeat: 4, beatsPerBar: 4) == 0)
    }

    @Test func sharedEpochKeepsMetronomeAndDrumQuartersAligned() {
        let bpm = 96.0
        let epoch = 1_700_000_000.0
        let sixteenth = (60.0 / bpm) / 4.0
        for absoluteStep in stride(from: 0, through: 64, by: 4) {
            let elapsed = Double(absoluteStep) * sixteenth
            let hostNow = epoch + elapsed
            let spb = MetronomePhaseMath.secondsPerBeat(bpm: bpm, beatUnit: 4)
            let beat = MetronomePhaseMath.absoluteBeatIndex(
                elapsed: hostNow - epoch,
                secondsPerBeat: spb
            )
            let stepInBar = absoluteStep % 16
            #expect(DrumMetronomeSyncMath.isQuarterStep(stepInBar))
            #expect(MetronomePhaseMath.beatInBar(absoluteBeat: beat, beatsPerBar: 4) == stepInBar / 4)
            if stepInBar == 0 {
                #expect(
                    MetronomePhaseMath.drumDownbeatMatchesClickAccent(
                        elapsed: elapsed,
                        bpm: bpm,
                        beatsPerBar: 4,
                        beatUnit: 4
                    )
                )
            }
        }
    }
}

struct DrumMetronomeClickThroughTests {

    @Test func quartersAndDownbeatsAlignForClickThrough() {
        for step in 0..<16 {
            let isQuarter = step % 4 == 0
            #expect(DrumMetronomeSyncMath.isQuarterStep(step) == isQuarter)
            #expect(DrumMetronomeSyncMath.isDownbeatStep(step) == (step == 0))
            if isQuarter {
                #expect(DrumMetronomeSyncMath.beatInBar(forSixteenthStep: step) == step / 4)
            }
        }
        #expect(DrumMetronomeSyncMath.isDownbeatStep(16))
        #expect(DrumMetronomeSyncMath.beatInBar(forSixteenthStep: 20) == 1)
    }

    @Test func clickThroughZerosDelayOnlyOnQuarters() {
        #expect(DrumMetronomeSyncMath.shouldZeroGrooveDelay(clickThrough: true, stepInBar: 0))
        #expect(DrumMetronomeSyncMath.shouldZeroGrooveDelay(clickThrough: true, stepInBar: 4))
        #expect(DrumMetronomeSyncMath.shouldZeroGrooveDelay(clickThrough: true, stepInBar: 8))
        #expect(DrumMetronomeSyncMath.shouldZeroGrooveDelay(clickThrough: true, stepInBar: 12))
        #expect(!DrumMetronomeSyncMath.shouldZeroGrooveDelay(clickThrough: true, stepInBar: 2))
        #expect(!DrumMetronomeSyncMath.shouldZeroGrooveDelay(clickThrough: true, stepInBar: 6))
        #expect(!DrumMetronomeSyncMath.shouldZeroGrooveDelay(clickThrough: false, stepInBar: 0))
    }
}

