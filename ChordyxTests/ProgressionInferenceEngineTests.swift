//
//  ProgressionInferenceEngineTests.swift
//  ChordyxTests
//

import Foundation
import Testing
@testable import Chordyx

struct ProgressionInferenceEngineTests {

    @Test func detectsPopProgressionLoop() {
        let engine = ProgressionInferenceEngine(debounce: 0.1)
        let cycle = ["C", "G", "Am", "F"]
        // Two full repetitions with stable holds past debounce.
        feed(cycle + cycle, into: engine, start: 0, step: 0.4)

        let result = engine.currentInference()
        #expect(result != nil)
        #expect(result?.normalized == ["C", "G", "Am", "F"])
        #expect((result?.confidence ?? 0) >= ProgressionInferenceEngine.applyConfidenceThreshold)
        #expect((result?.repetitions ?? 0) >= 2)
    }

    @Test func noInferenceWithoutRepetition() {
        let engine = ProgressionInferenceEngine(debounce: 0.1)
        feed(["C", "G", "Am", "F", "Dm", "Em"], into: engine, start: 0, step: 0.4)

        let result = engine.currentInference()
        #expect(result == nil || (result?.confidence ?? 0) < ProgressionInferenceEngine.applyConfidenceThreshold)
    }

    @Test func toleratesOnePassingChord() {
        let engine = ProgressionInferenceEngine(debounce: 0.1)
        // C G Am F | C G Dm Am F | C G Am F  (Dm is a passing chord)
        let sequence = ["C", "G", "Am", "F", "C", "G", "Dm", "Am", "F", "C", "G", "Am", "F"]
        feed(sequence, into: engine, start: 0, step: 0.4)

        let result = engine.currentInference()
        #expect(result != nil)
        #expect(result?.normalized == ["C", "G", "Am", "F"])
        #expect((result?.confidence ?? 0) >= 0.65)
    }

    @Test func resetClearsState() {
        let engine = ProgressionInferenceEngine(debounce: 0.1)
        feed(["G", "D", "Em", "C", "G", "D", "Em", "C"], into: engine, start: 0, step: 0.4)
        #expect(engine.currentInference() != nil)

        engine.reset()
        #expect(engine.currentInference() == nil)
        #expect(engine.committedSymbols.isEmpty)
    }

    @Test func prefersSmallestCycle() {
        let engine = ProgressionInferenceEngine(debounce: 0.1)
        // Am F Am F Am F — cycle length 2, not 4 or 6
        feed(["Am", "F", "Am", "F", "Am", "F"], into: engine, start: 0, step: 0.4)

        let result = engine.currentInference()
        #expect(result?.normalized == ["Am", "F"])
    }

    /// Feeds each symbol twice spaced by `step` so debounce commits every change.
    private func feed(
        _ symbols: [String],
        into engine: ProgressionInferenceEngine,
        start: TimeInterval,
        step: TimeInterval
    ) {
        var t = start
        for symbol in symbols {
            _ = engine.observe(symbol: symbol, at: t)
            t += step
            _ = engine.observe(symbol: symbol, at: t)
            t += step * 0.25
        }
        _ = engine.flush(at: t)
    }
}
