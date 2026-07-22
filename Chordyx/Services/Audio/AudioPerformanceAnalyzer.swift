//
//  AudioPerformanceAnalyzer.swift
//  Chordyx
//
//  Live audio AI pipeline: capture → features → beat tracking → neural style classification.
//

#if os(macOS) || os(iOS)
import AVFoundation
import Foundation
import Observation

@Observable
@MainActor
final class AudioPerformanceAnalyzer {
    private(set) var estimatedBPM: Double?
    private(set) var tempoConfidence: Double = 0
    private(set) var detectedStyle: LiveMusicStyle = .unknown
    private(set) var styleConfidence: Double = 0
    private(set) var suggestedPattern: DrumPattern?
    private(set) var syncopationIndex: Double = 0
    private(set) var onsetDensityPerSecond: Double = 0
    private(set) var latinRhythmAnalysis: LatinRhythmAnalysis = .empty
    private(set) var detectedClave: ClaveOrientation = .unknown
    private(set) var lastStyleProbabilities: [LiveMusicStyle: Double] = [:]
    private(set) var isListening = false
    private(set) var isTracking = false
    private(set) var lastError: String?
    private(set) var inputLevel: Float = 0
    private(set) var availableInputDevices: [AudioInputDevice] = []
    private(set) var estimatedAudioKey: MusicalKey?
    private(set) var audioKeyConfidence: Double = 0
    private(set) var audioKeyScores: [MusicalKey: Double] = [:]

    private let capture = AudioInputCapture()
    private nonisolated let featureExtractor = AudioFeatureExtractor()
    private nonisolated let beatTracker = AudioBeatTracker()
    private nonisolated let chromaKeyEstimator = AudioChromaKeyEstimator()
    private let styleClassifier = AudioStyleNeuralClassifier()

    private var recentFeatures: [AudioFeatureSnapshot] = []
    private let maxFeatureHistory = 48
    private var selectedDeviceID: AudioInputDeviceID?
    private var lastUIPublishTime: TimeInterval = 0
    private let uiPublishInterval: TimeInterval = 0.12

    var onAnalysisUpdated: (() -> Void)?

    func refreshDevices() {
        availableInputDevices = AudioInputCapture.availableInputDevices()
    }

    func selectInputDevice(_ device: AudioInputDevice?) {
        selectedDeviceID = device?.id
        capture.selectDevice(device?.id)
    }

    func startListening() {
        refreshDevices()
        lastError = nil
        capture.onBuffer = { [weak self] buffer, time in
            self?.process(buffer: buffer, at: time)
        }
        capture.selectDevice(selectedDeviceID)
        do {
            try capture.start()
            isListening = true
        } catch {
            lastError = error.localizedDescription
            isListening = false
        }
    }

    func stopListening() {
        capture.stop()
        capture.onBuffer = nil
        isListening = false
        resetAnalysis()
    }

    func resetAnalysis() {
        beatTracker.reset()
        chromaKeyEstimator.reset()
        recentFeatures.removeAll()
        estimatedBPM = nil
        tempoConfidence = 0
        detectedStyle = .unknown
        styleConfidence = 0
        suggestedPattern = nil
        syncopationIndex = 0
        onsetDensityPerSecond = 0
        isTracking = false
        inputLevel = 0
        latinRhythmAnalysis = .empty
        detectedClave = .unknown
        lastStyleProbabilities = [:]
        estimatedAudioKey = nil
        audioKeyConfidence = 0
        audioKeyScores = [:]
        lastUIPublishTime = 0
    }

    nonisolated private func process(buffer: AVAudioPCMBuffer, at time: TimeInterval) {
        let features = featureExtractor.analyze(buffer: buffer, at: time)
        guard !features.isEmpty else { return }

        beatTracker.ingest(features: features)
        for feature in features {
            chromaKeyEstimator.ingest(frameChroma: feature.chroma, rms: feature.rms)
        }
        let keyEstimate = chromaKeyEstimator.estimate()
        let peakRMS = features.map(\.rms).max() ?? 0
        let bpm = beatTracker.estimatedBPM
        let tempoConf = beatTracker.confidence
        let syncopation = beatTracker.syncopationIndex
        let onsetDensity = beatTracker.onsetDensityPerSecond

        Task { @MainActor [weak self] in
            guard let self, self.isListening else { return }

            // Always keep a light feature history, but throttle expensive UI/classifier work
            // so enabling Audio AI on iPhone doesn't freeze the main thread.
            self.recentFeatures.append(contentsOf: features)
            if self.recentFeatures.count > self.maxFeatureHistory {
                self.recentFeatures.removeFirst(self.recentFeatures.count - self.maxFeatureHistory)
            }

            let now = Date().timeIntervalSince1970
            guard now - self.lastUIPublishTime >= self.uiPublishInterval else { return }
            self.lastUIPublishTime = now

            self.inputLevel = peakRMS
            self.estimatedBPM = bpm
            self.tempoConfidence = tempoConf
            self.syncopationIndex = syncopation
            self.onsetDensityPerSecond = onsetDensity
            self.isTracking = (bpm != nil) || peakRMS > 0.006

            if let keyEstimate {
                self.estimatedAudioKey = keyEstimate.key
                self.audioKeyConfidence = keyEstimate.confidence
                self.audioKeyScores = keyEstimate.scores
            }

            self.classifyStyle()
            self.onAnalysisUpdated?()
        }
    }

    func spectralProfile() -> (brightness: Double, lowRatio: Double) {
        let tail = recentFeatures.suffix(12)
        guard !tail.isEmpty else { return (0.5, 0.33) }
        let avgHigh = tail.map(\.lowMidHighRatio.high).reduce(0, +) / Float(tail.count)
        let avgLow = tail.map(\.lowMidHighRatio.low).reduce(0, +) / Float(tail.count)
        let brightness = Double(min(1, max(0, avgHigh / max(0.001, avgHigh + avgLow))))
        return (brightness, Double(avgLow))
    }

    private func classifyStyle() {
        guard recentFeatures.count >= 8 else { return }

        let vector = styleClassifier.buildFeatureVector(
            recentFeatures: recentFeatures,
            bpm: estimatedBPM,
            beatConfidence: tempoConfidence,
            syncopation: syncopationIndex,
            onsetDensity: onsetDensityPerSecond
        )

        let prediction = styleClassifier.predict(features: vector)
        lastStyleProbabilities = prediction.probabilities

        var blendedStyle = prediction.style
        var blendedConfidence = prediction.confidence

        if let bpm = estimatedBPM, bpm > 0 {
            let latin = LatinRhythmPatternEngine.analyzeAudio(
                onsets: beatTracker.recentOnsetSnapshot(),
                bpm: bpm
            )
            latinRhythmAnalysis = latin
            detectedClave = latin.clave

            if latin.confidence >= 0.28,
               let patternStyle = latin.bestStyle,
               latin.confidence > blendedConfidence * 0.85 || blendedConfidence < 0.25 {
                blendedStyle = patternStyle
                blendedConfidence = max(blendedConfidence * 0.72, latin.confidence * 0.92)
            } else if latin.montunoOstinatoStrength >= 0.42,
                      latin.montunoOstinatoStrength > blendedConfidence * 0.7 {
                blendedStyle = .montuno
                blendedConfidence = max(blendedConfidence, latin.montunoOstinatoStrength * 0.88)
            }
        }

        if blendedConfidence > styleConfidence * 0.65 || styleConfidence < 0.2 {
            detectedStyle = blendedStyle
            styleConfidence = blendedConfidence
            suggestedPattern = blendedStyle.suggestedDrumPattern
        }
    }
}
#endif
