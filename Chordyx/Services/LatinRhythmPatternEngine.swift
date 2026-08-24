//
//  LatinRhythmPatternEngine.swift
//  Chordyx
//
//  Deep Latin rhythm fingerprinting: montuno ostinato, clave orientation,
//  and 16th-grid template matching against known accompaniment patterns.
//

import Foundation

enum ClaveOrientation: String, Sendable, Codable {
    case unknown
    case twoThree
    case threeTwo

    var label: String {
        switch self {
        case .unknown: String(localized: "Clave listening…")
        case .twoThree: String(localized: "Clave 2-3")
        case .threeTwo: String(localized: "Clave 3-2")
        }
    }
}

struct LatinRhythmAnalysis: Sendable {
    var styleScores: [LiveMusicStyle: Double] = [:]
    var bestStyle: LiveMusicStyle?
    var confidence: Double = 0
    var clave: ClaveOrientation = .unknown
    var claveConfidence: Double = 0
    var montunoOstinatoStrength: Double = 0
    var eighthNoteRatio: Double = 0
    var matchedPatternLabel: String?

    static let empty = LatinRhythmAnalysis()
}

enum LatinRhythmPatternEngine {
    private static let gridSteps = 16

    /// Piano montuno block-chord grid (syncopated 8ths / 16ths).
    private static let pianoMontunoGrid: [Double] = [
        1.0, 0.15, 0.55, 0.85, 0.95, 0.2, 0.7, 0.9,
        1.0, 0.25, 0.65, 0.88, 0.92, 0.18, 0.72, 0.82
    ]

    /// Son clave hits on a 32-step (2-bar) grid.
    private static let claveThreeTwo: [Double] = {
        var g = [Double](repeating: 0, count: 32)
        for step in [0, 6, 12, 18, 24] { g[step] = 1.0 }
        return g
    }()

    private static let claveTwoThree: [Double] = {
        var g = [Double](repeating: 0, count: 32)
        for step in [0, 8, 14, 20, 28] { g[step] = 1.0 }
        return g
    }()

    static func analyzeMIDI(
        onsets: [RhythmOnsetEvent],
        bpm: Double
    ) -> LatinRhythmAnalysis {
        guard bpm > 0, onsets.count >= 6 else { return .empty }
        let beatPeriod = 60.0 / bpm
        let weighted = onsets.map { (time: $0.time, strength: $0.strength * ($0.isChordChange ? 1.15 : 1.0)) }
        return analyze(onsets: weighted, beatPeriod: beatPeriod, midiOnsets: onsets)
    }

    static func analyzeAudio(
        onsets: [(time: TimeInterval, strength: Double)],
        bpm: Double
    ) -> LatinRhythmAnalysis {
        guard bpm > 0, onsets.count >= 5 else { return .empty }
        let beatPeriod = 60.0 / bpm
        return analyze(onsets: onsets, beatPeriod: beatPeriod, midiOnsets: nil)
    }

    private static func analyze(
        onsets: [(time: TimeInterval, strength: Double)],
        beatPeriod: TimeInterval,
        midiOnsets: [RhythmOnsetEvent]?
    ) -> LatinRhythmAnalysis {
        guard let reference = onsets.first?.time else { return .empty }

        let grid = quantizeToGrid(onsets: onsets, beatPeriod: beatPeriod, referenceTime: reference)
        let templates = buildTemplateScores(grid: grid)

        var scores = templates.styleScores
        let montunoStrength = midiOnsets.map { montunoOstinatoStrength(onsets: $0, beatPeriod: beatPeriod) }
            ?? estimateMontunoFromDensity(onsets: onsets, beatPeriod: beatPeriod)

        if montunoStrength >= 0.42 {
            scores[.montuno] = max(scores[.montuno] ?? 0, montunoStrength * 0.92)
            scores[.salsa] = (scores[.salsa] ?? 0) + montunoStrength * 0.28
        }

        let eighthRatio = estimateEighthRatio(onsets: onsets, beatPeriod: beatPeriod)
        let inferredBPM = beatPeriod > 0 ? 60.0 / beatPeriod : 0
        if eighthRatio >= 0.55 {
            scores[.songo] = (scores[.songo] ?? 0) + eighthRatio * 0.28
            scores[.montuno] = (scores[.montuno] ?? 0) + eighthRatio * 0.12
        }
        if eighthRatio >= 0.62, inferredBPM >= 100, inferredBPM <= 140 {
            scores[.songo] = (scores[.songo] ?? 0) + 0.18
        }
        if eighthRatio <= 0.28 {
            scores[.merengue] = (scores[.merengue] ?? 0) + (1.0 - eighthRatio) * 0.22
        }

        let claveResult = detectClave(onsets: onsets, beatPeriod: beatPeriod, referenceTime: reference)
        if claveResult.confidence >= 0.38 {
            scores[.salsa] = (scores[.salsa] ?? 0) + claveResult.confidence * 0.2
            scores[.montuno] = (scores[.montuno] ?? 0) + claveResult.confidence * 0.15
            scores[.songo] = (scores[.songo] ?? 0) + claveResult.confidence * 0.12
        }

        guard let best = scores.max(by: { $0.value < $1.value }), best.value > 0.12 else {
            return LatinRhythmAnalysis(
                montunoOstinatoStrength: montunoStrength,
                eighthNoteRatio: eighthRatio
            )
        }

        let margin = best.value - (scores.filter { $0.key != best.key }.max(by: { $0.value < $1.value })?.value ?? 0)
        let confidence = min(1.0, best.value * 0.7 + margin * 0.55 + montunoStrength * 0.15)

        return LatinRhythmAnalysis(
            styleScores: scores,
            bestStyle: best.key,
            confidence: confidence,
            clave: claveResult.orientation,
            claveConfidence: claveResult.confidence,
            montunoOstinatoStrength: montunoStrength,
            eighthNoteRatio: eighthRatio,
            matchedPatternLabel: templates.bestLabel
        )
    }

    private static func buildTemplateScores(grid: [Double]) -> (styleScores: [LiveMusicStyle: Double], bestLabel: String?) {
        let patternMap: [(LiveMusicStyle, String)] = [
            (.merengue, "Merengue"),
            (.salsa, "Salsa / montuno bell"),
            (.songo, "Songó"),
            (.bossaNova, "Bossa nova"),
            (.funkGroove, "Funk"),
            (.gospelGroove, "Gospel"),
            (.bolero, "Bolero")
        ]

        var scores: [LiveMusicStyle: Double] = [:]
        var bestLabel: String?
        var bestScore = 0.0

        for (style, label) in patternMap {
            let template = drumGrid(for: style)
            let score = correlate(grid: grid, template: template)
            scores[style] = score
            if score > bestScore {
                bestScore = score
                bestLabel = label
            }
        }

        let montunoScore = correlate(grid: grid, template: pianoMontunoGrid)
        scores[.montuno] = max(scores[.montuno] ?? 0, montunoScore * 1.08)
        if montunoScore > bestScore {
            bestScore = montunoScore
            bestLabel = String(localized: "Piano montuno")
        }

        return (scores, bestLabel)
    }

    /// 16th-note density templates derived from former accompaniment grids (style-only).
    static func drumGrid(for style: LiveMusicStyle) -> [Double] {
        switch style {
        case .merengue:
            [0.8, 0.405, 0.55, 0.57, 0.74, 0.36, 0.55, 0.57, 0.8, 0.405, 0.55, 0.57, 0.74, 0.36, 0.55, 0.57]
        case .salsa:
            [0.838, 0.0, 0.51, 0.52, 0.35, 0.4, 0.835, 0.51, 0.85, 0.62, 0.567, 0.44, 0.7, 0.4, 0.51, 0.48]
        case .songo:
            [0.885, 0.0, 0.593, 0.68, 0.85, 0.637, 0.59, 0.44, 0.885, 0.0, 0.753, 0.477, 0.85, 0.6, 0.56, 0.465]
        case .bossaNova:
            [0.54, 0.3, 0.32, 0.62, 0.4, 0.36, 0.4, 0.535, 0.4, 0.3, 0.47, 0.45, 0.4, 0.36, 0.4, 0.0]
        case .funkGroove:
            [0.935, 0.29, 0.43, 0.6, 0.935, 0.6, 0.47, 0.353, 0.935, 0.29, 0.68, 0.35, 0.935, 0.51, 0.47, 0.353]
        case .gospelGroove:
            [0.915, 0.27, 0.42, 0.63, 0.915, 0.32, 0.42, 0.22, 0.915, 0.27, 0.64, 0.35, 0.915, 0.32, 0.42, 0.22]
        case .bolero:
            [0.74, 0.0, 0.33, 0.55, 0.58, 0.38, 0.55, 0.35, 0.78, 0.38, 0.48, 0.55, 0.58, 0.33, 0.55, 0.42]
        default:
            [Double](repeating: 0, count: gridSteps)
        }
    }

    private static func quantizeToGrid(
        onsets: [(time: TimeInterval, strength: Double)],
        beatPeriod: TimeInterval,
        referenceTime: TimeInterval
    ) -> [Double] {
        var grid = [Double](repeating: 0, count: gridSteps)
        let sixteenth = beatPeriod / 4.0
        guard sixteenth > 0 else { return grid }

        for onset in onsets {
            let elapsed = onset.time - referenceTime
            guard elapsed >= -0.05 else { continue }
            let absoluteStep = Int((max(0, elapsed) / sixteenth).rounded())
            let step = ((absoluteStep % gridSteps) + gridSteps) % gridSteps
            grid[step] += onset.strength
        }

        let peak = grid.max() ?? 0
        guard peak > 0 else { return grid }
        return grid.map { $0 / peak }
    }

    private static func correlate(grid: [Double], template: [Double]) -> Double {
        guard grid.count == template.count, !grid.isEmpty else { return 0 }
        var best = 0.0
        for phase in 0..<grid.count {
            var sum = 0.0
            var templateEnergy = 0.0
            for index in 0..<grid.count {
                let t = template[(index + phase) % grid.count]
                sum += grid[index] * t
                templateEnergy += t
            }
            let normalized = templateEnergy > 0 ? sum / (Double(grid.count) * templateEnergy * 0.35) : 0
            best = max(best, min(1.0, normalized))
        }
        return best
    }

    private static func montunoOstinatoStrength(onsets: [RhythmOnsetEvent], beatPeriod: TimeInterval) -> Double {
        let recent = Array(onsets.suffix(24))
        guard recent.count >= 8 else { return 0 }

        let noteOnsets = recent.filter { !$0.isChordChange }
        guard noteOnsets.count >= 5 else { return 0 }

        let eighthRatio = estimateEighthRatio(
            onsets: noteOnsets.map { ($0.time, $0.strength) },
            beatPeriod: beatPeriod
        )
        let densityScore = min(1.0, Double(noteOnsets.count) / 14.0)
        let chordChanges = recent.filter(\.isChordChange).count
        let harmonicSparsity = 1.0 - min(1.0, Double(chordChanges) / 5.0)

        return min(1.0, eighthRatio * 0.48 + densityScore * 0.32 + harmonicSparsity * 0.2)
    }

    private static func estimateMontunoFromDensity(
        onsets: [(time: TimeInterval, strength: Double)],
        beatPeriod: TimeInterval
    ) -> Double {
        guard onsets.count >= 6 else { return 0 }
        let eighthRatio = estimateEighthRatio(onsets: onsets, beatPeriod: beatPeriod)
        let span = max(0.5, (onsets.last?.time ?? 0) - (onsets.first?.time ?? 0))
        let density = Double(onsets.count) / span
        let densityScore = min(1.0, density / 8.0)
        return min(1.0, eighthRatio * 0.5 + densityScore * 0.35)
    }

    private static func estimateEighthRatio(
        onsets: [(time: TimeInterval, strength: Double)],
        beatPeriod: TimeInterval
    ) -> Double {
        guard onsets.count >= 3, beatPeriod > 0 else { return 0 }
        let eighth = beatPeriod / 2.0
        let sixteenth = beatPeriod / 4.0
        var hits = 0
        var total = 0
        for index in 1..<onsets.count {
            let gap = onsets[index].time - onsets[index - 1].time
            guard gap >= sixteenth * 0.6, gap <= beatPeriod * 1.1 else { continue }
            total += 1
            if gap >= eighth * 0.72, gap <= eighth * 1.28 { hits += 1 }
            else if gap >= sixteenth * 0.85, gap <= sixteenth * 1.2 { hits += 1 }
        }
        return total > 0 ? Double(hits) / Double(total) : 0
    }

    private static func detectClave(
        onsets: [(time: TimeInterval, strength: Double)],
        beatPeriod: TimeInterval,
        referenceTime: TimeInterval
    ) -> (orientation: ClaveOrientation, confidence: Double) {
        let sixteenth = beatPeriod / 4.0
        guard sixteenth > 0, onsets.count >= 6 else { return (.unknown, 0) }

        var grid32 = [Double](repeating: 0, count: 32)
        for onset in onsets {
            let elapsed = onset.time - referenceTime
            guard elapsed >= 0 else { continue }
            let step = Int((elapsed / sixteenth).rounded()) % 32
            grid32[step] += onset.strength
        }
        let peak = grid32.max() ?? 0
        if peak > 0 { grid32 = grid32.map { $0 / peak } }

        let score32 = correlate32(grid: grid32, template: claveThreeTwo)
        let score23 = correlate32(grid: grid32, template: claveTwoThree)
        let best = max(score32, score23)
        guard best >= 0.28 else { return (.unknown, best) }
        if score32 >= score23 + 0.06 { return (.threeTwo, score32) }
        if score23 >= score32 + 0.06 { return (.twoThree, score23) }
        return (.unknown, best * 0.7)
    }

    private static func correlate32(grid: [Double], template: [Double]) -> Double {
        guard grid.count == template.count else { return 0 }
        var best = 0.0
        for phase in 0..<grid.count {
            var sum = 0.0
            for index in 0..<grid.count {
                sum += grid[index] * template[(index + phase) % grid.count]
            }
            best = max(best, sum / Double(grid.count))
        }
        return min(1.0, best)
    }
}
