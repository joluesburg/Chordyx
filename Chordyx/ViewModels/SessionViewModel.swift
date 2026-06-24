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
    let metronome = MetronomeEngine()
    let backingTrack = BackingTrackEngine()
    let midi = MIDIInputManager()
    #if os(iOS)
    private let sessionBackground = SessionBackgroundManager()
    #endif

    var midiSources: [String] = []
    var midiAvailableSources: [MIDISourceInfo] = []
    private var previousActiveChordID: UUID?
    private var transitionTask: Task<Void, Never>?
    private var cueClearTask: Task<Void, Never>?
    private var songEndingTask: Task<Void, Never>?
    var autoAdvanceSetlistSongs = false
    var shouldAutoAdvanceSetlist = false

    struct ImportSessionGuide: Equatable {
        var title: String
        var message: String
    }

    var importSessionGuide: ImportSessionGuide?
    var pendingReconnectRecord: RecentSessionRecord?
    var showReconnectBanner = false

    static let minBPM: Double = 40
    static let maxBPM: Double = 240

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

    static let maxFreestyleChords = 8

    var freestyleChordEntries: [ChordEntry] {
        payload.freestyleChordSymbols.enumerated().map { index, symbol in
            ChordEntry.freestyle(symbol: symbol, order: index)
        }
    }

    var liveFreestyleChord: ChordEntry? {
        livePianoChordEntry()
    }

    var isHostPianoLive: Bool {
        !payload.pianoNotes.isEmpty
    }

    var guestPreferredNotation: ChordNotation {
        let raw = UserDefaults.standard.string(forKey: "preferredNotation") ?? ChordNotation.symbol.rawValue
        return ChordNotation(rawValue: raw) ?? payload.notation
    }

    func displayNotation(isGuest: Bool) -> ChordNotation {
        if isGuest {
            return GuestDisplaySettings.effectiveNotation(hostNotation: payload.notation, isGuest: true)
        }
        return payload.notation
    }

    func effectiveDisplayMode(isGuest: Bool) -> SessionDisplayMode {
        GuestDisplaySettings.effectiveDisplayMode(hostMode: payload.displayMode, isGuest: isGuest)
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
    }

    private(set) var isLiveProgressionSession = false
    var loadedProgressionID: UUID?

    init() {
        sessionManager.onPayloadReceived = { [weak self] received in
            guard let self, self.role == .guest else { return }
            let priorChord = self.payload.activeChordID
            let priorPiano = self.payload.pianoNotes
            self.payload = received
            if priorChord != received.activeChordID {
                self.previousActiveChordID = priorChord
            }
            self.applyMetronome()
            let pianoChanged = priorPiano != received.pianoNotes
            let chordChanged = priorChord != received.activeChordID || pianoChanged
            self.pushWatchUpdate(chordChanged: chordChanged)
            RecentSessionStore.updateProgress(
                sessionToken: received.sessionToken,
                activeChordID: received.activeChordID,
                progressionName: received.sessionName
            )
            #if os(iOS)
            self.refreshLockScreenDisplay(force: true)
            #endif
        }
        sessionManager.onControlRequest = { [weak self] action, peer in
            Task { @MainActor in self?.handleControlRequest(action, from: peer) }
        }
        sessionManager.onGuestDisconnected = { [weak self] in
            Task { @MainActor in self?.handleGuestDisconnected() }
        }
        sessionManager.onPeersUpdated = { [weak self] peers in
            guard let self else { return }
            if self.role == .host {
                self.sync()
            } else if self.role == .guest, !peers.isEmpty {
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
                #if os(iOS)
                if self.isInSession {
                    LiveActivityManager.updateBeat(from: self)
                }
                #endif
            }
        }
        midi.onNotesChanged = { [weak self] notes in
            Task { @MainActor in self?.handleMIDINotes(notes) }
        }
        midi.onSourcesChanged = { [weak self] names in
            Task { @MainActor in self?.midiSources = names }
        }
        midi.onAvailableSourcesChanged = { [weak self] sources in
            Task { @MainActor in self?.midiAvailableSources = sources }
        }
        midi.onPedalAction = { [weak self] action in
            Task { @MainActor in self?.handlePedalAction(action) }
        }
        midi.start()
        _ = WatchSessionBridge.shared
    }

    private func handlePedalAction(_ action: MIDIPedalAction) {
        guard canDriveSession else { return }
        switch action {
        case .nextChord: advanceChord()
        case .previousChord: previousChord()
        }
    }

    private func handleControlRequest(_ action: SessionControlAction, from peer: MCPeerID) {
        guard role == .host else { return }
        guard payload.coHostPeerName == peer.displayName else { return }
        applyControlAction(action)
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
        }
    }

    func requestControlAction(_ action: SessionControlAction) {
        if canDriveSession && (role == .host || isPracticeMode) {
            applyControlAction(action)
        } else if isCoHost {
            sessionManager.sendControlRequest(action)
        }
    }

    private func handleMIDINotes(_ midiNotes: [Int]) {
        guard canDriveSession else { return }
        let indices = midiNotes.map { $0 - 12 }.filter { $0 >= 0 }.sorted()
        applyPianoNotes(indices)
    }

    private func applyPianoNotes(_ indices: [Int]) {
        guard canDriveSession else { return }
        payload.pianoNotes = indices
        updateFreestyleRecognition(from: indices)
        sync()
    }

    private func updateFreestyleRecognition(from indices: [Int]) {
        guard !indices.isEmpty else {
            payload.liveChordSymbol = nil
            return
        }

        let pitchClasses = Set(indices.map { PianoNote.pitchClass(of: $0) })
        let bass = indices.min().map { PianoNote.pitchClass(of: $0) }
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

        guard let symbol else { return }

        if pitchClasses.count == 1, !isLiveProgressionSession {
            if payload.ringShowsLiveChords {
                appendFreestyleHistory(symbol: symbol)
            }
            return
        }

        if isLiveProgressionSession {
            appendLiveProgressionChord(symbol: symbol)
            if payload.ringShowsLiveChords {
                appendFreestyleHistory(symbol: symbol)
            }
        } else {
            appendFreestyleHistory(symbol: symbol)
        }
    }

    func singleNoteSymbol(for index: Int) -> String {
        let pc = PianoNote.pitchClass(of: index)
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
        if let existing = payload.chords.last(where: { $0.symbolName == symbol }) {
            payload.activeChordID = existing.id
            payload.beatsOnActiveChord = 0
            updateActiveSection()
            return
        }

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

    private func appendFreestyleHistory(symbol: String) {
        guard payload.freestyleChordSymbols.last != symbol else { return }
        payload.freestyleChordSymbols.append(symbol)
        if payload.freestyleChordSymbols.count > Self.maxFreestyleChords {
            payload.freestyleChordSymbols.removeFirst(
                payload.freestyleChordSymbols.count - Self.maxFreestyleChords
            )
        }
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
        pushWatchUpdate()
        activateSessionBackgroundServices()
    }

    func hostSession(name: String, key: MusicalKey, notation: ChordNotation, performanceMode: SessionPerformanceMode = .live) {
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
        payload.displayMode = performanceMode == .live ? .stage : .ring
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
    func hostLiveChordsSession(name: String, key: MusicalKey, notation: ChordNotation) {
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
        sync()
    }

    func stopBackingTrack() {
        guard canDriveSession else { return }
        backingTrack.stop()
        payload.isBackingTrackPlaying = false
        sync()
    }

    func clearBackingTrack() {
        guard canDriveSession else { return }
        backingTrack.clear()
        payload.backingTrackDisplayName = ""
        payload.isBackingTrackPlaying = false
        sync()
    }

    private func pauseBackingTrackForSongChange() {
        backingTrack.stop()
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
        sync()
    }

    private func applySavedProgression(
        _ saved: SavedProgression,
        sessionName: String,
        preserveSessionToken: Bool = false
    ) {
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
        newPayload.sessionToken = preserveSessionToken ? payload.sessionToken : UUID()
        newPayload.displayMode = preferredDisplayMode(
            chordCount: sortedChords.count,
            sectionCount: cleaned.sections.count,
            hasLyrics: !cleaned.lyricsLines.isEmpty
        )
        backingTrack.stop()
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
        showReconnectBanner = true
        role = .guest
        isPracticeMode = false
        sessionManager.startBrowsing()
    }

    func tryAutoReconnectIfPossible() {
        guard let record = pendingReconnectRecord else { return }
        guard let host = sessionManager.discoveredHosts.first(where: {
            $0.sessionName == record.sessionName && $0.peer.displayName == record.hostDeviceName
        }) else { return }
        join(host: host)
    }

    private func handleGuestDisconnected() {
        guard role == .guest, isInSession else { return }
        showReconnectBanner = true
        pendingReconnectRecord = RecentSessionRecord(
            sessionName: payload.sessionName,
            hostDeviceName: sessionManager.connectedPeers.first?.displayName ?? "",
            sessionToken: payload.sessionToken,
            key: payload.key,
            lastActiveChordID: payload.activeChordID,
            progressionName: payload.sessionName
        )
        RecentSessionStore.updateProgress(
            sessionToken: payload.sessionToken,
            activeChordID: payload.activeChordID,
            progressionName: payload.sessionName
        )
        sessionManager.startBrowsing()
    }

    private func beginHostingSession(named name: String) {
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
            progressionName: name
        )
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
        sessionManager.startBrowsing()
    }

    func join(host: DiscoveredHost) {
        isPracticeMode = false
        role = .guest
        sessionManager.joinHost(host)
        isInSession = true
        showReconnectBanner = false
        pendingReconnectRecord = nil
        RecentSessionStore.rememberJoin(
            sessionName: host.sessionName,
            hostDeviceName: host.peer.displayName,
            sessionToken: host.sessionToken ?? UUID(),
            key: host.key ?? .C
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
        if steps != 0 {
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

    func refreshMetronomeAudioPolicy() {
        if role == .host || isPracticeMode {
            metronome.localAudioEnabled = true
        } else if role == .guest {
            let guestAudio = UserDefaults.standard.object(forKey: "guestMetronomeAudioEnabled") as? Bool ?? true
            metronome.localAudioEnabled = guestAudio && !GuestDisplaySettings.acousticRoomMode
        }
        applyMetronome()
    }

    private func handleMetronomeBeat() {
        guard canDriveSession, payload.isMetronomePlaying, !payload.isCountingIn else { return }
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
            if autoAdvanceSetlistSongs, activeSetlist != nil {
                payload.activeChordID = sorted[index].id
            } else {
                payload.activeChordID = sorted[0].id
            }
            signalSongEndingIfNeeded()
        } else {
            payload.activeChordID = sorted[index + 1].id
        }
        payload.beatsOnActiveChord = 0
        updateActiveSection()
        sync()

        if index + 1 >= sorted.count, autoAdvanceSetlistSongs, activeSetlist != nil {
            // Song finished — host should call nextSetlistSong from UI/timer
        }
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
            payload.activeChordID = sectionChords[0].id
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
    }

    private func applyMetronome() {
        metronome.apply(
            bpm: payload.tempoBPM,
            beatsPerBar: payload.beatsPerBar,
            beatUnit: payload.beatUnit,
            isPlaying: payload.isMetronomePlaying,
            startEpoch: payload.metronomeStartEpoch ?? Date().timeIntervalSince1970,
            clockOffset: role == .guest ? sessionManager.clockOffset : 0,
            countInBars: payload.countInBars,
            isCountingIn: payload.isCountingIn,
            countInStartEpoch: payload.countInStartEpoch
        )
        if payload.isCountingIn == false, payload.isMetronomePlaying {
            // Count-in finished on this device.
        }
    }

    func leaveSession() {
        transitionTask?.cancel()
        transitionTask = nil
        cueClearTask?.cancel()
        cueClearTask = nil
        songEndingTask?.cancel()
        songEndingTask = nil
        showReconnectBanner = false
        pendingReconnectRecord = nil
        if !isPracticeMode {
            sessionManager.disconnect()
        }
        deactivateSessionBackgroundServices()
        metronome.stop()
        backingTrack.clear()
        isInSession = false
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
        metronome.reassertBackgroundPlayback()
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
            }
            metronome.reassertBackgroundPlayback()
            refreshLockScreenDisplay(force: true)
        }
    }

    func refreshLockScreenDisplay(force: Bool = false) {
        guard isInSession else { return }
        LiveActivityManager.update(from: self, force: force)
    }

    private func activateSessionBackgroundServices() {
        refreshMetronomeAudioPolicy()
        setScreenAlwaysOn(true)
        metronome.setSessionKeepAlive(true)
        LiveActivityManager.update(from: self, force: true)
    }

    private func deactivateSessionBackgroundServices() {
        setScreenAlwaysOn(false)
        stopBackgroundRefreshLoop()
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
                    self.metronome.reassertBackgroundPlayback()
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

    private func activateSessionBackgroundServices() {}

    private func deactivateSessionBackgroundServices() {}
    #endif

    private func reindexChords() {
        let sorted = sortedChords
        payload.chords = sorted.enumerated().map { index, chord in
            chord.copying(order: index)
        }
    }

    private func sync() {
        pushWatchUpdate()
        guard !isPracticeMode else { return }
        if role == .host {
            sessionManager.updateDiscoveryMetadata(
                key: payload.key,
                tempoBPM: Int(payload.tempoBPM.rounded()),
                sessionToken: payload.sessionToken
            )
        }
        sessionManager.broadcast(payload)
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
            tempo: payload.tempoBPM,
            isPlaying: payload.isMetronomePlaying,
            beat: metronome.currentBeat,
            chordChanged: chordChanged,
            isAccentBeat: metronome.currentBeat == 0
        )
        #if os(iOS)
        LiveActivityManager.update(from: self, force: chordChanged || isAppInBackground || role == .guest)
        #endif
    }
}
