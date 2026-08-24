//
//  SessionViewModel+MacServiceLearning.swift
//  Chordyx
//
//  Captures and replays how your church band plays — tempo, drums, chords, style.
//

#if os(macOS) || os(iOS)
import Foundation

extension SessionViewModel {
    private static let serviceLearningProfileKey = "serviceLearningProfileName"

    var serviceLearningProfileName: String {
        get {
            UserDefaults.standard.string(forKey: Self.serviceLearningProfileKey)
                ?? String(localized: "My church")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.serviceLearningProfileKey)
        }
    }

    func refreshServiceLearningLibrary() {
        serviceLearningRecords = ServiceLearningStore.shared.loadAll()
    }

    func setServiceLearningEnabled(_ enabled: Bool) {
        serviceLearningEnabled = enabled
        if enabled {
            refreshServiceLearningLibrary()
            refreshBandStemLearningCapture()
        } else {
            bandStemLearning.stopLearning()
        }
    }

    func setServiceLearningAutoSaveOnLock(_ enabled: Bool) {
        serviceLearningAutoSaveOnLock = enabled
    }

    func saveServiceLearningSnapshot(source: ServiceLearningCaptureSource = .manual) -> ServiceLearningRecord? {
        guard soloAccompanimentAvailable else { return nil }

        let bpm = soloLockedBPM ?? livePerformanceFusion.estimatedBPM ?? payload.tempoBPM
        guard bpm >= 48, bpm <= 220 else { return nil }

        captureStemLearningForSnapshot(bpm: bpm)

        let chords = chordsForServiceLearningCapture()
        let symbols = chords.map(\.symbolName)
        let bassStyle = activeLearnedBassLine != nil ? BassAccompanimentStyle.learned : suggestedBassStyle(for: detectedLiveStyle)

        let record = ServiceLearningRecord(
            profileName: serviceLearningProfileName,
            songTitle: resolvedServiceLearningSongTitle(),
            serviceSessionName: payload.sessionName,
            tempoBPM: (bpm * 2).rounded() / 2,
            drumPatternRaw: soloDrumPattern.rawValue,
            detectedStyleRaw: detectedLiveStyle.rawValue,
            styleConfidence: detectedStyleConfidence,
            syncopationIndex: liveSyncopationIndex,
            key: payload.key,
            notation: payload.notation,
            beatsPerBar: max(1, payload.beatsPerBar),
            chordSymbols: symbols,
            chords: chords,
            captureSource: source,
            learnedDrumPattern: activeLearnedDrumPattern,
            learnedBassLine: activeLearnedBassLine,
            bassStyleRaw: bassStyle.rawValue,
            autoBandModeRaw: autoBandMode.rawValue
        )

        ServiceLearningStore.shared.save(record)
        refreshServiceLearningLibrary()
        lastServiceLearningSaveMessage = String(localized: "Saved “\(record.songTitle)” at \(Int(record.tempoBPM)) BPM")
        return record
    }

    func deleteServiceLearningRecord(_ id: UUID) {
        ServiceLearningStore.shared.delete(id: id)
        refreshServiceLearningLibrary()
    }

    /// Restores tempo, drum pattern, key, and chords from a saved church snapshot.
    func applyServiceLearningRecord(_ record: ServiceLearningRecord) {
        guard canDriveSession else { return }

        soloDrumPattern = record.drumPattern
        payload.tempoBPM = record.tempoBPM
        payload.beatsPerBar = record.beatsPerBar
        payload.key = record.key
        payload.notation = record.notation

        if !record.chords.isEmpty {
            applyChordsFromServiceLearning(record.chords)
        }

        if soloAccompanimentEnabled {
            if soloTempoLocked {
                drumAccompaniment.setPattern(soloDrumPattern, force: true)
                applyAutoBandFromRecord(record)
            } else {
                if let learned = record.learnedDrumPattern, !learned.isEmpty {
                    activeLearnedDrumPattern = learned
                    drumAccompaniment.setLearnedPattern(learned)
                }
                activeLearnedBassLine = record.learnedBassLine
                soloBassStyle = record.bassStyle
                autoBandMode = record.autoBandMode
                lockSoloDrums(at: record.tempoBPM)
            }
        } else {
            applyAutoBandFromRecord(record)
        }

        sync()
        lastServiceLearningSaveMessage = String(
            localized: "Using “\(record.songTitle)” — \(Int(record.tempoBPM)) BPM · \(record.bandSummary)"
        )
    }

    func promoteServiceLearningToLibrary(_ record: ServiceLearningRecord, store: ProgressionStore) {
        guard !record.chords.isEmpty else { return }
        let saved = SavedProgression(
            name: record.songTitle,
            key: record.key,
            notation: record.notation,
            chords: record.chords.sorted { $0.order < $1.order },
            tempoBPM: record.tempoBPM,
            beatsPerBar: record.beatsPerBar,
            savedAt: record.recordedAt,
            rehearsalNotes: String(localized: "Learned from live service on \(record.recordedAtLabel)")
        )
        _ = store.save(saved)
        lastServiceLearningSaveMessage = String(localized: "Added “\(record.songTitle)” to chord library")
    }

    func autoSaveServiceLearningOnDrumLockIfNeeded() {
        guard serviceLearningEnabled, serviceLearningAutoSaveOnLock else { return }
        guard soloTempoLocked, soloLockedBPM != nil else { return }

        let fingerprint = "\(resolvedServiceLearningSongTitle())|\(soloLockedBPM ?? 0)|\(soloDrumPattern.rawValue)"
        guard fingerprint != lastServiceLearningAutoSaveFingerprint else { return }
        lastServiceLearningAutoSaveFingerprint = fingerprint
        _ = saveServiceLearningSnapshot(source: .autoDrumLock)
    }

    func clearServiceLearningStatusMessage() {
        lastServiceLearningSaveMessage = nil
    }

    // MARK: - Private

    func resolvedServiceLearningSongTitle() -> String {
        if let setlistTitle = currentSetlistSongTitle, !setlistTitle.isEmpty {
            return setlistTitle
        }
        if !payload.sessionName.isEmpty, payload.sessionName != String(localized: "Live Session") {
            return payload.sessionName
        }
        if let symbol = payload.liveChordSymbol, !symbol.isEmpty {
            return String(localized: "Live — \(symbol)")
        }
        return String(localized: "Untitled song")
    }

    func chordsForServiceLearningCapture() -> [ChordEntry] {
        let formal = sortedChords
        if !formal.isEmpty { return formal }

        var orderedSymbols: [String] = []
        for segment in payload.liveRingSegments {
            for symbol in segment where !symbol.isEmpty {
                if orderedSymbols.last != symbol {
                    orderedSymbols.append(symbol)
                }
            }
        }
        for symbol in payload.freestyleChordSymbols where !symbol.isEmpty {
            if orderedSymbols.last != symbol {
                orderedSymbols.append(symbol)
            }
        }
        return orderedSymbols.enumerated().map { index, symbol in
            ChordEntry.freestyle(symbol: symbol, order: index)
        }
    }
}
#endif
