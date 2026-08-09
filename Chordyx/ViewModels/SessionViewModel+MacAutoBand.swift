//
//  SessionViewModel+MacAutoBand.swift
//  Chordyx
//
//  Phase 3 — auto drums + bass when musicians are missing; stem learning from mixer sends.
//

#if os(macOS) || os(iOS)
import Foundation
#if os(macOS)
import CoreAudio
#endif

extension SessionViewModel {
    private static let bandDrumInputKey = "bandStemDrumInputDeviceID"
    private static let bandBassInputKey = "bandStemBassInputDeviceID"

    var bandDrumInputDeviceID: AudioInputDeviceID? {
        get {
            guard let value = UserDefaults.standard.object(forKey: Self.bandDrumInputKey) as? Int32 else { return nil }
            return AudioInputDeviceID(UInt32(bitPattern: value))
        }
        set {
            if let newValue {
                UserDefaults.standard.set(Int32(bitPattern: UInt32(newValue)), forKey: Self.bandDrumInputKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.bandDrumInputKey)
            }
            refreshBandStemLearningCapture()
        }
    }

    var bandBassInputDeviceID: AudioInputDeviceID? {
        get {
            guard let value = UserDefaults.standard.object(forKey: Self.bandBassInputKey) as? Int32 else { return nil }
            return AudioInputDeviceID(UInt32(bitPattern: value))
        }
        set {
            if let newValue {
                UserDefaults.standard.set(Int32(bitPattern: UInt32(newValue)), forKey: Self.bandBassInputKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.bandBassInputKey)
            }
            refreshBandStemLearningCapture()
        }
    }

    func setAutoBandMode(_ mode: AutoBandMode) {
        autoBandMode = mode
        guard soloAccompanimentEnabled, soloTempoLocked else { return }

        let bpm = soloLockedBPM ?? Double(payload.tempoBPM)
        let beats = 4

        if mode.includesDrums {
            if !drumAccompaniment.isPlaying {
                drumAccompaniment.volume = soloDrumVolume
                if let learned = activeLearnedDrumPattern, !learned.isEmpty {
                    drumAccompaniment.setLearnedPattern(learned, force: true)
                } else {
                    drumAccompaniment.setLearnedPattern(nil, force: true)
                }
                drumAccompaniment.start(
                    bpm: bpm,
                    pattern: soloDrumPattern,
                    beatsPerBar: beats,
                    freezeToWallClock: true
                )
                applySoloDrumsMetronomePolicy()
            }
        } else if drumAccompaniment.isPlaying || drumAccompaniment.isGrooveFrozen {
            drumAccompaniment.unfreezeGroove()
            drumAccompaniment.stop(force: true)
            applySoloDrumsMetronomePolicy()
        }

        if soloBassEnabled, mode.includesBass {
            startBassAccompanimentIfNeeded(at: bpm)
        } else {
            bassAccompaniment.stop(force: true)
        }
    }

    func setSoloBassEnabled(_ enabled: Bool) {
        soloBassEnabled = enabled
        if !enabled {
            bassAccompaniment.stop(force: true)
        } else if soloTempoLocked, autoBandMode.includesBass {
            startBassAccompanimentIfNeeded(at: soloLockedBPM ?? payload.tempoBPM)
        }
    }

    func setSoloBassStyle(_ style: BassAccompanimentStyle) {
        soloBassStyle = style
        bassAccompaniment.setStyle(style)
    }

    func setSoloBassVolume(_ volume: Float) {
        soloBassVolume = volume
        bassAccompaniment.volume = volume
    }

    func setBandStemLearningEnabled(_ enabled: Bool) {
        #if os(iOS)
        // Dual-input stem learning stays Mac-only (separate Core Audio / mixer sends).
        _ = enabled
        bandStemLearningEnabled = false
        bandStemLearning.stopLearning()
        #else
        bandStemLearningEnabled = enabled
        refreshBandStemLearningCapture()
        #endif
    }

    func refreshBandStemLearningCapture() {
        #if os(iOS)
        bandStemLearning.stopLearning()
        return
        #else
        guard serviceLearningEnabled, bandStemLearningEnabled else {
            bandStemLearning.stopLearning()
            return
        }
        bandStemLearning.drumInputDeviceID = bandDrumInputDeviceID
        bandStemLearning.bassInputDeviceID = bandBassInputDeviceID
        if !bandStemLearning.isLearning {
            bandStemLearning.startLearning()
        }
        #endif
    }

    /// Starts or updates auto band after drums lock.
    func startAutoBandAccompanimentIfNeeded(at bpm: Double) {
        guard soloAccompanimentEnabled, autoBandMode != .off else { return }

        if autoBandMode.includesDrums {
            if let learned = activeLearnedDrumPattern, !learned.isEmpty {
                drumAccompaniment.setLearnedPattern(learned)
            } else {
                drumAccompaniment.setLearnedPattern(nil)
            }
        }

        if soloBassEnabled, autoBandMode.includesBass {
            startBassAccompanimentIfNeeded(at: bpm)
        }
    }

    func startBassAccompanimentIfNeeded(at bpm: Double) {
        guard soloBassEnabled, autoBandMode.includesBass else { return }

        let style: BassAccompanimentStyle = {
            if let line = activeLearnedBassLine, !line.isEmpty { return .learned }
            return soloBassStyle
        }()

        bassAccompaniment.volume = soloBassVolume
        bassAccompaniment.kickPocketLock = true
        bassAccompaniment.start(
            bpm: bpm,
            style: style,
            chordSymbol: payload.liveChordSymbol,
            learnedLine: activeLearnedBassLine,
            beatsPerBar: max(1, payload.beatsPerBar),
            anchorTime: drumAccompaniment.grooveAnchor
        )
    }

    func stopAutoBandAccompaniment(force: Bool = false) {
        bassAccompaniment.stop(force: force)
        if force {
            activeLearnedDrumPattern = nil
            activeLearnedBassLine = nil
            drumAccompaniment.setLearnedPattern(nil)
        }
    }

    func updateAutoBandLiveChord(_ symbol: String?) {
        guard soloTempoLocked, bassAccompaniment.isPlaying else { return }
        bassAccompaniment.updateChord(symbol)
    }

    func captureStemLearningForSnapshot(bpm: Double) {
        guard bandStemLearningEnabled else { return }
        if let drums = bandStemLearning.buildLearnedDrumPattern(bpm: bpm) {
            activeLearnedDrumPattern = drums
        }
        if let bass = bandStemLearning.buildLearnedBassLine(bpm: bpm) {
            activeLearnedBassLine = bass
            soloBassStyle = .learned
        }
    }

    func applyAutoBandFromRecord(_ record: ServiceLearningRecord) {
        autoBandMode = record.autoBandMode
        soloBassStyle = record.hasLearnedBass ? .learned : record.bassStyle
        activeLearnedDrumPattern = record.learnedDrumPattern
        activeLearnedBassLine = record.learnedBassLine

        if let learned = record.learnedDrumPattern, !learned.isEmpty {
            drumAccompaniment.setLearnedPattern(learned, force: soloTempoLocked)
        } else {
            drumAccompaniment.setLearnedPattern(nil, force: soloTempoLocked)
        }

        if soloAccompanimentEnabled, soloTempoLocked {
            startAutoBandAccompanimentIfNeeded(at: record.tempoBPM)
        }
    }

    func suggestedBassStyle(for musicStyle: LiveMusicStyle) -> BassAccompanimentStyle {
        switch musicStyle {
        case .songo: return .songoPulse
        case .merengue: return .merengueOctave
        case .montuno, .salsa, .bossaNova: return .latinTumbao
        case .bolero, .worshipBallad, .softPulse, .brushWaltz: return .slowBallad
        case .jazzSwing, .bluesShuffle: return .walkSupport
        case .funkGroove, .rbSoul: return .funkPocket
        case .edmPulse: return .worshipPocket
        case .rockDrive, .popRock, .gospelGroove, .countryTrain, .reggaeOneDrop:
            return .worshipPocket
        case .unknown: return .worshipPocket
        }
    }
}
#endif
