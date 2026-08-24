//
//  SessionViewModel+MacSoloAccompaniment.swift
//  Chordyx
//
//  Mac: listen → confirm tempo/style → steady drum loop (no chord-reactive beat).
//

#if os(macOS) || os(iOS)
import Foundation
import Combine

private enum HostLiveGrooveSyncCache {
    static var lastPublishedSignature = ""
}

extension SessionViewModel {
    var soloAccompanimentAvailable: Bool {
        guard canDriveSession, isInSession else { return false }
        return PlatformDevice.canHostSoloAccompaniment
    }

    var soloDrumsWaitingForTempo: Bool {
        soloAccompanimentEnabled && (soloDrumPhase == .listening || soloDrumPhase == .awaitingConfirmation)
    }

    var soloDrumsAwaitingConfirmation: Bool {
        soloDrumPhase == .awaitingConfirmation && soloPendingProposal != nil
    }

    var soloDrumsAwaitingTempoShift: Bool {
        soloDrumPhase == .awaitingTempoShiftConfirmation && soloProposedTempoShiftBPM != nil
    }

    var detectedLiveBPM: Double? {
        soloLockedBPM ?? soloPendingProposal?.bpm ?? livePerformanceFusion.estimatedBPM
    }

    var detectedTempoConfidence: Double {
        soloPendingProposal?.tempoConfidence ?? livePerformanceFusion.tempoConfidence
    }

    var detectedLiveStyle: LiveMusicStyle {
        soloPendingProposal?.style ?? livePerformanceFusion.detectedStyle
    }

    var detectedStyleConfidence: Double {
        soloPendingProposal?.styleConfidence ?? livePerformanceFusion.styleConfidence
    }

    var suggestedDrumPattern: DrumPattern? {
        soloPendingProposal?.pattern ?? livePerformanceFusion.suggestedPattern
    }

    var liveSyncopationIndex: Double {
        livePerformanceFusion.syncopationIndex
    }

    var liveChordChangesPerMinute: Double {
        livePerformanceFusion.chordChangesPerMinute
    }

    var detectedClaveOrientation: ClaveOrientation {
        livePerformanceFusion.detectedClave
    }

    var liveMontunoStrength: Double {
        livePerformanceFusion.montunoStrength
    }

    var matchedRhythmPatternLabel: String? {
        livePerformanceFusion.matchedRhythmPatternLabel
    }

    var detectedGlobalGenre: GlobalMusicGenre? {
        livePerformanceFusion.detectedGlobalGenre
    }

    var detectedGlobalGenreConfidence: Double {
        livePerformanceFusion.detectedGlobalGenreConfidence
    }

    var globalGenreAlternatives: [GlobalGenreCandidate] {
        livePerformanceFusion.globalGenreAnalysis.alternatives
    }

    var primaryGenreDisplayLabel: String {
        if let genre = detectedGlobalGenre, detectedGlobalGenreConfidence >= 0.28 {
            return genre.label
        }
        return detectedLiveStyle.label
    }

    var primaryGenreDisplaySubtitle: String {
        if detectedGlobalGenre != nil, detectedGlobalGenreConfidence >= 0.28 {
            return livePerformanceFusion.globalGenreAnalysis.displaySubtitle
        }
        if detectedLiveStyle != .unknown {
            switch detectedLiveStyle.category {
            case .latin: return String(localized: "Latin / Caribbean groove")
            case .urban: return String(localized: "Urban groove")
            case .world: return String(localized: "World groove")
            case .worship: return String(localized: "Worship groove")
            case .jazzBlues: return String(localized: "Jazz / blues groove")
            case .popRock: return String(localized: "Groove family")
            }
        }
        return ""
    }

    var primaryTempoSource: PerformanceAnalysisSource {
        livePerformanceFusion.primaryTempoSource
    }

    var primaryStyleSource: PerformanceAnalysisSource {
        livePerformanceFusion.primaryStyleSource
    }

    var midiTempoConfidence: Double {
        livePerformanceFusion.midiTempoConfidence
    }

    var audioTempoConfidence: Double {
        livePerformanceFusion.audioTempoConfidence
    }

    var audioInputLevel: Float {
        livePerformanceFusion.audioInputLevel
    }

    var isAudioAIListening: Bool {
        livePerformanceFusion.isAudioListening
    }

    var audioAILastError: String? {
        livePerformanceFusion.audioLastError
    }

    var availableAudioInputDevices: [AudioInputDevice] {
        livePerformanceFusion.availableAudioInputDevices
    }

    var isSoloDrumGroovePlaying: Bool {
        drumAccompaniment.isPlaying && soloTempoLocked
    }

    var isSoloStyleLearningActive: Bool {
        soloAccompanimentEnabled && soloTempoLocked && livePerformanceFusion.isTracking
    }

    var soloUsesSampleDrumKit: Bool {
        drumAccompaniment.usesSampleDrumKit
    }

    var soloDrumSoundSourceLabel: String {
        drumAccompaniment.soundSourceLabel
    }

    var soloDrumSoundSourceKind: DrumSoundSourceKind {
        drumAccompaniment.soundSourceSelection.kind
    }

    var soloDrumAvailableAudioUnits: [DrumAUComponentRef] {
        drumAccompaniment.availableAudioUnits
    }

    var soloDrumSoundSourceError: String? {
        drumAccompaniment.soundSourceError
    }

    var isSoloDrumSoundSourceLoading: Bool {
        drumAccompaniment.isLoadingSoundSource
    }

    func refreshDrumAudioUnits() {
        drumAccompaniment.refreshAvailableAudioUnits()
    }

    func setSoloDrumSoundSourceKind(_ kind: DrumSoundSourceKind) {
        Task {
            var selection = drumAccompaniment.soundSourceSelection
            selection.kind = kind
            await drumAccompaniment.applySoundSourceSelection(selection)
        }
    }

    func setSoloDrumAudioUnit(_ component: DrumAUComponentRef?) {
        Task {
            var selection = drumAccompaniment.soundSourceSelection
            selection.kind = .audioUnit
            selection.audioUnit = component
            await drumAccompaniment.applySoundSourceSelection(selection)
        }
    }

    func importSoloDrumSoundFont(from url: URL) {
        Task {
            await drumAccompaniment.importSoundFont(from: url)
        }
    }

    /// 0…1 progress while the app listens before drums enter (auto) or ask for confirmation.
    var soloDrumsJoinProgress: Double {
        guard soloAccompanimentEnabled, soloDrumPhase == .listening else {
            return soloDrumPhase == .playing ? 1 : 0
        }
        guard livePerformanceFusion.estimatedBPM != nil else { return 0 }
        let needed = soloAutoAccompanyLockSampleTarget
        let sampleProgress = Double(soloTempoLockSamples.count) / Double(max(1, needed))
        let confProgress = min(1, livePerformanceFusion.tempoConfidence / Self.soloTempoLockConfidenceThreshold)
        return min(1, max(sampleProgress, confProgress * 0.85))
    }

    /// Status line for Auto accompany / listening UI.
    var soloAutoAccompanyStatusLine: String {
        if !soloAccompanimentEnabled {
            return String(localized: "Turn on Solo Drums, then play piano — drums follow you.")
        }
        switch soloDrumPhase {
        case .listening:
            if let bpm = livePerformanceFusion.estimatedBPM {
                let conf = Int((livePerformanceFusion.tempoConfidence * 100).rounded())
                if ChordyxPreferences.soloAutoAccompany {
                    return String(localized: "Hearing \(TempoMarking.caption(for: bpm)) · \(conf)% — locking…")
                }
                return String(localized: "Hearing \(TempoMarking.caption(for: bpm)) · \(conf)%")
            }
            return ChordyxPreferences.soloAutoAccompany
                ? String(localized: "Play the piano — listening for your tempo…")
                : String(localized: "Listening… play a steady groove")
        case .awaitingConfirmation:
            if let proposal = soloPendingProposal {
                return String(localized: "Ready at \(TempoMarking.caption(for: proposal.bpm)) — confirm to start")
            }
            return String(localized: "Ready to start")
        case .playing:
            if let bpm = soloLockedBPM {
                if soloBeatFollowEnabled {
                    return String(localized: "Accompanying at \(TempoMarking.caption(for: bpm)) · following you")
                }
                return String(localized: "Accompanying at \(TempoMarking.caption(for: bpm))")
            }
            return String(localized: "Accompanying")
        case .awaitingTempoShiftConfirmation:
            if let bpm = soloProposedTempoShiftBPM {
                return String(localized: "Tempo drift — switch to \(TempoMarking.caption(for: bpm))?")
            }
            return String(localized: "Tempo drift detected")
        case .idle:
            return String(localized: "Solo Drums idle")
        }
    }

    private var soloAutoAccompanyLockSampleTarget: Int {
        if ChordyxPreferences.soloAutoAccompany,
           livePerformanceFusion.primaryTempoSource == .midi || livePerformanceFusion.primaryTempoSource == .fused,
           livePerformanceFusion.tempoConfidence >= Self.soloAutoAccompanyMIDIConfidence {
            return Self.soloAutoAccompanyLockSampleCount
        }
        return Self.soloTempoLockSampleCount
    }

    func setSoloAutoAccompanyEnabled(_ enabled: Bool) {
        ChordyxPreferences.soloAutoAccompany = enabled
        if enabled {
            setSoloBeatFollowEnabled(true)
            if soloAccompanimentEnabled, soloDrumPhase == .idle || soloDrumPhase == .listening {
                // Already listening — keep going.
            } else if !soloAccompanimentEnabled {
                setSoloAccompanimentEnabled(true)
            }
        }
    }

    func trackLivePerformanceFromPiano(activeNotes: [Int]) {
        guard soloAccompanimentAvailable else { return }

        if soloAccompanimentEnabled, !activeNotes.isEmpty, soloPlayingSince == nil {
            soloPlayingSince = Date().timeIntervalSince1970
        }

        // Only count newly struck pitches as rhythm onsets — note-offs were
        // poisoning tempo toward half-time / irregular gaps.
        let notesAdded = activeNotes.contains { !lastTrackedPianoNotes.contains($0) }
        let chordChanged = payload.liveChordSymbol != lastTrackedChordSymbol
        if soloTempoLocked {
            let now = Date().timeIntervalSince1970
            // Keep feeding note onsets into the drift analyzer so half-time locks can recover.
            if notesAdded || chordChanged || (now - lastStyleLearnTime >= Self.soloStyleLearnThrottle) {
                if chordChanged || notesAdded {
                    lastStyleLearnTime = now
                }
                livePerformanceFusion.registerMIDIPerformance(
                    chordSymbol: payload.liveChordSymbol,
                    activeNoteCount: activeNotes.count,
                    newNotesAdded: notesAdded || chordChanged
                )
            }
            if soloPendingBeatFollowBPM != nil || chordChanged || notesAdded {
                evaluateSoloTempoDriftWhilePlaying()
            }
        } else if soloAccompanimentEnabled {
            livePerformanceFusion.registerMIDIPerformance(
                chordSymbol: payload.liveChordSymbol,
                activeNoteCount: activeNotes.count,
                newNotesAdded: notesAdded
            )
            refreshSuggestedSoloInstrumentCategory()
        }
        lastTrackedPianoNotes = activeNotes
        lastTrackedChordSymbol = payload.liveChordSymbol

        if soloTempoLocked {
            updateAutoBandLiveChord(payload.liveChordSymbol)
        }

        guard soloAccompanimentEnabled, soloDrumPhase == .listening else { return }
        evaluateSoloDrumListening()
    }

    func setSoloAccompanimentEnabled(_ enabled: Bool) {
        #if os(iOS)
        // iPhone remains guest-only for Solo host — multi-engine AVAudioSession is riskier there.
        if PlatformDevice.isPhone {
            if enabled {
                soloAccompanimentEnabled = false
            }
            return
        }
        #endif
        guard !enabled || soloAccompanimentAvailable else {
            soloAccompanimentEnabled = false
            return
        }
        soloAccompanimentEnabled = enabled
        livePerformanceFusion.audioAIEnabled = soloAudioAIEnabled
        if enabled {
            #if os(iOS)
            // Defer engine / session work so the toggle animation, Live Activity, and layout finish first.
            Task { @MainActor [weak self] in
                await Task.yield()
                try? await Task.sleep(for: .milliseconds(80))
                guard let self, self.soloAccompanimentEnabled else { return }
                self.beginSoloDrumListening()
                self.syncHostLiveGrooveToPayload(force: true)
                self.refreshSessionAudioPolicy()
            }
            #else
            beginSoloDrumListening()
            syncHostLiveGrooveToPayload(force: true)
            refreshSessionAudioPolicy()
            #endif
        } else {
            livePerformanceFusion.stopAudioAI()
            stopAutoBandAccompaniment(force: true)
            drumAccompaniment.unfreezeGroove()
            drumAccompaniment.stop(force: true)
            resetSoloTempoLock()
            soloDrumPhase = .idle
            soloPendingProposal = nil
            soloProposedTempoShiftBPM = nil
            soloDrumsMetronomeArmed = false
            applySoloDrumsMetronomePolicy()
            syncHostLiveGrooveToPayload(force: true)
            refreshSessionAudioPolicy()
        }
    }

    func setSoloAudioAIEnabled(_ enabled: Bool) {
        soloAudioAIEnabled = enabled
        guard soloAccompanimentEnabled else {
            if !enabled {
                livePerformanceFusion.stopAudioAI()
            }
            return
        }
        // Let the toggle animation finish before touching AVAudioSession / a second engine.
        Task { @MainActor in
            await Task.yield()
            refreshSoloAudioCapturePolicy()
        }
    }

    func refreshAudioInputDevices() {
        livePerformanceFusion.refreshAudioDevices()
    }

    func selectAudioInputDevice(_ device: AudioInputDevice?) {
        livePerformanceFusion.selectAudioInputDevice(device)
    }

    func setSoloAutoStyleEnabled(_ enabled: Bool) {
        soloAutoStyleEnabled = enabled
        if enabled, soloDrumPhase == .listening {
            applyAutoDetectedStyleIfNeeded()
        }
    }

    func setSoloDrumInstrumentCategory(_ category: SoloDrumInstrumentCategory, userPicked: Bool = true) {
        if userPicked {
            soloInstrumentCategoryUserPicked = true
            if soloSuggestedInstrumentCategory == category {
                soloSuggestedInstrumentCategory = nil
            }
        }
        guard category != soloDrumInstrumentCategory else {
            drumAccompaniment.setInstrumentCategory(category)
            return
        }
        soloDrumInstrumentCategory = category
        drumAccompaniment.setInstrumentCategory(category)
        syncHostLiveGrooveToPayload(force: true)
    }

    /// Instant A/B audition between two instrument families without stopping the loop.
    func swapSoloDrumInstrumentCategoryAB() {
        let previous = soloDrumInstrumentCategory
        setSoloDrumInstrumentCategory(soloDrumInstrumentCategoryB, userPicked: true)
        soloDrumInstrumentCategoryB = previous
    }

    func applySuggestedSoloInstrumentCategory() {
        guard let suggested = soloSuggestedInstrumentCategory else { return }
        setSoloDrumInstrumentCategory(suggested, userPicked: true)
        soloSuggestedInstrumentCategory = nil
    }

    func setSoloBeatFollowEnabled(_ enabled: Bool) {
        soloBeatFollowEnabled = enabled
        SoloDrumBeatFollowStore.save(enabled)
        if enabled {
            soloTempoDriftSamples.removeAll()
            soloBeatFollowEMA = soloLockedBPM
            soloPendingBeatFollowBPM = nil
        } else {
            soloPendingBeatFollowBPM = nil
            soloBeatFollowEMA = nil
        }
    }

    func setSoloDrumCountInBars(_ bars: Int) {
        soloDrumCountInBars = min(2, max(0, bars))
    }

    func applySuggestedDrumPattern() {
        guard let pattern = suggestedDrumPattern else { return }
        setSoloDrumPattern(pattern)
    }

    func setSoloDrumPattern(_ pattern: DrumPattern) {
        let changed = pattern != soloDrumPattern
        soloDrumPattern = pattern
        soloDrumLoopPack = DrumMIDILoopPack.pack(for: pattern)
        drumAccompaniment.setLoopPack(soloDrumLoopPack)
        guard changed, soloAccompanimentEnabled, soloTempoLocked else { return }
        // Keep the frozen groove clock — swap feel on the same grid so metronome stays locked.
        activeLearnedDrumPattern = nil
        drumAccompaniment.setLearnedPattern(nil, force: true)
        drumAccompaniment.setPattern(pattern, force: true)
        applySoloDrumLoopSettingsToEngine()
        if payload.isMetronomePlaying {
            alignMetronomeEpochToSoloGroove()
            applyMetronome()
        }
        syncHostLiveGrooveToPayload(force: true)
    }

    func setSoloDrumVolume(_ volume: Float) {
        soloDrumVolume = volume
        // Apply even during preview / pre-lock so the slider always matches what you hear.
        drumAccompaniment.volume = volume
    }

    func setSoloDrumArrangeMode(_ mode: DrumArrangeMode) {
        soloDrumArrangeMode = mode
        drumAccompaniment.setArrangeMode(mode)
    }

    func setSoloDrumLoopPack(_ pack: DrumMIDILoopPack) {
        soloDrumLoopPack = pack
        drumAccompaniment.setLoopPack(pack)
    }

    func setSoloDrumHybridLayers(_ enabled: Bool) {
        soloDrumHybridLayers = enabled
        drumAccompaniment.setHybridMIDILayers(enabled)
    }

    var soloCurrentPhraseLabel: String {
        drumAccompaniment.currentPhraseKind.shortLabel
    }

    func refreshSoloUserMIDILoops() {
        soloUserMIDILoops = UserMIDIDrumLoopStore.load()
    }

    /// Capture the current arranged MIDI feel as a reusable tempo-native loop.
    func saveCurrentSoloMIDILoop(named name: String, bars: Int = 4) {
        let loop = drumAccompaniment.captureUserMIDILoop(
            displayName: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? String(localized: "My drum loop")
                : name,
            bars: bars
        )
        UserMIDIDrumLoopStore.upsert(loop)
        refreshSoloUserMIDILoops()
        selectUserMIDIDrumLoop(loop.id)
    }

    func selectUserMIDIDrumLoop(_ id: UUID?) {
        activeUserMIDIDrumLoopID = id
        if let id, let loop = soloUserMIDILoops.first(where: { $0.id == id }) {
            drumAccompaniment.setUserMIDILoop(loop)
        } else {
            drumAccompaniment.setUserMIDILoop(nil)
        }
    }

    func deleteUserMIDIDrumLoop(_ id: UUID) {
        UserMIDIDrumLoopStore.delete(id)
        if activeUserMIDIDrumLoopID == id {
            activeUserMIDIDrumLoopID = nil
            drumAccompaniment.setUserMIDILoop(nil)
        }
        refreshSoloUserMIDILoops()
    }

    func applySoloDrumLoopSettingsToEngine() {
        drumAccompaniment.setArrangeMode(soloDrumArrangeMode)
        drumAccompaniment.setLoopPack(soloDrumLoopPack)
        drumAccompaniment.setHybridMIDILayers(soloDrumHybridLayers)
        drumAccompaniment.setInstrumentCategory(soloDrumInstrumentCategory)
        if let id = activeUserMIDIDrumLoopID,
           let loop = soloUserMIDILoops.first(where: { $0.id == id }) {
            drumAccompaniment.setUserMIDILoop(loop)
        } else {
            drumAccompaniment.setUserMIDILoop(nil)
        }
    }

    func relearnSoloTempo() {
        guard soloAccompanimentEnabled else { return }
        stopAutoBandAccompaniment(force: true)
        drumAccompaniment.unfreezeGroove()
        drumAccompaniment.stop(force: true)
        resetSoloTempoLock()
        beginSoloDrumListening()
    }

    /// Manual tempo from the Solo Drums panel (no need to leave for the metronome tab).
    func setSoloManualTempo(_ bpm: Double) {
        guard soloAccompanimentEnabled else { return }
        if soloProposedTempoShiftBPM != nil {
            soloProposedTempoShiftBPM = nil
            soloTempoDriftSamples.removeAll()
            if soloTempoLocked {
                soloDrumPhase = .playing
            }
            livePerformanceFusion.resetDriftAnalysis()
        }
        setTempo(bpm)
        if soloTempoLocked {
            syncHostLiveGrooveToPayload(force: true)
        }
    }

    /// Lock and start drums immediately at the panel tempo (skip listen/confirm).
    func startSoloDrumsAtManualTempo() {
        guard soloAccompanimentEnabled, !soloTempoLocked else { return }
        let bpm = min(max(payload.tempoBPM, Self.minBPM), Self.maxBPM)
        soloPendingProposal = nil
        soloProposedTempoShiftBPM = nil
        soloTempoLockSamples.removeAll()
        soloTempoDriftSamples.removeAll()
        if !autoBandMode.includesDrums {
            autoBandMode = autoBandMode.includesBass ? .fullBand : .drumsOnly
        }
        lockSoloDrums(at: bpm, pattern: soloDrumPattern)
        soloDrumPhase = .playing
        refreshSoloAudioCapturePolicy()
        syncHostLiveGrooveToPayload(force: true)
    }

    /// User asks for an immediate proposal from whatever the app has heard so far.
    func proposeSoloDrumDetectionNow() {
        guard soloAccompanimentEnabled, soloDrumPhase == .listening else { return }
        let bpm = livePerformanceFusion.estimatedBPM ?? Double(payload.tempoBPM)
        let conf = max(livePerformanceFusion.tempoConfidence, livePerformanceFusion.estimatedBPM == nil ? 0.15 : 0)
        presentSoloDrumProposal(bpm: bpm, tempoConfidence: conf)
    }

    func confirmSoloDrumGroove() {
        guard let proposal = soloPendingProposal else { return }
        soloDrumPattern = proposal.pattern
        soloPendingProposal = nil
        if !autoBandMode.includesDrums {
            // "Yes, start drums" must actually include drums — upgrade bass-only / off.
            autoBandMode = autoBandMode.includesBass ? .fullBand : .drumsOnly
        }
        lockSoloDrums(at: proposal.bpm, pattern: proposal.pattern)
        soloDrumPhase = .playing
        refreshSoloAudioCapturePolicy()
        syncHostLiveGrooveToPayload(force: true)
    }

    func rejectSoloDrumGroove() {
        soloPendingProposal = nil
        soloTempoLockSamples.removeAll()
        soloPlayingSince = Date().timeIntervalSince1970
        soloDrumPhase = .listening
        refreshSoloAudioCapturePolicy()
        syncHostLiveGrooveToPayload(force: true)
    }

    func confirmSoloTempoShift() {
        guard let bpm = soloProposedTempoShiftBPM else { return }
        soloProposedTempoShiftBPM = nil
        soloTempoDriftSamples.removeAll()
        soloPendingBeatFollowBPM = nil
        soloBeatFollowEMA = bpm
        soloDrumPhase = .playing
        soloLockedBPM = bpm
        payload.tempoBPM = bpm
        livePerformanceFusion.resetDriftAnalysis()
        drumAccompaniment.retimeLockedGroove(to: bpm)
        if soloBassEnabled, autoBandMode.includesBass {
            if bassAccompaniment.isPlaying {
                bassAccompaniment.retimeLockedGroove(to: bpm)
            } else {
                startBassAccompanimentIfNeeded(at: bpm)
            }
        }
        if payload.isMetronomePlaying {
            alignMetronomeEpochToSoloGroove()
            applyMetronome()
        }
        refreshSoloAudioCapturePolicy()
        syncHostLiveGrooveToPayload(force: true)
    }

    func rejectSoloTempoShift() {
        soloProposedTempoShiftBPM = nil
        soloTempoDriftSamples.removeAll()
        soloDrumPhase = .playing
        livePerformanceFusion.resetDriftAnalysis()
        refreshSoloAudioCapturePolicy()
        syncHostLiveGrooveToPayload(force: true)
    }

    func stopSoloAccompaniment() {
        saveSoloGrooveResumeSnapshotIfNeeded()
        groovePreviewTask?.cancel()
        groovePreviewTask = nil
        soloAccompanimentEnabled = false
        stopAutoBandAccompaniment(force: true)
        drumAccompaniment.unfreezeGroove()
        drumAccompaniment.stop(force: true)
        livePerformanceFusion.reset()
        resetSoloTempoLock()
        soloDrumPhase = .idle
        soloPendingProposal = nil
        soloProposedTempoShiftBPM = nil
        lastTrackedPianoNotes.removeAll()
        lastTrackedChordSymbol = nil
        applySoloDrumsMetronomePolicy()
        syncHostLiveGrooveToPayload(force: true)
    }

    func applySoloDrumsMetronomePolicy() {
        let drumsPlaying = soloAccompanimentEnabled && soloTempoLocked && isSoloDrumGroovePlaying
        if drumsPlaying {
            // Never auto-start the click with Solo Drums — only phase-lock if the user
            // already turned the metronome on (or turns it on later via toggleMetronome).
            if payload.isMetronomePlaying {
                soloDrumsMetronomeArmed = true
                alignMetronomeEpochToSoloGroove()
                applyMetronome()
            } else {
                soloDrumsMetronomeArmed = false
            }
            refreshMetronomeAudioPolicy()
        } else {
            soloDrumsMetronomeArmed = false
            refreshMetronomeAudioPolicy()
        }
    }

    /// User path: turn metronome on and lock its bar phase to the drum groove.
    func startSyncedMetronomeWithSoloDrums() {
        guard canDriveSession else { return }
        if let locked = soloLockedBPM {
            payload.tempoBPM = locked
        }
        // Solo Drums patterns are authored on a quarter-note / 16th grid.
        payload.beatUnit = 4
        soloDrumsMetronomeArmed = true
        alignMetronomeEpochToSoloGroove()
        payload.isMetronomePlaying = true
        payload.isCountingIn = false
        payload.countInStartEpoch = nil
        refreshMetronomeAudioPolicy()
        applyMetronome()
        sync()
    }

    /// Maps drum groove wall-clock anchor → metronome start epoch (shared beat grid).
    func alignMetronomeEpochToSoloGroove() {
        if let locked = soloLockedBPM {
            payload.tempoBPM = locked
        }
        // Drum groove always advances in quarter-note BPM; force click math to match.
        payload.beatUnit = 4
        if let epoch = drumAccompaniment.grooveStartUnixEpoch {
            payload.metronomeStartEpoch = epoch
        } else {
            payload.metronomeStartEpoch = Date().timeIntervalSince1970
        }
    }

    func refreshSoloAudioCapturePolicy() {
        // Keep the mic off while drums are playing — matches the UI copy and avoids
        // feedback / dual-engine freezes on iPhone. Auto-key chroma can still listen.
        let wantSoloMic = soloAccompanimentEnabled
            && soloAudioAIEnabled
            && soloDrumPhase == .listening
        let wantKeyMic = payload.autoDetectKey && canDriveSession && isInSession

        livePerformanceFusion.audioAIEnabled = soloAudioAIEnabled || wantKeyMic
        livePerformanceFusion.setAudioKeyAssistEnabled(wantKeyMic)

        if wantSoloMic || wantKeyMic {
            if !livePerformanceFusion.isAudioListening {
                livePerformanceFusion.startAudioAI()
            }
        } else {
            livePerformanceFusion.stopAllAudioCapture()
        }
        refreshSessionAudioPolicy()
    }

    func evaluateSoloAccompanimentFromFusion() {
        guard soloAccompanimentEnabled else { return }
        if soloDrumPhase == .listening {
            evaluateSoloDrumListening()
        } else if soloDrumPhase == .playing {
            evaluateSoloTempoDriftWhilePlaying()
        }
    }

    private func beginSoloDrumListening() {
        resetSoloTempoLock()
        soloPendingProposal = nil
        soloProposedTempoShiftBPM = nil
        soloDrumPhase = .listening
        soloDrumsMetronomeArmed = false
        if ChordyxPreferences.soloAutoAccompany {
            setSoloBeatFollowEnabled(true)
        }
        stopHostMetronomeForSoloListening()
        ensureSoloAccompanimentRunning()
    }

    /// Tempo learning never auto-starts the click — the user turns it on from the metronome control.
    private func stopHostMetronomeForSoloListening() {
        guard canDriveSession else { return }
        guard payload.isMetronomePlaying || payload.isCountingIn else { return }
        payload.isMetronomePlaying = false
        payload.isCountingIn = false
        payload.metronomeStartEpoch = nil
        payload.countInStartEpoch = nil
        refreshMetronomeAudioPolicy()
        sync()
    }

    private func evaluateSoloDrumListening() {
        guard soloAccompanimentEnabled, soloDrumPhase == .listening else { return }
        guard soloAccompanimentAvailable else { return }

        applyAutoDetectedStyleIfNeeded()
        tryFallbackTempoProposal()

        guard let bpm = livePerformanceFusion.estimatedBPM else {
            soloTempoLockSamples.removeAll()
            return
        }

        let confidence = livePerformanceFusion.tempoConfidence
        let confGate = ChordyxPreferences.soloAutoAccompany
            ? min(Self.soloTempoLockConfidenceThreshold, 0.32)
            : Self.soloTempoLockConfidenceThreshold
        guard confidence >= confGate else {
            soloTempoLockSamples.removeAll()
            return
        }

        soloTempoLockSamples.append((bpm: bpm, confidence: confidence))
        if soloTempoLockSamples.count > 10 {
            soloTempoLockSamples.removeFirst(soloTempoLockSamples.count - 10)
        }

        let needed = soloAutoAccompanyLockSampleTarget
        guard soloTempoLockSamples.count >= needed else { return }

        let recent = Array(soloTempoLockSamples.suffix(needed))
        let bpms = recent.map(\.bpm)
        guard let minBPM = bpms.min(), let maxBPM = bpms.max() else { return }
        let maxSpread = ChordyxPreferences.soloAutoAccompany ? Self.soloTempoLockMaxSpread + 1.5 : Self.soloTempoLockMaxSpread
        guard maxBPM - minBPM <= maxSpread else {
            soloTempoLockSamples.removeFirst()
            return
        }

        let avgConf = recent.map(\.confidence).reduce(0, +) / Double(recent.count)
        guard avgConf >= confGate else { return }

        let averaged = bpms.reduce(0, +) / Double(bpms.count)
        presentSoloDrumProposal(bpm: averaged, tempoConfidence: avgConf)
    }

    private func tryFallbackTempoProposal() {
        guard soloDrumPhase == .listening else { return }
        guard let started = soloPlayingSince else { return }
        let delay = ChordyxPreferences.soloAutoAccompany
            ? min(Self.soloTempoProposalFallbackDelay, 9)
            : Self.soloTempoProposalFallbackDelay
        guard Date().timeIntervalSince1970 - started >= delay else { return }
        guard livePerformanceFusion.isTracking else { return }

        let fallbackConf = ChordyxPreferences.soloAutoAccompany ? 0.22 : 0.24
        if let bpm = livePerformanceFusion.estimatedBPM,
           livePerformanceFusion.tempoConfidence >= fallbackConf {
            presentSoloDrumProposal(
                bpm: bpm,
                tempoConfidence: livePerformanceFusion.tempoConfidence
            )
        }
    }

    private func presentSoloDrumProposal(bpm: Double, tempoConfidence: Double) {
        let rounded = SoloDrumPolish.roundHalfBPM(bpm)
        let style = resolvedStyleForProposal()
        let pattern = resolvedPatternForProposal(style: style)
        refreshSuggestedSoloInstrumentCategory()
        let proposal = SoloDrumGrooveProposal(
            bpm: rounded,
            style: style,
            pattern: pattern,
            tempoConfidence: tempoConfidence,
            styleConfidence: livePerformanceFusion.styleConfidence,
            globalGenreID: livePerformanceFusion.detectedGlobalGenre?.id,
            globalGenreLabel: livePerformanceFusion.detectedGlobalGenre?.label,
            globalGenreRegion: livePerformanceFusion.globalGenreAnalysis.region
        )
        guard proposal != soloPendingProposal else { return }
        soloPendingProposal = proposal
        soloTempoLockSamples.removeAll()

        // Auto accompany: lock immediately — church musicians shouldn't tap Yes mid-song.
        if ChordyxPreferences.soloAutoAccompany {
            confirmSoloDrumGroove()
            return
        }

        soloDrumPhase = .awaitingConfirmation
        syncHostLiveGrooveToPayload(force: true)
    }

    private func resolvedStyleForProposal() -> LiveMusicStyle {
        if soloAutoStyleEnabled,
           let global = livePerformanceFusion.detectedGlobalGenre,
           livePerformanceFusion.detectedGlobalGenreConfidence >= 0.32 {
            return global.closestGroove
        }
        if soloAutoStyleEnabled,
           livePerformanceFusion.detectedStyle != .unknown,
           livePerformanceFusion.styleConfidence >= 0.28 {
            return livePerformanceFusion.detectedStyle
        }
        return .unknown
    }

    private func resolvedPatternForProposal(style: LiveMusicStyle) -> DrumPattern {
        if let fromStyle = style.suggestedDrumPattern {
            return fromStyle
        }
        if let suggested = livePerformanceFusion.suggestedPattern {
            return suggested
        }
        return soloDrumPattern
    }

    private func evaluateSoloTempoDriftWhilePlaying() {
        guard soloDrumPhase == .playing else { return }
        guard soloProposedTempoShiftBPM == nil else { return }
        guard let locked = soloLockedBPM else { return }

        // Flush a queued soft nudge on the next downbeat.
        if let pending = soloPendingBeatFollowBPM {
            if drumAccompaniment.isNearDownbeat() {
                soloPendingBeatFollowBPM = nil
                applyLiveBeatFollowNudge(to: pending)
            }
            return
        }

        // Don't shove tempo during fills / intros — keep the phrase musical.
        if SoloDrumPolish.shouldHoldTempoFollow(during: drumAccompaniment.currentPhraseKind) {
            return
        }

        guard let drift = livePerformanceFusion.driftEstimatedBPM,
              livePerformanceFusion.driftTempoConfidence >= 0.34 else {
            soloTempoDriftSamples.removeAll()
            return
        }

        let smoothed = SoloDrumPolish.emaBPM(
            previous: soloBeatFollowEMA ?? locked,
            sample: drift,
            alpha: ChordyxPreferences.soloAutoAccompany
                ? Self.soloAutoAccompanyEMAAlpha
                : Self.soloBeatFollowEMAAlpha
        )
        soloBeatFollowEMA = smoothed

        let delta = abs(smoothed - locked)
        let sampleFloor: Double = {
            if !soloBeatFollowEnabled { return Self.soloTempoDriftMinDelta }
            if ChordyxPreferences.soloAutoAccompany { return Self.soloAutoAccompanyFollowSoftDelta }
            return Self.soloTempoFollowSoftDelta
        }()
        guard delta >= sampleFloor else {
            soloTempoDriftSamples.removeAll()
            return
        }

        soloTempoDriftSamples.append((bpm: smoothed, confidence: livePerformanceFusion.driftTempoConfidence))
        if soloTempoDriftSamples.count > 8 {
            soloTempoDriftSamples.removeFirst(soloTempoDriftSamples.count - 8)
        }
        let driftNeeded = ChordyxPreferences.soloAutoAccompany
            ? Self.soloAutoAccompanyDriftSampleCount
            : Self.soloTempoDriftSampleCount
        guard soloTempoDriftSamples.count >= driftNeeded else { return }

        let bpms = soloTempoDriftSamples.map(\.bpm)
        guard let minBPM = bpms.min(), let maxBPM = bpms.max(), maxBPM - minBPM <= 8 else {
            soloTempoDriftSamples.removeFirst()
            return
        }

        let averaged = bpms.reduce(0, +) / Double(bpms.count)
        let rounded = SoloDrumPolish.roundHalfBPM(averaged)
        let averagedDelta = abs(rounded - locked)

        let hardDelta = ChordyxPreferences.soloAutoAccompany
            ? Self.soloAutoAccompanyFollowHardDelta
            : Self.soloTempoFollowHardDelta

        // Professional live follow: small stable nudges apply on the next downbeat.
        if soloBeatFollowEnabled, averagedDelta < hardDelta {
            soloTempoDriftSamples.removeAll()
            if drumAccompaniment.isNearDownbeat() {
                applyLiveBeatFollowNudge(to: rounded)
            } else {
                soloPendingBeatFollowBPM = rounded
            }
            return
        }

        // Auto accompany: absorb medium–large drifts without interrupting the pianist.
        if ChordyxPreferences.soloAutoAccompany,
           soloBeatFollowEnabled,
           averagedDelta < 14,
           livePerformanceFusion.driftTempoConfidence >= 0.38 {
            soloTempoDriftSamples.removeAll()
            if drumAccompaniment.isNearDownbeat() {
                applyLiveBeatFollowNudge(to: rounded)
            } else {
                soloPendingBeatFollowBPM = rounded
            }
            return
        }

        // Large shift (or beat-follow off): ask the host before retiming.
        guard averagedDelta >= Self.soloTempoDriftMinDelta else {
            soloTempoDriftSamples.removeAll()
            return
        }
        soloProposedTempoShiftBPM = rounded
        soloDrumPhase = .awaitingTempoShiftConfirmation
        soloTempoDriftSamples.removeAll()
        syncHostLiveGrooveToPayload(force: true)
    }

    /// Smooth locked-groove retime for small live tempo drift (no confirmation card).
    private func applyLiveBeatFollowNudge(to bpm: Double) {
        guard soloTempoLocked, soloDrumPhase == .playing else { return }
        let clamped = min(max(bpm, 48), 200)
        let rounded = SoloDrumPolish.roundHalfBPM(clamped)
        guard let locked = soloLockedBPM, abs(rounded - locked) >= 0.5 else { return }

        soloLockedBPM = rounded
        soloBeatFollowEMA = rounded
        payload.tempoBPM = rounded
        drumAccompaniment.retimeLockedGroove(to: rounded)
        if soloBassEnabled, autoBandMode.includesBass {
            if bassAccompaniment.isPlaying {
                bassAccompaniment.retimeLockedGroove(to: rounded)
            } else {
                startBassAccompanimentIfNeeded(at: rounded)
            }
        }
        if payload.isMetronomePlaying {
            alignMetronomeEpochToSoloGroove()
            applyMetronome()
        }
        syncHostLiveGrooveToPayload(force: true)
    }

    func refreshSoloDrumSectionDynamics() {
        guard ChordyxPreferences.sectionDynamicsEnabled,
              soloAccompanimentEnabled,
              soloTempoLocked else {
            drumAccompaniment.dynamicsGain = 1
            return
        }
        drumAccompaniment.dynamicsGain = SoloDrumPolish.sectionDynamicsScale(for: activeSection?.kind)
    }

    /// One-tap service preset: tempo + feel + kit + arrangement.
    func applySoloServicePreset(_ preset: SoloServicePreset, startImmediately: Bool = true) {
        guard canDriveSession else { return }
        if !soloAccompanimentEnabled {
            setSoloAccompanimentEnabled(true)
        }
        setSoloDrumInstrumentCategory(preset.category, userPicked: true)
        setSoloDrumArrangeMode(preset.arrangeMode)
        setSoloDrumPattern(preset.pattern)
        setTempo(preset.bpm)
        if startImmediately, !soloTempoLocked {
            startSoloDrumsAtManualTempo()
        } else if soloTempoLocked {
            lockOrRetimeSolo(at: preset.bpm, pattern: preset.pattern)
        }
        syncHostLiveGrooveToPayload(force: true)
    }

    var customSoloChurchPresets: [CustomSoloChurchPreset] {
        CustomSoloChurchPresetStore.loadAll()
    }

    func refreshCustomSoloChurchPresets() {
        // Trigger observation by touching a published-adjacent flag if needed.
        // Custom presets live in UserDefaults; UI reloads via explicit refresh binding.
        objectWillChangeSendForCustomPresets()
    }

    private func objectWillChangeSendForCustomPresets() {
        objectWillChange.send()
        soloCustomPresetsRevision &+= 1
    }

    /// Save the current Solo setup as a church preset (max 12).
    @discardableResult
    func saveCurrentSoloAsChurchPreset(named name: String) -> CustomSoloChurchPreset? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let bpm = soloLockedBPM ?? payload.tempoBPM
        let preset = CustomSoloChurchPreset(
            label: trimmed,
            bpm: SoloDrumPolish.roundHalfBPM(bpm),
            pattern: soloDrumPattern,
            category: soloDrumInstrumentCategory,
            arrangeMode: soloDrumArrangeMode
        )
        CustomSoloChurchPresetStore.upsert(preset)
        soloCustomPresetsRevision &+= 1
        return preset
    }

    func deleteCustomSoloChurchPreset(_ id: UUID) {
        CustomSoloChurchPresetStore.delete(id: id)
        soloCustomPresetsRevision &+= 1
    }

    func applyCustomSoloChurchPreset(_ preset: CustomSoloChurchPreset, startImmediately: Bool = true) {
        applySoloServicePreset(preset.asServicePreset, startImmediately: startImmediately)
    }

    /// Soft / Full / Build stage cues nudge kit level without leaving the ring.
    func applySoloStageCueDynamics(scale: Float) {
        guard soloAccompanimentEnabled else { return }
        if soloDrumsCueMuted {
            soloDrumsCueMuted = false
            if let previous = soloDrumsVolumeBeforeCueMute {
                soloDrumVolume = previous
                soloDrumsVolumeBeforeCueMute = nil
            }
        }
        let base = max(0.35, min(1.15, soloDrumVolume * scale))
        setSoloDrumVolume(base)
        if ChordyxPreferences.sectionDynamicsEnabled, soloTempoLocked {
            // Keep section dynamics relative — cue is an extra push.
            drumAccompaniment.dynamicsGain = SoloDrumPolish.sectionDynamicsScale(for: activeSection?.kind) * max(0.85, min(1.2, scale))
        }
    }

    func toggleSoloDrumsMutedByCue() {
        guard soloAccompanimentEnabled else { return }
        if soloDrumsCueMuted {
            soloDrumsCueMuted = false
            let restore = soloDrumsVolumeBeforeCueMute ?? 0.72
            soloDrumsVolumeBeforeCueMute = nil
            setSoloDrumVolume(restore)
        } else {
            soloDrumsCueMuted = true
            soloDrumsVolumeBeforeCueMute = soloDrumVolume
            setSoloDrumVolume(0)
        }
    }

    func saveSoloGrooveResumeSnapshotIfNeeded() {
        guard ChordyxPreferences.rememberSoloGroove,
              soloTempoLocked,
              let bpm = soloLockedBPM else { return }
        SoloGrooveResumeStore.save(
            SoloGrooveResumeSnapshot(
                bpm: bpm,
                patternRaw: soloDrumPattern.rawValue,
                categoryRaw: soloDrumInstrumentCategory.rawValue,
                arrangeModeRaw: soloDrumArrangeMode.rawValue,
                savedAt: Date()
            )
        )
    }

    var soloGrooveResumeSnapshot: SoloGrooveResumeSnapshot? {
        SoloGrooveResumeStore.load()
    }

    /// Resume last locked Solo groove (BPM / feel / kit).
    func resumeLastSoloGroove() {
        guard canDriveSession, let snapshot = SoloGrooveResumeStore.load() else { return }
        if !soloAccompanimentEnabled {
            setSoloAccompanimentEnabled(true)
        }
        setSoloDrumInstrumentCategory(snapshot.category, userPicked: true)
        setSoloDrumArrangeMode(snapshot.arrangeMode)
        setSoloDrumPattern(snapshot.pattern)
        setTempo(snapshot.bpm)
        if soloTempoLocked {
            drumAccompaniment.retimeLockedGroove(to: snapshot.bpm)
            drumAccompaniment.setPattern(snapshot.pattern, force: true)
            applySoloDrumLoopSettingsToEngine()
        } else {
            startSoloDrumsAtManualTempo()
        }
        syncHostLiveGrooveToPayload(force: true)
    }

    /// Setlist / song change: church memory first, else song tempo on locked groove.
    func applySoloGrooveForSetlistSong(_ saved: SavedProgression) {
        guard ChordyxPreferences.autoApplySoloGrooveOnSetlist else { return }
        guard canDriveSession, soloAccompanimentEnabled else { return }

        refreshServiceLearningLibrary()
        let title = saved.name.lowercased()
        if let match = serviceLearningRecords.first(where: {
            $0.songTitle.compare(saved.name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
                || $0.songTitle.lowercased().contains(title)
                || title.contains($0.songTitle.lowercased())
        }) {
            // Tempo + pattern only — chords already come from the setlist song.
            soloDrumPattern = match.drumPattern
            payload.tempoBPM = match.tempoBPM
            if soloTempoLocked {
                drumAccompaniment.setPattern(match.drumPattern, force: true)
                drumAccompaniment.retimeLockedGroove(to: match.tempoBPM)
                soloLockedBPM = match.tempoBPM
                if payload.isMetronomePlaying {
                    alignMetronomeEpochToSoloGroove()
                    applyMetronome()
                }
            }
            syncHostLiveGrooveToPayload(force: true)
            lastServiceLearningSaveMessage = String(
                localized: "Groove from memory — \(Int(match.tempoBPM)) BPM · \(match.drumPattern.label)"
            )
            return
        }

        let bpm = SoloDrumPolish.roundHalfBPM(min(max(saved.tempoBPM, Self.minBPM), Self.maxBPM))
        payload.tempoBPM = bpm
        if soloTempoLocked {
            soloLockedBPM = bpm
            drumAccompaniment.retimeLockedGroove(to: bpm)
            if payload.isMetronomePlaying {
                alignMetronomeEpochToSoloGroove()
                applyMetronome()
            }
            syncHostLiveGrooveToPayload(force: true)
        }
    }

    private func lockOrRetimeSolo(at bpm: Double, pattern: DrumPattern) {
        let rounded = SoloDrumPolish.roundHalfBPM(bpm)
        soloDrumPattern = pattern
        payload.tempoBPM = rounded
        if soloTempoLocked {
            soloLockedBPM = rounded
            drumAccompaniment.setPattern(pattern, force: true)
            drumAccompaniment.retimeLockedGroove(to: rounded)
            applySoloDrumLoopSettingsToEngine()
            if payload.isMetronomePlaying {
                alignMetronomeEpochToSoloGroove()
                applyMetronome()
            }
        }
    }

    func refreshSuggestedSoloInstrumentCategory() {
        guard soloAccompanimentEnabled, soloAutoStyleEnabled else {
            soloSuggestedInstrumentCategory = nil
            return
        }
        let style = detectedLiveStyle
        guard style != .unknown || detectedGlobalGenre != nil else {
            soloSuggestedInstrumentCategory = nil
            return
        }
        let suggested = SoloDrumPolish.suggestedInstrumentCategory(
            style: style == .unknown ? .popRock : style,
            globalGenre: detectedGlobalGenre
        )
        if suggested == soloDrumInstrumentCategory {
            soloSuggestedInstrumentCategory = nil
            return
        }
        soloSuggestedInstrumentCategory = suggested
        // Auto-apply while listening if the host hasn't locked a manual choice.
        if !soloInstrumentCategoryUserPicked, soloDrumPhase == .listening || soloDrumPhase == .awaitingConfirmation {
            setSoloDrumInstrumentCategory(suggested, userPicked: false)
        }
    }

    /// Publishes Mac live-groove state so iPhone guests see tempo & genre.
    func syncHostLiveGrooveToPayload(force: Bool) {
        guard canDriveSession else { return }
        let now = Date().timeIntervalSince1970
        if !force, now - lastHostLiveGroovePayloadSync < Self.hostLiveGroovePayloadSyncThrottle {
            return
        }
        lastHostLiveGroovePayloadSync = now

        if soloAccompanimentEnabled {
            payload.hostLiveGrooveActive = true
            payload.hostLiveGroovePhaseRaw = soloDrumPhase.rawValue
            payload.hostSoloInstrumentCategoryRaw = soloDrumInstrumentCategory.rawValue

            let style = soloPendingProposal?.style ?? detectedLiveStyle
            payload.hostLiveGrooveStyleRaw = style != .unknown ? style.rawValue : nil

            let globalGenre = livePerformanceFusion.detectedGlobalGenre
            payload.hostGlobalGenreID = globalGenre?.id
            payload.hostGlobalGenreLabel = globalGenre?.label
            payload.hostGlobalGenreRegionRaw = livePerformanceFusion.globalGenreAnalysis.region?.rawValue

            let rawBPM = soloLockedBPM ?? soloPendingProposal?.bpm ?? livePerformanceFusion.estimatedBPM
            if let rawBPM {
                let rounded = (rawBPM * 2).rounded() / 2
                payload.hostLiveGrooveBPM = rounded
                if soloDrumPhase == .playing {
                    payload.tempoBPM = rounded
                }
            } else {
                payload.hostLiveGrooveBPM = nil
            }

        } else {
            payload.hostLiveGrooveActive = false
            payload.hostLiveGrooveBPM = nil
            payload.hostLiveGrooveStyleRaw = nil
            payload.hostLiveGroovePhaseRaw = SoloDrumWorkflowPhase.idle.rawValue
            payload.hostGlobalGenreID = nil
            payload.hostGlobalGenreLabel = nil
            payload.hostGlobalGenreRegionRaw = nil
            payload.hostSoloInstrumentCategoryRaw = nil
        }

        let signature = payload.hostLiveGrooveGuestSignature()
        guard force || signature != HostLiveGrooveSyncCache.lastPublishedSignature else { return }
        HostLiveGrooveSyncCache.lastPublishedSignature = signature
        sync()
    }

    private func ensureSoloAccompanimentRunning() {
        refreshSoloAudioCapturePolicy()
    }

    func resetSoloTempoLock() {
        soloDrumEntranceTask?.cancel()
        soloDrumEntranceTask = nil
        soloTempoLocked = false
        soloLockedBPM = nil
        soloTempoLockSamples.removeAll()
        soloTempoDriftSamples.removeAll()
        soloBeatFollowEMA = nil
        soloPendingBeatFollowBPM = nil
        soloPlayingSince = nil
        lastStyleLearnTime = 0
        lastServiceLearningAutoSaveFingerprint = nil
        livePerformanceFusion.grooveLocked = false
        livePerformanceFusion.resetDriftAnalysis()
        drumAccompaniment.entranceGain = 1
        drumAccompaniment.dynamicsGain = 1
        drumAccompaniment.unfreezeGroove()
        stopAutoBandAccompaniment(force: true)
        refreshSoloAudioCapturePolicy()
        applySoloDrumsMetronomePolicy()
    }

    func lockSoloDrums(at bpm: Double, pattern: DrumPattern? = nil) {
        guard !soloTempoLocked else { return }

        let drumPattern = pattern ?? soloDrumPattern
        soloDrumPattern = drumPattern

        let rounded = SoloDrumPolish.roundHalfBPM(bpm)
        soloTempoLocked = true
        soloLockedBPM = rounded
        soloBeatFollowEMA = rounded
        soloPendingBeatFollowBPM = nil
        soloTempoLockSamples.removeAll()
        livePerformanceFusion.grooveLocked = true

        refreshSoloAudioCapturePolicy()
        applySoloDrumsMetronomePolicy()

        let beats = max(1, payload.beatsPerBar)
        if autoBandMode.includesDrums {
            if let learned = activeLearnedDrumPattern, !learned.isEmpty {
                drumAccompaniment.setLearnedPattern(learned)
            } else {
                drumAccompaniment.setLearnedPattern(nil)
            }
            soloDrumLoopPack = DrumMIDILoopPack.pack(for: drumPattern)
            applySoloDrumLoopSettingsToEngine()
            // Start silent (or full) — count-in fades the kit in on bar 1.
            drumAccompaniment.volume = soloDrumVolume
            drumAccompaniment.entranceGain = soloDrumCountInBars > 0 ? 0 : 1
            drumAccompaniment.start(bpm: rounded, pattern: drumPattern, beatsPerBar: beats)
            drumAccompaniment.freezeGroove()
            refreshSoloDrumSectionDynamics()
            scheduleSoloDrumEntranceFadeIn(bpm: rounded, beatsPerBar: beats)
        }
        if activeLearnedBassLine == nil, soloAutoStyleEnabled {
            soloBassStyle = suggestedBassStyle(for: detectedLiveStyle)
        }
        if soloBassEnabled, autoBandMode.includesBass {
            bassAccompaniment.kickPocketLock = true
            startBassAccompanimentIfNeeded(at: rounded)
        }
        // Arm metronome after the groove clock exists so phase can lock to the drum grid.
        applySoloDrumsMetronomePolicy()
        autoSaveServiceLearningOnDrumLockIfNeeded()
        saveSoloGrooveResumeSnapshotIfNeeded()
        refreshSessionAudioPolicy()
        syncHostLiveGrooveToPayload(force: true)
    }

    /// Silent count-in (0–2 bars) then a short fade so drums enter on the grid.
    private func scheduleSoloDrumEntranceFadeIn(bpm: Double, beatsPerBar: Int) {
        soloDrumEntranceTask?.cancel()
        let bars = soloDrumCountInBars
        guard bars > 0 else {
            drumAccompaniment.entranceGain = 1
            return
        }
        let barSeconds = (60.0 / max(48, bpm)) * Double(max(1, beatsPerBar))
        let delay = barSeconds * Double(bars)
        drumAccompaniment.entranceGain = 0
        soloDrumEntranceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, !Task.isCancelled, self.soloTempoLocked else { return }
            await self.fadeInSoloDrumEntrance(duration: 0.32)
        }
    }

    private func fadeInSoloDrumEntrance(duration: Double) async {
        let steps = 8
        let slice = duration / Double(steps)
        for i in 1...steps {
            guard soloTempoLocked, !Task.isCancelled else { return }
            drumAccompaniment.entranceGain = Float(i) / Float(steps)
            try? await Task.sleep(for: .seconds(slice))
        }
        drumAccompaniment.entranceGain = 1
    }

    private func applyAutoDetectedStyleIfNeeded() {
        guard soloAutoStyleEnabled else { return }
        guard soloDrumPhase == .listening else { return }
        guard livePerformanceFusion.styleConfidence >= 0.32,
              livePerformanceFusion.detectedStyle != .unknown,
              let pattern = livePerformanceFusion.suggestedPattern else { return }
        guard pattern != soloDrumPattern else { return }
        soloDrumPattern = pattern
    }

    func applyLiveGroovePreset(_ preset: LiveGroovePreset) {
        if soloTempoLocked {
            setSoloDrumPattern(preset.drumPattern)
            if activeLearnedBassLine == nil {
                soloBassStyle = preset.bassStyle
            }
            return
        }
        soloDrumPattern = preset.drumPattern
        if activeLearnedBassLine == nil {
            soloBassStyle = preset.bassStyle
        }
    }

    func previewLiveGroove() {
        groovePreviewTask?.cancel()
        let wasLocked = soloTempoLocked
        let bpm = soloLockedBPM ?? detectedLiveBPM ?? Double(payload.tempoBPM)
        let beats = max(1, payload.beatsPerBar)

        drumAccompaniment.volume = soloDrumVolume
        drumAccompaniment.setLearnedPattern(nil)
        applySoloDrumLoopSettingsToEngine()
        drumAccompaniment.start(bpm: bpm, pattern: soloDrumPattern, beatsPerBar: beats)

        if soloBassEnabled, autoBandMode.includesBass, soloTempoLocked {
            bassAccompaniment.updateChord(payload.liveChordSymbol)
            startBassAccompanimentIfNeeded(at: bpm)
        }

        groovePreviewTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard let self, !Task.isCancelled, !wasLocked else { return }
            self.drumAccompaniment.stop(force: true)
            self.bassAccompaniment.stop(force: true)
        }
    }
}

enum LiveGroovePreset: String, CaseIterable, Identifiable {
    case worshipBallad
    case slowBallad
    case gospelUptempo
    case merengue
    case salsa
    case songo
    case bachata
    case cumbia
    case dembow
    case funk
    case hipHop
    case afrobeat
    case disco

    var id: String { rawValue }

    var label: String {
        switch self {
        case .worshipBallad: String(localized: "Worship")
        case .slowBallad: String(localized: "Balada")
        case .gospelUptempo: String(localized: "Gospel")
        case .merengue: String(localized: "Merengue")
        case .salsa: String(localized: "Salsa")
        case .songo: String(localized: "Songó")
        case .bachata: String(localized: "Bachata")
        case .cumbia: String(localized: "Cumbia")
        case .dembow: String(localized: "Dembow")
        case .funk: String(localized: "Funk")
        case .hipHop: String(localized: "Hip-hop")
        case .afrobeat: String(localized: "Afrobeat")
        case .disco: String(localized: "Disco")
        }
    }

    var drumPattern: DrumPattern {
        switch self {
        case .worshipBallad: .worshipBallad
        case .slowBallad: .softPulse
        case .gospelUptempo: .gospelGroove
        case .merengue: .merengue
        case .salsa: .salsa
        case .songo: .songo
        case .bachata: .bachata
        case .cumbia: .cumbia
        case .dembow: .dembow
        case .funk: .funkGroove
        case .hipHop: .hipHopBoomBap
        case .afrobeat: .afrobeat
        case .disco: .discoFour
        }
    }

    var bassStyle: BassAccompanimentStyle {
        switch self {
        case .worshipBallad: .worshipPocket
        case .slowBallad: .slowBallad
        case .gospelUptempo: .worshipPocket
        case .merengue: .merengueOctave
        case .salsa, .bachata, .cumbia: .latinTumbao
        case .songo, .afrobeat: .songoPulse
        case .dembow, .funk, .hipHop: .funkPocket
        case .disco: .worshipPocket
        }
    }
}
#endif
