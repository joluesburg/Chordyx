//
//  SessionViewModel.swift
//  Chordyx
//

import Foundation
import MultipeerConnectivity
import Observation
#if os(iOS)
import UIKit
#endif

@Observable
@MainActor
final class SessionViewModel {
    let sessionManager = SessionManager()
    let cloudRelay = InternetSessionRelayCoordinator()
    let metronome = MetronomeEngine()
    let backingTrack = BackingTrackEngine()
    let midi = MIDIInputManager()
    #if os(macOS) || os(iOS)
    let livePerformanceFusion = LivePerformanceFusionEngine()
    let drumAccompaniment = DrumAccompanimentEngine()
    var soloAccompanimentEnabled = false
    var soloDrumPhase: SoloDrumWorkflowPhase = .idle
    var soloPendingProposal: SoloDrumGrooveProposal?
    var soloProposedTempoShiftBPM: Double?
    var soloTempoDriftSamples: [(bpm: Double, confidence: Double)] = []
    var soloAudioAIEnabled = false // opt-in; MIDI tempo works without mic
    var soloAutoStyleEnabled = true
    var soloDrumPattern: DrumPattern = .worshipBallad
    var soloDrumVolume: Float = 0.72
    var lastTrackedPianoNotes: [Int] = []
    var lastTrackedChordSymbol: String?
    var soloTempoLocked = false
    var soloLockedBPM: Double?
    var soloTempoLockSamples: [(bpm: Double, confidence: Double)] = []
    var soloPlayingSince: TimeInterval?
    var lastStyleLearnTime: TimeInterval = 0
    static let soloStyleLearnThrottle: TimeInterval = 0.4
    static let soloTempoLockConfidenceThreshold = 0.36
    static let soloTempoLockSampleCount = 5
    static let soloTempoLockMaxSpread = 6.0
    static let soloTempoProposalFallbackDelay: TimeInterval = 18
    static let soloTempoDriftMinDelta = 6.0
    static let soloTempoDriftSampleCount = 4
    var soloDrumsMetronomeSilenced = false
    var lastHostLiveGroovePayloadSync: TimeInterval = 0
    static let hostLiveGroovePayloadSyncThrottle: TimeInterval = 0.45
    var serviceLearningEnabled = false
    var serviceLearningAutoSaveOnLock = true
    var serviceLearningRecords: [ServiceLearningRecord] = []
    var lastServiceLearningSaveMessage: String?
    var lastServiceLearningAutoSaveFingerprint: String?
    let bassAccompaniment = BassAccompanimentEngine()
    let bandStemLearning = BandStemLearningEngine()
    var soloBassEnabled = false
    var soloBassStyle: BassAccompanimentStyle = .worshipPocket
    var soloBassVolume: Float = 0.65
    var autoBandMode: AutoBandMode = .off
    var bandStemLearningEnabled = false
    var activeLearnedDrumPattern: LearnedDrumPattern?
    var activeLearnedBassLine: LearnedBassLine?
    #endif
    #if os(iOS)
    private let sessionBackground = SessionBackgroundManager()
    #endif

    var midiSources: [String] = []
    var midiAvailableSources: [MIDISourceInfo] = []
    private var previousActiveChordID: UUID?
    private var transitionTask: Task<Void, Never>?
    private var cueClearTask: Task<Void, Never>?
    private var songEndingTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var guestReconnectInProgress = false
    private var midiSyncTask: Task<Void, Never>?
    private var pianoSideEffectsTask: Task<Void, Never>?
    var groovePreviewTask: Task<Void, Never>?
    private var outboundSyncTask: Task<Void, Never>?
    private var outboundSyncNeedsFull = false
    private var outboundSyncLivePending = false
    private var hostKeepAliveTask: Task<Void, Never>?
    private var lastSyncedLiveChordSymbol: String?
    private var liveWireRevision: UInt64 = 0
    private var lastAppliedLiveWireRevision: UInt64 = 0
    private var outboundSyncImmediate = false
    private var lastGuestMetronomeSignature: MetronomeSyncSignature?
    private var sectionCountdownTask: Task<Void, Never>?
    private var handoffCountdownTask: Task<Void, Never>?
    private var lastTrackedSectionID: UUID?
    private var lastBeatEpoch: Double = 0
    private var pendingDetectedKey: MusicalKey?
    private var pendingDetectedKeyHits = 0
    private var symbolsAtLastAutoKeyDetection: [String] = []
    private var keyUsedForAutoDetection: MusicalKey?
    private let progressionInference = ProgressionInferenceEngine()
    /// True after a repeating live loop was auto-applied to `payload.chords`.
    private(set) var hasInferredLiveProgression = false
    private(set) var inferredProgressionConfidence: Double = 0
    private var inferredOutOfCycleHits = 0
    var autoAdvanceSetlistSongs = false
    var shouldAutoAdvanceSetlist = false

    struct ImportSessionGuide: Equatable {
        var title: String
        var message: String
    }

    var importSessionGuide: ImportSessionGuide?
    var pendingReconnectRecord: RecentSessionRecord?
    var showReconnectBanner = false
    private(set) var isRemoteLinkActive = false
    private var connectedHostDeviceName = ""

    static let minBPM: Double = 40
    static let maxBPM: Double = 240
    static let remoteBackupDefaultsKey = "chordyxRemoteBackupEnabled"
    static let showInternetJoinCodeKey = "chordyxShowInternetJoinCode"

    var payload = SessionSyncPayload.empty
    var isInSession = false
    var isPracticeMode = false
    var role: SessionRole = .none
    #if os(iOS)
    private(set) var isAppInBackground = false
    private var backgroundRefreshTask: Task<Void, Never>?
    #endif

    private var activeSetlist: Setlist?
    private var activeSetlistIndex = 0

    enum SessionRole {
        case none
        case host
        case guest
    }

    var isCoHost: Bool {
        role == .guest
            && payload.coHostPeerName == SessionManager.currentDisplayName()
    }

    var canDriveSession: Bool {
        guard isInSession else { return false }
        if isPracticeMode { return true }
        if role == .host { return true }
        if isCoHost { return true }
        return false
    }

    var effectiveSyncQuality: SyncQuality {
        if isRemoteLinkActive, sessionManager.connectedPeers.isEmpty {
            return .remote
        }
        return sessionManager.syncQuality
    }

    /// Single tempo source for UI + metronome (guests follow Mac live groove when active).
    var displayedSessionTempoBPM: Double {
        if role == .guest, let groove = payload.guestLiveGrooveDisplayBPM {
            return groove
        }
        return payload.tempoBPM
    }

    var displayedMetronomePlaying: Bool {
        if role == .guest, payload.guestShouldFollowHostLiveGrooveMetronome {
            return true
        }
        return payload.isMetronomePlaying
    }

    var sortedChords: [ChordEntry] {
        payload.chords.sorted { $0.order < $1.order }
    }

    var activeChord: ChordEntry? {
        guard let id = payload.activeChordID else { return nil }
        return payload.chords.first { $0.id == id }
    }

    var upcomingChord: ChordEntry? {
        guard !payload.isLiveChordsOnly else { return nil }
        let scoped = navigationChords
        guard scoped.count > 1,
              let activeID = payload.activeChordID,
              let index = scoped.firstIndex(where: { $0.id == activeID }) else { return nil }

        if index + 1 < scoped.count {
            return scoped[index + 1]
        }

        if !payload.sections.isEmpty,
           let active = activeSection,
           let sectionIndex = sectionsInOrder.firstIndex(where: { $0.id == active.id }),
           sectionIndex + 1 < sectionsInOrder.count {
            return chords(for: sectionsInOrder[sectionIndex + 1]).first
        }

        return scoped[0]
    }

    /// Full song order for non-sectioned songs; active section chords when the chart has sections.
    var navigationChords: [ChordEntry] {
        payload.sections.isEmpty ? sortedChords : chordsInActiveSection()
    }

    var sectionsInOrder: [SectionMarker] {
        payload.sections.sorted { lhs, rhs in
            let li = sortedChords.firstIndex(where: { $0.id == lhs.startChordID }) ?? Int.max
            let ri = sortedChords.firstIndex(where: { $0.id == rhs.startChordID }) ?? Int.max
            return li < ri
        }
    }

    var activeSectionRingSummary: (section: SectionMarker, index: Int, count: Int)? {
        guard let section = activeSection else { return nil }
        let chords = chordsInActiveSection()
        guard !chords.isEmpty else { return nil }
        let position = payload.activeChordID.flatMap { id in
            chords.firstIndex(where: { $0.id == id })
        } ?? 0
        return (section, position + 1, chords.count)
    }

    /// Chords for the ring — one ring per section (Intro, Verse, Chorus, Bridge, …).
    var ringSectionChords: [ChordEntry] {
        chordsInActiveSection()
    }

    var activeSection: SectionMarker? {
        guard let activeID = payload.activeChordID else { return nil }
        let sortedSections = sectionsInOrder.reversed()
        return sortedSections.first { section in
            guard let startIndex = sortedChords.firstIndex(where: { $0.id == section.startChordID }) else { return false }
            guard let activeIndex = sortedChords.firstIndex(where: { $0.id == activeID }) else { return false }
            return activeIndex >= startIndex
        }
    }

    func chordsInActiveSection() -> [ChordEntry] {
        let sorted = sortedChords
        guard !sorted.isEmpty else { return [] }
        guard !payload.sections.isEmpty else { return sorted }

        let sectionsByIndex = sectionsInOrder.compactMap { section -> (SectionMarker, Int)? in
            guard let index = sorted.firstIndex(where: { $0.id == section.startChordID }) else { return nil }
            return (section, index)
        }

        guard !sectionsByIndex.isEmpty else { return sorted }

        let startIndex: Int
        if let active = activeSection,
           let index = sorted.firstIndex(where: { $0.id == active.startChordID }) {
            startIndex = index
        } else if let activeID = payload.activeChordID,
                  let activeIndex = sorted.firstIndex(where: { $0.id == activeID }),
                  let containing = sectionsByIndex.last(where: { $0.1 <= activeIndex }) {
            startIndex = containing.1
        } else {
            startIndex = sectionsByIndex[0].1
        }

        let endIndex = sectionsByIndex.first(where: { $0.1 > startIndex })?.1 ?? sorted.count
        guard startIndex < endIndex else { return sorted }
        return Array(sorted[startIndex..<endIndex])
    }

    func chords(for section: SectionMarker) -> [ChordEntry] {
        let sorted = sortedChords
        guard let startIndex = sorted.firstIndex(where: { $0.id == section.startChordID }) else { return [] }
        let ordered = sectionsInOrder
        guard let sectionIndex = ordered.firstIndex(where: { $0.id == section.id }) else {
            return Array(sorted[startIndex...])
        }
        let endIndex: Int
        if sectionIndex + 1 < ordered.count,
           let nextStart = sorted.firstIndex(where: { $0.id == ordered[sectionIndex + 1].startChordID }) {
            endIndex = nextStart
        } else {
            endIndex = sorted.count
        }
        guard startIndex < endIndex else { return [] }
        return Array(sorted[startIndex..<endIndex])
    }

    var freestyleChordEntries: [ChordEntry] {
        payload.freestyleChordSymbols.enumerated().map { index, symbol in
            ChordEntry.freestyle(symbol: symbol, order: index)
        }
    }

    var liveFreestyleChord: ChordEntry? {
        livePianoChordEntry()
    }

    var isHostPianoLive: Bool {
        !payload.pianoNotes.isEmpty || payload.liveChordSymbol != nil
    }

    var guestPreferredNotation: ChordNotation {
        let raw = UserDefaults.standard.string(forKey: "preferredNotation") ?? ChordNotation.symbol.rawValue
        return ChordNotation(rawValue: raw) ?? payload.notation
    }

    /// Incremented when notation is cycled so chord labels refresh without waiting for a new chord.
    private(set) var displayNotationVersion = 0

    func displayNotation(isGuest: Bool) -> ChordNotation {
        _ = displayNotationVersion
        if isGuest {
            return GuestDisplaySettings.effectiveNotation(hostNotation: payload.notation, isGuest: true)
        }
        return payload.notation
    }

    func effectiveDisplayMode(isGuest: Bool) -> SessionDisplayMode {
        GuestDisplaySettings.effectiveDisplayMode(
            hostMode: payload.displayMode,
            isGuest: isGuest,
            isLivePerformance: payload.performanceMode.usesCompactStageUI,
            isLiveChordsOnly: payload.isLiveChordsOnly
        )
    }

    var activeScaleHint: String? {
        guard let chord = activeChord else { return nil }
        return ScaleHint.hint(for: chord.symbolName, songKey: payload.key)
    }

    var setlistTimelineTitles: [String] {
        payload.setlistSongTitles
    }

    var nextSetlistSongTitle: String? {
        guard let index = payload.setlistSongIndex,
              index + 1 < payload.setlistSongTitles.count else { return nil }
        return payload.setlistSongTitles[index + 1]
    }

    var currentSetlistSongTitle: String? {
        guard let index = payload.setlistSongIndex,
              index < payload.setlistSongTitles.count else { return nil }
        return payload.setlistSongTitles[index]
    }

    var hasFreestyleActivity: Bool {
        isHostPianoLive || payload.liveChordSymbol != nil || !payload.freestyleChordSymbols.isEmpty
            || !payload.liveRingUsageCounts.isEmpty
    }

    /// 1-based index of the current live ring song within this session.
    var liveRingSongNumber: Int {
        payload.liveRingSegments.count + 1
    }

    var usesLiveFreestyleRing: Bool {
        payload.isLiveChordsOnly || payload.ringShowsLiveChords || isLiveProgressionSession
    }

    private(set) var isLiveProgressionSession = false
    var loadedProgressionID: UUID?
    private var didBootstrap = false

    init() {
        sessionManager.onPayloadReceived = { [weak self] received in
            Task { @MainActor in
                guard let self, self.isInSession else { return }
                self.applyGuestPayload(received, fromRemote: false)
            }
        }
        sessionManager.onLiveChordReceived = { [weak self] wire in
            Task { @MainActor(priority: .userInteractive) in
                guard let self, self.isInSession else { return }
                self.applyLiveChordWire(wire)
            }
        }
        sessionManager.onControlRequest = { [weak self] action, peer in
            Task { @MainActor in
                guard let self, self.isInSession else { return }
                self.handleControlRequest(action, from: peer)
            }
        }
        sessionManager.onGuestDisconnected = { [weak self] in
            Task { @MainActor in
                guard let self, self.isInSession else { return }
                self.handleGuestDisconnected()
            }
        }
        sessionManager.onPeersUpdated = { [weak self] peers in
            guard let self, self.isInSession else { return }
            if self.role == .host {
                self.refreshPeerPresence()
                if !peers.isEmpty {
                    self.sync()
                }
            } else if self.role == .guest, !peers.isEmpty {
                self.isRemoteLinkActive = false
                self.guestReconnectInProgress = false
                if let hostName = peers.first?.displayName, !hostName.isEmpty {
                    self.connectedHostDeviceName = hostName
                }
                self.stopReconnectPolling()
                self.showReconnectBanner = false
                self.pendingReconnectRecord = nil
            }
            #if os(iOS)
            if self.isInSession {
                self.refreshLockScreenDisplay(force: true)
            }
            #endif
        }
        sessionManager.onClockOffsetUpdated = { [weak self] in
            guard let self, self.role == .guest else { return }
            self.applyMetronome()
            #if os(iOS)
            if self.isInSession {
                self.refreshLockScreenDisplay(force: true)
            }
            #endif
        }
        metronome.onBeat = { [weak self] _, _, isCountIn in
            Task { @MainActor in
                guard let self else { return }
                if !isCountIn, self.payload.isCountingIn, self.canDriveSession {
                    self.payload.isCountingIn = false
                    self.payload.countInStartEpoch = nil
                    self.sync()
                }
                if !isCountIn {
                    self.handleMetronomeBeat()
                }
                self.payload.countInBeatsRemaining = self.metronome.countInBeatsRemaining
                #if os(iOS)
                if self.isInSession {
                    LiveActivityManager.updateBeat(from: self)
                }
                #endif
            }
        }
        midi.onNotesChanged = { [weak self] notes in
            self?.handleMIDINotes(notes)
        }
        midi.onSourcesChanged = { [weak self] names in
            self?.midiSources = names
        }
        midi.onAvailableSourcesChanged = { [weak self] sources in
            self?.midiAvailableSources = sources
        }
        midi.onPedalAction = { [weak self] action in
            self?.handlePedalAction(action)
        }
        cloudRelay.onPayloadReceived = { [weak self] received in
            Task { @MainActor in self?.applyGuestPayload(received, fromRemote: true) }
        }
        cloudRelay.onControlRequest = { [weak self] action, guestName in
            Task { @MainActor in self?.handleRemoteControlRequest(action, from: guestName) }
        }
        #if os(macOS) || os(iOS)
        livePerformanceFusion.onFusionUpdated = { [weak self] in
            guard let self else { return }
            self.syncHostLiveGrooveToPayload(force: false)
            self.evaluateSoloAccompanimentFromFusion()
        }
        #endif
    }

    /// Starts MIDI, Watch bridge, and cloud account refresh after the splash screen.
    func bootstrapIfNeeded() {
        guard !didBootstrap else { return }
        didBootstrap = true
        Task { await cloudRelay.refreshAccountStatus() }
        midi.start()
        _ = WatchSessionBridge.shared
        configureFeatureBridges()
    }

    private func handlePedalAction(_ action: MIDIPedalAction) {
        guard canDriveSession else { return }
        switch action {
        case .nextChord: advanceChord()
        case .previousChord: previousChord()
        }
    }

    private func handleControlRequest(_ action: SessionControlAction, from peer: MCPeerID) {
        guard isInSession, role == .host else { return }
        switch action {
        case .reportChordPosition(let chordID):
            payload.peerChordPositions[peer.displayName] = chordID
            refreshPeerPresence()
        default:
            guard payload.coHostPeerName == peer.displayName else { return }
            applyControlAction(action)
        }
    }

    private func handleRemoteControlRequest(_ action: SessionControlAction, from guestName: String) {
        guard role == .host else { return }
        guard payload.coHostPeerName == guestName else { return }
        applyControlAction(action)
    }

    private func applyGuestPayload(_ received: SessionSyncPayload, fromRemote: Bool) {
        guard isInSession, role == .guest else { return }
        if fromRemote, !sessionManager.connectedPeers.isEmpty { return }
        if received == payload { return }

        let priorCueSentAt = payload.activeCue?.sentAt
        let priorChord = payload.activeChordID
        let priorLiveSymbol = payload.liveChordSymbol
        let priorNudgeSequence = payload.silentNudgeSequence
        let priorMetronomeSignature = payload.metronomeSyncSignature()
        let priorRoles = payload.guestRoleAssignments
        let priorHostGrooveSignature = payload.hostLiveGrooveGuestSignature()

        let mergedPayload: SessionSyncPayload
        if received.isLiveChordBurst(comparedTo: payload) {
            mergedPayload = payload.applyingLiveBurst(from: received)
            if mergedPayload == payload { return }
        } else {
            mergedPayload = received
        }

        payload = mergedPayload
        if role == .guest, mergedPayload.hostLiveGrooveActive {
            payload.tempoDriftBPM = 0
        }

        if fromRemote {
            isRemoteLinkActive = true
            sessionManager.syncQuality = .remote
            guestReconnectInProgress = false
            showReconnectBanner = false
        } else {
            isRemoteLinkActive = false
        }

        if priorChord != mergedPayload.activeChordID {
            previousActiveChordID = priorChord
        }

        let liveChordChanged = priorLiveSymbol != mergedPayload.liveChordSymbol
        let chordChanged = priorChord != mergedPayload.activeChordID || liveChordChanged
        let metronomeChanged = priorMetronomeSignature != mergedPayload.metronomeSyncSignature()
        let hostGrooveChanged = priorHostGrooveSignature != mergedPayload.hostLiveGrooveGuestSignature()
        let rolesChanged = priorRoles != mergedPayload.guestRoleAssignments

        if metronomeChanged || hostGrooveChanged {
            applyMetronome()
            lastGuestMetronomeSignature = mergedPayload.metronomeSyncSignature()
            reapplyGuestMetronomeAudioPreference()
        }

        if rolesChanged {
            applyHostAssignedRoleIfNeeded()
        }
        acceptHostHandoffIfPending()
        if let cue = mergedPayload.activeCue, cue.sentAt != priorCueSentAt {
            triggerCueHaptic(cue.text)
        }
        if mergedPayload.silentNudgeSequence != priorNudgeSequence,
           let nudge = mergedPayload.broadcastSilentNudge {
            deliverSilentNudge(nudge)
        }

        if chordChanged || metronomeChanged || hostGrooveChanged {
            pushWatchUpdate(chordChanged: chordChanged)
        }

        if chordChanged || mergedPayload.activeCue?.sentAt != priorCueSentAt {
            RecentSessionStore.updateProgress(
                sessionToken: mergedPayload.sessionToken,
                activeChordID: mergedPayload.activeChordID,
                progressionName: mergedPayload.sessionName
            )
        }
        if let code = mergedPayload.remoteJoinCode {
            var list = RecentSessionStore.records
            if let index = list.firstIndex(where: { $0.sessionToken == mergedPayload.sessionToken }) {
                list[index].remoteJoinCode = code
                RecentSessionStore.records = list
            }
        }
        #if os(iOS)
        if chordChanged || mergedPayload.activeCue?.sentAt != priorCueSentAt {
            refreshLockScreenDisplay(force: chordChanged)
        }
        #endif
    }

    private func applyLiveChordWire(_ wire: LiveChordWire) {
        guard isInSession, role == .guest else { return }
        guard wire.sessionToken == payload.sessionToken else { return }
        guard wire.revision > lastAppliedLiveWireRevision else { return }
        lastAppliedLiveWireRevision = wire.revision

        let priorSymbol = payload.liveChordSymbol
        let merged = payload.applyingLiveWire(wire)
        if merged == payload { return }
        payload = merged

        let chordChanged = priorSymbol != wire.liveChordSymbol
        if chordChanged {
            pushWatchUpdate(chordChanged: true)
            #if os(iOS)
            refreshLockScreenDisplay(force: true)
            #endif
        }
    }

    private func applyControlAction(_ action: SessionControlAction) {
        switch action {
        case .advanceChord:
            advanceChord()
        case .previousChord:
            previousChord()
        case .jumpToSection(let sectionID):
            jumpToSection(id: sectionID)
        case .setActiveChord(let chordID):
            if let chord = payload.chords.first(where: { $0.id == chordID }) {
                setActiveChord(chord)
            }
        case .sendCue(let cue):
            sendLiveCue(cue)
        case .passControl(let peerName):
            if let peer = sessionManager.connectedPeers.first(where: { $0.displayName == peerName }) {
                promoteCoHost(peer)
            }
        case .toggleMetronome:
            toggleMetronome()
        case .tempoNudge(let delta):
            setTempo(payload.tempoBPM + Double(delta))
        case .requestHostHandoff(let peerName):
            payload.pendingHostHandoffPeer = peerName
            sync()
        case .silentNudge(let kind):
            deliverSilentNudge(kind)
        case .reportChordPosition(let chordID):
            reportGuestChordPosition(chordID)
        }
    }

    func requestControlAction(_ action: SessionControlAction) {
        if canDriveSession && (role == .host || isPracticeMode) {
            applyControlAction(action)
        } else if isCoHost {
            if sessionManager.connectedPeers.isEmpty,
               isRemoteLinkActive,
               let code = payload.remoteJoinCode {
                Task {
                    await cloudRelay.sendControl(
                        action: action,
                        joinCode: code,
                        guestName: SessionManager.currentDisplayName()
                    )
                }
            } else {
                sessionManager.sendControlRequest(action)
            }
        }
    }

    private func handleMIDINotes(_ midiNotes: [Int]) {
        guard canDriveSession else { return }
        let notes = midiNotes
            .map { PianoNote.fromMIDINote($0) }
            .filter { PianoNote.keyboardRange.contains($0) }
            .sorted()
        applyPianoNotes(notes)
    }

    private func applyPianoNotes(_ indices: [Int]) {
        guard canDriveSession else { return }
        let notes = indices
            .map { PianoNote.normalizeToInternal($0) }
            .filter { PianoNote.keyboardRange.contains($0) }

        let priorSymbol = payload.liveChordSymbol
        payload.pianoNotes = notes

        if !notes.isEmpty {
            updateLiveChordSymbol(from: notes)
        }

        if priorSymbol != payload.liveChordSymbol {
            #if os(macOS) || os(iOS)
            if soloAccompanimentEnabled, soloTempoLocked, isSoloDrumGroovePlaying {
                syncLiveCoalesced()
            } else {
                syncLiveImmediate()
            }
            #else
            syncLiveImmediate()
            #endif
        } else {
            syncLiveCoalesced()
        }

        schedulePianoSideEffects(notes: notes)
    }

    private func schedulePianoSideEffects(notes: [Int]) {
        pianoSideEffectsTask?.cancel()
        pianoSideEffectsTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, !Task.isCancelled, self.isInSession else { return }
            guard self.payload.pianoNotes == notes else { return }

            if !notes.isEmpty, let symbol = self.payload.liveChordSymbol {
                self.applyFreestyleSideEffects(for: symbol)
                self.updatePianoChartMismatch()
            }
            #if os(macOS) || os(iOS)
            self.trackLivePerformanceFromPiano(activeNotes: notes)
            #endif
        }
    }

    private func updateLiveChordSymbol(from indices: [Int]) {
        let pitchClasses = Set(indices.map { PianoNote.pitchClass(forStored: $0) })
        let bass = indices.min().map { PianoNote.pitchClass(forStored: $0) }
        let symbol: String?
        if pitchClasses.count == 1, let pc = pitchClasses.first {
            let names = payload.key.prefersFlats ? Transposer.flatNames : Transposer.sharpNames
            symbol = names[pc]
        } else {
            var resolved = ChordRecognizer.symbol(
                forPitchClasses: pitchClasses,
                bassPitchClass: bass,
                preferFlats: payload.key.prefersFlats
            )
            if resolved == nil, let index = indices.min() {
                resolved = singleNoteSymbol(for: index)
            }
            symbol = resolved
        }
        payload.liveChordSymbol = symbol
    }

    private func applyFreestyleSideEffects(for symbol: String) {
        let registeredRingPlay: Bool
        if hasInferredLiveProgression {
            registeredRingPlay = registerLiveRingChordPlay(symbol: symbol)
            advanceInferredProgression(with: symbol)
        } else if isLiveProgressionSession {
            appendLiveProgressionChord(symbol: symbol)
            registeredRingPlay = registerLiveRingChordPlay(symbol: symbol)
        } else if payload.ringShowsLiveChords || payload.isLiveChordsOnly {
            registeredRingPlay = registerLiveRingChordPlay(symbol: symbol)
        } else {
            registeredRingPlay = false
        }
        if registeredRingPlay || usesLiveFreestyleRing {
            maybeAutoDetectKey()
            maybeInferLiveProgression(symbol: symbol)
        }
    }

    private func syncLiveImmediate() {
        outboundSyncLivePending = true
        outboundSyncImmediate = true
        midiSyncTask?.cancel()
        midiSyncTask = nil
        outboundSyncTask?.cancel()
        outboundSyncTask = nil
        flushOutboundSync()
    }

    private func syncLiveCoalesced() {
        outboundSyncLivePending = true
        requestOutboundSync(delayMs: 12)
    }

    private func updateFreestyleRecognition(from indices: [Int]) {
        guard !indices.isEmpty else { return }
        updateLiveChordSymbol(from: indices)
        guard let symbol = payload.liveChordSymbol else { return }
        applyFreestyleSideEffects(for: symbol)
        updatePianoChartMismatch()
    }

    func singleNoteSymbol(for index: Int) -> String {
        let pc = PianoNote.pitchClass(forStored: index)
        let names = payload.key.prefersFlats ? Transposer.flatNames : Transposer.sharpNames
        return names[pc]
    }

    func livePianoChordEntry() -> ChordEntry? {
        guard !payload.pianoNotes.isEmpty else {
            guard let symbol = payload.liveChordSymbol else { return nil }
            return ChordEntry.freestyle(symbol: symbol, order: -1)
        }
        if let symbol = payload.liveChordSymbol {
            return ChordEntry.freestyle(symbol: symbol, order: -1)
        }
        if let index = payload.pianoNotes.first {
            let symbol = singleNoteSymbol(for: index)
            return ChordEntry.freestyle(symbol: symbol, order: -1)
        }
        return nil
    }

    func guestVisibleChord(preferLivePiano: Bool = true) -> ChordEntry? {
        if preferLivePiano, let live = livePianoChordEntry() {
            return live
        }
        if payload.isLiveChordsOnly || payload.ringShowsLiveChords {
            return liveFreestyleChord ?? activeChord
        }
        return activeChord
    }

    func guestDisplayName(
        for chord: ChordEntry,
        isGuest: Bool,
        transposeSemitones: Int = 0,
        capoFret: Int = 0
    ) -> String {
        ChordDisplayHelper.displayName(
            for: chord,
            notation: displayNotation(isGuest: isGuest),
            songKey: payload.key,
            transposeSemitones: transposeSemitones,
            capoFret: capoFret
        )
    }

    private func appendLiveProgressionChord(symbol: String) {
        if let existing = payload.chords.first(where: { LiveRing.matches($0.symbolName, symbol) }) {
            payload.activeChordID = existing.id
            payload.beatsOnActiveChord = 0
            updateActiveSection()
            return
        }

        guard payload.chords.count < LiveRing.maxLiveProgressionChords else { return }

        let chord = ChordEntry(
            symbolName: symbol,
            latinName: ChordCatalog.latinName(forSymbol: symbol),
            order: payload.chords.count
        )
        payload.chords.append(chord)
        payload.activeChordID = chord.id
        payload.beatsOnActiveChord = 0
        updateActiveSection()
    }

    /// Records each live chord play and rebuilds the ring from the most-used symbols.
    @discardableResult
    private func registerLiveRingChordPlay(symbol: String) -> Bool {
        guard usesLiveFreestyleRing else { return false }
        let normalized = LiveRing.normalize(symbol)
        guard !normalized.isEmpty else { return false }

        payload.liveRingUsageCounts[normalized, default: 0] += 1
        payload.liveRingCanonicalSymbols[normalized] = symbol
        if let existingIndex = payload.liveRingRecentOrder.firstIndex(of: normalized) {
            payload.liveRingRecentOrder.remove(at: existingIndex)
        }
        payload.liveRingRecentOrder.append(normalized)
        rebuildLiveRingDisplay()
        return true
    }

    private func rebuildLiveRingDisplay() {
        payload.freestyleChordSymbols = LiveRing.rankedDisplaySymbols(
            counts: payload.liveRingUsageCounts,
            recentOrder: payload.liveRingRecentOrder,
            canonicalByNormalized: payload.liveRingCanonicalSymbols
        )
    }

    private func clearLiveRingTracking() {
        payload.freestyleChordSymbols = []
        payload.liveRingUsageCounts = [:]
        payload.liveRingRecentOrder = []
        payload.liveRingCanonicalSymbols = [:]
    }

    /// Archives the current ring and clears usage stats — use when starting a new song.
    func startNewLiveSongRing() {
        guard canDriveSession, usesLiveFreestyleRing else { return }
        beginNewLiveRingSegment()
        clearInferredLiveProgression(resetEngine: true)
        if isLiveProgressionSession {
            payload.chords = []
            payload.activeChordID = nil
            payload.beatsOnActiveChord = 0
            updateActiveSection()
        }
        pendingDetectedKey = nil
        pendingDetectedKeyHits = 0
        syncLiveImmediate()
    }

    private func liveRingSymbolsForKeyDetection() -> [String] {
        var symbols = payload.liveRingRecentOrder.map { payload.liveRingCanonicalSymbols[$0] ?? $0 }
        if symbols.isEmpty {
            symbols = payload.freestyleChordSymbols
        }
        if let live = payload.liveChordSymbol, !LiveRing.contains(live, in: symbols) {
            symbols.append(live)
        }
        return symbols
    }

    private func maybeAutoDetectKey() {
        guard payload.autoDetectKey, canDriveSession else { return }

        let symbols = liveRingSymbolsForKeyDetection()
        guard symbols.count >= 3,
              let result = AdaptiveKeyLearningEngine.shared.detect(
                from: symbols,
                sessionName: payload.sessionName
              ) else { return }

        if result.key == payload.key {
            pendingDetectedKey = nil
            pendingDetectedKeyHits = 0
            payload.isKeyAutoDetected = true
            symbolsAtLastAutoKeyDetection = symbols
            keyUsedForAutoDetection = payload.key
            return
        }

        if result.key == pendingDetectedKey {
            pendingDetectedKeyHits += 1
        } else {
            pendingDetectedKey = result.key
            pendingDetectedKeyHits = 1
        }

        let isInitialGuess = payload.liveRingRecentOrder.count <= 4 && !payload.isKeyAutoDetected
        let memoryConfirmed = result.source == .memory
        let requiredHits: Int
        if memoryConfirmed {
            requiredHits = 1
        } else if isInitialGuess {
            requiredHits = 1
        } else if result.confidence >= 0.5 {
            requiredHits = 2
        } else {
            requiredHits = 3
        }
        guard pendingDetectedKeyHits >= requiredHits else { return }

        applyAutoDetectedKeyChange(to: result.key, from: symbols)
    }

    private func applyAutoDetectedKeyChange(to newKey: MusicalKey, from symbols: [String]) {
        let keyChanged = newKey.pitchClass != payload.key.pitchClass
        let hadLiveRing = !payload.freestyleChordSymbols.isEmpty || !payload.liveRingUsageCounts.isEmpty

        if keyChanged, hadLiveRing, usesLiveFreestyleRing {
            beginNewLiveRingSegment()
            clearInferredLiveProgression(resetEngine: true)
            if isLiveProgressionSession {
                payload.chords = []
                payload.activeChordID = nil
                payload.beatsOnActiveChord = 0
                updateActiveSection()
            }
        }

        payload.key = newKey
        payload.isKeyAutoDetected = true
        pendingDetectedKey = nil
        pendingDetectedKeyHits = 0
        symbolsAtLastAutoKeyDetection = symbols
        keyUsedForAutoDetection = newKey
        AdaptiveKeyLearningEngine.shared.confirmDetection(
            symbols: symbols,
            key: newKey,
            sessionName: payload.sessionName
        )
        sync()
    }

    private func maybeInferLiveProgression(symbol: String) {
        guard canDriveSession, usesLiveFreestyleRing else { return }

        let now = CFAbsoluteTimeGetCurrent()
        guard let inference = progressionInference.observe(symbol: symbol, at: now) else { return }
        inferredProgressionConfidence = inference.confidence

        guard inference.confidence >= ProgressionInferenceEngine.applyConfidenceThreshold else { return }

        if hasInferredLiveProgression,
           progressionMatchesInference(inference) {
            return
        }

        applyInferredProgression(inference)
    }

    private func progressionMatchesInference(_ inference: InferredProgression) -> Bool {
        let current = sortedChords.map { LiveRing.normalize($0.symbolName) }
        return current == inference.normalized
    }

    private func applyInferredProgression(_ inference: InferredProgression) {
        let chords = inference.symbols.prefix(LiveRing.maxLiveProgressionChords).enumerated().map { index, symbol in
            ChordEntry(
                symbolName: symbol,
                latinName: ChordCatalog.latinName(forSymbol: symbol),
                order: index
            )
        }
        guard !chords.isEmpty else { return }

        payload.chords = Array(chords)
        if let live = payload.liveChordSymbol,
           let match = payload.chords.first(where: { LiveRing.matches($0.symbolName, live) }) {
            payload.activeChordID = match.id
        } else {
            payload.activeChordID = payload.chords.first?.id
        }
        payload.beatsOnActiveChord = 0
        hasInferredLiveProgression = true
        inferredProgressionConfidence = inference.confidence
        inferredOutOfCycleHits = 0
        updateActiveSection()
        syncLiveImmediate()
    }

    private func advanceInferredProgression(with symbol: String) {
        guard hasInferredLiveProgression, !payload.chords.isEmpty else { return }

        let chords = sortedChords
        guard let matchIndex = chords.firstIndex(where: { LiveRing.matches($0.symbolName, symbol) }) else {
            inferredOutOfCycleHits += 1
            if inferredOutOfCycleHits >= 3 {
                // Sustained playing outside the locked cycle — release and keep listening.
                clearInferredLiveProgression(resetEngine: false)
                payload.chords = []
                payload.activeChordID = nil
                payload.beatsOnActiveChord = 0
                updateActiveSection()
            }
            return
        }

        inferredOutOfCycleHits = 0

        if let activeID = payload.activeChordID,
           let activeIndex = chords.firstIndex(where: { $0.id == activeID }) {
            let expectedNext = (activeIndex + 1) % chords.count
            if matchIndex == expectedNext || matchIndex == activeIndex {
                payload.activeChordID = chords[matchIndex].id
                payload.beatsOnActiveChord = 0
                updateActiveSection()
                return
            }
        }

        payload.activeChordID = chords[matchIndex].id
        payload.beatsOnActiveChord = 0
        updateActiveSection()
    }

    private func clearInferredLiveProgression(resetEngine: Bool) {
        hasInferredLiveProgression = false
        inferredProgressionConfidence = 0
        inferredOutOfCycleHits = 0
        if resetEngine {
            progressionInference.reset()
        }
    }

    /// Archives the current live ring and starts a fresh one (e.g. next song or new key).
    private func beginNewLiveRingSegment() {
        let current = payload.freestyleChordSymbols
        if !current.isEmpty {
            payload.liveRingSegments.append(current)
            if payload.liveRingSegments.count > LiveRing.maxStoredRings {
                payload.liveRingSegments.removeFirst(
                    payload.liveRingSegments.count - LiveRing.maxStoredRings
                )
            }
        }
        clearLiveRingTracking()
    }

    func startPractice(from saved: SavedProgression? = nil) {
        isPracticeMode = true
        role = .host
        isInSession = true
        activeSetlist = nil
        activeSetlistIndex = 0
        metronome.stop()

        if let saved {
            applySavedProgression(saved, sessionName: L10n.practiceSessionName(saved.name))
            loadedProgressionID = saved.id
            isLiveProgressionSession = false
        } else {
            payload = SessionSyncPayload(
                sessionName: String(localized: "Practice"),
                key: .C,
                notation: .symbol,
                chords: [],
                activeChordID: nil,
                isHost: true
            )
            loadedProgressionID = nil
            isLiveProgressionSession = true
        }
        beginPracticeStats(named: payload.sessionName)
        pushWatchUpdate()
        activateSessionBackgroundServices()
    }

    func hostSession(
        name: String,
        key: MusicalKey,
        notation: ChordNotation,
        performanceMode: SessionPerformanceMode = .live,
        autoDetectKey: Bool = true
    ) {
        isPracticeMode = false
        activeSetlist = nil
        payload = SessionSyncPayload(
            sessionName: name,
            key: key,
            notation: notation,
            chords: [],
            activeChordID: nil,
            isHost: true
        )
        payload.performanceMode = performanceMode
        payload.displayMode = performanceMode.usesCompactStageUI ? .stage : .ring
        payload.ringShowsLiveChords = performanceMode.usesCompactStageUI
        payload.autoDetectKey = autoDetectKey
        payload.isKeyAutoDetected = false
        payload.isRemoteBackupEnabled = UserDefaults.standard.object(forKey: Self.remoteBackupDefaultsKey) as? Bool ?? true
        payload.sessionToken = UUID()
        loadedProgressionID = nil
        isLiveProgressionSession = true
        role = .host
        isInSession = true
        metronome.stop()
        beginHostingSession(named: name)
        pushWatchUpdate()
        activateSessionBackgroundServices()
    }

    /// Host a freestyle session — guests see only the current live chord (piano/MIDI), with no next-chord preview.
    func hostLiveChordsSession(
        name: String,
        key: MusicalKey,
        notation: ChordNotation,
        autoDetectKey: Bool = true
    ) {
        isPracticeMode = false
        activeSetlist = nil
        payload = SessionSyncPayload(
            sessionName: name,
            key: key,
            notation: notation,
            chords: [],
            activeChordID: nil,
            isHost: true
        )
        payload.performanceMode = .live
        payload.displayMode = .stage
        payload.isLiveChordsOnly = true
        payload.autoDetectKey = autoDetectKey
        payload.isKeyAutoDetected = false
        payload.isRemoteBackupEnabled = UserDefaults.standard.object(forKey: Self.remoteBackupDefaultsKey) as? Bool ?? true
        payload.sessionToken = UUID()
        loadedProgressionID = nil
        isLiveProgressionSession = false
        role = .host
        isInSession = true
        metronome.stop()
        beginHostingSession(named: name)
        pushWatchUpdate()
        activateSessionBackgroundServices()
    }

    func hostSession(from saved: SavedProgression, importGuide: ImportSessionGuide? = nil) {
        isPracticeMode = false
        activeSetlist = nil
        applySavedProgression(saved, sessionName: saved.name)
        loadedProgressionID = saved.id
        isLiveProgressionSession = false
        if payload.performanceMode.usesCompactStageUI {
            payload.displayMode = .stage
            payload.ringShowsLiveChords = true
        }
        payload.autoDetectKey = false
        payload.isKeyAutoDetected = false
        payload.isRemoteBackupEnabled = UserDefaults.standard.object(forKey: Self.remoteBackupDefaultsKey) as? Bool ?? true
        role = .host
        isInSession = true
        importSessionGuide = importGuide
        metronome.stop()
        beginHostingSession(named: saved.name)
        pushWatchUpdate()
        activateSessionBackgroundServices()
    }

    func clearImportSessionGuide() {
        importSessionGuide = nil
    }

    func hostSession(from setlist: Setlist, store: ProgressionStore, startingAt index: Int = 0) {
        let songs = store.progressions(for: setlist)
        guard !songs.isEmpty else { return }
        isPracticeMode = false
        activeSetlist = setlist
        activeSetlistIndex = min(max(0, index), songs.count - 1)
        let saved = songs[activeSetlistIndex]
        applySavedProgression(saved, sessionName: setlist.name)
        payload.setlistName = setlist.name
        payload.setlistSongIndex = activeSetlistIndex
        payload.setlistSongCount = songs.count
        payload.setlistSongTitles = songs.map(\.name)
        loadedProgressionID = saved.id
        isLiveProgressionSession = false
        payload.autoDetectKey = false
        payload.isKeyAutoDetected = false
        payload.isRemoteBackupEnabled = UserDefaults.standard.object(forKey: Self.remoteBackupDefaultsKey) as? Bool ?? true
        role = .host
        isInSession = true
        metronome.stop()
        beginHostingSession(named: setlist.name)
        pushWatchUpdate()
        activateSessionBackgroundServices()
    }

    func nextSetlistSong(store: ProgressionStore) {
        guard canDriveSession, let setlist = activeSetlist else { return }
        let songs = store.progressions(for: setlist)
        guard activeSetlistIndex + 1 < songs.count else { return }
        loadSetlistSong(at: activeSetlistIndex + 1, from: setlist, store: store, animated: false)
    }

    func previousSetlistSong(store: ProgressionStore) {
        guard canDriveSession, let setlist = activeSetlist else { return }
        guard activeSetlistIndex > 0 else { return }
        loadSetlistSong(at: activeSetlistIndex - 1, from: setlist, store: store, animated: false)
    }

    func loadSetlistSongAnimated(store: ProgressionStore) {
        guard canDriveSession, let setlist = activeSetlist else { return }
        let songs = store.progressions(for: setlist)
        guard activeSetlistIndex + 1 < songs.count else { return }
        loadSetlistSong(at: activeSetlistIndex + 1, from: setlist, store: store, animated: true)
    }

    func isLastSetlistSong(in store: ProgressionStore) -> Bool {
        guard let setlist = activeSetlist else { return true }
        let songs = store.progressions(for: setlist)
        return activeSetlistIndex + 1 >= songs.count
    }

    func importBackingTrack(from url: URL) throws {
        guard canDriveSession else { return }
        try backingTrack.importTrack(from: url)
        payload.backingTrackDisplayName = backingTrack.displayName
        payload.isBackingTrackPlaying = false
        sync()
    }

    func toggleBackingTrack() {
        guard canDriveSession, backingTrack.hasTrack else { return }
        if backingTrack.isPlaying {
            backingTrack.pause()
            payload.isBackingTrackPlaying = false
        } else {
            backingTrack.play()
            payload.isBackingTrackPlaying = true
        }
        refreshSessionAudioPolicy()
        sync()
    }

    func stopBackingTrack() {
        guard canDriveSession else { return }
        backingTrack.stop()
        payload.isBackingTrackPlaying = false
        refreshSessionAudioPolicy()
        sync()
    }

    func seekBackingTrack(to time: TimeInterval) {
        guard canDriveSession, backingTrack.hasTrack else { return }
        backingTrack.seek(to: time)
    }

    func skipBackingTrack(by interval: TimeInterval) {
        guard canDriveSession, backingTrack.hasTrack else { return }
        backingTrack.skip(by: interval)
    }

    func clearBackingTrack() {
        guard canDriveSession else { return }
        backingTrack.clear()
        payload.backingTrackDisplayName = ""
        payload.isBackingTrackPlaying = false
        sync()
    }

    private func pauseBackingTrackForSongChange() {
        backingTrack.clear()
        payload.backingTrackDisplayName = ""
        payload.isBackingTrackPlaying = false
    }

    private func loadSetlistSong(at index: Int, from setlist: Setlist, store: ProgressionStore, animated: Bool) {
        let songs = store.progressions(for: setlist)
        guard index >= 0, index < songs.count else { return }
        activeSetlistIndex = index
        let saved = songs[index]
        pauseBackingTrackForSongChange()

        if animated {
            beginSetlistTransition(to: saved.name)
            transitionTask?.cancel()
            transitionTask = Task { [weak self] in
                for tick in stride(from: 3, through: 1, by: -1) {
                    guard !Task.isCancelled, let self else { return }
                    self.payload.transitionCountdown = tick
                    self.sync()
                    try? await Task.sleep(for: .seconds(1))
                }
                guard !Task.isCancelled, let self else { return }
                self.finishSetlistTransition(
                    saved: saved,
                    setlist: setlist,
                    songCount: songs.count,
                    songTitles: songs.map(\.name)
                )
            }
        } else {
            applySavedProgression(saved, sessionName: setlist.name, preserveSessionToken: true)
            payload.setlistName = setlist.name
            payload.setlistSongIndex = activeSetlistIndex
            payload.setlistSongCount = songs.count
            payload.setlistSongTitles = songs.map(\.name)
            loadedProgressionID = saved.id
            sync()
        }
    }

    private func beginSetlistTransition(to title: String) {
        payload.transitionTitle = title
        payload.transitionCountdown = 3
        sync()
    }

    private func finishSetlistTransition(
        saved: SavedProgression,
        setlist: Setlist,
        songCount: Int,
        songTitles: [String]
    ) {
        applySavedProgression(saved, sessionName: setlist.name, preserveSessionToken: true)
        payload.setlistName = setlist.name
        payload.setlistSongIndex = activeSetlistIndex
        payload.setlistSongCount = songCount
        payload.setlistSongTitles = songTitles
        payload.transitionTitle = nil
        payload.transitionCountdown = nil
        loadedProgressionID = saved.id
        updateNextSetlistSongTitle()
        sync()
    }

    private func applySavedProgression(
        _ saved: SavedProgression,
        sessionName: String,
        preserveSessionToken: Bool = false
    ) {
        var archivedLiveRings: [[String]] = []
        if preserveSessionToken {
            beginNewLiveRingSegment()
            archivedLiveRings = payload.liveRingSegments
        }

        let cleaned = SongImportParser.sanitizeProgression(saved)
        let sortedChords = cleaned.chords.sorted { $0.order < $1.order }
        var newPayload = SessionSyncPayload(
            sessionName: sessionName,
            key: saved.key,
            notation: saved.notation,
            chords: sortedChords,
            activeChordID: sortedChords.first?.id,
            isHost: true
        )
        newPayload.tempoBPM = cleaned.tempoBPM
        newPayload.beatsPerBar = cleaned.beatsPerBar
        newPayload.beatUnit = cleaned.beatUnit
        newPayload.sections = cleaned.sections
        newPayload.lyrics = cleaned.lyrics
        newPayload.lyricsLines = cleaned.lyricsLines
        newPayload.loopStartChordID = cleaned.loopStartChordID
        newPayload.loopEndChordID = cleaned.loopEndChordID
        newPayload.isLoopEnabled = cleaned.isLoopEnabled
        newPayload.rehearsalNotes = cleaned.rehearsalNotes
        newPayload.syncedRoleNotes = cleaned.roleNotes
        newPayload.sessionToken = preserveSessionToken ? payload.sessionToken : UUID()
        if preserveSessionToken {
            newPayload.performanceMode = payload.performanceMode
            newPayload.displayMode = payload.displayMode
            newPayload.autoAdvanceSetlist = payload.autoAdvanceSetlist
            newPayload.showBeatSyncHints = payload.showBeatSyncHints
            newPayload.ringShowsLiveChords = payload.ringShowsLiveChords
            newPayload.liveRingSegments = archivedLiveRings
        } else {
            newPayload.displayMode = preferredDisplayMode(
                chordCount: sortedChords.count,
                sectionCount: cleaned.sections.count,
                hasLyrics: !cleaned.lyricsLines.isEmpty
            )
        }
        newPayload.isAutoAdvancePaused = false
        newPayload.isVampActive = false
        newPayload.activeCue = nil
        newPayload.isSongEnding = false
        newPayload.backingTrackDisplayName = ""
        newPayload.isBackingTrackPlaying = false
        backingTrack.clear()
        payload = newPayload
        updateActiveSection()
        applyMetronome()
    }

    private func preferredDisplayMode(chordCount: Int, sectionCount: Int, hasLyrics: Bool) -> SessionDisplayMode {
        if sectionCount >= 2 {
            return .ring
        }
        if chordCount > 10 {
            return hasLyrics ? .chart : .stage
        }
        if chordCount > 6 {
            return .stage
        }
        return .ring
    }

    func snapshotForSaving(named name: String, overwrite: Bool) -> SavedProgression {
        SavedProgression(
            id: overwrite ? (loadedProgressionID ?? UUID()) : UUID(),
            name: name,
            key: payload.key,
            notation: payload.notation,
            chords: sortedChords,
            tempoBPM: payload.tempoBPM,
            beatsPerBar: payload.beatsPerBar,
            beatUnit: payload.beatUnit,
            sections: payload.sections,
            lyrics: payload.lyrics,
            loopStartChordID: payload.loopStartChordID,
            loopEndChordID: payload.loopEndChordID,
            isLoopEnabled: payload.isLoopEnabled,
            lyricsLines: payload.lyricsLines,
            rehearsalNotes: payload.rehearsalNotes
        )
    }

    #if os(macOS) || os(iOS)
    func applyChordsFromServiceLearning(_ chords: [ChordEntry]) {
        guard !chords.isEmpty else { return }
        let sorted = chords.sorted { $0.order < $1.order }
        payload.chords = sorted
        payload.activeChordID = sorted.first?.id
        isLiveProgressionSession = false
    }
    #endif

    func setRehearsalNotes(_ notes: String) {
        guard canDriveSession else { return }
        payload.rehearsalNotes = notes
        sync()
    }

    func setShowBeatSyncHints(_ enabled: Bool) {
        guard canDriveSession else { return }
        payload.showBeatSyncHints = enabled
        sync()
    }

    func toggleSectionLoop() {
        guard canDriveSession else { return }
        payload.isSectionLoopEnabled.toggle()
        sync()
    }

    func passControl(to peer: MCPeerID) {
        guard role == .host else { return }
        promoteCoHost(peer)
    }

    func rehostRecent(_ record: RecentSessionRecord, store: ProgressionStore) {
        if let match = store.progressions.first(where: { $0.name == record.progressionName }) {
            hostSession(from: match)
            return
        }
        hostSession(
            name: record.sessionName,
            key: record.key,
            notation: .symbol,
            performanceMode: .live
        )
    }

    func attemptReconnect(to record: RecentSessionRecord) {
        pendingReconnectRecord = record
        connectedHostDeviceName = record.hostDeviceName
        showReconnectBanner = true
        role = .guest
        isPracticeMode = false
        sessionManager.startBrowsing()
        startReconnectPolling()
    }

    func tryAutoReconnectIfPossible() {
        guard let record = pendingReconnectRecord else { return }
        guard showReconnectBanner else { return }
        if case .connected = sessionManager.connectionState { return }
        if !sessionManager.connectedPeers.isEmpty { return }
        if sessionManager.isInviting { return }

        if let host = sessionManager.discoveredHosts.first(where: { host in
            host.peer.displayName == record.hostDeviceName &&
            (host.sessionToken == record.sessionToken || host.sessionName == record.sessionName)
        }) {
            join(host: host)
            return
        }

        if let code = record.remoteJoinCode ?? payload.remoteJoinCode, RemoteJoinCode.isValid(code) {
            Task { await reconnectViaRemoteCode(code) }
        }
    }

    private func reconnectViaRemoteCode(_ code: String) async {
        guard showReconnectBanner || guestReconnectInProgress || isInSession else { return }
        cloudRelay.startPolling(joinCode: code)
        if let initial = await cloudRelay.fetchSession(joinCode: code) {
            isInSession = true
            role = .guest
            isRemoteLinkActive = true
            guestReconnectInProgress = false
            showReconnectBanner = false
            pendingReconnectRecord = nil
            connectedHostDeviceName = initial.sessionName
            applyGuestPayload(initial, fromRemote: true)
            activateSessionBackgroundServices()
        }
    }

    private func assignRemoteJoinCredentials(forSessionName name: String) {
        guard payload.remoteJoinCode == nil else { return }
        let myName = SessionManager.currentDisplayName()
        if let recent = RecentSessionStore.records.first(where: { record in
            record.hostDeviceName == myName &&
            record.sessionName == name &&
            record.remoteJoinCode != nil &&
            Date().timeIntervalSince(record.lastJoinedAt) < 45 * 60
        }) {
            payload.remoteJoinCode = recent.remoteJoinCode
            payload.sessionToken = recent.sessionToken
        } else {
            payload.remoteJoinCode = RemoteJoinCode.generate()
        }
    }

    private func handleGuestDisconnected() {
        guard role == .guest, isInSession else { return }
        guard !guestReconnectInProgress else { return }
        guestReconnectInProgress = true
        showReconnectBanner = true
        let hostName = connectedHostDeviceName.isEmpty
            ? RecentSessionStore.records.first(where: { $0.sessionToken == payload.sessionToken })?.hostDeviceName ?? ""
            : connectedHostDeviceName
        pendingReconnectRecord = RecentSessionRecord(
            sessionName: payload.sessionName,
            hostDeviceName: hostName,
            sessionToken: payload.sessionToken,
            key: payload.key,
            lastActiveChordID: payload.activeChordID,
            progressionName: payload.sessionName,
            remoteJoinCode: payload.remoteJoinCode
        )
        RecentSessionStore.updateProgress(
            sessionToken: payload.sessionToken,
            activeChordID: payload.activeChordID,
            progressionName: payload.sessionName
        )
        if payload.isRemoteBackupEnabled, let code = payload.remoteJoinCode {
            cloudRelay.startPolling(joinCode: code)
            Task { await reconnectViaRemoteCode(code) }
        }
        sessionManager.startBrowsing()
        startReconnectPolling()
    }

    private func startReconnectPolling() {
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            for _ in 0..<72 {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled, let self, self.showReconnectBanner else { return }
                self.tryAutoReconnectIfPossible()
            }
        }
    }

    private func stopReconnectPolling() {
        reconnectTask?.cancel()
        reconnectTask = nil
    }

    private func beginHostingSession(named name: String) {
        if payload.isRemoteBackupEnabled {
            assignRemoteJoinCredentials(forSessionName: name)
        }
        sessionManager.startHosting(
            sessionName: name,
            key: payload.key,
            tempoBPM: Int(payload.tempoBPM.rounded()),
            sessionToken: payload.sessionToken
        )
        RecentSessionStore.rememberJoin(
            sessionName: name,
            hostDeviceName: SessionManager.currentDisplayName(),
            sessionToken: payload.sessionToken,
            key: payload.key,
            progressionName: name,
            remoteJoinCode: payload.remoteJoinCode
        )
        Task { await startRemoteHostingIfNeeded() }
    }

    private func startRemoteHostingIfNeeded() async {
        guard role == .host, payload.isRemoteBackupEnabled, let code = payload.remoteJoinCode else { return }
        await cloudRelay.refreshAccountStatus()
        cloudRelay.beginHosting(joinCode: code, sessionToken: payload.sessionToken)
        cloudRelay.schedulePublish(payload: payload, joinCode: code)
    }

    func setRemoteBackupEnabled(_ enabled: Bool) {
        guard canDriveSession, role == .host else { return }
        payload.isRemoteBackupEnabled = enabled
        if enabled {
            if payload.remoteJoinCode == nil {
                payload.remoteJoinCode = RemoteJoinCode.generate()
            }
            Task { await startRemoteHostingIfNeeded() }
        } else if let code = payload.remoteJoinCode {
            let relay = cloudRelay
            Task { await relay.stopHosting(joinCode: code) }
        }
        sync()
    }

    func joinWithRemoteCode(
        _ rawCode: String,
        maxAttempts: Int = 10,
        retryDelay: TimeInterval = 2
    ) async -> Bool {
        cloudRelay.clearError()
        sessionManager.lastError = nil
        let code = RemoteJoinCode.normalize(rawCode)
        guard RemoteJoinCode.isValid(code) else {
            sessionManager.lastError = String(localized: "Enter a 6-character join code.")
            return false
        }

        await cloudRelay.refreshAccountStatus()

        let attempts = max(1, maxAttempts)
        for attempt in 0..<attempts {
            if Task.isCancelled { return false }

            if let initial = await cloudRelay.fetchSession(joinCode: code) {
                isPracticeMode = false
                role = .guest
                payload = initial
                isInSession = true
                isRemoteLinkActive = true
                sessionManager.syncQuality = .remote
                showReconnectBanner = false
                pendingReconnectRecord = nil
                guestReconnectInProgress = false
                connectedHostDeviceName = initial.sessionName
                cloudRelay.startPolling(joinCode: code)
                RecentSessionStore.rememberJoin(
                    sessionName: initial.sessionName,
                    hostDeviceName: initial.sessionName,
                    sessionToken: initial.sessionToken,
                    key: initial.key,
                    progressionName: initial.sessionName,
                    remoteJoinCode: code
                )
                activateSessionBackgroundServices()
                applyMetronome()
                pushWatchUpdate(chordChanged: true)
                #if os(iOS)
                refreshLockScreenDisplay(force: true)
                #endif
                return true
            }

            if attempt < attempts - 1 {
                try? await Task.sleep(for: .seconds(retryDelay))
                if Task.isCancelled { return false }
            }
        }

        if sessionManager.lastError == nil {
            sessionManager.lastError = cloudRelay.lastError
                ?? String(localized: "No live session found for that code. Ask the host to wait for the green checkmark on their join code.")
        }
        return false
    }

    func setLyricsLines(_ lines: [LyricsLine]) {
        guard canDriveSession else { return }
        payload.lyricsLines = lines
        sync()
    }

    func setPerformanceMode(_ mode: SessionPerformanceMode) {
        guard canDriveSession else { return }
        payload.performanceMode = mode
        if mode == .live, payload.displayMode == .ring {
            payload.displayMode = .stage
        }
        sync()
    }

    func setDisplayMode(_ mode: SessionDisplayMode) {
        guard canDriveSession else { return }
        payload.displayMode = mode
        sync()
    }

    func setRingShowsLiveChords(_ showsLive: Bool) {
        guard canDriveSession else { return }
        payload.ringShowsLiveChords = showsLive
        sync()
    }

    func setAutoDetectKey(_ enabled: Bool) {
        guard canDriveSession else { return }
        payload.autoDetectKey = enabled
        if enabled {
            maybeAutoDetectKey()
        } else {
            payload.isKeyAutoDetected = false
            pendingDetectedKey = nil
            pendingDetectedKeyHits = 0
        }
        sync()
    }

    func promoteCoHost(_ peer: MCPeerID) {
        guard role == .host else { return }
        payload.coHostPeerName = peer.displayName
        sync()
    }

    func demoteCoHost() {
        guard role == .host else { return }
        payload.coHostPeerName = nil
        sync()
    }

    func sendLiveCue(_ text: String, symbol: String = "megaphone.fill") {
        let cue = LiveCue(text: text, symbol: symbol, sentAt: Date().timeIntervalSince1970)
        sendLiveCue(cue)
    }

    func sendLiveCue(_ cue: LiveCue) {
        guard canDriveSession else { return }
        applyCueAction(cue.text)
        cueClearTask?.cancel()
        payload.activeCue = cue
        notifyFeatureSyncHooks(cueText: cue.text)
        sync()
        cueClearTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled, let self else { return }
            if self.payload.activeCue?.sentAt == cue.sentAt {
                self.payload.activeCue = nil
                self.sync()
            }
        }
    }

    private func applyCueAction(_ cueText: String) {
        switch cueText {
        case "Hold":
            payload.isAutoAdvancePaused.toggle()
        case "Vamp":
            payload.isVampActive.toggle()
            if payload.isVampActive {
                payload.isAutoAdvancePaused = false
            }
        case "Break":
            if payload.isMetronomePlaying {
                payload.isMetronomePlaying = false
                payload.metronomeStartEpoch = nil
                payload.isCountingIn = false
                payload.countInStartEpoch = nil
                applyMetronome()
            }
        case "Repeat":
            if !payload.isSectionLoopEnabled {
                payload.isSectionLoopEnabled = true
            }
        case "Ending":
            signalSongEndingIfNeeded()
        default:
            break
        }
    }

    /// True during the last bar before a timed chord change.
    var shouldShowChordChangeWarning: Bool {
        guard !payload.isAutoAdvancePaused, !payload.isVampActive, !payload.isLiveChordsOnly else { return false }
        guard payload.isMetronomePlaying, !payload.isCountingIn else { return false }
        guard let active = activeChord, let duration = active.durationBeats, duration > 0 else { return false }
        let total = Int(duration.rounded())
        guard total > payload.beatsPerBar else { return false }
        let remaining = total - payload.beatsOnActiveChord
        return remaining > 0 && remaining <= payload.beatsPerBar
    }

    var chordChangeBeatsRemaining: Int? {
        guard shouldShowChordChangeWarning,
              let active = activeChord,
              let duration = active.durationBeats else { return nil }
        return max(0, Int(duration.rounded()) - payload.beatsOnActiveChord)
    }

    func triggerChordChangeWarningHaptic() {
        #if os(iOS)
        let enabled = role == .host || GuestDisplaySettings.watchHapticsEnabled
        guard enabled else { return }
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        #endif
    }

    func jumpToSection(_ section: SectionMarker) {
        jumpToSection(id: section.id)
    }

    func jumpToSection(id sectionID: UUID) {
        if isCoHost, role == .guest {
            requestControlAction(.jumpToSection(sectionID))
            return
        }
        guard canDriveSession else { return }
        guard let section = payload.sections.first(where: { $0.id == sectionID }),
              let chord = payload.chords.first(where: { $0.id == section.startChordID }) else { return }
        setActiveChord(chord)
    }

    func addSection(kind: WorshipSectionKind, at chord: ChordEntry, customName: String? = nil) {
        guard canDriveSession else { return }
        let name: String
        if let customName, !customName.isEmpty {
            name = customName
        } else {
            let existing = payload.sections.filter { $0.kind == kind }.count
            name = existing > 0 ? L10n.numberedSectionName(kind.defaultName, number: existing + 1) : kind.defaultName
        }
        let marker = SectionMarker(name: name, startChordID: chord.id, kind: kind)
        payload.sections.append(marker)
        updateActiveSection()
        sync()
    }

    func advanceChord() {
        if isCoHost, role == .guest {
            requestControlAction(.advanceChord)
            return
        }
        guard canDriveSession else { return }
        advanceToNextChord()
    }

    func previousChord() {
        if isCoHost, role == .guest {
            requestControlAction(.previousChord)
            return
        }
        guard canDriveSession else { return }

        if !payload.sections.isEmpty {
            previousWithinActiveSection()
            return
        }

        let sorted = sortedChords
        guard sorted.count > 1,
              let activeID = payload.activeChordID,
              let index = sorted.firstIndex(where: { $0.id == activeID }) else { return }
        let prevIndex = (index - 1 + sorted.count) % sorted.count
        payload.activeChordID = sorted[prevIndex].id
        payload.beatsOnActiveChord = 0
        updateActiveSection()
        sync()
    }

    func setAutoAdvanceSetlist(_ enabled: Bool) {
        guard canDriveSession else { return }
        autoAdvanceSetlistSongs = enabled
        payload.autoAdvanceSetlist = enabled
        sync()
    }

    func midiSetSourceConnected(id: Int32, connected: Bool) {
        midi.setSourceConnected(id: id, connected: connected)
    }

    func midiConnectAllSources() {
        midi.connectAllSources()
    }

    func markSaved(as progression: SavedProgression) {
        loadedProgressionID = progression.id
        isLiveProgressionSession = false
        payload.sessionName = progression.name
        sync()
    }

    func beginJoining() {
        isPracticeMode = false
        role = .guest
        guestReconnectInProgress = false
        cloudRelay.clearError()
        sessionManager.startBrowsing()
    }

    func cancelJoinBrowsing() {
        stopReconnectPolling()
        showReconnectBanner = false
        pendingReconnectRecord = nil
        guestReconnectInProgress = false
        cloudRelay.stopPolling()
        guard !isInSession else { return }
        sessionManager.disconnect()
        role = .none
    }

    func join(host: DiscoveredHost) {
        isPracticeMode = false
        role = .guest
        connectedHostDeviceName = host.peer.displayName
        sessionManager.joinHost(host)
        guard sessionManager.lastError == nil, sessionManager.isInviting else { return }
        isInSession = true
        showReconnectBanner = false
        pendingReconnectRecord = nil
        guestReconnectInProgress = false
        RecentSessionStore.rememberJoin(
            sessionName: host.sessionName,
            hostDeviceName: host.peer.displayName,
            sessionToken: host.sessionToken ?? UUID(),
            key: host.key ?? .C,
            remoteJoinCode: nil
        )
        activateSessionBackgroundServices()
    }

    func addChord(symbolName: String, latinName: String) {
        guard canDriveSession else { return }
        isLiveProgressionSession = false
        let order = payload.chords.count
        let chord = ChordEntry(symbolName: symbolName, latinName: latinName, order: order)
        payload.chords.append(chord)
        if payload.activeChordID == nil {
            payload.activeChordID = chord.id
        }
        sync()
    }

    func removeChord(_ chord: ChordEntry) {
        guard canDriveSession else { return }
        payload.chords.removeAll { $0.id == chord.id }
        payload.sections.removeAll { $0.startChordID == chord.id }
        reindexChords()
        if payload.activeChordID == chord.id {
            payload.activeChordID = sortedChords.first?.id
        }
        if sortedChords.isEmpty, loadedProgressionID == nil {
            isLiveProgressionSession = true
        }
        sync()
    }

    func updateProgressionChords(_ chords: [ChordEntry]) {
        guard canDriveSession else { return }
        isLiveProgressionSession = false
        payload.chords = chords
        if let activeID = payload.activeChordID,
           !chords.contains(where: { $0.id == activeID }) {
            payload.activeChordID = chords.first?.id
        } else if payload.activeChordID == nil {
            payload.activeChordID = chords.first?.id
        }
        if chords.isEmpty, loadedProgressionID == nil {
            isLiveProgressionSession = true
        }
        sync()
    }

    func setActiveChord(_ chord: ChordEntry) {
        if isCoHost, role == .guest {
            requestControlAction(.setActiveChord(chord.id))
            return
        }
        guard canDriveSession else { return }
        payload.activeChordID = chord.id
        payload.beatsOnActiveChord = 0
        updateActiveSection()
        notifyFeatureSyncHooks(chordChanged: true)
        sync()
    }

    func updateNotation(_ notation: ChordNotation) {
        guard canDriveSession else { return }
        payload.notation = notation
        sync()
    }

    /// Cycles symbol → solfège → Nashville. Host updates the session; guests change only their chart.
    func cycleDisplayNotation(isGuest: Bool) {
        let current = displayNotation(isGuest: isGuest)
        let next = current.nextInCycle()
        if isGuest {
            UserDefaults.standard.set(next.rawValue, forKey: "preferredNotation")
            displayNotationVersion += 1
            pushWatchUpdate(chordChanged: true)
            #if os(iOS)
            refreshLockScreenDisplay(force: true)
            #endif
        } else if canDriveSession {
            updateNotation(next)
        }
    }

    func transpose(to newKey: MusicalKey) {
        guard canDriveSession else { return }
        let steps = Transposer.semitones(from: payload.key, to: newKey)
        guard steps != 0 else { return }

        if payload.isKeyAutoDetected, let detected = keyUsedForAutoDetection {
            var symbols = symbolsAtLastAutoKeyDetection
            if symbols.isEmpty {
                symbols = payload.freestyleChordSymbols
                if let live = payload.liveChordSymbol, !LiveRing.contains(live, in: symbols) {
                    symbols.append(live)
                }
            }
            AdaptiveKeyLearningEngine.shared.recordCorrection(
                symbols: symbols,
                detectedKey: detected,
                correctedKey: newKey,
                sessionName: payload.sessionName
            )
        }

        pendingDetectedKey = nil
        pendingDetectedKeyHits = 0
        payload.isKeyAutoDetected = false
        symbolsAtLastAutoKeyDetection = []
        keyUsedForAutoDetection = nil

        if isLiveProgressionSession {
            beginNewLiveRingSegment()
            payload.chords = []
            payload.activeChordID = nil
            payload.beatsOnActiveChord = 0
            updateActiveSection()
        } else {
            let preferFlats = newKey.prefersFlats
            payload.chords = payload.chords.map { chord in
                let newSymbol = Transposer.transpose(symbol: chord.symbolName, by: steps, preferFlats: preferFlats)
                return chord.copying(
                    symbolName: newSymbol,
                    latinName: ChordCatalog.latinName(forSymbol: newSymbol)
                )
            }
        }
        payload.key = newKey
        sync()
    }

    func setLoopRange(start: ChordEntry?, end: ChordEntry?, enabled: Bool) {
        guard canDriveSession else { return }
        payload.loopStartChordID = start?.id
        payload.loopEndChordID = end?.id
        payload.isLoopEnabled = enabled && start != nil && end != nil
        sync()
    }

    func setProgressionLyrics(_ lyrics: String) {
        guard canDriveSession else { return }
        payload.lyrics = lyrics
        sync()
    }

    func setSections(_ sections: [SectionMarker]) {
        guard canDriveSession else { return }
        payload.sections = sections
        updateActiveSection()
        sync()
    }

    func setCountInBars(_ bars: Int) {
        guard canDriveSession else { return }
        payload.countInBars = max(0, min(bars, 4))
        sync()
    }

    func toggleMetronome() {
        guard canDriveSession else { return }
        #if os(macOS) || os(iOS)
        if !payload.isMetronomePlaying, soloAccompanimentEnabled, isSoloDrumGroovePlaying {
            return
        }
        #endif
        if payload.isMetronomePlaying {
            payload.isMetronomePlaying = false
            payload.metronomeStartEpoch = nil
            payload.isCountingIn = false
            payload.countInStartEpoch = nil
        } else {
            let now = Date().timeIntervalSince1970
            payload.isMetronomePlaying = true
            if payload.countInBars > 0 {
                payload.isCountingIn = true
                payload.countInStartEpoch = now
                let barDuration = (60.0 / payload.tempoBPM) * (4.0 / Double(payload.beatUnit)) * Double(payload.beatsPerBar)
                payload.metronomeStartEpoch = now + barDuration * Double(payload.countInBars)
            } else {
                payload.isCountingIn = false
                payload.countInStartEpoch = nil
                payload.metronomeStartEpoch = now
            }
        }
        applyMetronome()
        sync()
    }

    func setTempo(_ bpm: Double) {
        guard canDriveSession else { return }
        let clamped = min(max(bpm, Self.minBPM), Self.maxBPM).rounded()
        guard clamped != payload.tempoBPM else { return }
        payload.tempoBPM = clamped
        if payload.isMetronomePlaying {
            let now = Date().timeIntervalSince1970
            if payload.countInBars > 0, !payload.isCountingIn {
                payload.isCountingIn = true
                payload.countInStartEpoch = now
                let barDuration = (60.0 / payload.tempoBPM) * (4.0 / Double(payload.beatUnit)) * Double(payload.beatsPerBar)
                payload.metronomeStartEpoch = now + barDuration * Double(payload.countInBars)
            } else if payload.isCountingIn == false {
                payload.metronomeStartEpoch = now
            }
        }
        applyMetronome()
        sync()
    }

    func setTimeSignature(beats: Int, unit: Int) {
        guard canDriveSession else { return }
        payload.beatsPerBar = max(1, beats)
        payload.beatUnit = max(1, unit)
        if payload.isMetronomePlaying, !payload.isCountingIn {
            payload.metronomeStartEpoch = Date().timeIntervalSince1970
        }
        applyMetronome()
        sync()
    }

    func openPiano() {
        guard canDriveSession else { return }
        payload.isPianoActive = true
        sync()
    }

    func closePiano() {
        guard canDriveSession else { return }
        payload.isPianoActive = false
        payload.pianoNotes = []
        sync()
    }

    func playPianoNote(_ index: Int) {
        guard canDriveSession else { return }
        let nextNotes: [Int] = payload.pianoNotes == [index] ? [] : [index]
        applyPianoNotes(nextNotes)
    }

    func clearPianoNotes() {
        guard canDriveSession else { return }
        payload.liveChordSymbol = nil
        applyPianoNotes([])
    }

    var fretChord: ChordEntry? {
        guard let id = payload.fretChordID else { return nil }
        return payload.chords.first { $0.id == id }
    }

    func openFretboard() {
        guard canDriveSession else { return }
        payload.isFretboardActive = true
        if payload.fretChordID == nil || fretChord == nil {
            payload.fretChordID = payload.activeChordID ?? sortedChords.first?.id
        }
        sync()
    }

    func closeFretboard() {
        guard canDriveSession else { return }
        payload.isFretboardActive = false
        sync()
    }

    func setFretInstrument(_ instrument: FretInstrument) {
        guard canDriveSession else { return }
        payload.fretInstrument = instrument
        sync()
    }

    func setBassStrings(_ count: Int) {
        guard canDriveSession else { return }
        payload.bassStrings = count
        sync()
    }

    func setFretChord(_ chord: ChordEntry) {
        guard canDriveSession else { return }
        payload.fretChordID = chord.id
        sync()
    }

    func setGuestMetronomeAudioEnabled(_ enabled: Bool) {
        let effective = enabled && !GuestDisplaySettings.acousticRoomMode
        metronome.localAudioEnabled = effective
        applyMetronome()
    }

    func reapplyGuestMetronomeAudioPreference() {
        guard role == .guest else { return }
        let enabled = UserDefaults.standard.object(forKey: "guestMetronomeAudioEnabled") as? Bool ?? true
        setGuestMetronomeAudioEnabled(enabled)
    }

    func refreshMetronomeAudioPolicy() {
        #if os(macOS) || os(iOS)
        if soloAccompanimentEnabled, soloTempoLocked, isSoloDrumGroovePlaying {
            metronome.localAudioEnabled = false
            applyMetronome()
            return
        }
        #endif
        if role == .host || isPracticeMode {
            metronome.localAudioEnabled = true
        } else if role == .guest {
            let guestAudio = UserDefaults.standard.object(forKey: "guestMetronomeAudioEnabled") as? Bool ?? true
            metronome.localAudioEnabled = guestAudio && !GuestDisplaySettings.acousticRoomMode
        }
        applyMetronome()
        applyClickTrackLaneVolume()
    }

    private func handleMetronomeBeat() {
        guard canDriveSession, payload.isMetronomePlaying, !payload.isCountingIn else { return }

        if metronome.currentBeat == 0 {
            processTempoRampOnBar()
        }

        guard let active = activeChord else { return }
        guard !payload.isAutoAdvancePaused else { return }

        payload.beatsOnActiveChord += 1
        if let duration = active.durationBeats, payload.beatsOnActiveChord >= Int(duration.rounded()) {
            if payload.isVampActive {
                payload.beatsOnActiveChord = 0
                sync()
                return
            }
            let sorted = sortedChords
            if autoAdvanceSetlistSongs,
               let activeID = payload.activeChordID,
               let index = sorted.firstIndex(where: { $0.id == activeID }),
               index + 1 >= sorted.count,
               activeSetlist != nil {
                shouldAutoAdvanceSetlist = true
            } else {
                advanceToNextChord()
            }
        }
    }

    private func advanceToNextChord() {
        payload.isVampActive = false

        if !payload.sections.isEmpty {
            advanceWithinActiveSection()
            return
        }

        let sorted = sortedChords
        guard sorted.count > 1, let activeID = payload.activeChordID,
              let index = sorted.firstIndex(where: { $0.id == activeID }) else { return }

        if payload.isLoopEnabled,
           let loopEnd = payload.loopEndChordID,
           activeID == loopEnd,
           let loopStart = payload.loopStartChordID,
           let startChord = sorted.first(where: { $0.id == loopStart }) {
            payload.activeChordID = startChord.id
        } else if index + 1 >= sorted.count {
            payload.activeChordID = sorted[index].id
            if autoAdvanceSetlistSongs, activeSetlist != nil {
                shouldAutoAdvanceSetlist = true
            } else {
                signalSongEndingIfNeeded()
            }
        } else {
            payload.activeChordID = sorted[index + 1].id
        }
        payload.beatsOnActiveChord = 0
        updateActiveSection()
        sync()
    }

    private func isOnLastChord(_ chordID: UUID?) -> Bool {
        guard let chordID, let last = sortedChords.last else { return false }
        return chordID == last.id
    }

    private func signalSongEndingIfNeeded() {
        guard !payload.isLiveChordsOnly, !sortedChords.isEmpty else { return }
        payload.isSongEnding = true
        sync()
        songEndingTask?.cancel()
        songEndingTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, let self else { return }
            self.payload.isSongEnding = false
            self.sync()
        }
    }

    private func advanceWithinActiveSection() {
        let sectionChords = chordsInActiveSection()
        guard !sectionChords.isEmpty,
              let activeID = payload.activeChordID,
              let index = sectionChords.firstIndex(where: { $0.id == activeID }) else { return }

        if index + 1 < sectionChords.count {
            payload.activeChordID = sectionChords[index + 1].id
        } else if payload.isSectionLoopEnabled {
            if payload.sectionLoopCountInBars > 0, canDriveSession {
                triggerSectionLoopCountIn()
            }
            payload.activeChordID = sectionChords[0].id
        } else if let active = activeSection,
                  let sectionIndex = sectionsInOrder.firstIndex(where: { $0.id == active.id }),
                  sectionIndex + 1 < sectionsInOrder.count {
            let nextSection = sectionsInOrder[sectionIndex + 1]
            if let first = chords(for: nextSection).first {
                payload.activeChordID = first.id
            } else {
                payload.activeChordID = sectionChords[0].id
            }
        } else {
            payload.activeChordID = sectionChords[index].id
            if autoAdvanceSetlistSongs, activeSetlist != nil, isOnLastChord(sectionChords[index].id) {
                shouldAutoAdvanceSetlist = true
            } else {
                signalSongEndingIfNeeded()
            }
        }
        payload.beatsOnActiveChord = 0
        updateActiveSection()
        sync()
    }

    private func previousWithinActiveSection() {
        let sectionChords = chordsInActiveSection()
        guard !sectionChords.isEmpty,
              let activeID = payload.activeChordID,
              let index = sectionChords.firstIndex(where: { $0.id == activeID }) else { return }

        if index > 0 {
            payload.activeChordID = sectionChords[index - 1].id
        } else if let active = activeSection,
                  let sectionIndex = sectionsInOrder.firstIndex(where: { $0.id == active.id }),
                  sectionIndex > 0 {
            let previousSection = sectionsInOrder[sectionIndex - 1]
            let previousChords = chords(for: previousSection)
            payload.activeChordID = previousChords.last?.id ?? sectionChords[0].id
        } else {
            payload.activeChordID = sectionChords[sectionChords.count - 1].id
        }
        payload.beatsOnActiveChord = 0
        updateActiveSection()
        sync()
    }

    private func updateActiveSection() {
        payload.activeSectionID = activeSection?.id
        handleExtendedFeatureSectionChange(to: activeSection)
    }

    private func applyMetronome() {
        #if os(iOS)
        let bpm = displayedSessionTempoBPM
        let isPlaying = displayedMetronomePlaying
        #else
        let bpm = payload.tempoBPM
        let isPlaying = payload.isMetronomePlaying
        #endif
        metronome.apply(
            bpm: bpm,
            beatsPerBar: payload.beatsPerBar,
            beatUnit: payload.beatUnit,
            isPlaying: isPlaying,
            startEpoch: payload.metronomeStartEpoch ?? Date().timeIntervalSince1970,
            clockOffset: role == .guest ? sessionManager.clockOffset : 0,
            countInBars: payload.countInBars,
            isCountingIn: payload.isCountingIn,
            countInStartEpoch: payload.countInStartEpoch
        )
        refreshSessionAudioPolicy()
    }

    func refreshSessionAudioPolicy() {
        #if os(iOS)
        let needsAudioEngine: Bool = {
            if displayedMetronomePlaying || payload.isCountingIn { return true }
            if backingTrack.isPlaying { return true }
            if soloAccompanimentEnabled {
                if drumAccompaniment.isPlaying { return true }
                if bassAccompaniment.isPlaying { return true }
                if livePerformanceFusion.isAudioListening { return true }
            }
            if role == .host { return false }
            return isInSession && isAppInBackground
        }()
        metronome.setSessionKeepAlive(needsAudioEngine)
        #endif
    }

    func leaveSession() {
        transitionTask?.cancel()
        transitionTask = nil
        pianoSideEffectsTask?.cancel()
        pianoSideEffectsTask = nil
        cueClearTask?.cancel()
        cueClearTask = nil
        songEndingTask?.cancel()
        songEndingTask = nil
        reconnectTask?.cancel()
        reconnectTask = nil
        midiSyncTask?.cancel()
        midiSyncTask = nil
        outboundSyncTask?.cancel()
        outboundSyncTask = nil
        outboundSyncNeedsFull = false
        outboundSyncLivePending = false
        outboundSyncImmediate = false
        hostKeepAliveTask?.cancel()
        hostKeepAliveTask = nil
        groovePreviewTask?.cancel()
        groovePreviewTask = nil
        lastSyncedLiveChordSymbol = nil
        liveWireRevision = 0
        lastAppliedLiveWireRevision = 0
        stopReconnectPolling()
        showReconnectBanner = false
        pendingReconnectRecord = nil
        guestReconnectInProgress = false
        connectedHostDeviceName = ""
        if role == .host, payload.isRemoteBackupEnabled {
            cloudRelay.stopPublishingOnly()
        } else {
            cloudRelay.stopAll()
        }
        isRemoteLinkActive = false
        // Dismiss session UI before tearing down Multipeer so SwiftUI is not
        // still observing connectedPeers while SF Symbol layers animate away.
        isInSession = false
        if !isPracticeMode {
            sessionManager.disconnect()
        }
        clearInferredLiveProgression(resetEngine: true)
        deactivateSessionBackgroundServices()
        metronome.stop()
        backingTrack.clear()
        #if os(macOS) || os(iOS)
        stopSoloAccompaniment()
        #endif
        if isPracticeMode {
            endPracticeStats()
        }
        if payload.isRecordingRehearsal {
            payload.isRecordingRehearsal = false
            _ = rehearsalStore.stopRecording(name: payload.sessionName)
        }
        rehearsalStore.stopReplay()
        endExtendedFeatureSession()
        isPracticeMode = false
        role = .none
        payload = .empty
        loadedProgressionID = nil
        isLiveProgressionSession = false
        activeSetlist = nil
        activeSetlistIndex = 0
    }

    #if os(iOS)
    func handleAppDidEnterBackground() {
        guard isInSession else { return }
        isAppInBackground = true
        sessionBackground.begin()
        if role == .host {
            sessionManager.refreshHostingIfNeeded()
        }
        refreshSessionAudioPolicy()
        if metronome.isRunning || role == .guest {
            metronome.reassertBackgroundPlayback()
        }
        refreshLockScreenDisplay(force: true)
        startBackgroundRefreshLoop()
    }

    func handleAppDidBecomeActive() {
        isAppInBackground = false
        stopBackgroundRefreshLoop()
        sessionBackground.end()
        if isInSession {
            if role == .host {
                sessionManager.refreshHostingIfNeeded()
                sync()
            }
            refreshSessionAudioPolicy()
            if metronome.isRunning || role == .guest {
                metronome.reassertBackgroundPlayback()
            }
            refreshLockScreenDisplay(force: true)
        }
    }

    func refreshLockScreenDisplay(force: Bool = false) {
        guard isInSession else { return }
        LiveActivityManager.update(from: self, force: force)
    }

    private func activateSessionBackgroundServices() {
        beginExtendedFeatureSession()
        refreshMetronomeAudioPolicy()
        setScreenAlwaysOn(true)
        metronome.setSessionKeepAlive(false)
        refreshSessionAudioPolicy()
        LiveActivityManager.update(from: self, force: true)
        if role == .host {
            startHostSyncKeepAlive()
        }
    }

    private func deactivateSessionBackgroundServices() {
        setScreenAlwaysOn(false)
        stopBackgroundRefreshLoop()
        stopHostSyncKeepAlive()
        isAppInBackground = false
        sessionBackground.end()
        metronome.setSessionKeepAlive(false)
        LiveActivityManager.end()
    }

    private func setScreenAlwaysOn(_ enabled: Bool) {
        UIApplication.shared.isIdleTimerDisabled = enabled
    }

    private func startBackgroundRefreshLoop() {
        stopBackgroundRefreshLoop()
        backgroundRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(8))
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self, self.isInSession, self.isAppInBackground else { return }
                    self.refreshSessionAudioPolicy()
                    if self.metronome.isRunning || self.role == .guest {
                        self.metronome.reassertBackgroundPlayback()
                    }
                    self.refreshLockScreenDisplay(force: true)
                    if self.role == .host {
                        self.sessionManager.refreshHostingIfNeeded()
                    }
                }
            }
        }
    }

    private func stopBackgroundRefreshLoop() {
        backgroundRefreshTask?.cancel()
        backgroundRefreshTask = nil
    }
    #else
    func handleAppDidEnterBackground() {}
    func handleAppDidBecomeActive() {}

    func refreshLockScreenDisplay(force: Bool = false) {}

    private func activateSessionBackgroundServices() {
        beginExtendedFeatureSession()
        if role == .host {
            startHostSyncKeepAlive()
        }
    }

    private func deactivateSessionBackgroundServices() {
        stopHostSyncKeepAlive()
    }
    #endif

    private func startHostSyncKeepAlive() {
        hostKeepAliveTask?.cancel()
        hostKeepAliveTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(12))
                guard !Task.isCancelled, let self, self.isInSession, self.role == .host else { return }
                guard !self.sessionManager.connectedPeers.isEmpty else { continue }
                self.sessionManager.broadcast(self.payload, mode: .reliable)
            }
        }
    }

    private func stopHostSyncKeepAlive() {
        hostKeepAliveTask?.cancel()
        hostKeepAliveTask = nil
    }

    private func reindexChords() {
        let sorted = sortedChords
        payload.chords = sorted.enumerated().map { index, chord in
            chord.copying(order: index)
        }
    }

    /// Fast path for MIDI / live piano updates — coalesced so the network layer is not flooded.
    private func syncLive() {
        syncLiveCoalesced()
    }

    private func sync() {
        outboundSyncNeedsFull = true
        outboundSyncImmediate = true
        requestOutboundSync(delayMs: 0)
    }

    private func requestOutboundSync(delayMs: UInt64? = nil) {
        if outboundSyncImmediate {
            guard outboundSyncTask == nil else { return }
            outboundSyncTask = Task { [weak self] in
                guard !Task.isCancelled, let self else { return }
                self.flushOutboundSync()
            }
            return
        }
        guard outboundSyncTask == nil else { return }
        let resolvedDelay = delayMs ?? 12
        outboundSyncTask = Task { [weak self] in
            if resolvedDelay > 0 {
                try? await Task.sleep(for: .milliseconds(resolvedDelay))
            }
            guard !Task.isCancelled, let self else { return }
            self.flushOutboundSync()
        }
    }

    private func flushOutboundSync() {
        outboundSyncTask = nil
        let sendFull = outboundSyncNeedsFull
        outboundSyncNeedsFull = false
        let hadLive = outboundSyncLivePending
        outboundSyncLivePending = false
        let flushImmediate = outboundSyncImmediate
        outboundSyncImmediate = false

        let liveChordChanged = payload.liveChordSymbol != lastSyncedLiveChordSymbol
        if liveChordChanged {
            lastSyncedLiveChordSymbol = payload.liveChordSymbol
        }

        let shouldPushSideEffects = sendFull || (hadLive && liveChordChanged)
        if shouldPushSideEffects {
            pushWatchUpdate(chordChanged: sendFull || liveChordChanged)
        }

        guard !isPracticeMode else {
            if outboundSyncNeedsFull || outboundSyncLivePending { requestOutboundSync() }
            return
        }
        if role == .host {
            sessionManager.updateDiscoveryMetadata(
                key: payload.key,
                tempoBPM: Int(payload.tempoBPM.rounded()),
                sessionToken: payload.sessionToken
            )
            let isLiveBurst = hadLive && !sendFull
            if payload.isRemoteBackupEnabled, let code = payload.remoteJoinCode, sendFull || liveChordChanged {
                let debounceMs = sendFull ? 250 : (liveChordChanged ? 100 : 350)
                let cloudPayload = isLiveBurst ? payload.forHighFrequencyPeerSync() : payload
                cloudRelay.schedulePublish(payload: cloudPayload, joinCode: code, debounceMs: debounceMs)
            }
            if isLiveBurst {
                liveWireRevision &+= 1
                sessionManager.broadcastLive(payload.liveChordWire(revision: liveWireRevision))
            } else {
                sessionManager.broadcast(payload, mode: .reliable)
            }
        }

        if outboundSyncNeedsFull || outboundSyncLivePending {
            requestOutboundSync(delayMs: flushImmediate ? 0 : 12)
        }
    }

    private func pushWatchUpdate(chordChanged: Bool = false) {
        let notation = role == .guest ? guestPreferredNotation : payload.notation
        let transpose = GuestDisplaySettings.transposeSemitones
        let capo = GuestDisplaySettings.capoFret
        let visible = guestVisibleChord(preferLivePiano: true) ?? activeChord
        let chordName = visible.map {
            ChordDisplayHelper.displayName(
                for: $0,
                notation: notation,
                songKey: payload.key,
                transposeSemitones: transpose,
                capoFret: capo
            )
        } ?? "—"
        let upcoming = upcomingChord.map {
            ChordDisplayHelper.displayName(
                for: $0,
                notation: notation,
                songKey: payload.key,
                transposeSemitones: transpose,
                capoFret: capo
            )
        }
        WatchSessionBridge.shared.sendSessionUpdate(
            sessionName: payload.sessionName,
            chordName: chordName,
            upcoming: upcoming,
            nextSongTitle: payload.nextSetlistSongTitle,
            tempo: payload.tempoBPM,
            isPlaying: payload.isMetronomePlaying,
            beat: metronome.currentBeat,
            chordChanged: chordChanged,
            isAccentBeat: metronome.currentBeat == 0,
            canRemoteControl: canDriveSession || isCoHost
        )
        #if os(iOS)
        LiveActivityManager.update(from: self, force: chordChanged || isAppInBackground)
        #endif
    }
}

// MARK: - Features

extension SessionViewModel {
    var rehearsalStore: RehearsalTimelineStore { RehearsalTimelineStore.shared }
    var practiceStats: PracticeStatsStore { PracticeStatsStore.shared }
    var isRecordingRehearsal: Bool { payload.isRecordingRehearsal }

    func configureFeatureBridges() {
        #if os(iOS)
        WatchSessionBridge.shared.onRemoteCommand = { [weak self] command in
            Task { @MainActor in self?.handleWatchRemoteCommand(command) }
        }
        ChordyxShortcutBridge.install(on: self)
        #endif
    }

    func hostAssignedRole(for peerName: String) -> GuestViewRole? {
        payload.guestRoleAssignments[peerName]
    }

    func assignGuestRole(_ guestRole: GuestViewRole, to peer: MCPeerID) {
        guard self.role == .host else { return }
        payload.guestRoleAssignments[peer.displayName] = guestRole
        sync()
    }

    func assignGuestRolePreset(_ guestRole: GuestViewRole, to peerName: String) {
        guard self.role == .host else { return }
        payload.guestRoleAssignments[peerName] = guestRole
        sync()
    }

    func applyHostAssignedRoleIfNeeded() {
        guard role == .guest else { return }
        let name = SessionManager.currentDisplayName()
        guard let assigned = payload.guestRoleAssignments[name] else { return }
        let preset = GuestRolePreset.preset(for: assigned)
        GuestDisplaySettings.viewRole = preset.role
        GuestDisplaySettings.transposeSemitones = preset.transposeSemitones
        GuestDisplaySettings.capoFret = preset.capoFret
        if let notation = preset.notation {
            UserDefaults.standard.set(notation.rawValue, forKey: "preferredNotation")
        }
    }

    func toggleStageDisplayOnly() {
        guard canDriveSession else { return }
        payload.isStageDisplayOnly.toggle()
        if payload.isStageDisplayOnly {
            payload.displayMode = .stage
        }
        sync()
    }

    func toggleRehearsalRecording() {
        guard canDriveSession else { return }
        if payload.isRecordingRehearsal {
            payload.isRecordingRehearsal = false
            _ = rehearsalStore.stopRecording(name: payload.sessionName)
        } else {
            payload.isRecordingRehearsal = true
            rehearsalStore.startRecording(sessionName: payload.sessionName, payload: payload)
        }
        sync()
    }

    func replayRecording(_ recording: RehearsalRecording) {
        guard canDriveSession, let initial = recording.initialPayload else { return }
        payload = initial
        rehearsalStore.replay(recording) { [weak self] event in
            guard let self else { return }
            switch event.kind {
            case .chordChange:
                if let id = event.chordID,
                   let chord = self.payload.chords.first(where: { $0.id == id }) {
                    self.setActiveChord(chord)
                }
            case .tempoChange:
                if let bpm = event.tempoBPM {
                    self.setTempo(bpm)
                }
            case .cue:
                if let text = event.cueText {
                    self.sendLiveCue(text)
                }
            case .sectionJump:
                if let id = event.sectionID {
                    self.jumpToSection(id: id)
                }
            case .metronomeToggle:
                self.toggleMetronome()
            case .setlistAdvance:
                break
            case .errorMarker:
                break
            }
        }
    }

    func stopRehearsalReplay() {
        rehearsalStore.stopReplay()
    }

    func recordTimelineEvent(_ kind: RehearsalEventKind, chordID: UUID? = nil, cueText: String? = nil, sectionID: UUID? = nil) {
        guard payload.isRecordingRehearsal else { return }
        rehearsalStore.log(kind, chordID: chordID, tempoBPM: payload.tempoBPM, cueText: cueText, sectionID: sectionID, songTitle: currentSetlistSongTitle)
    }

    func updatePianoChartMismatch() {
        guard payload.isPianoActive || isHostPianoLive else {
            payload.pianoChartMismatch = nil
            return
        }
        guard let live = payload.liveChordSymbol,
              let chart = activeChord?.symbolName,
              !LiveRing.matches(live, chart) else {
            payload.pianoChartMismatch = nil
            return
        }
        payload.pianoChartMismatch = String(format: String(localized: "Played %@ · chart %@"), live, chart)
    }

    func toggleMIDICueOut(_ enabled: Bool) {
        guard role == .host else { return }
        payload.isMIDICueOutEnabled = enabled
        MIDIOutputManager.shared.setEnabled(enabled)
        sync()
    }

    func requestHostHandoff(to peer: MCPeerID) {
        guard role == .host else { return }
        initiateHandoffCountdown(to: peer)
    }

    func requestHostHandoffFromCoHost() {
        guard isCoHost else { return }
        requestControlAction(.requestHostHandoff(SessionManager.currentDisplayName()))
    }

    func acceptHostHandoffIfPending() {
        guard role == .guest,
              let pending = payload.pendingHostHandoffPeer,
              pending == SessionManager.currentDisplayName() else { return }
        payload.pendingHostHandoffPeer = nil
        payload.coHostPeerName = SessionManager.currentDisplayName()
    }

    func applyServiceTemplateDefaults(_ template: ServiceTemplate) {
        payload.countInBars = template.countInBars
        payload.tempoBPM = template.defaultTempoBPM
        payload.performanceMode = template.performanceMode
        payload.isRemoteBackupEnabled = template.internetBackupEnabled
    }

    func applyServiceTemplate(_ template: ServiceTemplate, store: ProgressionStore) {
        applyServiceTemplateDefaults(template)
        if let setlistID = template.setlistID,
           let setlist = store.setlists.first(where: { $0.id == setlistID }) {
            hostSession(from: setlist, store: store)
        }
    }

    func handleWatchRemoteCommand(_ command: String) {
        guard canDriveSession || isCoHost else { return }
        switch command {
        case "advance": advanceChord()
        case "previous": previousChord()
        case "hold": sendLiveCue("Hold", symbol: "hand.raised.fill")
        case "vamp": sendLiveCue("Vamp", symbol: "infinity.circle.fill")
        case "break": sendLiveCue("Break", symbol: "pause.circle.fill")
        case "ready": sendQuickMessage(String(localized: "Ready"), symbol: "hand.thumbsup.fill")
        case "metronome": toggleMetronome()
        default: break
        }
    }

    func notifyFeatureSyncHooks(chordChanged: Bool = false, cueText: String? = nil) {
        updatePianoChartMismatch()
        payload.countInBeatsRemaining = metronome.countInBeatsRemaining

        if payload.isRecordingRehearsal, chordChanged, let id = payload.activeChordID {
            recordTimelineEvent(.chordChange, chordID: id)
        }

        if let cueText {
            practiceStats.recordCue(cueText)
            serviceStatsStore.recordCue()
            if payload.isRecordingRehearsal {
                recordTimelineEvent(.cue, cueText: cueText)
            }
            if payload.isMIDICueOutEnabled {
                MIDIOutputManager.shared.sendCue(cueText)
            }
            triggerCueHaptic(cueText)
        }

        if chordChanged, payload.isMIDICueOutEnabled, let chord = activeChord,
           let pc = Transposer.pitchClass(ofRoot: Transposer.parse(chord.symbolName)?.root ?? "") {
            MIDIOutputManager.shared.sendChordChange(rootPitchClass: pc)
        }
    }

    func triggerCueHaptic(_ cueText: String) {
        #if os(iOS)
        guard GuestDisplaySettings.cueHapticsEnabled else { return }
        let style: UIImpactFeedbackGenerator.FeedbackStyle = cueText == "Break" ? .heavy : .medium
        UIImpactFeedbackGenerator(style: style).impactOccurred()
        #endif
    }

    func beginPracticeStats(named name: String) {
        practiceStats.beginSession(named: name)
    }

    func endPracticeStats() {
        practiceStats.endSession()
    }
}

// MARK: - Extended features

extension SessionViewModel {
    var serviceStatsStore: ServiceStatsStore { ServiceStatsStore.shared }
    var teamLibraryStore: TeamLibraryStore { TeamLibraryStore.shared }

    var currentRoleLiveNote: String? {
        guard role == .guest else { return nil }
        let name = SessionManager.currentDisplayName()
        let assigned = payload.guestRoleAssignments[name] ?? GuestDisplaySettings.viewRole
        if let note = payload.syncedRoleNotes[assigned.rawValue], !note.isEmpty {
            return note
        }
        let presetNote = GuestRolePreset.preset(for: assigned).liveNote
        return presetNote.isEmpty ? nil : presetNote
    }

    var capoSuggestion: CapoSuggestion? {
        guard let vocalName = payload.vocalTargetKeyName,
              let vocal = MusicalKey(rawValue: vocalName) else { return nil }
        return SetlistIntelligenceEngine.capoSuggestion(chartKey: payload.key, vocalKey: vocal)
    }

    func beginExtendedFeatureSession() {
        serviceStatsStore.beginSession()
        refreshPeerPresence()
        updateNextSetlistSongTitle()
    }

    func endExtendedFeatureSession() {
        _ = serviceStatsStore.endSession(
            named: payload.sessionName,
            songsPlayed: payload.setlistSongIndex.map { $0 + 1 } ?? 1
        )
        sectionCountdownTask?.cancel()
        handoffCountdownTask?.cancel()
        payload.sectionCountdownBeats = 0
        payload.sectionCountdownLabel = nil
        payload.handoffCountdown = nil
        payload.handoffFromPeer = nil
        payload.isGhostBandReplayActive = false
    }

    func handleExtendedFeatureSectionChange(to section: SectionMarker?) {
        guard canDriveSession, let section else { return }
        if lastTrackedSectionID != section.id {
            lastTrackedSectionID = section.id
            serviceStatsStore.recordSectionJump()
            applySectionAutoCue(section, trigger: .onEnter)
        }
    }

    func applySectionAutoCue(_ section: SectionMarker, trigger: SectionCueTrigger) {
        guard section.autoCueTrigger == trigger,
              let text = section.autoCueText,
              !text.isEmpty else { return }
        let symbol = section.autoCueSymbol ?? "megaphone.fill"
        sendLiveCue(text, symbol: symbol)
    }

    func scheduleNextSectionCountdown(beats: Int = 4) {
        guard canDriveSession else { return }
        guard let active = activeSection,
              let sectionIndex = sectionsInOrder.firstIndex(where: { $0.id == active.id }),
              sectionIndex + 1 < sectionsInOrder.count else { return }

        let next = sectionsInOrder[sectionIndex + 1]
        payload.sectionCountdownLabel = next.name
        payload.sectionCountdownBeats = beats
        sync()

        sectionCountdownTask?.cancel()
        sectionCountdownTask = Task { [weak self] in
            for remaining in stride(from: beats, through: 1, by: -1) {
                guard !Task.isCancelled, let self else { return }
                self.payload.sectionCountdownBeats = remaining
                self.sync()
                let ms = Int(60_000 / max(self.payload.tempoBPM, 40))
                try? await Task.sleep(for: .milliseconds(ms))
            }
            guard !Task.isCancelled, let self else { return }
            self.payload.sectionCountdownBeats = 0
            self.payload.sectionCountdownLabel = nil
            self.jumpToSection(next)
            self.sync()
        }
    }

    func cancelSectionCountdown() {
        sectionCountdownTask?.cancel()
        payload.sectionCountdownBeats = 0
        payload.sectionCountdownLabel = nil
        sync()
    }

    func updateTempoDrift(now: Date = Date()) {
        #if os(iOS)
        if role == .guest { return }
        #endif
        guard payload.isMetronomePlaying, payload.tempoBPM > 0 else {
            payload.tempoDriftBPM = 0
            return
        }
        #if os(macOS) || os(iOS)
        if payload.hostLiveGrooveActive { return }
        #endif
        let beatDuration = 60.0 / payload.tempoBPM
        let start = payload.metronomeStartEpoch ?? now.timeIntervalSince1970
        let elapsed = now.timeIntervalSince1970 - start
        let expectedBeatEpoch = start + (floor(elapsed / beatDuration) * beatDuration)
        if lastBeatEpoch > 0 {
            let drift = TempoDriftMonitor.driftBPM(
                expectedBeatEpoch: expectedBeatEpoch,
                actualBeatEpoch: lastBeatEpoch,
                tempoBPM: payload.tempoBPM
            )
            if abs(drift - payload.tempoDriftBPM) >= 0.25 {
                payload.tempoDriftBPM = drift
            }
        }
        lastBeatEpoch = now.timeIntervalSince1970
        serviceStatsStore.recordTempo(payload.tempoBPM)
    }

    func sendQuickMessage(_ text: String, symbol: String = "bubble.left.fill") {
        let message = SessionQuickMessage(
            senderName: SessionManager.currentDisplayName(),
            text: text,
            symbol: symbol
        )
        payload.quickMessages.insert(message, at: 0)
        if payload.quickMessages.count > 8 {
            payload.quickMessages = Array(payload.quickMessages.prefix(8))
        }
        sync()
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard let self else { return }
            self.payload.quickMessages.removeAll { $0.id == message.id }
            self.sync()
        }
    }

    func refreshPeerPresence() {
        guard role == .host else { return }
        var map: [String: PeerPresenceInfo] = [:]
        let activeChordID = payload.activeChordID
        for peer in sessionManager.connectedPeers {
            let assigned = payload.guestRoleAssignments[peer.displayName] ?? .auto
            let instrument: MusicianInstrument = switch assigned {
            case .guitar: .guitar
            case .bass: .bass
            case .keys: .keys
            case .vocal: .vocal
            default: .other
            }
            let reported = payload.peerChordPositions[peer.displayName]
            map[peer.displayName] = PeerPresenceInfo(
                instrument: instrument,
                syncQuality: sessionManager.syncQuality,
                isLagging: sessionManager.syncQuality == .poor,
                reportedChordID: reported,
                isOnCurrentChord: reported != nil && reported == activeChordID
            )
        }
        guard map != payload.peerPresence else { return }
        payload.peerPresence = map
        sync()
    }

    func initiateHandoffCountdown(to peer: MCPeerID, seconds: Int = 5) {
        guard role == .host else { return }
        payload.handoffFromPeer = SessionManager.currentDisplayName()
        payload.handoffCountdown = seconds
        payload.pendingHostHandoffPeer = peer.displayName
        sync()

        handoffCountdownTask?.cancel()
        handoffCountdownTask = Task { [weak self] in
            for tick in stride(from: seconds, through: 1, by: -1) {
                guard !Task.isCancelled, let self else { return }
                self.payload.handoffCountdown = tick
                self.sync()
                try? await Task.sleep(for: .seconds(1))
            }
            guard !Task.isCancelled, let self else { return }
            self.payload.handoffCountdown = nil
            self.payload.handoffFromPeer = nil
            self.sync()
        }
    }

    func setVocalTargetKey(_ key: MusicalKey) {
        guard canDriveSession else { return }
        payload.vocalTargetKeyName = key.rawValue
        sync()
    }

    func syncRoleNotes(from progression: SavedProgression) {
        payload.syncedRoleNotes = progression.roleNotes
        sync()
    }

    func setRoleNote(_ text: String, for role: GuestViewRole) {
        guard canDriveSession else { return }
        var notes = payload.syncedRoleNotes
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            notes.removeValue(forKey: role.rawValue)
        } else {
            notes[role.rawValue] = trimmed
        }
        payload.syncedRoleNotes = notes
        sync()
    }

    func startGhostBandReplay(_ recording: RehearsalRecording) {
        payload.isGhostBandReplayActive = true
        replayRecording(recording)
        sync()
    }

    func stopGhostBandReplay() {
        payload.isGhostBandReplayActive = false
        stopRehearsalReplay()
        sync()
    }

    func markRehearsalError() {
        guard payload.isRecordingRehearsal else { return }
        recordTimelineEvent(.errorMarker)
        if let recording = rehearsalStore.inProgressRecording(sessionName: payload.sessionName) {
            PracticeQueueStore.shared.addFromLatestMistake(recording: recording)
        }
    }

    func setDirectorMode() {
        guard canDriveSession else { return }
        payload.displayMode = .director
        sync()
    }

    func setAudienceMode() {
        guard canDriveSession else { return }
        payload.displayMode = .audience
        sync()
    }

    func setAcousticMode() {
        guard canDriveSession else { return }
        payload.performanceMode = .acoustic
        payload.isRemoteBackupEnabled = false
        sync()
    }

    func updateNextSetlistSongTitle() {
        guard let index = payload.setlistSongIndex,
              !payload.setlistSongTitles.isEmpty,
              index + 1 < payload.setlistSongTitles.count else {
            payload.nextSetlistSongTitle = nil
            return
        }
        payload.nextSetlistSongTitle = payload.setlistSongTitles[index + 1]
    }

    func recordTeamPackImport(packName: String, songCount: Int) {
        teamLibraryStore.recordImport(
            packName: packName,
            songCount: songCount,
            revisionLabel: String(localized: "Imported")
        )
    }
}

// MARK: - Advanced features

extension SessionViewModel {
    var practiceQueueStore: PracticeQueueStore { PracticeQueueStore.shared }
    var sundayFolderStore: SundayFolderStore { SundayFolderStore.shared }
    var teamPackSubscriptionStore: TeamPackSubscriptionStore { TeamPackSubscriptionStore.shared }
    var stageLayoutStore: StageLayoutStore { StageLayoutStore.shared }
    var teamDigestStore: TeamDigestStore { TeamDigestStore.shared }

    func toggleSectionMapLock() {
        guard canDriveSession else { return }
        payload.isSectionMapLocked.toggle()
        sync()
    }

    func setCongregationMode(enabled: Bool) {
        guard canDriveSession else { return }
        payload.isCongregationModeActive = enabled
        if enabled {
            payload.displayMode = .congregation
            payload.congregationJoinToken = String(payload.remoteJoinCode?.suffix(4) ?? payload.sessionToken.uuidString.prefix(4))
        }
        sync()
    }

    func setVoicingHintsEnabled(_ enabled: Bool) {
        guard canDriveSession else { return }
        payload.voicingHintsEnabled = enabled
        sync()
    }

    var currentVoicingHint: String? {
        guard payload.voicingHintsEnabled || GuestDisplaySettings.voicingHintsEnabled else { return nil }
        guard let chord = activeChord else { return nil }
        let viewRole = self.role == .guest
            ? GuestDisplaySettings.viewRole
            : (hostAssignedRole(for: SessionManager.currentDisplayName()) ?? .auto)
        return VoicingHintsEngine.hint(for: viewRole, chordSymbol: chord.symbolName, key: payload.key)
    }

    var vocalRangeSuggestion: VocalRangeSuggestion? {
        guard let targetName = payload.vocalTargetKeyName,
              let target = MusicalKey(rawValue: targetName) else { return nil }
        return VocalRangeAssistant.suggest(chartKey: payload.key, vocalTarget: target)
    }

    func startTempoRamp(to targetBPM: Double, overBars: Int) {
        guard canDriveSession else { return }
        payload.tempoRampTargetBPM = min(max(targetBPM, Self.minBPM), Self.maxBPM)
        payload.tempoRampBarsRemaining = max(1, overBars)
        sync()
    }

    func cancelTempoRamp() {
        guard canDriveSession else { return }
        payload.tempoRampTargetBPM = nil
        payload.tempoRampBarsRemaining = 0
        sync()
    }

    func processTempoRampOnBar() {
        guard canDriveSession,
              let target = payload.tempoRampTargetBPM,
              payload.tempoRampBarsRemaining > 0 else { return }
        let result = TempoRampEngine.nextBPM(
            current: payload.tempoBPM,
            target: target,
            barsRemaining: payload.tempoRampBarsRemaining,
            beatsPerBar: payload.beatsPerBar
        )
        setTempo(result.bpm)
        payload.tempoRampBarsRemaining = result.barsLeft
        if result.barsLeft == 0 {
            payload.tempoRampTargetBPM = nil
        }
        sync()
    }

    func setClickTrackLane(_ lane: ClickTrackLane, for peerName: String) {
        guard canDriveSession else { return }
        payload.clickTrackLanes[peerName] = lane.rawValue
        sync()
    }

    func clickTrackVolume(for peerName: String?) -> Double {
        let name = peerName ?? SessionManager.currentDisplayName()
        if role == .host, let laneRaw = payload.clickTrackLanes[name], let lane = ClickTrackLane(rawValue: laneRaw) {
            return lane.volumeMultiplier
        }
        if role == .guest {
            return GuestDisplaySettings.clickTrackLane.volumeMultiplier
        }
        return 1.0
    }

    func applyClickTrackLaneVolume() {
        let multiplier = clickTrackVolume(for: SessionManager.currentDisplayName())
        metronome.volume = Float(0.8 * multiplier)
    }

    func setChartDeliveryMode(_ mode: ChartDeliveryMode, for peerName: String) {
        guard canDriveSession else { return }
        payload.chartDeliveryModes[peerName] = mode.rawValue
        sync()
    }

    func sendSilentNudge(_ kind: SilentNudgeKind) {
        guard canDriveSession else { return }
        payload.broadcastSilentNudge = kind
        payload.silentNudgeSequence += 1
        sync()
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard let self else { return }
            self.payload.broadcastSilentNudge = nil
            self.sync()
        }
    }

    func deliverSilentNudge(_ kind: SilentNudgeKind) {
        guard GuestDisplaySettings.silentNudgesEnabled else { return }
        #if os(iOS)
        let generator = UIImpactFeedbackGenerator(style: .medium)
        for delay in kind.hapticPattern {
            if delay > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    generator.impactOccurred()
                }
            } else {
                generator.impactOccurred()
            }
        }
        #endif
    }

    func reportGuestChordPosition(_ chordID: UUID) {
        let name = SessionManager.currentDisplayName()
        if role == .guest {
            sessionManager.sendControlRequest(.reportChordPosition(chordID))
        } else if role == .host {
            payload.peerChordPositions[name] = chordID
            refreshPeerPresence()
        }
    }

    func reportGuestChordPositionOnChange() {
        guard role == .guest, let chordID = payload.activeChordID else { return }
        sessionManager.sendControlRequest(.reportChordPosition(chordID))
    }

    func triggerSectionLoopCountIn() {
        guard canDriveSession else { return }
        let bars = max(1, payload.sectionLoopCountInBars)
        payload.countInBars = bars
        let now = Date().timeIntervalSince1970
        payload.isCountingIn = true
        payload.countInStartEpoch = now
        let barDuration = (60.0 / payload.tempoBPM) * (4.0 / Double(payload.beatUnit)) * Double(payload.beatsPerBar)
        payload.metronomeStartEpoch = now + barDuration * Double(bars)
        applyMetronome()
    }

    func setSectionLoopCountInBars(_ bars: Int) {
        guard canDriveSession else { return }
        payload.sectionLoopCountInBars = max(0, min(bars, 2))
        sync()
    }

    func startServiceTimeline() {
        guard canDriveSession else { return }
        payload.serviceTimelineStartEpoch = Date().timeIntervalSince1970
        sync()
    }

    func serviceTimelineElapsedMinutes() -> Double? {
        guard let start = payload.serviceTimelineStartEpoch else { return nil }
        return (Date().timeIntervalSince1970 - start) / 60.0
    }

    func evaluateReadinessReport(checklistSatisfied: Int, checklistTotal: Int, unrehearsedSongs: Int) -> ReadinessReport {
        ReadinessEngine.evaluate(
            payload: payload,
            connectedPeerCount: sessionManager.connectedPeers.count,
            unrehearsedSongCount: unrehearsedSongs,
            checklistSatisfied: checklistSatisfied,
            checklistTotal: checklistTotal
        )
    }

    func publishReadinessScore(_ score: Int) {
        guard payload.readinessScore != score else { return }
        payload.readinessScore = score
        sync()
    }

    func applyArrangementVariant(_ variant: ArrangementVariant) {
        guard canDriveSession else { return }
        payload.key = variant.key
        payload.notation = variant.notation
        payload.chords = variant.chords
        payload.sections = variant.sections
        payload.rehearsalNotes = variant.rehearsalNotes
        if let first = variant.chords.sorted(by: { $0.order < $1.order }).first {
            payload.activeChordID = first.id
        }
        sync()
    }

    func saveArrangementVariant(named name: String, to progression: inout SavedProgression) {
        let variant = ArrangementVariantStore.createVariant(named: name, from: progression)
        progression.arrangementVariants.removeAll { $0.name == name }
        progression.arrangementVariants.append(variant)
    }

    func cacheSundayFolder(setlistName: String, progressionIDs: [UUID], songTitles: [String]) {
        sundayFolderStore.cacheSetlist(
            name: setlistName,
            progressionIDs: progressionIDs,
            songTitles: songTitles,
            serviceDate: Date()
        )
    }

    func subscribeToTeamPack(packName: String, teamName: String, revisionLabel: String) {
        teamPackSubscriptionStore.subscribe(packName: packName, teamName: teamName, revisionLabel: revisionLabel)
    }

    func applyStageLayoutPreset(_ preset: StageLayoutPreset) {
        guard canDriveSession else { return }
        payload.displayMode = preset.displayMode
        sync()
    }

    func buildWeeklyDigest() -> TeamDigestEntry {
        let entry = TeamDigestBuilder.buildWeekDigest(
            practiceStats: practiceStats.load(),
            serviceStats: ServiceStatsStore.shared.loadAll()
        )
        teamDigestStore.record(entry)
        return entry
    }

    func carPlayRehearsalItems(from store: ProgressionStore, progressionIDs: [UUID]) -> [CarPlayRehearsalItem] {
        let progressions = progressionIDs.compactMap { id in store.progressions.first { $0.id == id } }
        return CarPlayRehearsalBuilder.items(from: progressions)
    }

    func importPlanningCenterFromAPI(urlString: String) async -> PlanningCenterImportDraft? {
        await ChurchAppsSync.fetchPlan(from: urlString)
    }
}
