//
//  TempoOctaveResolver.swift
//  Chordyx
//
//  Pure tempo / octave disambiguation from inter-onset intervals.
//  Prefer note-level rhythm over slow harmonic rhythm so Latin/church
//  grooves (songó ~110–130) are not locked at half-time.
//

import Foundation

enum TempoOctaveResolver: Sendable {
    struct Estimate: Equatable, Sendable {
        let bpm: Double
        let confidence: Double
    }

    /// Pick BPM from IOIs. When dense/syncopated playing is likely, prefer the
    /// faster octave on near-ties (inverse of the old half-time bias).
    static func bpmFromIntervals(
        _ intervals: [Double],
        sampleFactor: Double,
        preferFasterOnTie: Bool,
        minBPM: Double = 48,
        maxBPM: Double = 200
    ) -> Estimate? {
        guard intervals.count >= 3 else { return nil }

        let sorted = intervals.sorted()
        let median = sorted[sorted.count / 2]

        var candidates: [(bpm: Double, score: Double)] = []
        for multiplier in [0.5, 1.0, 2.0, 4.0] {
            let beatPeriod = median * multiplier
            guard beatPeriod >= 0.28, beatPeriod <= 2.0 else { continue }
            let bpm = normalizeBPM(60.0 / beatPeriod, minBPM: minBPM, maxBPM: maxBPM)
            let period = 60.0 / bpm
            let score = intervalConsistencyScore(intervals, beatPeriod: period)
            candidates.append((bpm, score))
        }
        guard !candidates.isEmpty else { return nil }

        guard let best = candidates.max(by: { lhs, rhs in
            if abs(lhs.score - rhs.score) > 0.06 { return lhs.score < rhs.score }
            // Near-tie: dense grooves → faster; sparse ballads → slower.
            return preferFasterOnTie ? (lhs.bpm < rhs.bpm) : (lhs.bpm > rhs.bpm)
        }) else { return nil }

        let spread = sorted[sorted.count - 1] - sorted[0]
        let consistency = 1.0 - min(1.0, spread / max(median, 0.01))
        let confidence = min(
            1.0,
            max(0.25, sampleFactor) * max(0.45, consistency) * max(0.4, best.score)
        )
        return Estimate(bpm: best.bpm, confidence: confidence)
    }

    /// Fuse note-onset tempo with optional chord-change (harmonic) tempo.
    /// Chord changes may reinforce ballads; they must not force half-time on dense MIDI.
    static func fuseEstimates(
        noteOnset: Estimate?,
        chordChange: Estimate?,
        onsetDensityPerSecond: Double,
        preferFaster: Bool
    ) -> Estimate? {
        switch (noteOnset, chordChange) {
        case (nil, nil):
            return nil
        case (let note?, nil):
            return note
        case (nil, let chord?):
            // Chord-only: if density is high, double when the chord reading looks half-time.
            if preferFaster || onsetDensityPerSecond >= 2.4 {
                let doubled = normalizeBPM(chord.bpm * 2, minBPM: 48, maxBPM: 200)
                if doubled >= 96, doubled <= 168 {
                    return Estimate(bpm: doubled, confidence: chord.confidence * 0.85)
                }
            }
            return chord
        case (let note?, let chord?):
            let ratio = note.bpm / max(chord.bpm, 1)
            // Classic half-time trap: chords ~60, notes ~120.
            if ratio >= 1.7, ratio <= 2.35, preferFaster || onsetDensityPerSecond >= 2.0 {
                return Estimate(
                    bpm: note.bpm,
                    confidence: min(1, max(note.confidence, chord.confidence) + 0.08)
                )
            }
            // Notes look double-time of a slow ballad — keep chords if density is low.
            if ratio >= 1.7, ratio <= 2.35, onsetDensityPerSecond < 1.4, chord.bpm <= 90 {
                return Estimate(
                    bpm: chord.bpm,
                    confidence: min(1, chord.confidence + 0.05)
                )
            }
            if abs(note.bpm - chord.bpm) < 10 {
                return Estimate(
                    bpm: (note.bpm * 0.65 + chord.bpm * 0.35),
                    confidence: min(1, (note.confidence + chord.confidence) / 2 + 0.1)
                )
            }
            // Prefer the stronger estimate; break ties toward note onsets when dense.
            if note.confidence + (preferFaster ? 0.08 : 0) >= chord.confidence {
                return note
            }
            return chord
        }
    }

    static func onsetDensity(times: [TimeInterval], windowSeconds: TimeInterval = 4) -> Double {
        guard let last = times.last else { return 0 }
        let recent = times.filter { last - $0 <= windowSeconds }
        guard let first = recent.first, recent.count >= 2 else { return 0 }
        let span = max(0.35, last - first)
        return Double(recent.count - 1) / span
    }

    static func preferFasterOctave(
        onsetDensityPerSecond: Double,
        syncopationHint: Double = 0
    ) -> Bool {
        onsetDensityPerSecond >= 2.2 || (onsetDensityPerSecond >= 1.6 && syncopationHint >= 0.32)
    }

    static func normalizeBPM(_ bpm: Double, minBPM: Double = 48, maxBPM: Double = 200) -> Double {
        var value = bpm
        while value < minBPM { value *= 2 }
        while value > maxBPM { value /= 2 }
        return value
    }

    static func intervalConsistencyScore(_ intervals: [Double], beatPeriod: Double) -> Double {
        guard beatPeriod > 0, !intervals.isEmpty else { return 0 }
        var hits = 0.0
        for gap in intervals {
            let ratio = gap / beatPeriod
            var bestDistance = Double.greatestFiniteMagnitude
            // Include half-beat (eighth notes) and dotted values common in Latin grooves.
            for multiple in [0.5, 1.0, 1.5, 2.0, 3.0, 4.0] {
                bestDistance = min(bestDistance, abs(ratio - multiple))
            }
            if bestDistance < 0.22 {
                hits += 1.0 - (bestDistance / 0.22)
            }
        }
        return hits / Double(intervals.count)
    }
}
