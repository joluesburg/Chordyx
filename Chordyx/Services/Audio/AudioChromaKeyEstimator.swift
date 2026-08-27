//
//  AudioChromaKeyEstimator.swift
//  Chordyx
//
//  Industry MIR chroma → key + scale/mode (HPCP-style fold + multi-profile correlation).
//  Dual-timescale accumulator for live modulation follow (Auto-Key class).
//

#if os(macOS) || os(iOS)
import Foundation

struct AudioKeyEstimate: Equatable, Sendable {
    let key: MusicalKey
    let scale: MusicalScaleQuality
    let confidence: Double
    let scores: [MusicalKey: Double]
    /// Accumulated 12-bin chroma (normalized).
    let chroma: [Double]
    let relativeKey: MusicalKey?
}

/// Accumulates live chroma frames and estimates tonal center + scale on-device.
nonisolated final class AudioChromaKeyEstimator: @unchecked Sendable {
    /// Long memory — stable key over ~8–12s of playing.
    private var chromaSlow = [Double](repeating: 0, count: 12)
    /// Short memory — flips within ~2–4s when the song modulates.
    private var chromaFast = [Double](repeating: 0, count: 12)
    private var frameCount = 0
    private let decaySlow = 0.972
    private let decayFast = 0.88
    private let silenceRMS: Float = 0.006

    func reset() {
        chromaSlow = [Double](repeating: 0, count: 12)
        chromaFast = [Double](repeating: 0, count: 12)
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
            chromaSlow[i] = chromaSlow[i] * decaySlow + Double(frameChroma[i]) * energy
            chromaFast[i] = chromaFast[i] * decayFast + Double(frameChroma[i]) * energy
        }
        frameCount += 1
    }

    func estimate() -> AudioKeyEstimate? {
        guard frameCount >= 5 else { return nil }

        let slow = TonalScaleIntelligence.detectFromChroma(chromaSlow)
        let fast = TonalScaleIntelligence.detectFromChroma(chromaFast)

        let chosen: DetectedTonalCenter?
        if let fast, let slow {
            if fast.confidence >= 0.16,
               (fast.key != slow.key || fast.scale != slow.scale),
               fast.confidence + 0.04 >= slow.confidence {
                chosen = fast
            } else if slow.confidence >= fast.confidence {
                chosen = slow
            } else {
                chosen = fast
            }
        } else {
            chosen = fast ?? slow
        }

        guard let chosen, chosen.confidence >= 0.10, chosen.scores[chosen.key] ?? 0 >= 0.42 else {
            return nil
        }

        return AudioKeyEstimate(
            key: chosen.key,
            scale: chosen.scale,
            confidence: chosen.confidence,
            scores: chosen.scores,
            chroma: chosen.scalePitchClasses.isEmpty ? chromaSlow : {
                let sum = chromaSlow.reduce(0, +)
                return sum > 0 ? chromaSlow.map { $0 / sum } : chromaSlow
            }(),
            relativeKey: chosen.relativeKey
        )
    }
}
#endif
