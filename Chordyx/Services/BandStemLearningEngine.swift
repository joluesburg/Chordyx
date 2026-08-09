//
//  BandStemLearningEngine.swift
//  Chordyx
//
//  Learns drum grid + bass line from separate mixer sends (P16 / aux channels).
//

#if os(macOS) || os(iOS)
import AVFoundation
import Foundation
import Observation

@Observable
@MainActor
final class BandStemLearningEngine {
    private(set) var isLearning = false
    private(set) var drumInputLevel: Float = 0
    private(set) var bassInputLevel: Float = 0
    private(set) var drumOnsetCount = 0
    private(set) var bassNoteCount = 0
    private(set) var lastError: String?

    var drumInputDeviceID: AudioInputDeviceID?
    var bassInputDeviceID: AudioInputDeviceID?

    private let drumCapture = AudioInputCapture()
    private let bassCapture = AudioInputCapture()
    private nonisolated let drumFeatures = AudioFeatureExtractor()
    private nonisolated let bassFeatures = AudioFeatureExtractor()

    private var drumOnsets: [(time: TimeInterval, band: StemBand, strength: Float)] = []
    private var bassNotes: [(time: TimeInterval, midi: Int, velocity: Int)] = []
    private var learningStartedAt: TimeInterval?
    private var lastDrumFlux: Float = 0
    private var lastBassFlux: Float = 0
    private var bassFluxHistory: [Float] = []

    private enum StemBand {
        case low, mid, high
    }

    private let maxEvents = 256

    func startLearning() {
        lastError = nil
        drumOnsets.removeAll()
        bassNotes.removeAll()
        drumOnsetCount = 0
        bassNoteCount = 0
        learningStartedAt = Date().timeIntervalSince1970
        lastDrumFlux = 0
        lastBassFlux = 0
        bassFluxHistory.removeAll()

        drumCapture.onBuffer = { [weak self] buffer, time in
            self?.processDrumBuffer(buffer, at: time)
        }
        bassCapture.onBuffer = { [weak self] buffer, time in
            self?.processBassBuffer(buffer, at: time)
        }

        drumCapture.selectDevice(drumInputDeviceID)
        bassCapture.selectDevice(bassInputDeviceID)

        do {
            try drumCapture.start()
            try bassCapture.start()
            isLearning = true
        } catch {
            lastError = error.localizedDescription
            isLearning = false
        }
    }

    func stopLearning() {
        drumCapture.stop()
        bassCapture.stop()
        drumCapture.onBuffer = nil
        bassCapture.onBuffer = nil
        isLearning = false
    }

    func reset() {
        stopLearning()
        drumOnsets.removeAll()
        bassNotes.removeAll()
        drumOnsetCount = 0
        bassNoteCount = 0
        drumInputLevel = 0
        bassInputLevel = 0
    }

    func buildLearnedDrumPattern(bpm: Double) -> LearnedDrumPattern? {
        guard bpm >= 48, bpm <= 220, drumOnsets.count >= 8,
              let anchor = drumOnsets.first?.time,
              let lastOnset = drumOnsets.last?.time else { return nil }

        let barDuration = (60.0 / bpm) * 4.0
        let sixteenth = barDuration / 16.0
        guard sixteenth > 0 else { return nil }

        var grid = LearnedDrumPattern.emptyGrid()

        for onset in drumOnsets.suffix(120) {
            let phase = onset.time - anchor
            guard phase >= 0 else { continue }
            let step = Int((phase.truncatingRemainder(dividingBy: barDuration)) / sixteenth) % 16
            let voice = drumVoice(for: onset.band)
            if !grid[step].contains(voice.storageKey) {
                grid[step].append(voice.storageKey)
            }
        }

        let pattern = LearnedDrumPattern(
            stepVoices: grid,
            capturedAt: Date(),
            barsAnalyzed: max(1, Int((lastOnset - anchor) / barDuration))
        )
        return pattern.isEmpty ? nil : pattern
    }

    func buildLearnedBassLine(bpm: Double) -> LearnedBassLine? {
        guard bpm >= 48, bpm <= 220, bassNotes.count >= 4 else { return nil }

        let barDuration = (60.0 / bpm) * 4.0
        let sixteenth = barDuration / 16.0
        guard sixteenth > 0, let anchor = bassNotes.first?.time else { return nil }

        var events: [LearnedBassLine.Event] = []
        var usedSteps = Set<Int>()

        for note in bassNotes.suffix(64) {
            let phase = note.time - anchor
            guard phase >= 0 else { continue }
            let step = Int((phase.truncatingRemainder(dividingBy: barDuration)) / sixteenth) % 16
            guard !usedSteps.contains(step) else { continue }
            usedSteps.insert(step)
            events.append(LearnedBassLine.Event(
                sixteenthStep: step,
                midiNote: note.midi,
                velocity: note.velocity
            ))
        }

        let line = LearnedBassLine(events: events.sorted { $0.sixteenthStep < $1.sixteenthStep })
        return line.isEmpty ? nil : line
    }

    // MARK: - Processing

    nonisolated private func processDrumBuffer(_ buffer: AVAudioPCMBuffer, at time: TimeInterval) {
        let features = drumFeatures.analyze(buffer: buffer, at: time)
        guard !features.isEmpty else { return }

        Task { @MainActor [weak self] in
            guard let self, self.isLearning else { return }
            self.drumInputLevel = features.map(\.rms).max() ?? 0
            for snapshot in features {
                let threshold = max(0.004, self.lastDrumFlux * 1.08 + 0.002)
                if snapshot.spectralFlux > threshold, snapshot.rms > 0.005 {
                    let band = self.classifyDrumBand(snapshot)
                    self.drumOnsets.append((snapshot.time, band, snapshot.spectralFlux))
                    if self.drumOnsets.count > self.maxEvents {
                        self.drumOnsets.removeFirst(self.drumOnsets.count - self.maxEvents)
                    }
                    self.drumOnsetCount = self.drumOnsets.count
                }
                self.lastDrumFlux = snapshot.spectralFlux
            }
        }
    }

    nonisolated private func processBassBuffer(_ buffer: AVAudioPCMBuffer, at time: TimeInterval) {
        let features = bassFeatures.analyze(buffer: buffer, at: time)
        guard !features.isEmpty else { return }

        Task { @MainActor [weak self] in
            guard let self, self.isLearning else { return }
            self.bassInputLevel = features.map(\.rms).max() ?? 0
            for snapshot in features {
                self.bassFluxHistory.append(snapshot.spectralFlux)
                if self.bassFluxHistory.count > 24 {
                    self.bassFluxHistory.removeFirst(self.bassFluxHistory.count - 24)
                }
                let avg = self.bassFluxHistory.reduce(0, +) / Float(max(1, self.bassFluxHistory.count))
                let threshold = avg * 1.4 + 0.003

                if snapshot.spectralFlux > threshold,
                   snapshot.rms > 0.006,
                   snapshot.lowMidHighRatio.low > 0.38 {
                    if let midi = self.estimateBassMidi(from: snapshot) {
                        self.bassNotes.append((snapshot.time, midi, 88))
                        if self.bassNotes.count > self.maxEvents {
                            self.bassNotes.removeFirst(self.bassNotes.count - self.maxEvents)
                        }
                        self.bassNoteCount = self.bassNotes.count
                    }
                }
                self.lastBassFlux = snapshot.spectralFlux
            }
        }
    }

    private func classifyDrumBand(_ snapshot: AudioFeatureSnapshot) -> StemBand {
        let ratios = snapshot.lowMidHighRatio
        if ratios.low > ratios.mid, ratios.low > ratios.high { return .low }
        if ratios.high > ratios.mid { return .high }
        return .mid
    }

    private func drumVoice(for band: StemBand) -> DrumVoice {
        switch band {
        case .low: .kick
        case .mid: .snare
        case .high: .hihatClosed
        }
    }

    private func estimateBassMidi(from snapshot: AudioFeatureSnapshot) -> Int? {
        let lowEnergy = snapshot.lowMidHighRatio.low
        guard lowEnergy > 0.25 else { return nil }
        // Map spectral centroid in bass range to MIDI note (rough).
        let centroid = Double(snapshot.spectralCentroid)
        let hz = max(35, min(220, centroid))
        let midi = 69.0 + 12.0 * log2(hz / 440.0)
        return Int(midi.rounded())
    }
}
#endif
