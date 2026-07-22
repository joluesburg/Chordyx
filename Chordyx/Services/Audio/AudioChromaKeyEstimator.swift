//
//  AudioChromaKeyEstimator.swift
//  Chordyx
//
//  Industry MIR chroma → key (HPCP-style fold + Krumhansl–Schmuckler).
//  Used to fuse live mic/line audio with the chord-symbol key ensemble.
//

#if os(macOS) || os(iOS)
import Foundation

struct AudioKeyEstimate: Equatable, Sendable {
    let key: MusicalKey
    let confidence: Double
    let scores: [MusicalKey: Double]
    /// Accumulated 12-bin chroma (normalized).
    let chroma: [Double]
}

/// Accumulates live chroma frames and estimates tonal center on-device.
nonisolated final class AudioChromaKeyEstimator: @unchecked Sendable {
    private static let krumhanslMajor: [Double] = [
        6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88
    ]
    private static let krumhanslMinor: [Double] = [
        6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17
    ]

    private var chroma = [Double](repeating: 0, count: 12)
    private var frameCount = 0
    private let decay = 0.965
    private let silenceRMS: Float = 0.007

    func reset() {
        chroma = [Double](repeating: 0, count: 12)
        frameCount = 0
    }

    /// Fold FFT magnitudes into a 12-bin chroma vector (A4 = 440 Hz).
    static func chromaFromMagnitudes(
        _ magnitudes: [Float],
        sampleRate: Double,
        frameSize: Int
    ) -> [Float] {
        var bins = [Float](repeating: 0, count: 12)
        guard sampleRate > 0, frameSize > 0, magnitudes.count > 1 else { return bins }

        let nyquist = sampleRate / 2
        for index in 1..<magnitudes.count {
            let freq = Double(index) * sampleRate / Double(frameSize)
            guard freq >= 55, freq <= min(5_000, nyquist) else { continue }
            let midi = 69.0 + 12.0 * log2(freq / 440.0)
            let pc = Int((midi).rounded()) % 12
            let wrapped = (pc + 12) % 12
            // Slight bass emphasis (tonal roots live lower).
            let bassWeight = Float(max(0.35, 1.15 - (freq - 55) / 2_200))
            bins[wrapped] += magnitudes[index] * bassWeight
        }
        let peak = bins.max() ?? 0
        if peak > 0 {
            for i in 0..<12 { bins[i] /= peak }
        }
        return bins
    }

    func ingest(frameChroma: [Float], rms: Float) {
        guard frameChroma.count == 12, rms >= silenceRMS else { return }
        let energy = Double(min(1, max(0, rms * 8)))
        for i in 0..<12 {
            chroma[i] = chroma[i] * decay + Double(frameChroma[i]) * energy
        }
        frameCount += 1
    }

    func estimate() -> AudioKeyEstimate? {
        guard frameCount >= 8 else { return nil }
        let sum = chroma.reduce(0, +)
        guard sum > 0.01 else { return nil }

        let observed = chroma.map { $0 / sum }

        var scores = [MusicalKey: Double]()
        // Local PC table avoids MainActor isolation on MusicalKey under default isolation.
        let tonics: [(MusicalKey, Int)] = [
            (.C, 0), (.Cs, 1), (.D, 2), (.Eb, 3), (.E, 4), (.F, 5),
            (.Fs, 6), (.G, 7), (.Ab, 8), (.A, 9), (.Bb, 10), (.B, 11)
        ]
        for (key, tonic) in tonics {
            var majorProfile = [Double](repeating: 0, count: 12)
            var minorProfile = [Double](repeating: 0, count: 12)
            for pc in 0..<12 {
                let rel = (pc - tonic + 12) % 12
                majorProfile[pc] = Self.krumhanslMajor[rel]
                minorProfile[pc] = Self.krumhanslMinor[rel]
            }
            let majorCorr = pearson(observed, majorProfile)
            let minorCorr = pearson(observed, minorProfile)
            // Prefer major when tied — Chordyx keys are tonal centers / major spellings.
            scores[key] = max(majorCorr, minorCorr * 0.98)
        }

        // Shift correlations into 0…1 for blending with chord ensemble.
        let minScore = scores.values.min() ?? 0
        let maxScore = scores.values.max() ?? 0
        guard maxScore > minScore else { return nil }
        for (key, _) in tonics {
            scores[key] = ((scores[key] ?? 0) - minScore) / (maxScore - minScore)
        }

        let ranked = scores.sorted { $0.value > $1.value }
        guard let best = ranked.first, ranked.count >= 2 else { return nil }
        let runnerUp = ranked[1].value
        let margin = best.value - runnerUp
        let confidence = min(1, max(0.08, margin))

        guard confidence >= 0.08, best.value >= 0.55 else { return nil }

        return AudioKeyEstimate(
            key: best.key,
            confidence: confidence,
            scores: scores,
            chroma: observed
        )
    }

    private func pearson(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        let n = Double(a.count)
        let meanA = a.reduce(0, +) / n
        let meanB = b.reduce(0, +) / n
        var num = 0.0
        var denA = 0.0
        var denB = 0.0
        for i in 0..<a.count {
            let da = a[i] - meanA
            let db = b[i] - meanB
            num += da * db
            denA += da * da
            denB += db * db
        }
        let den = sqrt(denA * denB)
        return den > 0 ? num / den : 0
    }
}
#endif
