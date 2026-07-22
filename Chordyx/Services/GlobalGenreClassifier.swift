//
//  GlobalGenreClassifier.swift
//  Chordyx
//
//  Hierarchical worldwide genre identification from live performance features.
//

import Foundation

enum GlobalGenreClassifier {
    private static let minimumConfidence = 0.22
    private static let alternativeCount = 4

    static func classify(_ snapshot: GlobalGenrePerformanceSnapshot) -> GlobalGenreAnalysis {
        guard snapshot.bpm > 0 else { return .empty }

        var genreScores: [String: Double] = [:]
        for genre in GlobalMusicGenreCatalog.all {
            genreScores[genre.id] = score(genre, snapshot: snapshot)
        }

        let ranked = genreScores
            .sorted { $0.value > $1.value }
            .prefix(alternativeCount + 1)

        guard let top = ranked.first, top.value >= minimumConfidence,
              let primary = GlobalMusicGenreCatalog.genre(id: top.key) else {
            return fallbackFromLiveStyle(snapshot)
        }

        let secondScore = ranked.dropFirst().first?.value ?? 0
        let margin = top.value - secondScore
        let confidence = min(1.0, top.value * 0.62 + margin * 0.78)

        let regionScores = regionScores(from: genreScores)
        let bestRegion = regionScores.max(by: { $0.value < $1.value })

        let alternatives = ranked.dropFirst().compactMap { entry -> GlobalGenreCandidate? in
            guard let genre = GlobalMusicGenreCatalog.genre(id: entry.key) else { return nil }
            return GlobalGenreCandidate(genre: genre, score: entry.value)
        }

        return GlobalGenreAnalysis(
            primary: primary,
            confidence: confidence,
            region: bestRegion?.key,
            regionConfidence: bestRegion?.value ?? 0,
            alternatives: Array(alternatives),
            matchedPatternLabel: snapshot.latinAnalysis.matchedPatternLabel
        )
    }

    private static func fallbackFromLiveStyle(_ snapshot: GlobalGenrePerformanceSnapshot) -> GlobalGenreAnalysis {
        guard let bestLive = snapshot.liveStyleScores.max(by: { $0.value < $1.value }),
              bestLive.value > 0.15 else {
            return .empty
        }

        let matches = GlobalMusicGenreCatalog.all.filter { $0.closestGroove == bestLive.key }
        guard let primary = matches.first else { return .empty }

        return GlobalGenreAnalysis(
            primary: primary,
            confidence: bestLive.value * 0.55,
            region: primary.region,
            regionConfidence: 0.35,
            alternatives: matches.dropFirst().prefix(3).map {
                GlobalGenreCandidate(genre: $0, score: bestLive.value * 0.4)
            },
            matchedPatternLabel: snapshot.latinAnalysis.matchedPatternLabel
        )
    }

    private static func regionScores(from genreScores: [String: Double]) -> [GlobalMusicRegion: Double] {
        var totals: [GlobalMusicRegion: (sum: Double, count: Int)] = [:]
        for genre in GlobalMusicGenreCatalog.all {
            guard let score = genreScores[genre.id], score > 0.12 else { continue }
            var bucket = totals[genre.region, default: (0, 0)]
            bucket.sum += score
            bucket.count += 1
            totals[genre.region] = bucket
        }
        return totals.mapValues { $0.sum / Double(max(1, $0.count)) }
    }

    private static func score(_ genre: GlobalMusicGenre, snapshot: GlobalGenrePerformanceSnapshot) -> Double {
        let fp = genre.fingerprint

        let tempo = rangeScore(snapshot.bpm, in: fp.tempoRange, peak: fp.tempoPeak, tolerance: 38)
        let sync = rangeScore(snapshot.syncopation, in: fp.syncopationRange, peak: fp.syncopationPeak, tolerance: 0.35)
        let change = rangeScore(snapshot.chordChangeRate, in: fp.changeRateRange, peak: midpoint(fp.changeRateRange), tolerance: 14)
        let complexity = rangeScore(snapshot.avgHarmonicComplexity, in: fp.complexityRange, peak: midpoint(fp.complexityRange), tolerance: 2.2)

        let harmonic = fp.minor7Weight * snapshot.minor7Ratio
            + fp.dom7Weight * snapshot.dom7Ratio
            + fp.maj7Weight * snapshot.maj7Ratio
            + fp.triadWeight * snapshot.triadRatio
            + fp.extendedWeight * snapshot.extendedRatio
            + fp.powerWeight * snapshot.powerRatio
            + fp.waltzWeight * snapshot.waltzLikelihood

        let groovePrior = snapshot.liveStyleScores[fp.anchorGroove, default: 0]
        let audioPrior = snapshot.audioStyleProbabilities[fp.anchorGroove, default: 0]

        var latinBoost = 0.0
        if !fp.latinPatternTags.isEmpty, snapshot.latinAnalysis.confidence >= 0.22 {
            let label = (snapshot.latinAnalysis.matchedPatternLabel ?? "").lowercased()
            for tag in fp.latinPatternTags where label.contains(tag) || genre.id.contains(tag) {
                latinBoost = max(latinBoost, snapshot.latinAnalysis.confidence * 0.45)
            }
            if let best = snapshot.latinAnalysis.bestStyle, best == fp.anchorGroove {
                latinBoost = max(latinBoost, snapshot.latinAnalysis.confidence * 0.38)
            }
        }

        if genre.id == "montuno", snapshot.latinAnalysis.montunoOstinatoStrength >= 0.38 {
            latinBoost = max(latinBoost, snapshot.latinAnalysis.montunoOstinatoStrength * 0.55)
        }

        let spectral = brightnessAffinity(genre: genre, snapshot: snapshot)

        return tempo * 0.24
            + sync * 0.18
            + change * 0.08
            + complexity * 0.06
            + harmonic * 0.16
            + groovePrior * 0.18
            + audioPrior * 0.12
            + latinBoost * 0.22
            + spectral * 0.06
    }

    private static func brightnessAffinity(genre: GlobalMusicGenre, snapshot: GlobalGenrePerformanceSnapshot) -> Double {
        switch genre.region {
        case .popRockDance, .eastAsia:
            return snapshot.spectralBrightness * 0.6 + snapshot.onsetDensity * 0.04
        case .worshipGospel, .classicalArt:
            return (1.0 - snapshot.spectralBrightness) * 0.5 + snapshot.lowEnergyRatio * 0.3
        case .latinCaribbean, .africa:
            return snapshot.syncopation * 0.35 + snapshot.spectralBrightness * 0.25
        default:
            return 0.35
        }
    }

    private static func rangeScore(
        _ value: Double,
        in range: ClosedRange<Double>,
        peak: Double,
        tolerance: Double
    ) -> Double {
        if range.contains(value) {
            let halfWidth = max(0.001, (range.upperBound - range.lowerBound) / 2)
            return max(0.35, 1.0 - abs(value - peak) / halfWidth * 0.45)
        }
        let distance = min(abs(value - range.lowerBound), abs(value - range.upperBound))
        return max(0, 1.0 - distance / tolerance) * 0.55
    }

    private static func midpoint(_ range: ClosedRange<Double>) -> Double {
        (range.lowerBound + range.upperBound) / 2
    }
}
