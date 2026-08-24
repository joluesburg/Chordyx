//
//  LivePerformanceAnalyzer.swift
//  Chordyx
//
//  Sophisticated live tempo + style inference from chord changes, harmonic complexity,
//  and rhythmic syncopation (Mac solo accompaniment prototype).
//

import Foundation

@MainActor
final class LivePerformanceAnalyzer {
    private(set) var estimatedBPM: Double?
    private(set) var tempoConfidence: Double = 0
    private(set) var detectedStyle: LiveMusicStyle = .unknown
    private(set) var styleConfidence: Double = 0
    private(set) var suggestedStyle: LiveMusicStyle?
    private(set) var syncopationIndex: Double = 0
    private(set) var averageChordComplexity: Double = 0
    private(set) var chordChangesPerMinute: Double = 0
    private(set) var isTracking = false
    private(set) var latinRhythmAnalysis: LatinRhythmAnalysis = .empty
    private(set) var detectedClave: ClaveOrientation = .unknown
    private(set) var montunoStrength: Double = 0
    private(set) var lastStyleScores: [LiveMusicStyle: Double] = [:]

    private var rhythmOnsets: [RhythmOnsetEvent] = []
    private var chordEvents: [ChordPerformanceEvent] = []
    private var lastRhythmOnset: TimeInterval?
    private var lastChordSymbol: String?
    private var silenceTask: Task<Void, Never>?

    private let maxRhythmOnsets = 48
    private let maxChordEvents = 24
    private let minRhythmGap: TimeInterval = 0.07
    private let minBPM = 48.0
    private let maxBPM = 200.0

    func registerPerformance(
        chordSymbol: String?,
        activeNoteCount: Int,
        newNotesAdded: Bool,
        learnTempo: Bool = true,
        at time: TimeInterval = Date().timeIntervalSince1970
    ) {
        guard activeNoteCount > 0 || chordSymbol != nil else { return }

        let symbolChanged = {
            guard let chordSymbol, !chordSymbol.isEmpty else { return false }
            return chordSymbol != lastChordSymbol
        }()

        if symbolChanged, let chordSymbol {
            lastChordSymbol = chordSymbol
            let analysis = ChordSymbolAnalysis.analyze(chordSymbol)
            chordEvents.append(ChordPerformanceEvent(
                symbol: chordSymbol,
                time: time,
                analysis: analysis,
                noteCount: activeNoteCount
            ))
            if chordEvents.count > maxChordEvents {
                chordEvents.removeFirst(chordEvents.count - maxChordEvents)
            }
            appendRhythmOnset(at: time, strength: 1.0, isChordChange: true)
        } else if newNotesAdded {
            let strength = min(1.0, 0.45 + Double(activeNoteCount) * 0.12)
            appendRhythmOnset(at: time, strength: strength, isChordChange: false)
        }

        isTracking = true
        if learnTempo {
            recalculateTempo(at: time)
        }
        recalculateStyle(at: time)
        scheduleSilenceDecay()
    }

    func reset() {
        silenceTask?.cancel()
        silenceTask = nil
        rhythmOnsets.removeAll()
        chordEvents.removeAll()
        lastRhythmOnset = nil
        lastChordSymbol = nil
        estimatedBPM = nil
        tempoConfidence = 0
        detectedStyle = .unknown
        styleConfidence = 0
        suggestedStyle = nil
        syncopationIndex = 0
        averageChordComplexity = 0
        chordChangesPerMinute = 0
        isTracking = false
        latinRhythmAnalysis = .empty
        detectedClave = .unknown
        montunoStrength = 0
        lastStyleScores = [:]
    }

    func buildGenreSnapshot(
        audioProbabilities: [LiveMusicStyle: Double],
        onsetDensity: Double,
        spectralBrightness: Double,
        lowEnergyRatio: Double
    ) -> GlobalGenrePerformanceSnapshot {
        let bpm = estimatedBPM ?? 100
        let windowQualities = chordEvents.suffix(12).map(\.analysis.quality)
        let waltzLikelihood = lastStyleScores[.brushWaltz, default: 0] * 0.65
            + (beatsPerBarHint() == 3 ? 0.35 : 0)

        return GlobalGenrePerformanceSnapshot(
            bpm: bpm,
            syncopation: syncopationIndex,
            chordChangeRate: chordChangesPerMinute,
            avgHarmonicComplexity: averageChordComplexity,
            minor7Ratio: ratio(windowQualities, equals: .minor7),
            dom7Ratio: ratio(windowQualities, equals: .dominant),
            maj7Ratio: ratio(windowQualities, equals: .major7),
            triadRatio: ratio(windowQualities, equals: .major) + ratio(windowQualities, equals: .minor),
            extendedRatio: ratio(windowQualities, equals: .extended),
            powerRatio: ratio(windowQualities, equals: .power),
            susRatio: ratio(windowQualities, equals: .suspended),
            waltzLikelihood: waltzLikelihood,
            onsetDensity: onsetDensity,
            spectralBrightness: spectralBrightness,
            lowEnergyRatio: lowEnergyRatio,
            liveStyleScores: lastStyleScores,
            latinAnalysis: latinRhythmAnalysis,
            audioStyleProbabilities: audioProbabilities
        )
    }

    private func beatsPerBarHint() -> Int {
        guard rhythmOnsets.count >= 8, let bpm = estimatedBPM, bpm > 0 else { return 4 }
        let beatPeriod = 60.0 / bpm
        let barPeriod = beatPeriod * 3
        guard let reference = rhythmOnsets.first?.time else { return 4 }
        var tripleHits = 0
        var quadHits = 0
        for onset in rhythmOnsets.suffix(16) {
            let phase = (onset.time - reference).truncatingRemainder(dividingBy: barPeriod * 4 / 3)
            let triplePhase = phase.truncatingRemainder(dividingBy: barPeriod)
            let quadPhase = phase.truncatingRemainder(dividingBy: beatPeriod * 4)
            if min(triplePhase, barPeriod - triplePhase) < beatPeriod * 0.18 { tripleHits += 1 }
            if min(quadPhase, beatPeriod * 4 - quadPhase) < beatPeriod * 0.18 { quadHits += 1 }
        }
        return tripleHits > quadHits + 2 ? 3 : 4
    }

    private func appendRhythmOnset(at time: TimeInterval, strength: Double, isChordChange: Bool) {
        if let lastRhythmOnset, time - lastRhythmOnset < minRhythmGap, !isChordChange { return }
        lastRhythmOnset = time
        rhythmOnsets.append(RhythmOnsetEvent(time: time, strength: strength, isChordChange: isChordChange))
        if rhythmOnsets.count > maxRhythmOnsets {
            rhythmOnsets.removeFirst(rhythmOnsets.count - maxRhythmOnsets)
        }
    }

    private func scheduleSilenceDecay() {
        silenceTask?.cancel()
        silenceTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled, let self else { return }
            self.isTracking = false
            self.tempoConfidence = max(0, self.tempoConfidence - 0.3)
            self.styleConfidence = max(0, self.styleConfidence - 0.25)
        }
    }

    // MARK: - Tempo

    private func recalculateTempo(at time: TimeInterval) {
        let onsetEstimate = tempoFromOnsets(weightChordChangesHigher: true)
        let chordEstimate = tempoFromChordChanges(referenceTime: time)

        let estimates = [onsetEstimate, chordEstimate].compactMap { $0 }
        guard let best = estimates.max(by: { $0.confidence < $1.confidence }) else { return }
        var bpm = best.bpm
        var confidence = best.confidence

        if estimates.count == 2 {
            if abs(estimates[0].bpm - estimates[1].bpm) < 8 {
                bpm = (estimates[0].bpm + estimates[1].bpm) / 2
                confidence = min(1.0, (estimates[0].confidence + estimates[1].confidence) / 2 + 0.12)
            }
        }

        syncopationIndex = estimateSyncopation(assumedBeatPeriod: 60.0 / bpm)

        if let previous = estimatedBPM {
            let blend = min(0.4, 0.1 + confidence * 0.22)
            estimatedBPM = previous * (1 - blend) + bpm * blend
        } else {
            estimatedBPM = bpm
        }
        tempoConfidence = max(tempoConfidence * 0.88, confidence)
    }

    private struct TempoEstimate {
        let bpm: Double
        let confidence: Double
    }

    private func tempoFromOnsets(weightChordChangesHigher: Bool) -> TempoEstimate? {
        // Chord changes track slow ballads better than individual key presses.
        let chordChangeTimes = rhythmOnsets.filter(\.isChordChange).map(\.time)
        if chordChangeTimes.count >= 3 {
            if let chordEstimate = bpmFromOnsetTimes(
                chordChangeTimes,
                sampleFactor: Double(chordChangeTimes.count) / 6.0,
                minGap: 0.45,
                maxGap: 4.0
            ) {
                return TempoEstimate(
                    bpm: chordEstimate.bpm,
                    confidence: min(1.0, chordEstimate.confidence * 1.15)
                )
            }
        }

        guard rhythmOnsets.count >= 4 else { return nil }

        var weightedIntervals: [Double] = []
        for index in 1..<rhythmOnsets.count {
            let gap = rhythmOnsets[index].time - rhythmOnsets[index - 1].time
            guard gap >= 0.22, gap <= 2.4 else { continue }
            var weight = rhythmOnsets[index].strength
            if weightChordChangesHigher, rhythmOnsets[index].isChordChange {
                weight *= 2.2
            } else if !rhythmOnsets[index].isChordChange {
                weight *= 0.55
            }
            for _ in 0..<max(1, Int(weight * 2)) {
                weightedIntervals.append(gap)
            }
        }
        return bpmFromIntervals(weightedIntervals, sampleFactor: Double(rhythmOnsets.count) / 20.0)
    }

    private func bpmFromOnsetTimes(
        _ times: [TimeInterval],
        sampleFactor: Double,
        minGap: TimeInterval,
        maxGap: TimeInterval
    ) -> TempoEstimate? {
        var intervals: [Double] = []
        for index in 1..<times.count {
            let gap = times[index] - times[index - 1]
            if gap >= minGap, gap <= maxGap {
                intervals.append(gap)
            }
        }
        return bpmFromIntervals(intervals, sampleFactor: sampleFactor)
    }

    private func tempoFromChordChanges(referenceTime: TimeInterval) -> TempoEstimate? {
        guard chordEvents.count >= 3 else { return nil }

        var intervals: [Double] = []
        for index in 1..<chordEvents.count {
            let gap = chordEvents[index].time - chordEvents[index - 1].time
            if gap >= 0.35, gap <= 3.2 {
                intervals.append(gap)
            }
        }
        guard intervals.count >= 2 else { return nil }

        let sorted = intervals.sorted()
        let median = sorted[sorted.count / 2]

        var candidates: [Double] = []
        for harmonicRhythm in [1.0, 2.0, 4.0] {
            let beatPeriod = median / harmonicRhythm
            if beatPeriod >= 0.28, beatPeriod <= 1.25 {
                candidates.append(60.0 / beatPeriod)
            }
        }
        guard !candidates.isEmpty else { return nil }
        let scored = candidates.map { bpm -> (bpm: Double, score: Double) in
            let normalized = normalizeBPM(bpm)
            let period = 60.0 / normalized
            let fit = intervalConsistencyScore([median], beatPeriod: period)
            return (normalized, fit)
        }
        guard let best = scored.max(by: { lhs, rhs in
            if abs(lhs.score - rhs.score) > 0.05 { return lhs.score < rhs.score }
            return lhs.bpm > rhs.bpm
        }) else { return nil }
        let bpm = best.bpm
        guard let firstInterval = sorted.first, let lastInterval = sorted.last else { return nil }
        let consistency = 1.0 - min(1.0, (lastInterval - firstInterval) / max(median, 0.01))
        let confidence = min(1.0, Double(chordEvents.count) / 10.0) * consistency * 0.92
        return TempoEstimate(bpm: bpm, confidence: confidence)
    }

    private func bpmFromIntervals(_ intervals: [Double], sampleFactor: Double) -> TempoEstimate? {
        guard intervals.count >= 3 else { return nil }

        let sorted = intervals.sorted()
        let median = sorted[sorted.count / 2]

        var candidates: [(bpm: Double, score: Double)] = []
        for multiplier in [0.5, 1.0, 2.0, 4.0] {
            let beatPeriod = median * multiplier
            guard beatPeriod >= 0.32, beatPeriod <= 2.0 else { continue }
            let bpm = normalizeBPM(60.0 / beatPeriod)
            let period = 60.0 / bpm
            let score = intervalConsistencyScore(intervals, beatPeriod: period)
            candidates.append((bpm, score))
        }
        guard !candidates.isEmpty else { return nil }

        guard let best = candidates.max(by: { lhs, rhs in
            if abs(lhs.score - rhs.score) > 0.07 { return lhs.score < rhs.score }
            return lhs.bpm > rhs.bpm
        }) else { return nil }

        let spread = sorted[sorted.count - 1] - sorted[0]
        let consistency = 1.0 - min(1.0, spread / max(median, 0.01))
        let confidence = min(1.0, sampleFactor) * consistency * best.score
        return TempoEstimate(bpm: best.bpm, confidence: confidence)
    }

    /// How well gaps align to whole/half/quarter multiples of a beat period.
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

    private func normalizeBPM(_ bpm: Double) -> Double {
        var value = bpm
        while value < minBPM { value *= 2 }
        while value > maxBPM { value /= 2 }
        return value
    }

    private func estimateSyncopation(assumedBeatPeriod: TimeInterval) -> Double {
        guard rhythmOnsets.count >= 6, assumedBeatPeriod > 0, let reference = rhythmOnsets.first?.time else { return 0 }
        var offBeatHits = 0
        var scoredHits = 0

        for onset in rhythmOnsets.suffix(18) {
            let phase = (onset.time - reference).truncatingRemainder(dividingBy: assumedBeatPeriod * 4)
            let beatPhase = (phase / assumedBeatPeriod).truncatingRemainder(dividingBy: 1.0)
            let distanceToDownbeat = min(beatPhase, 1.0 - beatPhase)
            let distanceToOffbeat = abs(beatPhase - 0.5)
            if distanceToOffbeat < distanceToDownbeat {
                offBeatHits += onset.isChordChange ? 2 : 1
            }
            scoredHits += onset.isChordChange ? 2 : 1
        }
        guard scoredHits > 0 else { return 0 }
        return Double(offBeatHits) / Double(scoredHits)
    }

    // MARK: - Style

    private func recalculateStyle(at time: TimeInterval) {
        let windowStart = time - 45
        let recentChords = chordEvents.filter { $0.time >= windowStart }

        if recentChords.isEmpty {
            detectedStyle = .unknown
            styleConfidence = 0
            suggestedStyle = nil
            return
        }

        let bpm = estimatedBPM ?? 80
        let onsetSpan = rhythmOnsets.filter { $0.time >= windowStart }
        let rhythmicChangesPerMinute: Double = {
            guard onsetSpan.count >= 2,
                  let first = onsetSpan.first?.time,
                  let last = onsetSpan.last?.time else { return 0 }
            let span = max(0.35, last - first)
            return Double(onsetSpan.count - 1) / span * 60.0
        }()

        if recentChords.count >= 2 {
            let complexities = recentChords.map { Double($0.analysis.complexity) }
            averageChordComplexity = complexities.reduce(0, +) / Double(complexities.count)

            if let firstChord = recentChords.first, let lastChord = recentChords.last {
                let changeSpan = max(0.5, lastChord.time - firstChord.time)
                chordChangesPerMinute = Double(recentChords.count - 1) / changeSpan * 60.0
            }
        } else if let onlyChord = recentChords.first {
            averageChordComplexity = Double(onlyChord.analysis.complexity)
            chordChangesPerMinute = rhythmicChangesPerMinute
        }

        let changeRate = max(chordChangesPerMinute, rhythmicChangesPerMinute)
        var scores = scoreStyles(
            bpm: bpm,
            chords: recentChords,
            syncopation: syncopationIndex,
            changeRate: changeRate,
            avgComplexity: averageChordComplexity
        )

        let latin = LatinRhythmPatternEngine.analyzeMIDI(onsets: rhythmOnsets, bpm: bpm)
        latinRhythmAnalysis = latin
        detectedClave = latin.clave
        montunoStrength = latin.montunoOstinatoStrength
        scores = mergeLatinPatternScores(scores, latin: latin)
        lastStyleScores = scores

        guard let best = scores.max(by: { $0.value < $1.value }), best.value > 0.10 else {
            if recentChords.count == 1, rhythmOnsets.count >= 4, let tempoStyle = bestTempoLedStyle(bpm: bpm, syncopation: syncopationIndex) {
                detectedStyle = tempoStyle
                styleConfidence = max(styleConfidence * 0.8, 0.28)
                suggestedStyle = tempoStyle
            } else {
                detectedStyle = .unknown
                styleConfidence = max(0, styleConfidence - 0.08)
                suggestedStyle = nil
            }
            return
        }

        let secondBest = scores.filter { $0.key != best.key }.max(by: { $0.value < $1.value })?.value ?? 0
        let margin = best.value - secondBest
        let confidence = min(1.0, best.value * 0.65 + margin * 0.85)

        if confidence > styleConfidence * 0.65 || styleConfidence < 0.22 {
            detectedStyle = best.key
            styleConfidence = max(styleConfidence * 0.85, confidence)
            suggestedStyle = best.key
        }
    }

    /// When harmony data is thin, infer a coarse genre from tempo + feel alone.
    private func bestTempoLedStyle(bpm: Double, syncopation: Double) -> LiveMusicStyle? {
        if bpm >= 118, syncopation < 0.35 { return .merengue }
        if bpm >= 108, syncopation < 0.4 { return .popRock }
        if bpm >= 100, syncopation >= 0.45 { return .montuno }
        if bpm >= 100, syncopation >= 0.38 { return .salsa }
        if bpm >= 92, syncopation >= 0.4 { return .funkGroove }
        if bpm >= 88, syncopation < 0.35 { return .gospelGroove }
        if bpm >= 72, syncopation < 0.3 { return .worshipBallad }
        if bpm < 72 { return .softPulse }
        return .popRock
    }

    private func scoreStyles(
        bpm: Double,
        chords: [ChordPerformanceEvent],
        syncopation: Double,
        changeRate: Double,
        avgComplexity: Double
    ) -> [LiveMusicStyle: Double] {
        let qualities = chords.map(\.analysis.quality)
        let minor7Ratio = ratio(qualities, equals: .minor7)
        let dom7Ratio = ratio(qualities, equals: .dominant)
        let maj7Ratio = ratio(qualities, equals: .major7)
        let susRatio = ratio(qualities, equals: .suspended)
        let extendedRatio = ratio(qualities, equals: .extended)
        let triadRatio = ratio(qualities, equals: .major) + ratio(qualities, equals: .minor)
        let powerRatio = ratio(qualities, equals: .power)

        func tempoScore(_ target: ClosedRange<Double>, peak: Double) -> Double {
            guard target.contains(bpm) else {
                let distance = min(abs(bpm - target.lowerBound), abs(bpm - target.upperBound))
                return max(0, 1.0 - distance / 35.0)
            }
            return 1.0 - abs(bpm - peak) / max(1, (target.upperBound - target.lowerBound) / 2)
        }

        var scores: [LiveMusicStyle: Double] = [:]

        // Worship & ballad
        scores[.worshipBallad] = tempoScore(58...92, peak: 74) * 0.38
            + (maj7Ratio + extendedRatio) * 0.26
            + (1.0 - min(1.0, changeRate / 10.0)) * 0.2
            + (1.0 - syncopation) * 0.16

        scores[.softPulse] = tempoScore(48...78, peak: 64) * 0.42
            + (1.0 - min(1.0, changeRate / 8.0)) * 0.28
            + (1.0 - syncopation) * 0.2
            + (1.0 - min(1.0, avgComplexity / 2.5)) * 0.1

        scores[.gospelGroove] = tempoScore(68...128, peak: 96) * 0.3
            + (susRatio + dom7Ratio) * 0.32
            + min(1.0, changeRate / 14.0) * 0.18
            + syncopation * 0.12

        scores[.brushWaltz] = tempoScore(54...108, peak: 84) * 0.22
            + (1.0 - syncopation) * 0.2
            + maj7Ratio * 0.18
            + (avgComplexity <= 2.2 ? 0.25 : 0.05)

        // Pop, rock & dance
        scores[.popRock] = tempoScore(88...138, peak: 112) * 0.34
            + triadRatio * 0.28
            + (1.0 - syncopation) * 0.18
            + (1.0 - min(1.0, avgComplexity / 2.8)) * 0.14

        scores[.rockDrive] = tempoScore(108...168, peak: 132) * 0.36
            + powerRatio * 0.28
            + triadRatio * 0.18
            + min(1.0, changeRate / 16.0) * 0.12

        scores[.funkGroove] = tempoScore(92...128, peak: 108) * 0.28
            + syncopation * 0.34
            + min(1.0, changeRate / 12.0) * 0.18
            + (dom7Ratio + minor7Ratio) * 0.14

        scores[.rbSoul] = tempoScore(72...108, peak: 88) * 0.32
            + (extendedRatio + minor7Ratio + maj7Ratio) * 0.3
            + syncopation * 0.16
            + (1.0 - min(1.0, changeRate / 14.0)) * 0.12

        scores[.edmPulse] = tempoScore(118...148, peak: 128) * 0.38
            + (1.0 - syncopation) * 0.24
            + triadRatio * 0.16
            + min(1.0, changeRate / 20.0) * 0.12

        // Jazz & blues
        scores[.jazzSwing] = tempoScore(100...200, peak: 140) * 0.24
            + min(1.0, avgComplexity / 3.5) * 0.32
            + (extendedRatio + minor7Ratio + maj7Ratio) * 0.26
            + syncopation * 0.12

        scores[.bluesShuffle] = tempoScore(72...118, peak: 92) * 0.3
            + dom7Ratio * 0.36
            + syncopation * 0.14
            + (1.0 - min(1.0, avgComplexity / 3.0)) * 0.12

        // Latin & Caribbean
        scores[.merengue] = tempoScore(118...178, peak: 140) * 0.42
            + min(1.0, changeRate / 18.0) * 0.22
            + triadRatio * 0.2
            + (1.0 - syncopation) * 0.16

        scores[.montuno] = tempoScore(92...138, peak: 108) * 0.22
            + syncopation * 0.38
            + (minor7Ratio + dom7Ratio) * 0.22
            + min(1.0, changeRate / 14.0) * 0.18

        scores[.salsa] = tempoScore(88...148, peak: 112) * 0.28
            + (minor7Ratio + dom7Ratio) * 0.24
            + syncopation * 0.22
            + min(1.0, avgComplexity / 3.0) * 0.12

        scores[.songo] = tempoScore(82...138, peak: 102) * 0.24
            + syncopation * 0.28
            + (extendedRatio + minor7Ratio) * 0.2
            + min(1.0, avgComplexity / 3.5) * 0.16

        scores[.bossaNova] = tempoScore(100...148, peak: 124) * 0.3
            + (maj7Ratio + minor7Ratio) * 0.32
            + syncopation * 0.22
            + (1.0 - min(1.0, changeRate / 12.0)) * 0.1

        scores[.bolero] = tempoScore(56...88, peak: 72) * 0.36
            + (maj7Ratio + extendedRatio) * 0.24
            + (1.0 - syncopation) * 0.22
            + (1.0 - min(1.0, changeRate / 8.0)) * 0.12

        // World & folk
        scores[.reggaeOneDrop] = tempoScore(68...98, peak: 82) * 0.34
            + syncopation * 0.26
            + (1.0 - min(1.0, changeRate / 10.0)) * 0.2
            + minor7Ratio * 0.14

        scores[.countryTrain] = tempoScore(88...148, peak: 116) * 0.32
            + triadRatio * 0.28
            + (1.0 - syncopation) * 0.2
            + (1.0 - min(1.0, avgComplexity / 2.5)) * 0.12

        return scores
    }

    private func mergeLatinPatternScores(
        _ scores: [LiveMusicStyle: Double],
        latin: LatinRhythmAnalysis
    ) -> [LiveMusicStyle: Double] {
        guard latin.confidence >= 0.22 || latin.montunoOstinatoStrength >= 0.38 else { return scores }
        var merged = scores
        let weight = max(latin.confidence, latin.montunoOstinatoStrength * 0.85)

        for (style, patternScore) in latin.styleScores where patternScore > 0.15 {
            let prior = merged[style] ?? 0
            merged[style] = prior * (1.0 - weight * 0.52) + patternScore * weight * 0.68
        }

        if latin.montunoOstinatoStrength >= 0.45 {
            merged[.montuno] = max(merged[.montuno] ?? 0, latin.montunoOstinatoStrength * 0.88)
            merged[.salsa] = (merged[.salsa] ?? 0) + latin.montunoOstinatoStrength * 0.18
        }

        if let best = latin.bestStyle, latin.confidence >= 0.32 {
            merged[best] = max(merged[best] ?? 0, latin.confidence * 0.75)
        }

        return merged
    }

    private func ratio(_ qualities: [ChordQualityHint], equals quality: ChordQualityHint) -> Double {
        guard !qualities.isEmpty else { return 0 }
        let count = qualities.filter { $0 == quality }.count
        return Double(count) / Double(qualities.count)
    }
}
