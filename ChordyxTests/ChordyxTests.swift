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
        let result = LiveKeyIntelligence.detect(from: ["C", "G", "Am", "F", "C", "G", "Am", "F"])
        #expect(result?.key == .C)
        #expect((result?.confidence ?? 0) > 0.12)
    }

    @Test func detectsWorshipProgressionInG() {
        let result = LiveKeyIntelligence.detect(from: ["G", "D", "Em", "C", "G", "D", "Em", "C"])
        #expect(result?.key == .G)
    }

    @Test func detectsTwoFiveOneInF() {
        let result = LiveKeyIntelligence.detect(from: ["Gm", "C7", "F", "Gm", "C7", "F"])
        #expect(result?.key == .F)
    }

    @Test func reportsMIRContributors() {
        let breakdown = LiveKeyIntelligence.analyze(symbols: ["D", "A", "Bm", "G", "D", "A", "Bm", "G"])
        #expect(breakdown?.bestKey == .D)
        #expect((breakdown?.contributors.count ?? 0) >= 5)
    }

    @Test func needsAtLeastThreeChords() {
        #expect(LiveKeyIntelligence.detect(from: ["C", "G"]) == nil)
    }
}

struct WorshipAutoKeyRulesTests {

    private func two(_ loop: [String]) -> [String] { loop + loop }

    @MainActor
    @Test func dMajorFamilyNeverBecomesE() {
        let symbols = ["D", "G", "A", "Bm", "D", "G", "A", "Bm"]
        #expect(KeyChordAnalysis.establishedMajorFamilyTonic(in: symbols) == MusicalKey.D.pitchClass)
        #expect(KeyChordAnalysis.isImplausibleLiveKeyCandidate(symbols: symbols, candidate: .E))
        #expect(!KeyChordAnalysis.isImplausibleLiveKeyCandidate(symbols: symbols, candidate: .D))
        #expect(KeyChordAnalysis.hasProgressionEvidence(symbols))
        #expect(KeyChordAnalysis.resolveLiveTonalCenter(
            symbols: symbols,
            scores: Dictionary(uniqueKeysWithValues: MusicalKey.allCases.map { ($0, $0 == .E ? 1.0 : 0.1) }),
            currentBest: .E
        ) == .D)
        #expect(AdaptiveKeyLearningEngine.shared.detect(from: symbols, sessionName: nil)?.key == .D)
    }

    @MainActor
    @Test func dGAThreeChordsEnoughToVetoE() {
        let symbols = ["D", "G", "A", "D", "G", "A"]
        #expect(KeyChordAnalysis.establishedMajorFamilyTonic(in: symbols) == MusicalKey.D.pitchClass)
        #expect(KeyChordAnalysis.isImplausibleLiveKeyCandidate(symbols: symbols, candidate: .E))
        #expect(AdaptiveKeyLearningEngine.shared.detect(from: symbols, sessionName: nil)?.key == .D)
    }

    @MainActor
    @Test func dBmGAIsDNotE() {
        let symbols = ["D", "Bm", "G", "A", "D", "Bm", "G", "A"]
        #expect(KeyChordAnalysis.establishedMajorFamilyTonic(in: symbols) == MusicalKey.D.pitchClass)
        #expect(KeyChordAnalysis.isImplausibleLiveKeyCandidate(symbols: symbols, candidate: .E))
        #expect(AdaptiveKeyLearningEngine.shared.detect(from: symbols, sessionName: nil)?.key == .D)
    }

    @MainActor
    @Test func audioHintDetectsWithoutChordProgression() {
        AdaptiveKeyLearningEngine.shared.clearAudioKeyHint()
        var scores = Dictionary(uniqueKeysWithValues: MusicalKey.allCases.map { ($0, 0.05) })
        scores[.G] = 1.0
        AdaptiveKeyLearningEngine.shared.updateAudioKeyHint(
            key: .G,
            scale: .mixolydian,
            confidence: 0.42,
            scores: scores
        )
        let result = AdaptiveKeyLearningEngine.shared.detect(from: [], sessionName: nil)
        #expect(result?.key == .G)
        #expect(result?.source == .audio)
        #expect(result?.scale == .mixolydian)
        AdaptiveKeyLearningEngine.shared.clearAudioKeyHint()
    }

    @MainActor
    @Test func chordFamilyBeatsConflictingAudioHint() {
        AdaptiveKeyLearningEngine.shared.clearAudioKeyHint()
        var scores = Dictionary(uniqueKeysWithValues: MusicalKey.allCases.map { ($0, 0.05) })
        scores[.E] = 1.0
        AdaptiveKeyLearningEngine.shared.updateAudioKeyHint(
            key: .E,
            scale: .major,
            confidence: 0.9,
            scores: scores
        )
        let symbols = ["D", "G", "A", "Bm", "D", "G", "A", "Bm"]
        let result = AdaptiveKeyLearningEngine.shared.detect(from: symbols, sessionName: nil)
        #expect(result?.key == .D)
        #expect(result?.source == .ensemble)
        #expect(result?.scale == .major)
        AdaptiveKeyLearningEngine.shared.clearAudioKeyHint()
    }

    @Test func majorTriadLettersCountAsChordVoicing() {
        #expect(KeyChordAnalysis.isChordVoicing(pitchClassCount: 3, symbol: "C"))
        #expect(KeyChordAnalysis.isChordVoicing(pitchClassCount: 3, symbol: "G"))
        #expect(!KeyChordAnalysis.isChordVoicing(pitchClassCount: 1, symbol: "E"))
        #expect(KeyChordAnalysis.hasTriadOrSeventhQuality("C"))
        #expect(KeyChordAnalysis.hasTriadOrSeventhQuality("C/E"))
    }

    @Test func keyEvidenceSymbolPreservesInversion() {
        // Internal indices: E=4 bass, C=12, E=16, G=19 → C/E
        let symbol = KeyChordAnalysis.keyEvidenceSymbol(
            displaySymbol: "C",
            noteIndices: [4, 12, 16, 19],
            preferFlats: false
        )
        #expect(symbol == "C/E")
    }

    @MainActor
    @Test func midiVoicingChromaDetectsWithoutManySymbols() {
        AdaptiveKeyLearningEngine.shared.clearMIDIChroma()
        AdaptiveKeyLearningEngine.shared.clearAudioKeyHint()
        // Two C major voicings into MIDI chroma.
        AdaptiveKeyLearningEngine.shared.ingestMIDIVoicing(pitchClasses: [0, 4, 7], bassPitchClass: 0)
        AdaptiveKeyLearningEngine.shared.ingestMIDIVoicing(pitchClasses: [0, 4, 7], bassPitchClass: 0)
        AdaptiveKeyLearningEngine.shared.ingestMIDIVoicing(pitchClasses: [0, 2, 4, 5, 7, 9, 11], bassPitchClass: 0)
        let result = AdaptiveKeyLearningEngine.shared.detect(from: [], sessionName: nil)
        #expect(result?.key == .C)
        #expect(result?.source == .midi)
        AdaptiveKeyLearningEngine.shared.clearMIDIChroma()
    }

    @Test func dMajorFamilyInfersMajorScale() {
        let scale = TonalScaleIntelligence.inferScale(
            from: ["D", "G", "A", "Bm", "D", "G", "A", "Bm"],
            tonic: .D
        )
        #expect(scale == .major)
    }

    @Test func dominantOnTonicInfersMixolydian() {
        let scale = TonalScaleIntelligence.inferScale(
            from: ["G7", "C", "F", "G7", "C"],
            tonic: .G
        )
        #expect(scale == .mixolydian)
    }

    @Test func chromaMajorTemplateDetectsCMajor() {
        // Strong C tonic + C major collection (C D E F G A B).
        var chroma = [Double](repeating: 0.02, count: 12)
        chroma[0] = 1.6
        chroma[2] = 0.85
        chroma[4] = 1.1
        chroma[5] = 0.8
        chroma[7] = 1.35
        chroma[9] = 0.75
        chroma[11] = 0.7
        let detected = TonalScaleIntelligence.detectFromChroma(chroma)
        #expect(detected?.key == .C)
        let scale = detected?.scale
        #expect(
            scale == .major
                || scale == .majorPentatonic
                || scale == .lydian
                || scale == .mixolydian
                || scale == .naturalMinor
        )
    }

    @Test func fmaj7PadWithC7IsFNotE() {
        let symbols = ["Fmaj7", "Gm7", "Am7", "Gsus4", "D7", "C7"]
        #expect(KeyChordAnalysis.hasProgressionEvidence(symbols))
        #expect(KeyChordAnalysis.establishedMajorTonicFromIAndV7(in: symbols) == MusicalKey.F.pitchClass)
        #expect(KeyChordAnalysis.isImplausibleLiveKeyCandidate(symbols: symbols, candidate: .E))
        #expect(!KeyChordAnalysis.isImplausibleLiveKeyCandidate(symbols: symbols, candidate: .F))
        #expect(KeyChordAnalysis.resolveLiveTonalCenter(
            symbols: symbols,
            scores: Dictionary(uniqueKeysWithValues: MusicalKey.allCases.map { ($0, $0 == .E ? 1.0 : 0.15) }),
            currentBest: .E
        ) == .F)
    }

    @Test func amDBmEmAmDGIsGNotC() {
        let symbols = ["Am", "D", "Bm", "Em", "Am", "D", "G"]
        #expect(KeyChordAnalysis.hasProgressionEvidence(symbols))
        #expect(KeyChordAnalysis.authenticDominantCadenceDestination(in: symbols) == MusicalKey.G.pitchClass)
        #expect(KeyChordAnalysis.isImplausibleLiveKeyCandidate(symbols: symbols, candidate: .C))
        #expect(!KeyChordAnalysis.isImplausibleLiveKeyCandidate(symbols: symbols, candidate: .G))
        #expect(KeyChordAnalysis.resolveLiveTonalCenter(
            symbols: symbols,
            scores: Dictionary(uniqueKeysWithValues: MusicalKey.allCases.map { ($0, $0 == .C ? 1.0 : 0.2) }),
            currentBest: .C
        ) == .G)
        #expect(LiveKeyIntelligence.detect(from: symbols)?.key == .G)
    }

    @Test func amDBmEmTwoLoopsIsG() {
        let symbols = two(["Am", "D", "Bm", "Em"])
        #expect(WorshipAutoKeyRules.resolveKey(from: symbols) == .G)
    }

    @Test func threeChordsNeverUnlock() {
        #expect(!KeyChordAnalysis.hasProgressionEvidence(["Am", "F", "C"]))
        #expect(!WorshipAutoKeyRules.hasTwoLoopEvidence(["Am", "F", "C"]))
    }

    @Test func amFCGIsCAfterTwoLoops() {
        let symbols = two(["Am", "F", "C", "G"])
        #expect(WorshipAutoKeyRules.hasTwoLoopEvidence(symbols))
        #expect(WorshipAutoKeyRules.resolveKey(from: symbols) == .C)
        #expect(KeyChordAnalysis.hasProgressionEvidence(symbols))
    }

    @Test func gDEmCIsG() {
        let symbols = two(["G", "D", "Em", "C"])
        #expect(WorshipAutoKeyRules.resolveKey(from: symbols) == .G)
    }

    @Test func cBbFIsFNotC() {
        let symbols = two(["C", "Bb", "F"])
        #expect(WorshipAutoKeyRules.resolveKey(from: symbols) == .F)
        #expect(KeyChordAnalysis.resolveLiveTonalCenter(
            symbols: symbols,
            scores: Dictionary(uniqueKeysWithValues: MusicalKey.allCases.map { ($0, $0 == .C ? 1.0 : 0.1) }),
            currentBest: .C
        ) == .F)
    }

    @Test func andalusianIsAMinorLetter() {
        let symbols = two(["Am", "G", "F", "E"])
        #expect(WorshipAutoKeyRules.resolveKey(from: symbols) == .A)
    }

    @Test func ambiguousDEmGDependsOnFourth() {
        #expect(WorshipAutoKeyRules.resolveKey(from: two(["D", "Em", "G", "A"])) == .D)
        #expect(WorshipAutoKeyRules.resolveKey(from: two(["D", "Em", "G", "C"])) == .G)
    }

    @Test func ambiguousCDmFDependsOnFourth() {
        #expect(WorshipAutoKeyRules.resolveKey(from: two(["C", "Dm", "F", "Bb"])) == .F)
        #expect(WorshipAutoKeyRules.resolveKey(from: two(["C", "Dm", "F", "G"])) == .C)
    }

    @Test func amFGPlusCIsCPlusDmIsA() {
        #expect(WorshipAutoKeyRules.resolveKey(from: two(["Am", "F", "G", "C"])) == .C)
        #expect(WorshipAutoKeyRules.resolveKey(from: two(["Am", "F", "G", "Dm"])) == .A)
    }

    @Test func dmGCIIsC() {
        #expect(WorshipAutoKeyRules.resolveKey(from: two(["Dm", "G", "C"])) == .C)
    }

    @Test func longAmJourneyIsA() {
        let loop = ["Am", "E", "Am", "Dm", "G", "C", "F", "Dm", "E", "Am"]
        let symbols = two(loop)
        #expect(WorshipAutoKeyRules.hasTwoLoopEvidence(symbols))
        #expect(WorshipAutoKeyRules.resolveKey(from: symbols) == .A)
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

    @Test func notationChangeIsNotTreatedAsLiveBurst() {
        var prior = SessionSyncPayload.empty
        prior.sessionToken = UUID()
        prior.chords = [ChordEntry(symbolName: "C", latinName: "Do", order: 0)]
        prior.notation = .symbol

        var next = prior
        next.notation = .latin
        next.liveChordSymbol = "Am"

        #expect(!next.isLiveChordBurst(comparedTo: prior))
    }

    @Test func activeChordChangeIsNotTreatedAsLiveBurst() {
        let chordA = ChordEntry(symbolName: "C", latinName: "Do", order: 0)
        let chordB = ChordEntry(symbolName: "G", latinName: "Sol", order: 1)
        var prior = SessionSyncPayload.empty
        prior.sessionToken = UUID()
        prior.chords = [chordA, chordB]
        prior.activeChordID = chordA.id

        var next = prior
        next.activeChordID = chordB.id
        next.pianoNotes = [60, 64, 67]

        #expect(!next.isLiveChordBurst(comparedTo: prior))
    }

    @Test func pianoOnlyChangeIsLiveBurst() {
        var prior = SessionSyncPayload.empty
        prior.sessionToken = UUID()
        prior.chords = [ChordEntry(symbolName: "C", latinName: "Do", order: 0)]
        prior.activeChordID = prior.chords[0].id

        var next = prior
        next.liveChordSymbol = "C"
        next.pianoNotes = [60, 64, 67]
        next.isPianoActive = true

        #expect(next.isLiveChordBurst(comparedTo: prior))
    }

    @Test func joinQRDeepLinkRoundTrips() {
        let code = "BCDFGH"
        let url = SessionJoinQR.deepLink(for: code)
        #expect(url != nil)
        #expect(SessionJoinQR.parseCode(from: url!) == code)
        #expect(SessionJoinQR.parseScannedValue(url!.absoluteString) == code)
        #expect(SessionJoinQR.parseScannedValue("bcd-fgh") == code)
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
            #expect(stepInBar % 4 == 0)
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

#if false
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
#endif

// MARK: - Auto-key live path (same gates as SessionViewModel.maybeAutoDetectKey)

@MainActor
struct AutoKeyLivePathTests {

    private func decide(
        symbols: [String],
        currentKey: MusicalKey = .C,
        isKeyAutoDetected: Bool = false,
        lockedConfidence: Double = 0,
        pendingKey: MusicalKey? = nil,
        pendingHits: Int = 0,
        forcePeriodicReview: Bool = false,
        armedAt: TimeInterval = 0,
        now: TimeInterval = 10,
        detect: @escaping ([String], String?) -> AdaptiveKeyDetection?
    ) -> SessionViewModel.AutoKeyCommitDecision? {
        SessionViewModel.evaluateAutoKeyCommit(
            symbols: symbols,
            currentKey: currentKey,
            isKeyAutoDetected: isKeyAutoDetected,
            lockedConfidence: lockedConfidence,
            pendingKey: pendingKey,
            pendingHits: pendingHits,
            forcePeriodicReview: forcePeriodicReview,
            sessionName: nil,
            armedAt: armedAt,
            now: now,
            detect: detect
        )
    }

    private func stub(
        _ key: MusicalKey,
        confidence: Double,
        source: AdaptiveKeyDetection.Source = .ensemble
    ) -> ([String], String?) -> AdaptiveKeyDetection? {
        { _, _ in AdaptiveKeyDetection(key: key, confidence: confidence, source: source) }
    }

    @Test func singleNoteDoesNotAnnounceKey() {
        let decision = decide(symbols: ["E"], detect: stub(.E, confidence: 0.99))
        #expect(decision == nil)
        #expect(!KeyChordAnalysis.hasProgressionEvidence(["E"]))
        #expect(!KeyChordAnalysis.hasProgressionEvidence(["D", "E"]))
    }

    @Test func scaleFragmentEm7FGDoesNotUnlockAutoKey() {
        #expect(!KeyChordAnalysis.hasProgressionEvidence(["Em7", "F", "G"]))
        let decision = decide(symbols: ["Em7", "F", "G"], detect: stub(.E, confidence: 0.99))
        #expect(decision == nil)
    }

    @Test func powerChordsAloneDoNotUnlockAutoKey() {
        #expect(!KeyChordAnalysis.hasProgressionEvidence(["D5", "E5", "F5", "G5"]))
        let decision = decide(symbols: ["D5", "A5", "D5", "A5"], detect: stub(.D, confidence: 0.9))
        #expect(decision == nil)
    }

    @Test func vetoesEAgainstDMinorProgression() {
        let symbols = ["Dm", "Gm", "A", "Dm", "Dm", "Gm", "A", "Dm"]
        #expect(KeyChordAnalysis.hasProgressionEvidence(symbols))
        #expect(KeyChordAnalysis.isImplausibleLiveKeyCandidate(symbols: symbols, candidate: .E))
        let decision = decide(symbols: symbols, detect: stub(.E, confidence: 0.95, source: .memory))
        #expect(decision == nil)
    }

    @Test func liveFollowFlipsOnClearModulation() {
        // Already following D; recent window is clearly C major → flip without sticky lock.
        let symbols = ["C", "F", "G", "Am", "C", "F", "G", "Am"]
        let decision = decide(
            symbols: symbols,
            currentKey: .D,
            isKeyAutoDetected: true,
            lockedConfidence: 0.95,
            detect: stub(.C, confidence: 0.70)
        )
        #expect(decision?.action == .commit(key: .C, source: .ensemble))
    }

    @Test func audioAloneCanCommitWithoutChordEvidence() {
        let decision = decide(
            symbols: ["E"],
            currentKey: .C,
            isKeyAutoDetected: false,
            detect: stub(.D, confidence: 0.40, source: .audio)
        )
        #expect(decision?.action == .commit(key: .D, source: .audio))
    }

    @Test func nonAudioStillNeedsProgressionEvidence() {
        let decision = decide(
            symbols: ["E"],
            detect: stub(.E, confidence: 0.99, source: .ensemble)
        )
        #expect(decision == nil)
    }

    @Test func audioFollowFlipsOnMicChange() {
        let decision = decide(
            symbols: ["D", "A"],
            currentKey: .D,
            isKeyAutoDetected: true,
            lockedConfidence: 0.9,
            forcePeriodicReview: true,
            detect: stub(.G, confidence: 0.35, source: .audio)
        )
        #expect(decision?.action == .commit(key: .G, source: .audio))
    }

    @Test func dMinorProgressionCommitsDNotE() {
        let symbols = ["Dm", "Gm", "A", "Dm", "Dm", "Gm", "A", "Dm"]
        let intelligence = LiveKeyIntelligence.detect(from: symbols)
        #expect(intelligence?.key == .D)

        let decision = decide(symbols: symbols, detect: stub(.D, confidence: 0.72))
        #expect(decision?.action == .commit(key: .D, source: .ensemble))
    }

    @Test func dMinorProgressionUsesSameCommitFunctionAsSession() {
        let symbols = ["Dm", "Gm", "A", "Dm", "Dm", "Gm", "A", "Dm"]
        let decision = decide(
            symbols: symbols,
            detect: { live, _ in
                guard let result = LiveKeyIntelligence.detect(from: live) else { return nil }
                return AdaptiveKeyDetection(
                    key: result.key,
                    confidence: max(result.confidence, 0.70),
                    source: .ensemble
                )
            }
        )
        #expect(decision?.action == .commit(key: .D, source: .ensemble))
    }

    @Test func cooldownBlocksPrematureLetter() {
        let decision = decide(
            symbols: ["Dm", "Gm", "A", "Dm", "Dm", "Gm", "A", "Dm"],
            armedAt: 100,
            now: 101,
            detect: stub(.D, confidence: 0.9)
        )
        #expect(decision == nil)
    }

    @Test func oneLoopDoesNotUnlockEvenWithStrongStub() {
        let symbols = ["Am", "F", "C", "G"]
        #expect(!KeyChordAnalysis.hasProgressionEvidence(symbols))
        let decision = decide(symbols: symbols, detect: stub(.C, confidence: 0.99))
        #expect(decision == nil)
    }

    @Test func latinTonicForDIsRe() {
        #expect(ChordNotation.latin.cycleGlyph(for: .D) == "Re")
        #expect(ChordNotation.latin.cycleGlyph(for: .E) == "Mi")
        #expect(ChordNotation.symbol.cycleGlyph(for: .D) == "D")
    }
}

struct ChordRecognizerGuitarTests {

    @Test func openGTriadFromMIDINotes() {
        // G2 B2 D3 (MIDI 43, 47, 50)
        let notes = [43, 47, 50].map { PianoNote.fromMIDINote($0) }
        let symbol = ChordRecognizer.symbolForLiveGuitar(notes: notes, preferFlats: false)
        #expect(symbol == "G")
    }

    @Test func powerChordRootFifth() {
        // E2 B2 (40, 47)
        let notes = [40, 47].map { PianoNote.fromMIDINote($0) }
        let symbol = ChordRecognizer.symbolForLiveGuitar(notes: notes, preferFlats: false)
        #expect(symbol == "E5")
    }

    @Test func amTriadLowRegister() {
        // A2 C3 E3 (45, 48, 52)
        let notes = [45, 48, 52].map { PianoNote.fromMIDINote($0) }
        let symbol = ChordRecognizer.symbolForLiveGuitar(notes: notes, preferFlats: false)
        #expect(symbol == "Am")
    }
}

struct ChordRecognizerAutoKeyVoicingTests {

    @Test func dEGWithBassDIsNotEm7() {
        let symbol = ChordRecognizer.symbol(
            forPitchClasses: [2, 4, 7],
            bassPitchClass: 2,
            preferFlats: false
        )
        #expect(symbol != "Em7")
        #expect(symbol != "Em7/D")
        if let symbol {
            #expect(!symbol.hasPrefix("Em"))
        }
    }

    @Test func dEGClusterOnPianoIsNotEm7() {
        // D3 E3 G3 (MIDI 50/52/55) — live D minor cluster that was labeled Em7.
        let notes = [50, 52, 55]
        let symbol = ChordRecognizer.symbolConsideringBothHands(notes: notes, preferFlats: false)
        #expect(symbol != "Em7")
        #expect(symbol != "Em7/D")
        if let symbol {
            #expect(!symbol.hasPrefix("Em"))
        }
    }

    @Test func incompleteClusterIsNotAChordVoicing() {
        #expect(!KeyChordAnalysis.isChordVoicing(pitchClassCount: 3, symbol: "D"))
        #expect(!KeyChordAnalysis.isChordVoicing(pitchClassCount: 1, symbol: "E"))
        #expect(KeyChordAnalysis.isChordVoicing(pitchClassCount: 3, symbol: "Dm"))
    }

    @Test func em7RootPositionWithoutFifthStillMatchesWhenBassIsE() {
        // E G D (no B) with bass E is a legitimate incomplete Em7.
        let symbol = ChordRecognizer.symbol(
            forPitchClasses: [4, 7, 2],
            bassPitchClass: 4,
            preferFlats: false
        )
        #expect(symbol == "Em7")
    }
}


