//
//  LiveActivityManager.swift
//  Chordyx
//

import Foundation

#if os(iOS)
import ActivityKit

@MainActor
enum LiveActivityManager {
    private static var activity: Activity<ChordyxSessionAttributes>?
    private static var lastContentUpdate = Date.distantPast
    private static var lastBeatUpdate = Date.distantPast
    private static var lastChordName = ""
    private static var lastCueText = ""
    private static var chordChangeToken = 0
    private static var cueClearTask: Task<Void, Never>?
    private static var sessionToken = 0
    private static var startTask: Task<Void, Never>?

    static func update(from viewModel: SessionViewModel, force: Bool = false, beatOnly: Bool = false) {
        guard GuestDisplaySettings.liveActivityEnabled else {
            end()
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        guard viewModel.isInSession else {
            end()
            return
        }

        let inBackground = viewModel.isAppInBackground
        let now = Date()
        if beatOnly {
            guard viewModel.payload.isMetronomePlaying || viewModel.payload.isCountingIn else { return }
            let minInterval = inBackground ? 0.08 : 0.12
            if !force, now.timeIntervalSince(lastBeatUpdate) < minInterval { return }
            lastBeatUpdate = now
        } else {
            let minInterval = inBackground ? 0.12 : 0.35
            if !force, now.timeIntervalSince(lastContentUpdate) < minInterval { return }
            lastContentUpdate = now
        }

        let state = makeContentState(from: viewModel)
        let roleLabel = viewModel.role == .host ? String(localized: "Host") : String(localized: "Guest")
        let alert = makeCueAlert(for: state)

        Task {
            await applyUpdate(
                state: state,
                roleLabel: roleLabel,
                alert: alert,
                beatOnly: beatOnly
            )
        }

        if !beatOnly, let cue = viewModel.payload.activeCue?.text, !cue.isEmpty {
            scheduleCueClear()
        }
    }

    static func updateBeat(from viewModel: SessionViewModel) {
        update(from: viewModel, beatOnly: true)
    }

    static func end() {
        cueClearTask?.cancel()
        cueClearTask = nil
        startTask?.cancel()
        startTask = nil
        sessionToken += 1
        guard let ending = activity else {
            resetTrackingState()
            return
        }
        activity = nil
        resetTrackingState()
        Task {
            await ending.end(.init(state: ending.content.state, staleDate: nil), dismissalPolicy: .immediate)
        }
    }

    private static func resetTrackingState() {
        lastContentUpdate = .distantPast
        lastBeatUpdate = .distantPast
        lastChordName = ""
        lastCueText = ""
        chordChangeToken = 0
    }

    private static func applyUpdate(
        state: ChordyxSessionAttributes.ContentState,
        roleLabel: String,
        alert: AlertConfiguration?,
        beatOnly: Bool
    ) async {
        let staleDate = Date().addingTimeInterval(beatOnly ? 12 : 90)
        let content = ActivityContent(state: state, staleDate: staleDate)

        if activity == nil {
            await ensureStarted(state: state, roleLabel: roleLabel, content: content)
        }

        guard let current = activity else { return }
        await current.update(content, alertConfiguration: alert)
    }

    private static func ensureStarted(
        state: ChordyxSessionAttributes.ContentState,
        roleLabel: String,
        content: ActivityContent<ChordyxSessionAttributes.ContentState>
    ) async {
        if activity != nil { return }

        if let startTask {
            await startTask.value
            return
        }

        let token = sessionToken
        startTask = Task {
            defer { startTask = nil }
            do {
                let attributes = ChordyxSessionAttributes(roleLabel: roleLabel)
                let newActivity = try Activity.request(
                    attributes: attributes,
                    content: content,
                    pushType: nil
                )
                guard token == sessionToken else {
                    await newActivity.end(content, dismissalPolicy: .immediate)
                    return
                }
                activity = newActivity
            } catch {
                #if DEBUG
                print("Live Activity request failed: \(error)")
                #endif
            }
        }
        await startTask?.value
    }

    private static func makeCueAlert(for state: ChordyxSessionAttributes.ContentState) -> AlertConfiguration? {
        guard !state.cueText.isEmpty, state.cueText != lastCueText else {
            if state.cueText.isEmpty { lastCueText = "" }
            return nil
        }
        lastCueText = state.cueText
        let subtitle = state.sectionName.isEmpty ? state.currentChord : state.sectionName
        return AlertConfiguration(
            title: LocalizedStringResource(stringLiteral: state.cueText),
            body: LocalizedStringResource(stringLiteral: subtitle),
            sound: .default
        )
    }

    private static func scheduleCueClear() {
        cueClearTask?.cancel()
        cueClearTask = Task {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            guard let current = activity else { return }
            var state = current.content.state
            guard !state.cueText.isEmpty else { return }
            state.cueText = ""
            state.cueSymbol = ""
            lastCueText = ""
            await current.update(.init(state: state, staleDate: Date().addingTimeInterval(90)))
        }
    }

    private static func makeContentState(from viewModel: SessionViewModel) -> ChordyxSessionAttributes.ContentState {
        let isGuest = viewModel.role == .guest
        let notation = isGuest ? viewModel.guestPreferredNotation : viewModel.payload.notation
        let transpose = isGuest ? GuestDisplaySettings.transposeSemitones : 0
        let capo = isGuest ? GuestDisplaySettings.capoFret : 0
        let visible = viewModel.guestVisibleChord(preferLivePiano: true) ?? viewModel.activeChord
        let currentChord = visible.map {
            ChordDisplayHelper.displayName(
                for: $0,
                notation: notation,
                songKey: viewModel.payload.key,
                transposeSemitones: transpose,
                capoFret: capo
            )
        } ?? "—"
        let nextChord = viewModel.payload.isLiveChordsOnly ? "" : (viewModel.upcomingChord.map {
            ChordDisplayHelper.displayName(
                for: $0,
                notation: notation,
                songKey: viewModel.payload.key,
                transposeSemitones: transpose,
                capoFret: capo
            )
        } ?? "")

        if currentChord != lastChordName {
            lastChordName = currentChord
            chordChangeToken += 1
        }

        let sorted = viewModel.sortedChords
        let chordPosition: String = {
            guard !sorted.isEmpty,
                  let activeID = viewModel.payload.activeChordID,
                  let index = sorted.firstIndex(where: { $0.id == activeID }) else { return "" }
            return "\(index + 1)/\(sorted.count)"
        }()

        let setlistProgress: String = {
            guard let index = viewModel.payload.setlistSongIndex,
                  let count = viewModel.payload.setlistSongCount,
                  count > 0 else { return "" }
            return "\(index + 1)/\(count)"
        }()

        let personalChartNote: String = {
            guard isGuest else { return "" }
            var parts: [String] = []
            if capo > 0 {
                parts.append(String(format: String(localized: "Capo %lld"), capo))
            }
            if transpose != 0 {
                parts.append(transpose > 0 ? "+\(transpose)" : "\(transpose)")
            }
            return parts.joined(separator: " · ")
        }()

        let currentBeat = viewModel.payload.isMetronomePlaying || viewModel.payload.isCountingIn
            ? viewModel.metronome.currentBeat
            : -1

        let isConnected = sessionIsConnected(viewModel)
        let statusLine = makeStatusLine(
            viewModel: viewModel,
            currentChord: currentChord,
            isConnected: isConnected
        )

        return ChordyxSessionAttributes.ContentState(
            sessionName: viewModel.payload.sessionName,
            songTitle: viewModel.payload.sessionName,
            sectionName: viewModel.activeSection?.name ?? "",
            currentChord: currentChord,
            nextChord: nextChord,
            keyName: viewModel.isAutoKeyStillListening
                ? String(localized: "Detecting key…")
                : (viewModel.autoKeyDisplayGlyph(isGuest: false) ?? viewModel.payload.key.displayName),
            tempoBPM: Int(viewModel.payload.tempoBPM.rounded()),
            isMetronomePlaying: viewModel.payload.isMetronomePlaying,
            setlistProgress: setlistProgress,
            cueText: viewModel.payload.activeCue?.text ?? "",
            cueSymbol: viewModel.payload.activeCue?.symbol ?? "megaphone.fill",
            isCountingIn: viewModel.payload.isCountingIn,
            hideSongTitle: GuestDisplaySettings.hideSongTitleOnLockScreen,
            chordPosition: chordPosition,
            currentBeat: currentBeat,
            beatsPerBar: max(1, viewModel.payload.beatsPerBar),
            isAccentBeat: currentBeat == 0,
            personalChartNote: personalChartNote,
            isLiveChord: viewModel.hasFreestyleActivity || viewModel.payload.ringShowsLiveChords,
            chordChangeToken: chordChangeToken,
            isConnected: isConnected,
            statusLine: statusLine
        )
    }

    private static func sessionIsConnected(_ viewModel: SessionViewModel) -> Bool {
        if viewModel.isPracticeMode { return true }
        switch viewModel.sessionManager.connectionState {
        case .connected:
            return true
        case .hosting:
            return viewModel.role == .host
        case .browsing, .idle:
            return false
        }
    }

    private static func makeStatusLine(
        viewModel: SessionViewModel,
        currentChord: String,
        isConnected: Bool
    ) -> String {
        if !isConnected {
            return viewModel.guestLinkStatus == .reconnecting
                ? String(localized: "Reconnecting…")
                : viewModel.guestLinkStatus.label
        }
        if currentChord == "—" {
            return String(localized: "Waiting for chords")
        }
        if viewModel.role == .guest {
            return viewModel.sessionManager.syncQuality.label
        }
        if viewModel.sessionManager.connectedPeers.isEmpty {
            return String(localized: "Waiting for musicians")
        }
        return String(localized: "Live sync")
    }
}
#endif
