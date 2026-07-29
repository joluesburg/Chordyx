//
//  SessionViewModel+MacSoloAccompaniment.swift
//  Chordyx
//
//  Mac: listen → confirm tempo/style → steady drum loop (no chord-reactive beat).
//

#if os(macOS) || os(iOS)
import Foundation

private enum HostLiveGrooveSyncCache {
    static var lastPublishedSignature = ""
}

extension SessionViewModel {
    var soloAccompanimentAvailable: Bool {
        guard canDriveSession, isInSession else { return false }
        #if os(macOS)
        return true
        #elseif os(iOS)
        // iPad can host Solo Drums; iPhone stays a guest display for tempo/genre.
        return PlatformDevice.canHostSoloAccompaniment
        #else
        return false
        #endif
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
            return detectedLiveStyle.category == .latin ? String(localized: "Accompaniment groove") : String(localized: "Groove family")
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

    /// 0…1 progress while the app listens before asking for confirmation.
    var soloDrumsJoinProgress: Double {
        guard soloAccompanimentEnabled, soloDrumPhase == .listening else {
            return soloDrumPhase == .playing ? 1 : 0
        }
        guard livePerformanceFusion.estimatedBPM != nil else { return 0 }
        let sampleProgress = Double(soloTempoLockSamples.count) / Double(Self.soloTempoLockSampleCount)
        let confProgress = min(1, livePerformanceFusion.tempoConfidence / Self.soloTempoLockConfidenceThreshold)
        return min(1, max(sampleProgress, confProgress * 0.85))
    }

    func trackLivePerformanceFromPiano(activeNotes: [Int]) {
        guard soloAccompanimentAvailable else { return }

        if soloAccompanimentEnabled, !activeNotes.isEmpty, soloPlayingSince == nil {
            soloPlayingSince = Date().timeIntervalSince1970
        }

        let notesChanged = activeNotes != lastTrackedPianoNotes
        let chordChanged = payload.liveChordSymbol != lastTrackedChordSymbol
        if soloTempoLocked {
            let now = Date().timeIntervalSince1970
            if chordChanged || (now - lastStyleLearnTime >= Self.soloStyleLearnThrottle) {
                lastStyleLearnTime = now
                livePerformanceFusion.registerMIDIPerformance(
                    chordSymbol: payload.liveChordSymbol,
                    activeNoteCount: activeNotes.count,
                    newNotesAdded: chordChanged
                )
            }
            if chordChanged {
                evaluateSoloTempoDriftWhilePlaying()
            }
        } else if soloAccompanimentEnabled {
            livePerformanceFusion.registerMIDIPerformance(
                chordSymbol: payload.liveChordSymbol,
                activeNoteCount: activeNotes.count,
                newNotesAdded: notesChanged
            )
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
            // Defer engine / session work so the toggle animation and layout finish first.
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

    func applySuggestedDrumPattern() {
        guard let pattern = suggestedDrumPattern else { return }
        setSoloDrumPattern(pattern)
    }

    func setSoloDrumPattern(_ pattern: DrumPattern) {
        let changed = pattern != soloDrumPattern
        soloDrumPattern = pattern
        guard changed, soloAccompanimentEnabled, soloTempoLocked else { return }
        // Keep the frozen groove clock — swap feel on the same grid so metronome stays locked.
        activeLearnedDrumPattern = nil
        drumAccompaniment.setLearnedPattern(nil, force: true)
        drumAccompaniment.setPattern(pattern, force: true)
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

    func relearnSoloTempo() {
        guard soloAccompanimentEnabled else { return }
        stopAutoBandAccompaniment(force: true)
        drumAccompaniment.unfreezeGroove()
        drumAccompaniment.stop(force: true)
        resetSoloTempoLock()
        beginSoloDrumListening()
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
        // "Yes, start drums" must actually include drums — upgrade bass-only / off.
        if !autoBandMode.includesDrums {
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
        soloDrumPhase = .playing
        soloLockedBPM = bpm
        payload.tempoBPM = bpm
        livePerformanceFusion.resetDriftAnalysis()
        drumAccompaniment.retimeLockedGroove(to: bpm)
        if soloBassEnabled, autoBandMode.includesBass {
            bassAccompaniment.stop(force: true)
            startBassAccompanimentIfNeeded(at: bpm)
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
            armSyncedMetronomeWithSoloDrumsIfNeeded()
        } else {
            soloDrumsMetronomeArmed = false
            refreshMetronomeAudioPolicy()
        }
    }

    /// Starts (once per lock) a living metronome phase-locked to the Solo drum grid.
    func armSyncedMetronomeWithSoloDrumsIfNeeded() {
        guard canDriveSession else { return }
        if soloDrumsMetronomeArmed {
            if payload.isMetronomePlaying {
                alignMetronomeEpochToSoloGroove()
                applyMetronome()
            }
            return
        }
        soloDrumsMetronomeArmed = true
        startSyncedMetronomeWithSoloDrums()
    }

    /// User / Solo path: turn metronome on and lock its bar phase to the drum groove.
    func startSyncedMetronomeWithSoloDrums() {
        guard canDriveSession else { return }
        if let locked = soloLockedBPM {
            payload.tempoBPM = locked
        }
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
        if let grooveCF = drumAccompaniment.grooveAnchor {
            payload.metronomeStartEpoch = grooveCF + kCFAbsoluteTimeIntervalSince1970
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
        guard confidence >= Self.soloTempoLockConfidenceThreshold else {
            soloTempoLockSamples.removeAll()
            return
        }

        soloTempoLockSamples.append((bpm: bpm, confidence: confidence))
        if soloTempoLockSamples.count > 10 {
            soloTempoLockSamples.removeFirst(soloTempoLockSamples.count - 10)
        }

        guard soloTempoLockSamples.count >= Self.soloTempoLockSampleCount else { return }

        let recent = Array(soloTempoLockSamples.suffix(Self.soloTempoLockSampleCount))
        let bpms = recent.map(\.bpm)
        guard let minBPM = bpms.min(), let maxBPM = bpms.max() else { return }
        guard maxBPM - minBPM <= Self.soloTempoLockMaxSpread else {
            soloTempoLockSamples.removeFirst()
            return
        }

        let avgConf = recent.map(\.confidence).reduce(0, +) / Double(recent.count)
        guard avgConf >= Self.soloTempoLockConfidenceThreshold else { return }

        let averaged = bpms.reduce(0, +) / Double(bpms.count)
        presentSoloDrumProposal(bpm: averaged, tempoConfidence: avgConf)
    }

    private func tryFallbackTempoProposal() {
        guard soloDrumPhase == .listening else { return }
        guard let started = soloPlayingSince else { return }
        guard Date().timeIntervalSince1970 - started >= Self.soloTempoProposalFallbackDelay else { return }
        guard livePerformanceFusion.isTracking else { return }

        if let bpm = livePerformanceFusion.estimatedBPM,
           livePerformanceFusion.tempoConfidence >= 0.24 {
            presentSoloDrumProposal(
                bpm: bpm,
                tempoConfidence: livePerformanceFusion.tempoConfidence
            )
        }
    }

    private func presentSoloDrumProposal(bpm: Double, tempoConfidence: Double) {
        let rounded = (bpm * 2).rounded() / 2
        let style = resolvedStyleForProposal()
        let pattern = resolvedPatternForProposal(style: style)
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
        soloDrumPhase = .awaitingConfirmation
        soloTempoLockSamples.removeAll()
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
        guard let drift = livePerformanceFusion.driftEstimatedBPM,
              livePerformanceFusion.driftTempoConfidence >= 0.34 else {
            soloTempoDriftSamples.removeAll()
            return
        }
        guard abs(drift - locked) >= Self.soloTempoDriftMinDelta else {
            soloTempoDriftSamples.removeAll()
            return
        }

        soloTempoDriftSamples.append((bpm: drift, confidence: livePerformanceFusion.driftTempoConfidence))
        if soloTempoDriftSamples.count > 8 {
            soloTempoDriftSamples.removeFirst(soloTempoDriftSamples.count - 8)
        }
        guard soloTempoDriftSamples.count >= Self.soloTempoDriftSampleCount else { return }

        let bpms = soloTempoDriftSamples.map(\.bpm)
        guard let minBPM = bpms.min(), let maxBPM = bpms.max(), maxBPM - minBPM <= 8 else {
            soloTempoDriftSamples.removeFirst()
            return
        }

        let averaged = bpms.reduce(0, +) / Double(bpms.count)
        soloProposedTempoShiftBPM = (averaged * 2).rounded() / 2
        soloDrumPhase = .awaitingTempoShiftConfirmation
        soloTempoDriftSamples.removeAll()
        syncHostLiveGrooveToPayload(force: true)
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
        soloTempoLocked = false
        soloLockedBPM = nil
        soloTempoLockSamples.removeAll()
        soloTempoDriftSamples.removeAll()
        soloPlayingSince = nil
        lastStyleLearnTime = 0
        lastServiceLearningAutoSaveFingerprint = nil
        livePerformanceFusion.grooveLocked = false
        livePerformanceFusion.resetDriftAnalysis()
        drumAccompaniment.unfreezeGroove()
        stopAutoBandAccompaniment(force: true)
        refreshSoloAudioCapturePolicy()
        applySoloDrumsMetronomePolicy()
    }

    func lockSoloDrums(at bpm: Double, pattern: DrumPattern? = nil) {
        guard !soloTempoLocked else { return }

        let drumPattern = pattern ?? soloDrumPattern
        soloDrumPattern = drumPattern

        let rounded = (bpm * 2).rounded() / 2
        soloTempoLocked = true
        soloLockedBPM = rounded
        soloTempoLockSamples.removeAll()
        livePerformanceFusion.grooveLocked = true

        refreshSoloAudioCapturePolicy()
        applySoloDrumsMetronomePolicy()

        let beats = max(1, payload.beatsPerBar)
        if autoBandMode.includesDrums {
            drumAccompaniment.volume = soloDrumVolume
            if let learned = activeLearnedDrumPattern, !learned.isEmpty {
                drumAccompaniment.setLearnedPattern(learned)
            } else {
                drumAccompaniment.setLearnedPattern(nil)
            }
            drumAccompaniment.start(bpm: rounded, pattern: drumPattern, beatsPerBar: beats)
            drumAccompaniment.freezeGroove()
        }
        if activeLearnedBassLine == nil, soloAutoStyleEnabled {
            soloBassStyle = suggestedBassStyle(for: detectedLiveStyle)
        }
        if soloBassEnabled, autoBandMode.includesBass {
            startBassAccompanimentIfNeeded(at: rounded)
        }
        // Arm metronome after the groove clock exists so phase can lock to the drum grid.
        applySoloDrumsMetronomePolicy()
        autoSaveServiceLearningOnDrumLockIfNeeded()
        refreshSessionAudioPolicy()
        syncHostLiveGrooveToPayload(force: true)
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
    case funk

    var id: String { rawValue }

    var label: String {
        switch self {
        case .worshipBallad: String(localized: "Worship")
        case .slowBallad: String(localized: "Balada")
        case .gospelUptempo: String(localized: "Gospel")
        case .merengue: String(localized: "Merengue")
        case .salsa: String(localized: "Salsa")
        case .songo: String(localized: "Songó")
        case .funk: String(localized: "Funk")
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
        case .funk: .funkGroove
        }
    }

    var bassStyle: BassAccompanimentStyle {
        switch self {
        case .worshipBallad: .worshipPocket
        case .slowBallad: .slowBallad
        case .gospelUptempo: .worshipPocket
        case .merengue: .merengueOctave
        case .salsa: .latinTumbao
        case .songo: .songoPulse
        case .funk: .funkPocket
        }
    }
}
#endif
