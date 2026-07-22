//
//  AudioBeatTracker.swift
//  Chordyx
//

#if os(macOS) || os(iOS)
import Foundation

struct AudioOnsetEvent: Sendable {
    let time: TimeInterval
    let strength: Float
}

/// Runs on audio capture queues — explicitly not MainActor-isolated.
nonisolated final class AudioBeatTracker: @unchecked Sendable {
    private(set) var estimatedBPM: Double?
    private(set) var confidence: Double = 0
    private(set) var syncopationIndex: Double = 0
    private(set) var onsetDensityPerSecond: Double = 0

    private var onsets: [AudioOnsetEvent] = []
    private var fluxHistory: [Float] = []
    private var lastFlux: Float = 0
    private let maxOnsets = 64
    private let minBPM = 48.0
    private let maxBPM = 200.0

    func ingest(features: [AudioFeatureSnapshot]) {
        guard !features.isEmpty else { return }

        for snapshot in features {
            fluxHistory.append(snapshot.spectralFlux)
            if fluxHistory.count > 32 {
                fluxHistory.removeFirst(fluxHistory.count - 32)
            }

            let adaptiveThreshold = (fluxHistory.reduce(0, +) / Float(fluxHistory.count)) * 1.35 + 0.002
            if snapshot.spectralFlux > adaptiveThreshold,
               snapshot.rms > 0.004,
               snapshot.spectralFlux > lastFlux * 1.05 {
                onsets.append(AudioOnsetEvent(time: snapshot.time, strength: snapshot.spectralFlux))
                if onsets.count > maxOnsets {
                    onsets.removeFirst(onsets.count - maxOnsets)
                }
            }
            lastFlux = snapshot.spectralFlux
        }

        recalculate()
    }

    func reset() {
        onsets.removeAll()
        fluxHistory.removeAll()
        lastFlux = 0
        estimatedBPM = nil
        confidence = 0
        syncopationIndex = 0
        onsetDensityPerSecond = 0
    }

    func recentOnsetSnapshot() -> [(time: TimeInterval, strength: Double)] {
        onsets.suffix(28).map { ($0.time, Double($0.strength)) }
    }

    private func recalculate() {
        guard onsets.count >= 5 else { return }

        let recent = onsets.suffix(24)
        if let first = recent.first, let last = recent.last {
            let span = max(0.5, last.time - first.time)
            onsetDensityPerSecond = Double(recent.count) / span
        }

        var intervals: [Double] = []
        let onsetArray = Array(recent)
        for index in 1..<onsetArray.count {
            let gap = onsetArray[index].time - onsetArray[index - 1].time
            if gap >= 0.14, gap <= 1.8 {
                intervals.append(gap)
            }
        }
        guard intervals.count >= 3 else { return }

        let sorted = intervals.sorted()
        let median = sorted[sorted.count / 2]

        var candidates: [(bpm: Double, score: Double)] = []
        for multiplier in [0.5, 1.0, 2.0, 4.0] {
            let beatPeriod = median * multiplier
            guard beatPeriod >= 0.32, beatPeriod <= 2.0 else { continue }
            let bpm = 60.0 / beatPeriod
            var normalized = bpm
            while normalized < minBPM { normalized *= 2 }
            while normalized > maxBPM { normalized /= 2 }
            let period = 60.0 / normalized
            let score = intervalConsistencyScore(intervals, beatPeriod: period)
            candidates.append((normalized, score))
        }
        guard !candidates.isEmpty else { return }

        guard let best = candidates.max(by: { lhs, rhs in
            if abs(lhs.score - rhs.score) > 0.07 { return lhs.score < rhs.score }
            return lhs.bpm > rhs.bpm
        }) else { return }

        guard let firstInterval = sorted.first, let lastInterval = sorted.last else { return }
        let spread = lastInterval - firstInterval
        let consistency = 1.0 - min(1.0, spread / max(median, 0.01))
        let sampleConfidence = min(1.0, Double(onsets.count) / 22.0) * consistency * best.score

        syncopationIndex = estimateSyncopation(beatPeriod: 60.0 / best.bpm, onsets: onsetArray)

        if let previous = estimatedBPM {
            let blend = min(0.42, 0.1 + sampleConfidence * 0.25)
            estimatedBPM = previous * (1 - blend) + best.bpm * blend
        } else {
            estimatedBPM = best.bpm
        }
        confidence = max(confidence * 0.88, sampleConfidence)
    }

    private func intervalConsistencyScore(_ intervals: [Double], beatPeriod: Double) -> Double {
        guard beatPeriod > 0, !intervals.isEmpty else { return 0 }
        var hits = 0.0
        for gap in intervals {
            let ratio = gap / beatPeriod
            var bestDistance = Double.greatestFiniteMagnitude
            for divisor in [1.0, 2.0, 4.0, 0.5] {
                let multiple = (ratio * divisor).rounded()
                guard multiple >= 1 else { continue }
                let normalized = multiple / divisor
                bestDistance = min(bestDistance, abs(ratio - normalized))
            }
            if bestDistance < 0.22 {
                hits += 1.0 - (bestDistance / 0.22)
            }
        }
        return hits / Double(intervals.count)
    }

    private func estimateSyncopation(beatPeriod: Double, onsets: [AudioOnsetEvent]) -> Double {
        guard onsets.count >= 4, beatPeriod > 0, let reference = onsets.first?.time else { return 0 }
        var offBeat = 0
        var total = 0
        for onset in onsets {
            let phase = (onset.time - reference).truncatingRemainder(dividingBy: beatPeriod * 4)
            let beatPhase = (phase / beatPeriod).truncatingRemainder(dividingBy: 1.0)
            let downbeatDistance = min(beatPhase, 1.0 - beatPhase)
            let offbeatDistance = abs(beatPhase - 0.5)
            if offbeatDistance < downbeatDistance { offBeat += 1 }
            total += 1
        }
        return total > 0 ? Double(offBeat) / Double(total) : 0
    }
}
#endif
