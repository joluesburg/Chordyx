//
//  AudioFeatureExtractor.swift
//  Chordyx
//
//  Spectral analysis for live audio AI (onsets, mel bands, timbre).
//

#if os(macOS) || os(iOS)
import Accelerate
import AVFoundation
import Foundation

struct AudioFeatureSnapshot: Sendable {
    let time: TimeInterval
    let spectralFlux: Float
    let rms: Float
    let zeroCrossingRate: Float
    let spectralCentroid: Float
    let spectralRolloff: Float
    let melBands: [Float]
    let lowMidHighRatio: (low: Float, mid: Float, high: Float)
    /// 12-bin pitch-class chroma (0…1 peak-normalized) for live key MIR.
    let chroma: [Float]
}

/// Runs on audio capture queues — explicitly not MainActor-isolated.
nonisolated final class AudioFeatureExtractor: @unchecked Sendable {
    private let frameSize: Int
    private let hopSize: Int
    private let melBandCount: Int
    private let log2n: vDSP_Length
    private let fftSetup: FFTSetup?
    private var window: [Float]
    private var realp: [Float]
    private var imagp: [Float]
    private var previousMagnitudes: [Float]

    init(frameSize: Int = 2048, hopSize: Int = 512, melBandCount: Int = 8) {
        self.frameSize = frameSize
        self.hopSize = hopSize
        self.melBandCount = melBandCount
        self.log2n = vDSP_Length(log2(Float(frameSize)))
        self.fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))
        self.window = [Float](repeating: 0, count: frameSize)
        vDSP_hann_window(&window, vDSP_Length(frameSize), Int32(vDSP_HANN_NORM))
        let half = frameSize / 2
        self.realp = [Float](repeating: 0, count: half)
        self.imagp = [Float](repeating: 0, count: half)
        self.previousMagnitudes = [Float](repeating: 0, count: half)
    }

    deinit {
        if let fftSetup {
            vDSP_destroy_fftsetup(fftSetup)
        }
    }

    func analyze(buffer: AVAudioPCMBuffer, at time: TimeInterval) -> [AudioFeatureSnapshot] {
        guard fftSetup != nil else { return [] }
        guard let channelData = buffer.floatChannelData?[0] else { return [] }
        let frameCount = Int(buffer.frameLength)
        guard frameCount >= hopSize else { return [] }

        var snapshots: [AudioFeatureSnapshot] = []
        var offset = 0
        let sampleRate = buffer.format.sampleRate
        while offset + frameSize <= frameCount {
            var frame = [Float](repeating: 0, count: frameSize)
            frame.withUnsafeMutableBufferPointer { dst in
                guard let base = dst.baseAddress else { return }
                base.update(from: channelData + offset, count: frameSize)
            }
            if let snapshot = analyzeFrame(
                frame,
                at: time + Double(offset) / sampleRate,
                sampleRate: sampleRate
            ) {
                snapshots.append(snapshot)
            }
            offset += hopSize
        }
        return snapshots
    }

    private func analyzeFrame(
        _ frame: [Float],
        at time: TimeInterval,
        sampleRate: Double
    ) -> AudioFeatureSnapshot? {
        guard frame.count == frameSize, let fftSetup else { return nil }

        var windowed = [Float](repeating: 0, count: frameSize)
        vDSP_vmul(frame, 1, window, 1, &windowed, 1, vDSP_Length(frameSize))

        var rms: Float = 0
        vDSP_rmsqv(windowed, 1, &rms, vDSP_Length(frameSize))

        let half = frameSize / 2
        var packed = [Float](repeating: 0, count: frameSize)
        packed.replaceSubrange(0..<half, with: windowed[0..<half])
        packed.replaceSubrange(half..<frameSize, with: windowed[half..<frameSize])

        realp = Array(packed.prefix(half))
        imagp = Array(packed.suffix(half))

        realp.withUnsafeMutableBufferPointer { realPtr in
            imagp.withUnsafeMutableBufferPointer { imagPtr in
                guard let realBase = realPtr.baseAddress, let imagBase = imagPtr.baseAddress else { return }
                var split = DSPSplitComplex(realp: realBase, imagp: imagBase)
                vDSP_fft_zrip(fftSetup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
            }
        }

        var magnitudes = [Float](repeating: 0, count: half)
        realp.withUnsafeMutableBufferPointer { realPtr in
            imagp.withUnsafeMutableBufferPointer { imagPtr in
                guard let realBase = realPtr.baseAddress, let imagBase = imagPtr.baseAddress else { return }
                var split = DSPSplitComplex(realp: realBase, imagp: imagBase)
                vDSP_zvabs(&split, 1, &magnitudes, 1, vDSP_Length(half))
            }
        }

        var flux: Float = 0
        for index in 0..<half {
            let delta = magnitudes[index] - previousMagnitudes[index]
            if delta > 0 { flux += delta }
        }
        previousMagnitudes = magnitudes

        let zcr = zeroCrossingRate(windowed)
        let centroid = spectralCentroid(magnitudes)
        let rolloff = spectralRolloff(magnitudes)
        let melBands = melBandEnergies(magnitudes)
        let bands = lowMidHighRatio(magnitudes)
        let chroma = AudioChromaKeyEstimator.chromaFromMagnitudes(
            magnitudes,
            sampleRate: sampleRate,
            frameSize: frameSize
        )

        return AudioFeatureSnapshot(
            time: time,
            spectralFlux: flux,
            rms: rms,
            zeroCrossingRate: zcr,
            spectralCentroid: centroid,
            spectralRolloff: rolloff,
            melBands: melBands,
            lowMidHighRatio: bands,
            chroma: chroma
        )
    }

    private func zeroCrossingRate(_ frame: [Float]) -> Float {
        guard frame.count > 1 else { return 0 }
        var crossings = 0
        for index in 1..<frame.count {
            if (frame[index - 1] >= 0) != (frame[index] >= 0) { crossings += 1 }
        }
        return Float(crossings) / Float(frame.count - 1)
    }

    private func spectralCentroid(_ magnitudes: [Float]) -> Float {
        var weighted: Float = 0
        var total: Float = 0
        for (index, value) in magnitudes.enumerated() {
            weighted += Float(index) * value
            total += value
        }
        guard total > 0 else { return 0 }
        return weighted / total / Float(magnitudes.count)
    }

    private func spectralRolloff(_ magnitudes: [Float], percentile: Float = 0.85) -> Float {
        let total = magnitudes.reduce(0, +)
        guard total > 0 else { return 0 }
        let target = total * percentile
        var cumulative: Float = 0
        for (index, value) in magnitudes.enumerated() {
            cumulative += value
            if cumulative >= target {
                return Float(index) / Float(magnitudes.count)
            }
        }
        return 1
    }

    private func melBandEnergies(_ magnitudes: [Float]) -> [Float] {
        let binCount = magnitudes.count
        var bands = [Float](repeating: 0, count: melBandCount)
        for band in 0..<melBandCount {
            let start = Int(pow(2.0, Double(band) / Double(melBandCount)) * Double(binCount) * 0.02)
            let end = Int(pow(2.0, Double(band + 1) / Double(melBandCount)) * Double(binCount) * 0.45)
            let clampedStart = min(max(0, start), binCount - 1)
            let clampedEnd = min(max(clampedStart + 1, end), binCount)
            var energy: Float = 0
            for index in clampedStart..<clampedEnd {
                energy += magnitudes[index]
            }
            bands[band] = energy / Float(max(1, clampedEnd - clampedStart))
        }
        let maxBand = bands.max() ?? 1
        return bands.map { $0 / max(maxBand, 0.0001) }
    }

    private func lowMidHighRatio(_ magnitudes: [Float]) -> (low: Float, mid: Float, high: Float) {
        let count = magnitudes.count
        let lowEnd = count / 8
        let midEnd = count / 2
        let low = magnitudes[0..<lowEnd].reduce(0, +)
        let mid = magnitudes[lowEnd..<midEnd].reduce(0, +)
        let high = magnitudes[midEnd..<count].reduce(0, +)
        let total = max(low + mid + high, 0.0001)
        return (low / total, mid / total, high / total)
    }
}
#endif
