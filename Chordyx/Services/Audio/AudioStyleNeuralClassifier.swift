//
//  AudioStyleNeuralClassifier.swift
//  Chordyx
//
//  Small neural network (32→24→N) for live style classification from audio features.
//  Weights are hand-tuned priors; replace with a trained Core ML model later.
//

#if os(macOS) || os(iOS)
import Foundation

struct AudioStylePrediction: Sendable {
    let style: LiveMusicStyle
    let confidence: Double
    let probabilities: [LiveMusicStyle: Double]
}

final class AudioStyleNeuralClassifier: Sendable {
    private let outputStyles: [LiveMusicStyle] = LiveMusicStyle.detectableStyles

    private let inputSize = 32
    private let hiddenSize = 24

    func predict(features: [Float]) -> AudioStylePrediction {
        guard features.count == inputSize else {
            return AudioStylePrediction(style: .unknown, confidence: 0, probabilities: [:])
        }

        let hidden = relu(matVecMul(Self.weightsHidden, features, rows: hiddenSize, cols: inputSize), bias: Self.biasHidden)
        let logits = matVecMul(Self.weightsOutput, hidden, rows: outputStyles.count, cols: hiddenSize)
        let biased = zip(logits, Self.biasOutput).map(+)
        let probs = softmax(biased)

        var probabilities: [LiveMusicStyle: Double] = [:]
        for (index, style) in outputStyles.enumerated() where probs.indices.contains(index) {
            probabilities[style] = probs[index]
        }

        guard let bestIndex = probs.enumerated().max(by: { $0.element < $1.element })?.offset,
              outputStyles.indices.contains(bestIndex) else {
            return AudioStylePrediction(style: .unknown, confidence: 0, probabilities: probabilities)
        }

        let bestProb = probs[bestIndex]
        guard bestProb >= 0.18 else {
            return AudioStylePrediction(style: .unknown, confidence: bestProb, probabilities: probabilities)
        }

        return AudioStylePrediction(
            style: outputStyles[bestIndex],
            confidence: bestProb,
            probabilities: probabilities
        )
    }

    func buildFeatureVector(
        recentFeatures: [AudioFeatureSnapshot],
        bpm: Double?,
        beatConfidence: Double,
        syncopation: Double,
        onsetDensity: Double
    ) -> [Float] {
        var vector = [Float](repeating: 0, count: inputSize)
        guard !recentFeatures.isEmpty else { return vector }

        let tail = recentFeatures.suffix(12)
        let avgMel = averageMelBands(tail)
        for index in 0..<min(8, avgMel.count) {
            vector[index] = avgMel[index]
        }

        let avgRMS = tail.map(\.rms).reduce(0, +) / Float(tail.count)
        let avgFlux = tail.map(\.spectralFlux).reduce(0, +) / Float(tail.count)
        let avgCentroid = tail.map(\.spectralCentroid).reduce(0, +) / Float(tail.count)
        let avgRolloff = tail.map(\.spectralRolloff).reduce(0, +) / Float(tail.count)
        let avgZCR = tail.map(\.zeroCrossingRate).reduce(0, +) / Float(tail.count)

        let low = tail.map { $0.lowMidHighRatio.low }.reduce(0, +) / Float(tail.count)
        let mid = tail.map { $0.lowMidHighRatio.mid }.reduce(0, +) / Float(tail.count)
        let high = tail.map { $0.lowMidHighRatio.high }.reduce(0, +) / Float(tail.count)

        vector[8] = min(1, avgRMS * 8)
        vector[9] = min(1, avgFlux * 0.02)
        vector[10] = avgCentroid
        vector[11] = avgRolloff
        vector[12] = avgZCR
        vector[13] = low
        vector[14] = mid
        vector[15] = high

        if let bpm {
            vector[16] = Float(min(1, max(0, (bpm - 48) / 152)))
        }
        vector[17] = Float(beatConfidence)
        vector[18] = Float(syncopation)
        vector[19] = Float(min(1, onsetDensity / 10))

        let fluxVariance = variance(tail.map(\.spectralFlux))
        vector[20] = min(1, fluxVariance * 40)
        vector[21] = Float(tail.filter { $0.rms > 0.01 }.count) / Float(tail.count)
        vector[22] = high > low ? 1 : 0
        vector[23] = mid

        // Rhythm / brightness interaction features
        vector[24] = vector[16] * vector[18]
        vector[25] = vector[13] * vector[17]
        vector[26] = vector[9] * vector[19]
        vector[27] = vector[10] * vector[14]
        vector[28] = vector[11] * vector[15]
        vector[29] = vector[12]
        vector[30] = vector[0] * vector[13]
        vector[31] = vector[7] * vector[18]

        return vector
    }

    private func averageMelBands(_ snapshots: ArraySlice<AudioFeatureSnapshot>) -> [Float] {
        guard !snapshots.isEmpty else { return [] }
        let count = snapshots.count
        var sums = [Float](repeating: 0, count: 8)
        for snapshot in snapshots {
            for (index, value) in snapshot.melBands.prefix(8).enumerated() {
                sums[index] += value
            }
        }
        return sums.map { $0 / Float(count) }
    }

    private func variance(_ values: [Float]) -> Float {
        guard !values.isEmpty else { return 0 }
        let mean = values.reduce(0, +) / Float(values.count)
        let squared = values.map { ($0 - mean) * ($0 - mean) }
        return squared.reduce(0, +) / Float(values.count)
    }

    private func matVecMul(_ matrix: [Float], _ vector: [Float], rows: Int, cols: Int) -> [Float] {
        guard rows > 0, cols > 0, vector.count >= cols else {
            return Array(repeating: 0, count: max(rows, 0))
        }
        var result = [Float](repeating: 0, count: rows)
        for row in 0..<rows {
            var sum: Float = 0
            let rowOffset = row * cols
            for col in 0..<cols {
                let index = rowOffset + col
                guard matrix.indices.contains(index) else { continue }
                sum += matrix[index] * vector[col]
            }
            result[row] = sum
        }
        return result
    }

    private func relu(_ vector: [Float], bias: [Float]) -> [Float] {
        zip(vector, bias).map { max(0, $0 + $1) }
    }

    private func softmax(_ logits: [Float]) -> [Double] {
        let maxLogit = logits.max() ?? 0
        let exps = logits.map { exp(Double($0 - maxLogit)) }
        let sum = exps.reduce(0, +)
        guard sum > 0 else { return Array(repeating: 0, count: logits.count) }
        return exps.map { $0 / sum }
    }

    // Hand-tuned priors for worship + Caribbean grooves (replace with trained Core ML weights).
    private static let weightsHidden: [Float] = AudioStyleModelWeights.hidden
    private static let biasHidden: [Float] = AudioStyleModelWeights.biasHidden
    private static let weightsOutput: [Float] = AudioStyleModelWeights.output
    private static let biasOutput: [Float] = AudioStyleModelWeights.biasOutput
}

enum AudioStyleModelWeights {
    static let hidden: [Float] = AudioStyleModelWeights.generatedHidden
    static let biasHidden: [Float] = AudioStyleModelWeights.generatedBiasHidden
    static let output: [Float] = AudioStyleOutputWeights.build()
    static let biasOutput: [Float] = AudioStyleOutputWeights.biases()
}

/// Hand-tuned output profiles for every detectable genre (replace with Core ML later).
private enum AudioStyleOutputWeights {
    static func build() -> [Float] {
        let styles = LiveMusicStyle.detectableStyles
        var weights = [Float](repeating: 0, count: styles.count * 24)
        for (row, style) in styles.enumerated() {
            apply(style: style, row: row, into: &weights)
        }
        return weights
    }

    static func biases() -> [Float] {
        LiveMusicStyle.detectableStyles.map { style in
            switch style.category {
            case .worship: 0.05
            case .popRock: 0.0
            case .jazzBlues: 0.02
            case .latin: 0.04
            case .world: -0.02
            }
        }
    }

    private static func apply(style: LiveMusicStyle, row: Int, into weights: inout [Float]) {
        func set(_ col: Int, _ value: Float) {
            guard col >= 0, col < 24 else { return }
            weights[row * 24 + col] = value
        }

        switch style {
        case .worshipBallad:
            set(0, 0.4); set(8, 0.8); set(16, -0.9); set(18, -0.7)
        case .softPulse:
            set(0, 0.3); set(16, -1.2); set(19, -0.8); set(9, -0.4)
        case .gospelGroove:
            set(4, 0.5); set(12, 0.9); set(14, 0.7); set(18, 0.2)
        case .brushWaltz:
            set(8, 0.7); set(10, 0.6); set(18, -0.5); set(16, 0.1)
        case .popRock:
            set(0, 0.7); set(16, 0.6); set(18, -0.4); set(13, 0.5)
        case .rockDrive:
            set(0, 0.8); set(16, 1.1); set(19, 0.9); set(13, 0.6)
        case .funkGroove:
            set(4, 1.0); set(18, 1.2); set(20, 0.8); set(9, 0.7)
        case .rbSoul:
            set(14, 0.9); set(16, 0.4); set(18, 0.5); set(10, 0.5)
        case .edmPulse:
            set(0, 0.6); set(16, 1.0); set(18, -0.8); set(19, 1.0)
        case .jazzSwing:
            set(8, 0.8); set(10, 0.9); set(14, 0.7); set(18, 0.4); set(20, 0.6)
        case .bluesShuffle:
            set(12, 0.8); set(4, 0.5); set(18, 0.3); set(16, 0.2)
        case .merengue:
            set(0, 0.6); set(16, 1.3); set(19, 1.0); set(18, -0.6); set(13, 0.8)
        case .montuno:
            set(4, 1.1); set(18, 1.3); set(14, 0.85); set(9, 0.75); set(20, 0.55)
        case .salsa:
            set(4, 1.0); set(18, 1.2); set(14, 0.7); set(16, 0.5); set(9, 0.6)
        case .songo:
            set(4, 0.8); set(18, 1.0); set(20, 0.9); set(15, 0.7); set(23, 0.5)
        case .bossaNova:
            set(8, 0.7); set(14, 0.8); set(18, 0.6); set(16, 0.3); set(10, 0.5)
        case .bolero:
            set(8, 0.6); set(16, -0.8); set(18, -0.5); set(14, 0.7)
        case .reggaeOneDrop:
            set(4, 0.7); set(18, 0.9); set(16, -0.3); set(14, 0.5)
        case .countryTrain:
            set(0, 0.65); set(13, 0.9); set(16, 0.5); set(18, -0.3)
        case .unknown:
            break
        }
    }
}

private extension AudioStyleModelWeights {
    // 24 x 32 hidden weights — sparse hand-tuned structure
    static let generatedHidden: [Float] = {
        var w = [Float](repeating: 0, count: 24 * 32)
        func set(_ row: Int, _ col: Int, _ value: Float) {
            guard row >= 0, row < 24, col >= 0, col < 32 else { return }
            w[row * 32 + col] = value
        }

        // Rows 0-3: tempo + density
        for row in 0..<4 {
            set(row, 16, 1.2)
            set(row, 19, 0.9)
            set(row, 17, 0.5)
        }
        // Rows 4-7: syncopation + flux
        for row in 4..<8 {
            set(row, 18, 1.4)
            set(row, 9, 0.8)
            set(row, 20, 0.6)
        }
        // Rows 8-11: spectral brightness
        for row in 8..<12 {
            set(row, 10, 1.0)
            set(row, 15, 0.9)
            set(row, 11, 0.7)
        }
        // Rows 12-15: low-end / bass energy
        for row in 12..<16 {
            set(row, 13, 1.3)
            set(row, 0, 0.5)
            set(row, 1, 0.4)
        }
        // Rows 16-19: mid/high balance
        for row in 16..<20 {
            set(row, 14, 1.0)
            set(row, 15, 0.8)
            set(row, 22, 0.6)
        }
        // Rows 20-23: interaction terms
        for row in 20..<24 {
            set(row, 24 + (row - 20), 1.1)
            set(row, 16, 0.4)
            set(row, 18, 0.5)
        }
        return w
    }()

    static let generatedBiasHidden: [Float] = Array(repeating: 0.05, count: 24)
}
#endif
