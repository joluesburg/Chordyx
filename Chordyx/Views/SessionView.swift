//
//  SessionView.swift
//  Chordyx
//

import SwiftUI
import MultipeerConnectivity
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct SessionView: View {
    @Bindable var viewModel: SessionViewModel
    @Bindable var store: ProgressionStore
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.scenePhase) private var scenePhase
    @State private var showProgressionEditor = false
    @State private var showLeaveConfirmation = false
    @State private var showSaveDialog = false
    @State private var saveName = ""
    @State private var showSavedToast = false
    @State private var pendingHostProgression: SavedProgression?
    @State private var beatFlashEnabled = true
    @State private var flashOpacity: Double = 0
    @State private var flashColor: Color = AppTheme.accent
    @State private var showPianoOverlay = false
    @State private var showFretboardOverlay = false
    @AppStorage("metronomeVolume") private var metronomeVolume: Double = 0.8
    @AppStorage("metronomePanelVisible") private var metronomePanelVisible = true
    @AppStorage("guestShowLiveChordsOnRing") private var showLiveChordsOnRing = false
    @AppStorage(GuestDisplaySettings.liveNowOnlyKey) private var guestLiveNowOnly = false
    @AppStorage(SessionViewModel.showInternetJoinCodeKey) private var showInternetJoinCode = false
    @AppStorage("guestMetronomeAudioEnabled") private var guestMetronomeAudioEnabled = true
    @State private var showMetadataEditor = false
    @State private var showMIDISettings = false
    @State private var showGuestSettings = false
    @State private var showLockScreenSettings = false
    @State private var showPDFChart = false
    @State private var liveToolsExpanded = false
    @State private var showBackingTrackImporter = false
    @State private var backingTrackImportError: String?
    @State private var showPreServiceChecklist = false
    @State private var showExtendedFeaturesHub = false
    @State private var showAdvancedFeaturesHub = false
    @State private var showGuestRoles = false
    @State private var showRehearsalList = false
    @State private var showJoinQR = false
    @State private var isKeyMenuPresented = false
    @AppStorage(GuestDisplaySettings.transposeKey) private var guestTranspose = 0
    @AppStorage(GuestDisplaySettings.capoKey) private var guestCapo = 0
    @AppStorage(GuestDisplaySettings.bandCuePadVisibleKey) private var bandCuePadVisible = false
    @AppStorage(SessionDockSettings.layoutModeKey) private var liveDockLayoutModeRaw = LiveDockLayoutMode.automatic.rawValue
    @AppStorage(SessionDockSettings.heightPresetKey) private var liveDockHeightPresetRaw = LiveDockHeightPreset.standard.rawValue
    @AppStorage(SessionDockSettings.selectedTabKey) private var liveDockSelectedTabRaw = LiveHostDockTab.quick.rawValue
    @AppStorage(SessionDockSettings.sideRailVisibleKey) private var liveSideRailVisible = true

    private var isHost: Bool { viewModel.role == .host || viewModel.isPracticeMode }
    private var isGuest: Bool { viewModel.role == .guest }
    private var isPractice: Bool { viewModel.isPracticeMode }

    private var isLivePerformance: Bool {
        viewModel.payload.performanceMode.usesCompactStageUI && !isPractice
    }

    private var isLiveCompactHost: Bool {
        isHost && isLivePerformance && !liveToolsExpanded
    }

    private var showsLiveHostTransportDeck: Bool {
        needsLiveChordTransport
    }

    /// Prev/next chord transport — only when a saved progression has multiple chords to step through.
    private var needsLiveChordTransport: Bool {
        guard isLivePerformance, !liveToolsExpanded else { return false }
        guard isHost || viewModel.isCoHost else { return false }
        guard viewModel.canDriveSession || viewModel.isCoHost else { return false }
        guard !viewModel.payload.isLiveChordsOnly else { return false }
        guard !viewModel.isLiveProgressionSession else { return viewModel.sortedChords.count > 1 }
        return viewModel.sortedChords.count > 1
    }

    private var usesLiveChordHeroLayout: Bool {
        isLivePerformance && !liveToolsExpanded
    }

    /// Prefer Stage hero in Live unless the user explicitly chose Ring.
    private var prefersLiveChordHeroDisplay: Bool {
        guard effectiveDisplayMode != .ring else { return false }
        if viewModel.payload.isLiveChordsOnly { return true }
        if guestShowsLiveNowOnly { return true }
        if usesLiveChordHeroLayout { return true }
        if isLivePerformance && (viewModel.hasFreestyleActivity || ringShowsLiveChords) { return true }
        return false
    }

    private var usesChordRingLayout: Bool {
        effectiveDisplayMode == .ring
    }

    private var isCountInActive: Bool {
        viewModel.payload.isCountingIn || viewModel.metronome.isCountingIn
    }

    private var shouldOfferPreServiceChecklist: Bool {
        isHost && !isPractice && isLivePerformance
            && GuestDisplaySettings.preServiceChecklistAutoShowEnabled
            && GuestDisplaySettings.preServiceChecklistDismissedToken != viewModel.payload.sessionToken.uuidString
    }

    private var effectiveDisplayMode: SessionDisplayMode {
        viewModel.effectiveDisplayMode(isGuest: isGuest)
    }

    private var guestShowsLiveNowOnly: Bool {
        isGuest && isLivePerformance && guestLiveNowOnly
    }

    private var shouldShowScaleHint: Bool {
        guard GuestDisplaySettings.scaleHintsEnabled else { return false }
        if isLivePerformance && isHost { return false }
        return isGuest || isPractice || viewModel.payload.performanceMode == .rehearsal
    }

    private var shouldPulseBeatHint: Bool {
        let hintsOn = viewModel.payload.showBeatSyncHints || (isGuest && GuestDisplaySettings.beatSyncHintsEnabled)
        guard hintsOn, let active = viewModel.activeChord, let duration = active.durationBeats else { return false }
        return viewModel.payload.beatsOnActiveChord >= max(0, Int(duration.rounded()) - 1)
    }

    /// Target height for stage/chart modes; ring mode expands to fill available space.
    private var stageContentHeight: CGFloat {
        if horizontalSizeClass == .regular {
            return verticalSizeClass == .compact ? 360 : 480
        }
        return verticalSizeClass == .compact ? 280 : 420
    }

    private var ringRadiusFactor: CGFloat {
        horizontalSizeClass == .regular ? 0.50 : 0.46
    }

    private func ringBubbleSize(chordCount: Int) -> CGFloat {
        let base: CGFloat
        switch chordCount {
        case 0...4: base = 78
        case 5...8: base = 70
        default: base = 60
        }
        return horizontalSizeClass == .regular ? base + 14 : base
    }

    private var usesWideSessionLayout: Bool {
        PlatformLayout.usesWideSessionLayout(horizontalSizeClass: horizontalSizeClass)
    }

    private var usesWideLiveCompactDeck: Bool {
        usesWideSessionLayout && isLiveCompactHost && !usesLiveHostControlDock
    }

    private var usesLiveHostControlDock: Bool {
        usesWideSessionLayout && isLiveCompactHost && viewModel.canDriveSession
    }

    /// iPhone portrait live session — split chord hero and bottom controls ~50/50.
    private var usesPhonePortraitLiveSplit: Bool {
        #if os(iOS)
        PlatformDevice.isPhone && verticalSizeClass == .regular && isLivePerformance
        #else
        false
        #endif
    }

    private func phonePortraitLiveUsableHeight(viewportHeight: CGFloat) -> CGFloat {
        let header = maxHeaderHeight(for: viewportHeight)
        return max(0, viewportHeight - header - 12)
    }

    private var liveDockSelectedTab: Binding<LiveHostDockTab> {
        Binding(
            get: { LiveHostDockTab(rawValue: liveDockSelectedTabRaw) ?? .quick },
            set: { liveDockSelectedTabRaw = $0.rawValue }
        )
    }

    private var liveDockLayoutMode: Binding<LiveDockLayoutMode> {
        Binding(
            get: { LiveDockLayoutMode(rawValue: liveDockLayoutModeRaw) ?? .automatic },
            set: { liveDockLayoutModeRaw = $0.rawValue }
        )
    }

    private func resolvedLiveDockLayout(viewportWidth: CGFloat) -> LiveDockLayoutMode {
        let stored = LiveDockLayoutMode(rawValue: liveDockLayoutModeRaw) ?? .automatic
        return SessionDockSettings.resolvedLayoutMode(viewportWidth: viewportWidth, stored: stored)
    }

    private var sessionPanelMaxWidth: CGFloat {
        PlatformLayout.sessionPanelMaxWidth(horizontalSizeClass: horizontalSizeClass)
    }

    private var sessionHorizontalPadding: CGFloat {
        PlatformLayout.sessionHorizontalPadding(horizontalSizeClass: horizontalSizeClass)
    }

    private func maxBottomPanelHeight(for viewportHeight: CGFloat, viewportWidth: CGFloat = 1_000) -> CGFloat {
        if usesPhonePortraitLiveSplit {
            let usable = phonePortraitLiveUsableHeight(viewportHeight: viewportHeight)
            let fraction: CGFloat = bandCuePadVisible ? 0.56 : 0.50
            return usable * fraction
        }
        if usesLiveHostControlDock {
            let layout = resolvedLiveDockLayout(viewportWidth: viewportWidth)
            if layout == .sideRail {
                return needsLiveChordTransport ? 118 : 78
            }
            let preset = LiveDockHeightPreset(rawValue: liveDockHeightPresetRaw) ?? .standard
            return SessionDockSettings.bottomPanelHeight(
                viewportHeight: viewportHeight,
                preset: preset,
                bandCuePadVisible: bandCuePadVisible
            )
        }
        if prefersLiveChordHeroDisplay && isLivePerformance {
            let fraction = bandCuePadVisible ? 0.26 : 0.16
            return min(bandCuePadVisible ? 220 : 150, viewportHeight * fraction)
        }
        let isRingHero = usesChordRingLayout || guestShowsLiveNowOnly
        #if os(macOS)
        if isGuest && isRingHero {
            return min(240, viewportHeight * 0.30)
        }
        #endif
        let fraction: CGFloat
        if usesWideSessionLayout {
            if isHost && isLivePerformance && !liveToolsExpanded {
                fraction = bandCuePadVisible
                    ? (verticalSizeClass == .compact ? 0.34 : 0.38)
                    : (verticalSizeClass == .compact ? 0.24 : 0.26)
            } else if isRingHero {
                fraction = isGuest ? 0.30 : 0.28
            } else {
                fraction = 0.36
            }
        } else if isGuest {
            if isRingHero {
                fraction = verticalSizeClass == .compact ? 0.36 : 0.32
            } else {
                fraction = verticalSizeClass == .compact ? 0.50 : 0.46
            }
        } else if isHost {
            if isLivePerformance && !liveToolsExpanded {
                fraction = bandCuePadVisible
                    ? (verticalSizeClass == .compact ? 0.44 : 0.46)
                    : (verticalSizeClass == .compact ? 0.28 : 0.30)
            } else if isRingHero {
                fraction = verticalSizeClass == .compact ? 0.34 : 0.30
            } else {
                fraction = verticalSizeClass == .compact ? 0.44 : 0.40
            }
        } else {
            fraction = isRingHero ? 0.32 : 0.40
        }
        return viewportHeight * fraction
    }

    private func maxHeaderHeight(for viewportHeight: CGFloat) -> CGFloat {
        if usesChordRingLayout {
            return horizontalSizeClass == .regular ? 92 : 80
        }
        if prefersLiveChordHeroDisplay {
            return horizontalSizeClass == .regular ? 72 : 64
        }
        return horizontalSizeClass == .regular ? 220 : min(200, viewportHeight * 0.24)
    }

    private func effectiveStageHeight(
        viewportHeight: CGFloat,
        bottomMaxHeight: CGFloat,
        headerMaxHeight: CGFloat
    ) -> CGFloat {
        if usesPhonePortraitLiveSplit {
            let usable = phonePortraitLiveUsableHeight(viewportHeight: viewportHeight)
            return max(200, usable * 0.50)
        }
        let verticalPadding: CGFloat = verticalSizeClass == .compact ? 12 : 20
        let reserved = bottomMaxHeight + headerMaxHeight + verticalPadding
        let available = viewportHeight - reserved
        return min(stageContentHeight, max(verticalSizeClass == .compact ? 180 : 220, available))
    }

    private func ringRadius(
        in size: CGSize,
        bubbleSize: CGFloat
    ) -> CGFloat {
        let edgePadding: CGFloat = 8
        let maxRadius = (min(size.width, size.height) - bubbleSize) / 2 - edgePadding
        let preferred = min(size.width, size.height) * ringRadiusFactor
        return max(64, min(preferred, maxRadius))
    }

    private func ringLayout(
        in size: CGSize,
        chordCount: Int
    ) -> (bubbleSize: CGFloat, radius: CGFloat, centerDiameter: CGFloat) {
        let bubbleGap: CGFloat = 14
        var bubbleSize = ringBubbleSize(chordCount: chordCount)
        var radius = ringRadius(in: size, bubbleSize: bubbleSize)
        var clearance = max(0, radius - bubbleSize / 2 - bubbleGap)

        let minCenterDiameter: CGFloat = horizontalSizeClass == .regular ? 168 : 138
        while clearance * 2 < minCenterDiameter, bubbleSize > 54 {
            bubbleSize -= 3
            radius = ringRadius(in: size, bubbleSize: bubbleSize)
            clearance = max(0, radius - bubbleSize / 2 - bubbleGap)
        }

        let centerCap: CGFloat = {
            if horizontalSizeClass == .regular { return isGuest ? 300 : 280 }
            return isGuest ? 230 : 210
        }()
        let centerDiameter = max(minCenterDiameter, min(centerCap, clearance * 2))
        return (bubbleSize, radius, centerDiameter)
    }
    private var peerCount: Int {
        switch viewModel.sessionManager.connectionState {
        case .connected(let count): count
        default: 0
        }
    }

    private var guestShowsHostPiano: Bool {
        isGuest && hostSharingPiano
    }

    private var centerShowsLivePiano: Bool {
        if isHost { return !viewModel.payload.pianoNotes.isEmpty }
        return guestShowsHostPiano || viewModel.isHostPianoLive
    }

    private var ringShowsLiveChords: Bool {
        if viewModel.payload.isLiveChordsOnly { return true }
        if isHost { return viewModel.payload.ringShowsLiveChords }
        // Guests follow the host Live ring flag; local toggle can still force it on.
        return viewModel.payload.ringShowsLiveChords || showLiveChordsOnRing
    }

    private var ringSourceBinding: Binding<Bool> {
        if isHost {
            Binding(
                get: { viewModel.payload.ringShowsLiveChords },
                set: { viewModel.setRingShowsLiveChords($0) }
            )
        } else {
            $showLiveChordsOnRing
        }
    }

    private var ringChords: [ChordEntry] {
        if let live = liveRingChords { return live }
        return resolvedRingSectionChords
    }

    /// Live MIDI ring: unique chords for the current song only (not the full progression list).
    /// Once a repeating progression is inferred, fall back to the ordered `sortedChords` ring.
    private var liveRingChords: [ChordEntry]? {
        if viewModel.hasInferredLiveProgression, !viewModel.sortedChords.isEmpty {
            return nil
        }
        if ringShowsLiveChords || viewModel.isLiveProgressionSession || viewModel.payload.isLiveChordsOnly {
            let live = viewModel.freestyleChordEntries
            if !live.isEmpty { return live }
        }
        return nil
    }

    private var resolvedRingSectionChords: [ChordEntry] {
        let sectionChords = viewModel.ringSectionChords
        if !sectionChords.isEmpty { return sectionChords }
        return viewModel.sortedChords
    }

    private var centerChord: ChordEntry? {
        if viewModel.hasInferredLiveProgression {
            return viewModel.livePianoChordEntry() ?? viewModel.activeChord
        }
        if centerShowsLivePiano {
            return viewModel.livePianoChordEntry() ?? viewModel.activeChord
        }
        if liveRingChords != nil || ringShowsLiveChords || viewModel.payload.isLiveChordsOnly {
            return viewModel.liveFreestyleChord ?? viewModel.activeChord
        }
        return viewModel.activeChord
    }

    private var ringNotation: ChordNotation {
        viewModel.displayNotation(isGuest: isGuest)
    }

    private var keyControlTitle: String {
        let keyName = viewModel.payload.key.displayName
        if viewModel.payload.autoDetectKey {
            if viewModel.payload.isKeyAutoDetected {
                return String(format: String(localized: "Key %@ · AI"), keyName)
            }
            return String(format: String(localized: "Key %@ · AI listening"), keyName)
        }
        return String(format: String(localized: "Key %@"), keyName)
    }

    var body: some View {
        Group {
            if viewModel.payload.isStageDisplayOnly {
                stageDisplayOnlyLayout
            } else {
                sessionWithAlerts
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.backgroundGradient.ignoresSafeArea())
        .platformDesktopControls()
    }

    private var stageDisplayOnlyLayout: some View {
        ZStack(alignment: .topTrailing) {
            StageDisplayShellView(viewModel: viewModel, isGuest: isGuest)
            Button {
                viewModel.toggleStageDisplayOnly()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .padding()
            }
            .buttonStyle(.plain)
        }
    }

    private var sessionLayout: some View {
        GeometryReader { geometry in
            let bottomMaxHeight = maxBottomPanelHeight(
                for: geometry.size.height,
                viewportWidth: geometry.size.width
            )
            let headerMaxHeight = maxHeaderHeight(for: geometry.size.height)
            let stageHeight = effectiveStageHeight(
                viewportHeight: geometry.size.height,
                bottomMaxHeight: bottomMaxHeight,
                headerMaxHeight: headerMaxHeight
            )
            let dockLayout = resolvedLiveDockLayout(viewportWidth: geometry.size.width)
            let showSideRail = usesLiveHostControlDock
                && dockLayout == .sideRail
                && liveSideRailVisible

            if usesLiveHostControlDock, dockLayout == .sideRail {
                HStack(spacing: 0) {
                    sessionMainColumn(
                        stageHeight: stageHeight,
                        headerMaxHeight: headerMaxHeight,
                        bottomMaxHeight: bottomMaxHeight,
                        viewportWidth: geometry.size.width
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if showSideRail {
                        Divider()
                        liveHostControlRail(style: .sideRail)
                            .frame(width: SessionDockSettings.sideRailDefaultWidth)
                    }
                }
            } else {
                sessionMainColumn(
                    stageHeight: stageHeight,
                    headerMaxHeight: headerMaxHeight,
                    bottomMaxHeight: bottomMaxHeight,
                    viewportWidth: geometry.size.width
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func sessionMainColumn(
        stageHeight: CGFloat,
        headerMaxHeight: CGFloat,
        bottomMaxHeight: CGFloat,
        viewportWidth: CGFloat
    ) -> some View {
        sessionContent(stageHeight: stageHeight)
            .safeAreaInset(edge: .top, spacing: 0) {
                if usesChordRingLayout {
                    ringModeHeader
                } else if viewModel.payload.performanceMode == .rehearsal {
                    sessionHeader(maxHeight: headerMaxHeight)
                } else {
                    compactSessionHeader(maxHeight: headerMaxHeight)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                bottomPanel(maxHeight: bottomMaxHeight, viewportWidth: viewportWidth)
                    .animation(.spring(response: 0.32, dampingFraction: 0.86), value: liveDockHeightPresetRaw)
                    .animation(.spring(response: 0.32, dampingFraction: 0.86), value: verticalSizeClass)
            }
    }

    private var sessionWithOverlays: some View {
        sessionLayoutWithLifecycle
            .overlay { sessionOverlayStack }
    }

    private var sessionLayoutWithLifecycle: some View {
        sessionLayout
            .onAppear(perform: configureSessionOnAppear)
            .onChange(of: viewModel.isInSession) { _, inSession in
                if inSession { presentPreServiceChecklistIfNeeded() }
            }
            .onChange(of: guestMetronomeAudioEnabled) { _, enabled in
                if isGuest { viewModel.setGuestMetronomeAudioEnabled(enabled) }
            }
            .onChange(of: viewModel.role) { _, _ in
                viewModel.refreshMetronomeAudioPolicy()
            }
            .onChange(of: scenePhase) { _, phase in
                handleScenePhaseChange(phase)
            }
            .onChange(of: viewModel.metronome.currentBeat) { _, newBeat in
                handleMetronomeBeatChange(newBeat)
            }
    }

    @ViewBuilder
    private var sessionOverlayStack: some View {
        cueOverlayContent
        countInOverlayContent
        sectionCountdownOverlayContent
        extendedSessionOverlayContent
        chordChangeWarningOverlayContent
        transitionOverlayContent
        beatFlashOverlayContent
        songEndingOverlayContent
        reconnectOverlayContent
    }

    private func configureSessionOnAppear() {
        if isGuest {
            viewModel.setGuestMetronomeAudioEnabled(guestMetronomeAudioEnabled)
            showLiveChordsOnRing = viewModel.payload.ringShowsLiveChords
        } else {
            viewModel.refreshMetronomeAudioPolicy()
        }
        presentPreServiceChecklistIfNeeded()
    }

    private func handleScenePhaseChange(_ phase: ScenePhase) {
        switch phase {
        case .active:
            viewModel.handleAppDidBecomeActive()
        case .background:
            viewModel.handleAppDidEnterBackground()
        case .inactive:
            break
        @unknown default:
            break
        }
    }

    private func handleMetronomeBeatChange(_ newBeat: Int) {
        guard viewModel.isInSession else { return }
        guard newBeat >= 0 else { return }
        if newBeat == 0 {
            viewModel.updateTempoDrift()
        }

        if isCountInActive {
            pulseBeatFlash(
                color: newBeat == 0 ? AppTheme.accent : AppTheme.accentSecondary,
                intensity: newBeat == 0 ? 1.0 : 0.7
            )
            return
        }

        if viewModel.shouldShowChordChangeWarning {
            pulseBeatFlash(
                color: AppTheme.accentSecondary,
                intensity: newBeat == 0 ? 1.0 : 0.55
            )
            if newBeat == 0 {
                viewModel.triggerChordChangeWarningHaptic()
            }
            return
        }

        guard isGuest, beatFlashEnabled, viewModel.displayedMetronomePlaying else { return }
        pulseBeatFlash(
            color: newBeat == 0 ? AppTheme.accent : AppTheme.accentSecondary,
            intensity: newBeat == 0 ? 1.0 : 0.6
        )
    }

    private func pulseBeatFlash(color: Color, intensity: Double) {
        flashColor = color
        flashOpacity = intensity
        withAnimation(.easeOut(duration: 0.22)) { flashOpacity = 0 }
    }

    @ViewBuilder
    private var countInOverlayContent: some View {
        if isCountInActive, viewModel.metronome.countInBeatsRemaining > 0 {
            CountInOverlay(
                beatsRemaining: viewModel.metronome.countInBeatsRemaining,
                beatInBar: max(0, viewModel.metronome.currentBeat),
                beatsPerBar: viewModel.payload.beatsPerBar
            )
            .transition(.scale.combined(with: .opacity))
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var chordChangeWarningOverlayContent: some View {
        if viewModel.shouldShowChordChangeWarning,
           let remaining = viewModel.chordChangeBeatsRemaining {
            ChordChangeWarningBanner(beatsRemaining: remaining)
                .padding(.top, 72)
                .padding(.horizontal, sessionHorizontalPadding)
                .frame(maxWidth: .infinity, alignment: .top)
                .allowsHitTesting(false)
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    @ViewBuilder
    private var sectionCountdownOverlayContent: some View {
        if viewModel.payload.sectionCountdownBeats > 0,
           let label = viewModel.payload.sectionCountdownLabel {
            SectionCountdownOverlay(
                sectionName: label,
                beatsRemaining: viewModel.payload.sectionCountdownBeats
            )
            .padding(.top, 120)
            .padding(.horizontal, sessionHorizontalPadding)
            .frame(maxWidth: .infinity, alignment: .top)
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var extendedSessionOverlayContent: some View {
        VStack(spacing: 8) {
            if viewModel.payload.isGhostBandReplayActive {
                GhostBandReplayBanner {
                    viewModel.stopGhostBandReplay()
                }
            }

            if let handoff = viewModel.payload.handoffCountdown, handoff > 0 {
                HandoffCountdownBanner(
                    fromPeer: viewModel.payload.handoffFromPeer,
                    seconds: handoff
                )
            }

            if !isGuest,
               abs(viewModel.payload.tempoDriftBPM) > 2,
               viewModel.payload.isMetronomePlaying,
               !viewModel.payload.hostLiveGrooveActive {
                TempoDriftBanner(driftBPM: viewModel.payload.tempoDriftBPM)
            }

            if let note = viewModel.currentRoleLiveNote {
                RoleLiveNoteBanner(note: note)
            }

            if let suggestion = viewModel.capoSuggestion, isHost, showsSecondaryBandOverlays {
                CapoSuggestionBanner(suggestion: suggestion) {
                    viewModel.transpose(to: suggestion.vocalKey)
                }
            }

            if let suggestion = viewModel.vocalRangeSuggestion, isHost, showsSecondaryBandOverlays {
                VocalRangeBanner(suggestion: suggestion) {
                    viewModel.transpose(to: suggestion.suggestedKey)
                }
            }

            if let hint = viewModel.currentVoicingHint, showsSecondaryBandOverlays {
                VoicingHintBanner(hint: hint)
            }

            if !viewModel.payload.peerPresence.isEmpty, isHost, showsSecondaryBandOverlays {
                ChordPresenceStrip(
                    presence: viewModel.payload.peerPresence,
                    activeChordID: viewModel.payload.activeChordID
                )
            }

            if isHost, !viewModel.sessionManager.connectedPeers.isEmpty, showsSecondaryBandOverlays {
                SilentNudgePad(viewModel: viewModel)
            }

            if viewModel.isInSession, showsSessionQuickMessages {
                QuickMessageBar(viewModel: viewModel, canSend: !isGuest || viewModel.isCoHost)
            }
        }
        .padding(.horizontal, sessionHorizontalPadding)
        .padding(.top, 8)
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var showsSecondaryBandOverlays: Bool {
        !isLiveCompactHost
    }

    private var showsSessionQuickMessages: Bool {
        if isLiveCompactHost { return bandCuePadVisible }
        return isHost || showsSecondaryBandOverlays
    }

    private var notationOverlayAlignment: Alignment {
        #if os(iOS)
        if isLivePerformance || usesWideSessionLayout { return .topTrailing }
        #else
        if usesWideSessionLayout { return .topTrailing }
        #endif
        return .bottomTrailing
    }

    @ViewBuilder
    private var cueOverlayContent: some View {
        if let cue = viewModel.payload.activeCue {
            LiveCueBanner(
                cue: cue,
                isAutoAdvancePaused: viewModel.payload.isAutoAdvancePaused,
                isVampActive: viewModel.payload.isVampActive
            )
            .padding(.top, 80)
            .padding(.horizontal, sessionHorizontalPadding)
            .frame(maxWidth: .infinity, alignment: .top)
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var transitionOverlayContent: some View {
        if let title = viewModel.payload.transitionTitle {
            SetlistTransitionOverlay(title: title, countdown: viewModel.payload.transitionCountdown)
                .allowsHitTesting(true)
        }
    }

    @ViewBuilder
    private var songEndingOverlayContent: some View {
        if viewModel.payload.isSongEnding {
            SongEndingOverlay()
                .transition(.scale.combined(with: .opacity))
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var beatFlashOverlayContent: some View {
        let shouldFlash = isCountInActive
            || viewModel.shouldShowChordChangeWarning
            || (isGuest && beatFlashEnabled && viewModel.displayedMetronomePlaying)
        if shouldFlash {
            RoundedRectangle(cornerRadius: 0)
                .stroke(flashColor, lineWidth: isCountInActive ? 14 : 10)
                .padding(6)
                .opacity(flashOpacity)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var reconnectOverlayContent: some View {
        if viewModel.showReconnectBanner, isGuest {
            ReconnectBanner(
                sessionName: viewModel.payload.sessionName,
                onReconnect: { viewModel.tryAutoReconnectIfPossible() },
                onLeave: { showLeaveConfirmation = true }
            )
            .padding(.horizontal, sessionHorizontalPadding)
            .padding(.top, 8)
            .frame(maxWidth: .infinity, alignment: .top)
        }
    }

    @ViewBuilder
    private var sessionWithSheets: some View {
        sessionWithOverlays
            .platformSheet(isPresented: $showMIDISettings) {
                MIDISettingsView(viewModel: viewModel)
            }
            .platformSheet(isPresented: $showGuestSettings, onDismiss: {
                if isGuest {
                    viewModel.setGuestMetronomeAudioEnabled(guestMetronomeAudioEnabled)
                }
                viewModel.refreshMetronomeAudioPolicy()
            }) {
                GuestMusicianSettingsView()
            }
            .platformSheet(isPresented: $showLockScreenSettings) {
                LockScreenActivitySettingsView()
            }
            .platformSheet(isPresented: $showPDFChart) {
                pdfChartSheet
            }
            .platformSheet(isPresented: $showMetadataEditor) {
                metadataEditorSheet
            }
            .platformSheet(isPresented: $showProgressionEditor, large: true) {
                ProgressionEditorView(viewModel: viewModel)
            }
            .platformSheet(isPresented: $showPreServiceChecklist, onDismiss: markPreServiceChecklistDismissedForSession, large: true) {
                PreServiceChecklistView(viewModel: viewModel, store: store) {
                    markPreServiceChecklistDismissedForSession()
                    showPreServiceChecklist = false
                }
            }
            .platformSheet(isPresented: $showExtendedFeaturesHub, large: true) {
                ExtendedFeaturesHubView(viewModel: viewModel, store: store)
            }
            .platformSheet(isPresented: $showAdvancedFeaturesHub, large: true) {
                AdvancedFeaturesHubView(viewModel: viewModel, store: store)
            }
            .platformSheet(isPresented: $showGuestRoles) {
                GuestRoleAssignmentView(viewModel: viewModel)
            }
            .platformSheet(isPresented: $showRehearsalList) {
                RehearsalRecordingsView(viewModel: viewModel)
            }
            .platformSheet(isPresented: $showJoinQR) {
                if let code = viewModel.payload.remoteJoinCode {
                    SessionJoinQRSheet(joinCode: code)
                }
            }
            .platformPianoSheet(isPresented: $showPianoOverlay, onDismiss: dismissPianoOverlay) {
                PianoView(
                    viewModel: viewModel,
                    onDismiss: dismissPianoOverlay,
                    onLeaveSession: isGuest ? { showLeaveConfirmation = true } : nil
                )
            }
            .platformFullScreenCover(isPresented: $showFretboardOverlay) {
                InstrumentView(
                    viewModel: viewModel,
                    onDismiss: dismissFretboardOverlay,
                    onLeaveSession: isGuest ? { showLeaveConfirmation = true } : nil
                )
            }
            .onChange(of: viewModel.payload.isPianoActive) { _, isActive in
                if !isActive { showPianoOverlay = false }
            }
            .onChange(of: viewModel.payload.isFretboardActive) { _, isActive in
                if !isActive { showFretboardOverlay = false }
            }
            .onChange(of: viewModel.payload.ringShowsLiveChords) { _, showsLive in
                if isGuest {
                    showLiveChordsOnRing = showsLive
                }
            }
#if os(macOS)
            .onKeyPress(.leftArrow) {
                viewModel.requestControlAction(.previousChord)
                return .handled
            }
            .onKeyPress(.rightArrow) {
                viewModel.requestControlAction(.advanceChord)
                return .handled
            }
            .onKeyPress(.space) {
                if viewModel.canDriveSession { viewModel.toggleMetronome() }
                return .handled
            }
            .onKeyPress("1", phases: .down) { _ in
                guard usesLiveHostControlDock else { return .ignored }
                liveDockSelectedTabRaw = LiveHostDockTab.quick.rawValue
                liveSideRailVisible = true
                return .handled
            }
            .onKeyPress("2", phases: .down) { _ in
                guard usesLiveHostControlDock else { return .ignored }
                liveDockSelectedTabRaw = LiveHostDockTab.metronome.rawValue
                liveSideRailVisible = true
                return .handled
            }
            .onKeyPress("3", phases: .down) { _ in
                guard usesLiveHostControlDock else { return .ignored }
                liveDockSelectedTabRaw = LiveHostDockTab.audio.rawValue
                liveSideRailVisible = true
                return .handled
            }
            .onKeyPress("4", phases: .down) { _ in
                guard usesLiveHostControlDock else { return .ignored }
                liveDockSelectedTabRaw = LiveHostDockTab.cues.rawValue
                liveSideRailVisible = true
                return .handled
            }
            .onKeyPress("5", phases: .down) { _ in
                guard usesLiveHostControlDock else { return .ignored }
                liveDockSelectedTabRaw = LiveHostDockTab.session.rawValue
                liveSideRailVisible = true
                return .handled
            }
            .onKeyPress("\\", phases: .down) { _ in
                guard usesLiveHostControlDock else { return .ignored }
                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                    liveSideRailVisible.toggle()
                }
                return .handled
            }
#endif
            .fileImporter(
                isPresented: $showBackingTrackImporter,
                allowedContentTypes: [.mp3, .wav, .aiff, .mpeg4Audio, .audio],
                allowsMultipleSelection: false
            ) { result in
                guard case .success(let urls) = result, let url = urls.first else { return }
                do {
                    try viewModel.importBackingTrack(from: url)
                } catch {
                    backingTrackImportError = error.localizedDescription
                }
            }
            .alert(String(localized: "Import Failed"), isPresented: Binding(
                get: { backingTrackImportError != nil },
                set: { if !$0 { backingTrackImportError = nil } }
            )) {
                Button(String(localized: "OK"), role: .cancel) {}
            } message: {
                Text(backingTrackImportError ?? "")
            }
    }

    @ViewBuilder
    private var pdfChartSheet: some View {
        if let id = viewModel.loadedProgressionID,
           let progression = store.progression(with: id),
           let url = store.pdfURL(for: progression) {
            NavigationStack {
                PDFChartView(url: url)
                    .navigationTitle("Chart PDF")
                    .platformInlineNavigationTitle()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showPDFChart = false }
                        }
                    }
            }
            .preferredColorScheme(.dark)
        }
    }

    private var metadataEditorSheet: some View {
        NavigationStack {
            ProgressionMetadataEditor(viewModel: viewModel)
                .navigationTitle("Lyrics & Sections")
                .platformInlineNavigationTitle()
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showMetadataEditor = false }
                    }
                }
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var sessionWithDialogs: some View {
        sessionWithSheets
            .confirmationDialog("Leave Session?", isPresented: $showLeaveConfirmation, titleVisibility: .visible) {
                Button("Leave Session", role: .destructive) {
                    viewModel.leaveSession()
                }
                Button("Cancel", role: .cancel) {}
            }
            .alert(saveProgressionAlertTitle, isPresented: $showSaveDialog) {
                TextField("Progression name", text: $saveName)
                if isSaved {
                    Button("Update") { performSave(overwrite: true) }
                    Button("Save as Copy") { performSave(overwrite: false) }
                } else {
                    Button("Save") { performSave(overwrite: false) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Name this chord progression so you can reuse it later.")
            }
    }

    private var saveProgressionAlertTitle: String {
        isSaved ? "Update Progression" : "Save Progression"
    }

    @ViewBuilder
    private var sessionWithAlerts: some View {
        sessionWithDialogs
            .alert("Saved to Your Library", isPresented: Binding(
                get: { pendingHostProgression != nil },
                set: { if !$0 { pendingHostProgression = nil } }
            )) {
                Button("Host This Now") {
                    if let progression = pendingHostProgression {
                        viewModel.hostSession(from: progression)
                    }
                    pendingHostProgression = nil
                }
                Button("Keep Following", role: .cancel) {
                    pendingHostProgression = nil
                }
            } message: {
                Text("Start your own session with this progression, or keep following the current host.")
            }
            .preferredColorScheme(.dark)
            .onChange(of: viewModel.shouldAutoAdvanceSetlist) { _, should in
                guard should else { return }
                viewModel.shouldAutoAdvanceSetlist = false
                if !viewModel.isLastSetlistSong(in: store) {
                    viewModel.loadSetlistSongAnimated(store: store)
                }
            }
    }

    private func sessionContent(stageHeight: CGFloat) -> some View {
        ZStack {
            AppTheme.backgroundGradient.ignoresSafeArea()

            VStack(spacing: 0) {
                if !viewModel.payload.sections.isEmpty {
                    Group {
                        if isLivePerformance {
                            LiveSectionJumpBar(viewModel: viewModel)
                        } else {
                            SectionJumpBar(viewModel: viewModel)
                        }
                    }
                    .padding(.horizontal, sessionHorizontalPadding)
                    .padding(.top, 4)
                }

                if isLivePerformance, viewModel.payload.setlistName != nil {
                    LiveSetlistControlBar(viewModel: viewModel, store: store)
                        .padding(.horizontal, sessionHorizontalPadding)
                        .padding(.top, 4)
                } else if !viewModel.setlistTimelineTitles.isEmpty,
                          let index = viewModel.payload.setlistSongIndex {
                    SetlistTimelineBanner(titles: viewModel.setlistTimelineTitles, currentIndex: index)
                        .padding(.horizontal, sessionHorizontalPadding)
                        .padding(.top, 4)
                }

                if !viewModel.payload.backingTrackDisplayName.isEmpty {
                    BackingTrackStatusBanner(
                        title: viewModel.payload.backingTrackDisplayName,
                        isPlaying: viewModel.payload.isBackingTrackPlaying,
                        isGuestView: isGuest
                    )
                    .padding(.horizontal, sessionHorizontalPadding)
                    .padding(.top, 4)
                }

                if viewModel.payload.performanceMode == .rehearsal,
                   !viewModel.payload.rehearsalNotes.isEmpty {
                    RehearsalNotesBanner(notes: viewModel.payload.rehearsalNotes)
                        .padding(.horizontal, sessionHorizontalPadding)
                        .padding(.top, 4)
                }

                if shouldShowScaleHint, let hint = viewModel.activeScaleHint {
                    ScaleHintBadge(hint: hint)
                        .padding(.horizontal, sessionHorizontalPadding)
                        .padding(.top, 4)
                }

                if let mismatch = viewModel.payload.pianoChartMismatch, isHost {
                    PianoChartMismatchBanner(message: mismatch)
                        .padding(.horizontal, sessionHorizontalPadding)
                        .padding(.top, 4)
                }

                if !viewModel.payload.sections.isEmpty {
                    LiveSectionRoadmap(
                        sections: viewModel.payload.sections,
                        chords: viewModel.payload.chords,
                        activeSectionID: viewModel.payload.activeSectionID,
                        isLocked: viewModel.payload.isSectionMapLocked && isLivePerformance,
                        onJump: { viewModel.jumpToSection($0) }
                    )
                    .padding(.horizontal, sessionHorizontalPadding)
                    .padding(.top, 4)
                }

                if viewModel.isRecordingRehearsal, isHost {
                    Label(String(localized: "Recording rehearsal timeline"), systemImage: "record.circle")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.red)
                        .padding(.top, 4)
                }

                if !GuestDisplaySettings.externalDisplayGuideDismissed,
                   (isHost || isPractice),
                   !isLivePerformance {
                    ExternalDisplayGuide {
                        GuestDisplaySettings.externalDisplayGuideDismissed = true
                    }
                    .padding(.horizontal, sessionHorizontalPadding)
                    .padding(.top, 4)
                }

                if usesChordRingLayout {
                    chordRingContent()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .layoutPriority(1)
                } else if prefersLiveChordHeroDisplay {
                    StageDisplayView(
                        viewModel: viewModel,
                        isGuest: isGuest,
                        guestTranspose: guestTranspose,
                        guestCapo: guestCapo,
                        nowOnlyFocus: true
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .layoutPriority(1)
                } else {
                    Spacer(minLength: verticalSizeClass == .compact ? 4 : 8)

                    switch effectiveDisplayMode {
                    case .stage:
                        StageDisplayView(
                            viewModel: viewModel,
                            isGuest: isGuest,
                            guestTranspose: isGuest ? guestTranspose : 0,
                            guestCapo: isGuest ? guestCapo : 0,
                            nowOnlyFocus: usesLiveChordHeroLayout
                        )
                        .frame(maxHeight: stageHeight + 80)
                    case .chart:
                        LyricsChartView(
                            viewModel: viewModel,
                            isGuest: isGuest,
                            guestTranspose: isGuest ? guestTranspose : 0,
                            guestCapo: isGuest ? guestCapo : 0
                        )
                        .frame(maxHeight: stageHeight + 120)
                    case .director:
                        DirectorModePanel(viewModel: viewModel, store: store)
                            .frame(maxHeight: stageHeight + 120)
                    case .audience:
                        AudienceLyricsDisplay(
                            viewModel: viewModel,
                            guestTranspose: guestTranspose,
                            guestCapo: guestCapo
                        )
                        .frame(maxHeight: stageHeight + 120)
                    case .congregation:
                        CongregationDisplayView(viewModel: viewModel)
                            .frame(maxHeight: stageHeight + 120)
                    case .ring:
                        EmptyView()
                    }

                    Spacer(minLength: verticalSizeClass == .compact ? 4 : 8)
                }
            }

            if showSavedToast {
                savedToast
            }

            if let guide = viewModel.importSessionGuide {
                importSessionGuideBanner(guide)
            }
        }
        .overlay(alignment: notationOverlayAlignment) {
            NotationCycleButton(viewModel: viewModel, isGuest: isGuest)
                .padding(.trailing, sessionHorizontalPadding)
                .padding(notationOverlayAlignment == .topTrailing ? .top : .bottom, 8)
                .zIndex(20)
        }
    }

    private func importSessionGuideBanner(_ guide: SessionViewModel.ImportSessionGuide) -> some View {
        VStack {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "circle.grid.2x2.fill")
                    .foregroundStyle(AppTheme.accent)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 4) {
                    Text(guide.title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(AppTheme.textPrimary)
                    Text(guide.message)
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Button {
                    withAnimation(.easeOut(duration: 0.2)) {
                        viewModel.clearImportSessionGuide()
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppTheme.textSecondary)
                        .padding(8)
                }
            }
            .padding(14)
            .background(AppTheme.surfaceElevated.opacity(0.96))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
            .padding(.horizontal, sessionHorizontalPadding)
            .padding(.top, 8)

            Spacer()
        }
    }

    @ViewBuilder
    private var ringStatusBadge: some View {
        if viewModel.hasInferredLiveProgression, !viewModel.sortedChords.isEmpty {
            inferredProgressionBadge
        } else if liveRingChords != nil || ringShowsLiveChords {
            liveChordBadge
        } else if viewModel.isLiveProgressionSession && !viewModel.sortedChords.isEmpty {
            liveProgressionBadge
        } else if centerShowsLivePiano {
            liveChordBadge
        } else if !viewModel.sortedChords.isEmpty {
            progressionBadge
        }
    }

    private func chordRingContent() -> some View {
        GeometryReader { geo in
            let layout = ringLayout(in: geo.size, chordCount: ringChords.count)

            if ringChords.isEmpty && centerChord == nil {
                VStack(spacing: 12) {
                    Image(systemName: "circle.grid.cross")
                        .font(.system(size: 44))
                        .foregroundStyle(AppTheme.accent.opacity(0.8))
                    Text("Waiting for chords")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                    Text(liveRingEmptyMessage)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ZStack {
                    ChordRingView(
                        chords: ringChords,
                        notation: ringNotation,
                        key: viewModel.payload.key,
                        transposeSemitones: isGuest ? guestTranspose : 0,
                        capoFret: isGuest ? guestCapo : 0,
                        activeChordID: liveRingChords != nil ? nil : viewModel.payload.activeChordID,
                        activeChordSymbol: liveRingChords != nil
                            ? viewModel.payload.liveChordSymbol
                            : nil,
                        isInteractive: isHost,
                        containerSize: geo.size,
                        radius: layout.radius,
                        bubbleSize: layout.bubbleSize,
                        beatChangeHint: shouldPulseBeatHint,
                        preferInstantActiveChanges: isHost && (!viewModel.midiSources.isEmpty || viewModel.isHostPianoLive),
                        onTap: { viewModel.setActiveChord($0) }
                    )

                    CurrentChordDisplay(
                        chord: centerChord,
                        upcoming: viewModel.hasInferredLiveProgression
                            ? viewModel.upcomingChord
                            : (viewModel.payload.isLiveChordsOnly || ringShowsLiveChords
                                ? nil
                                : viewModel.upcomingChord),
                        notation: ringNotation,
                        key: viewModel.payload.key,
                        transposeSemitones: isGuest ? guestTranspose : 0,
                        capoFret: isGuest ? guestCapo : 0,
                        emphasized: isGuest,
                        isEmptyProgression: isHost
                            && viewModel.sortedChords.isEmpty
                            && !viewModel.isLiveProgressionSession,
                        onAddChords: isHost ? { showProgressionEditor = true } : nil,
                        isLiveFreestyle: !viewModel.hasInferredLiveProgression && (
                            centerShowsLivePiano
                            || ringShowsLiveChords
                            || viewModel.payload.isLiveChordsOnly
                            || (isHost && viewModel.isLiveProgressionSession && viewModel.sortedChords.isEmpty)
                        ),
                        isListeningForChord: !viewModel.hasInferredLiveProgression
                            && (ringShowsLiveChords || viewModel.payload.isLiveChordsOnly)
                            && centerChord == nil
                            && (isHost ? !viewModel.payload.pianoNotes.isEmpty : hostSharingPiano),
                        preferInstantActiveChanges: isHost && (!viewModel.midiSources.isEmpty || viewModel.isHostPianoLive),
                        diameter: layout.centerDiameter
                    )
                    .frame(width: layout.centerDiameter, height: layout.centerDiameter)
                    .clipped()
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
                }
                .overlay(alignment: .bottom) {
                    if !showsLiveHostTransportDeck {
                        ringStatusBadge
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .padding(.horizontal, sessionHorizontalPadding)
                            .padding(.bottom, 8)
                    }
                }
            }
        }
        .frame(minHeight: ringContentMinHeight)
        .padding(.horizontal, sessionHorizontalPadding)
    }

    private var liveRingEmptyMessage: String {
        if isGuest {
            return String(localized: "The host's live chords will appear on the ring.")
        }
        if viewModel.usesLiveFreestyleRing || viewModel.payload.isLiveChordsOnly {
            return String(localized: "Play on piano or MIDI — the ring shows your most-used chords (up to six). When you repeat a progression, Chordyx locks it automatically. Tap New Song when you start another song.")
        }
        return String(localized: "Add chords or load a saved progression.")
    }

    private var showsLiveRingSongControls: Bool {
        isHost && (viewModel.usesLiveFreestyleRing || viewModel.payload.isLiveChordsOnly)
    }

    @ViewBuilder
    private var newLiveSongRingButton: some View {
        Button {
            viewModel.startNewLiveSongRing()
        } label: {
            Label(String(localized: "New Song"), systemImage: "arrow.triangle.2.circlepath")
                .font(.caption.weight(.semibold))
        }
        .buttonStyle(.bordered)
        .tint(AppTheme.accentSecondary)
    }

    private var ringContentMinHeight: CGFloat {
        #if os(macOS)
        isGuest ? 360 : 320
        #else
        isGuest ? 280 : 240
        #endif
    }

    @ViewBuilder
    private func guestLiveViewStyleControls(includeRingSource: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            GuestLiveViewStylePicker(nowOnly: $guestLiveNowOnly)
            Text(
                guestLiveNowOnly
                    ? String(localized: "Following the host's current chord — no ring.")
                    : String(localized: "Ring shows the full progression. Now shows only the chord being played.")
            )
            .font(.caption2)
            .foregroundStyle(AppTheme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)

            if includeRingSource, !guestLiveNowOnly {
                RingSourcePicker(showsLiveChords: ringSourceBinding)
            }
        }
    }

    private var ringModeHeader: some View {
        VStack(spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.payload.sessionName)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        if isGuest, let host = viewModel.sessionManager.hostPeerDisplayName {
                            Text("Following \(host)")
                        } else {
                            Label(
                                isPractice ? String(localized: "Practice") : (isHost ? String(localized: "Host") : String(localized: "Guest")),
                                systemImage: isPractice ? "metronome" : (isHost ? "star.fill" : "person.fill")
                            )
                        }
                        Text("·")
                        if viewModel.payload.autoDetectKey {
                            if viewModel.payload.isKeyAutoDetected {
                                Text(String(format: String(localized: "Key of %@ · AI"), viewModel.payload.key.displayName))
                            } else {
                                Text(String(format: String(localized: "Key of %@ · AI listening"), viewModel.payload.key.displayName))
                            }
                        } else {
                            Text(String(format: String(localized: "Key of %@"), viewModel.payload.key.displayName))
                        }
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(1)
                }

                Spacer(minLength: 8)

                leaveSessionButton(style: .header)
            }

            if isGuest {
                guestLiveSessionStatusBar
            }

            if isGuest && viewModel.payload.hostLiveGrooveActive {
                GuestHostLiveGrooveBanner(payload: viewModel.payload)
            }

            if isGuest && isLivePerformance {
                guestLiveViewStyleControls(includeRingSource: true)
            } else if !(isLivePerformance && viewModel.payload.isLiveChordsOnly) {
                RingSourcePicker(showsLiveChords: ringSourceBinding)
            }

            if showsLiveRingSongControls {
                HStack(spacing: 10) {
                    if viewModel.liveRingSongNumber > 1 || !viewModel.payload.liveRingSegments.isEmpty {
                        Text(String(format: String(localized: "Song %lld"), viewModel.liveRingSongNumber))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                    newLiveSongRingButton
                    Spacer(minLength: 0)
                }
            }

            if isHost, !isPractice, !isLivePerformance, viewModel.payload.isRemoteBackupEnabled, let code = viewModel.payload.remoteJoinCode {
                hostRemoteJoinCodeSection(code: code)
            }
        }
        .padding(.horizontal, sessionHorizontalPadding)
        .padding(.vertical, 8)
        .background {
            AppTheme.background
                .opacity(0.92)
                .ignoresSafeArea(edges: .top)
        }
    }

    private var guestDisplayTempoBPM: Double {
        viewModel.displayedSessionTempoBPM
    }

    private var guestDisplayMetronomePlaying: Bool {
        viewModel.displayedMetronomePlaying
    }

    private var guestLiveSessionStatusBar: some View {
        LiveSessionStatusBar(
            isAutoAdvancePaused: viewModel.payload.isAutoAdvancePaused,
            isVampActive: viewModel.payload.isVampActive,
            tempoBPM: guestDisplayTempoBPM,
            isMetronomePlaying: guestDisplayMetronomePlaying,
            syncQuality: viewModel.effectiveSyncQuality,
            showSyncQuality: true,
            hostLiveGrooveActive: viewModel.payload.hostLiveGrooveActive,
            hostLiveGrooveStyle: viewModel.payload.hostLiveGrooveStyle,
            hostLiveGroovePhase: viewModel.payload.hostLiveGroovePhase
        )
    }

    private func compactSessionHeader(maxHeight: CGFloat) -> some View {
        VStack(spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.payload.sessionName)
                        .font(.headline.weight(.bold))
                        .lineLimit(1)
                    if isGuest {
                        if let host = viewModel.sessionManager.hostPeerDisplayName {
                            Text("Following \(host)")
                                .font(.caption)
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                        guestLiveSessionStatusBar
                    } else if isLivePerformance {
                        LiveSessionStatusBar(
                            isAutoAdvancePaused: viewModel.payload.isAutoAdvancePaused,
                            isVampActive: viewModel.payload.isVampActive,
                            tempoBPM: viewModel.payload.tempoBPM,
                            isMetronomePlaying: viewModel.payload.isMetronomePlaying
                        )
                    }
                }
                Spacer()
                leaveSessionButton(style: .header)
            }

            if isGuest && viewModel.payload.hostLiveGrooveActive {
                GuestHostLiveGrooveBanner(payload: viewModel.payload)
            }

            if isGuest && isLivePerformance {
                guestLiveViewStyleControls(includeRingSource: false)
            }

            if isHost, !isPractice, !isLivePerformance, viewModel.payload.isRemoteBackupEnabled, let code = viewModel.payload.remoteJoinCode {
                hostRemoteJoinCodeSection(code: code)
            }
        }
        .padding(.horizontal, sessionHorizontalPadding)
        .padding(.vertical, 8)
        .background {
            AppTheme.background.opacity(0.92).ignoresSafeArea(edges: .top)
        }
    }

    @ViewBuilder
    private func bottomPanel(maxHeight: CGFloat, viewportWidth: CGFloat) -> some View {
        if usesLiveHostControlDock {
            liveHostDockBottom(maxHeight: maxHeight, viewportWidth: viewportWidth)
        } else {
            legacyBottomPanel(maxHeight: maxHeight)
        }
    }

    @ViewBuilder
    private func liveHostDockBottom(maxHeight: CGFloat, viewportWidth: CGFloat) -> some View {
        let layout = resolvedLiveDockLayout(viewportWidth: viewportWidth)
        if layout == .sideRail {
            LiveHostTransportStrip(
                viewModel: viewModel,
                selectedTab: liveDockSelectedTab,
                sideRailVisible: $liveSideRailVisible,
                bandCuePadVisible: $bandCuePadVisible,
                needsLiveChordTransport: needsLiveChordTransport,
                usesSideRail: true,
                horizontalPadding: sessionHorizontalPadding,
                onPiano: {
                    showPianoOverlay = true
                    viewModel.openPiano()
                },
                onToggleDock: {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                        liveSideRailVisible.toggle()
                    }
                }
            )
        } else {
            liveHostControlRail(style: .bottomDock(maxHeight: maxHeight))
        }
    }

    private func liveHostControlRail(style: LiveHostControlRailStyle) -> some View {
        LiveHostControlRail(
            viewModel: viewModel,
            store: store,
            style: style,
            isHost: isHost,
            horizontalPadding: sessionHorizontalPadding,
            selectedTab: liveDockSelectedTab,
            layoutMode: liveDockLayoutMode,
            heightPresetRaw: $liveDockHeightPresetRaw,
            sideRailVisible: $liveSideRailVisible,
            bandCuePadVisible: $bandCuePadVisible,
            metronomePanelVisible: $metronomePanelVisible,
            metronomeVolume: $metronomeVolume,
            showPianoOverlay: $showPianoOverlay,
            showFretboardOverlay: $showFretboardOverlay,
            showProgressionEditor: $showProgressionEditor,
            showMetadataEditor: $showMetadataEditor,
            showMIDISettings: $showMIDISettings,
            showPreServiceChecklist: $showPreServiceChecklist,
            showExtendedFeaturesHub: $showExtendedFeaturesHub,
            showAdvancedFeaturesHub: $showAdvancedFeaturesHub,
            showGuestRoles: $showGuestRoles,
            showRehearsalList: $showRehearsalList,
            showJoinQR: $showJoinQR,
            showBackingTrackImporter: $showBackingTrackImporter,
            showSaveDialog: $showSaveDialog,
            saveName: $saveName,
            isKeyMenuPresented: $isKeyMenuPresented,
            showPDFChart: $showPDFChart,
            needsLiveChordTransport: needsLiveChordTransport,
            keyControlTitle: keyControlTitle,
            isSaved: isSaved,
            isLastSetlistSong: isLastSetlistSong,
            onCopyJoinCode: copyJoinCode
        )
    }

    @ViewBuilder
    private func legacyBottomPanel(maxHeight: CGFloat) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                if usesWideLiveCompactDeck {
                    wideLiveCompactHostPanelContent
                        .frame(minHeight: maxHeight, alignment: .center)
                } else {
                    if isLiveCompactHost {
                        liveHostWorkflowDeck
                    } else {
                        if (viewModel.canDriveSession || viewModel.isCoHost), !viewModel.payload.isLiveChordsOnly {
                            ChordAdvanceBar(viewModel: viewModel)
                                .padding(.horizontal, sessionHorizontalPadding)
                                .padding(.top, 8)
                        }

                        if isHost || isPractice, !viewModel.payload.isLiveChordsOnly {
                            PerformanceModePicker(viewModel: viewModel)
                                .padding(.horizontal, sessionHorizontalPadding)
                                .padding(.vertical, 8)
                            SessionDisplayModePicker(viewModel: viewModel)
                                .padding(.horizontal, sessionHorizontalPadding)
                                .padding(.bottom, 8)
                        }

                        if metronomePanelVisible {
                            metronomeBar
                        } else {
                            collapsedMetronomeBar(compact: false)
                        }

                        if isHost {
                            hostControls
                        } else if isGuest {
                            #if os(macOS)
                            macGuestControls
                            #else
                            guestBanner
                            #endif
                        }
                    }
                }
            }
            .padding(.bottom, 8)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(height: usesPhonePortraitLiveSplit ? maxHeight : nil)
        .frame(maxHeight: usesPhonePortraitLiveSplit ? nil : maxHeight)
        .frame(maxWidth: sessionPanelMaxWidth)
        .frame(maxWidth: .infinity)
        .safeAreaPadding(.bottom, 4)
        .background {
            AppTheme.background
                .opacity(0.92)
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private var wideLiveCompactHostPanelContent: some View {
        VStack(spacing: 22) {
            if needsLiveChordTransport {
                LiveChordTransportCompact(viewModel: viewModel)
            }

            HStack(alignment: .top, spacing: 18) {
                Group {
                    if metronomePanelVisible {
                        metronomeBar
                    } else {
                        collapsedMetronomeBar(compact: false)
                    }
                }
                .padding(.horizontal, -sessionHorizontalPadding)
                .padding(.bottom, -12)
                .frame(maxWidth: .infinity)

                if viewModel.canDriveSession {
                    BackingTrackPanel(viewModel: viewModel, onImport: {
                        showBackingTrackImporter = true
                    }, style: .compact)
                    .frame(maxWidth: 320)
                }
            }

            #if os(macOS)
            if viewModel.canDriveSession {
                SoloAccompanimentMacPanel(viewModel: viewModel, progressionStore: store)
            }
            #endif

            wideLiveBandCueSection

            liveCompactIconToolbar
        }
        .padding(.horizontal, sessionHorizontalPadding)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var liveBandCueSection: some View {
        if bandCuePadVisible {
            LiveCuePad(viewModel: viewModel, style: .liveCompact)
                .padding(.horizontal, sessionHorizontalPadding)
        }
    }

    @ViewBuilder
    private var wideLiveBandCueSection: some View {
        if bandCuePadVisible {
            LiveCuePad(viewModel: viewModel, usesWideLayout: true)
        }
    }

    private var liveHostWorkflowDeck: some View {
        VStack(spacing: 10) {
            if needsLiveChordTransport {
                LiveChordTransportCompact(viewModel: viewModel)
                    .padding(.horizontal, sessionHorizontalPadding)
            }

            liveBandCueSection

            liveCompactIconToolbar
                .padding(.horizontal, sessionHorizontalPadding)

            if metronomePanelVisible {
                metronomeBar
            } else {
                collapsedMetronomeBar(compact: true)
            }

            if viewModel.canDriveSession {
                BackingTrackPanel(viewModel: viewModel, onImport: {
                    showBackingTrackImporter = true
                }, style: .compact)
                .padding(.horizontal, sessionHorizontalPadding)
            }

            #if os(macOS)
            if viewModel.canDriveSession {
                SoloAccompanimentMacPanel(viewModel: viewModel, progressionStore: store)
                    .padding(.horizontal, sessionHorizontalPadding)
            }
            #endif
        }
        .padding(.bottom, 4)
    }

    private var liveCompactIconToolbar: some View {
        liveCompactIconToolbarButtons
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .glassCard()
            .foregroundStyle(AppTheme.textPrimary)
    }

    private var liveCompactToolbarSpacing: CGFloat {
        #if os(iOS)
        PlatformDevice.isPhone ? 6 : 8
        #else
        0
        #endif
    }

    private var liveCompactIconToolbarButtons: some View {
        HStack(spacing: liveCompactToolbarSpacing) {
            liveCompactToolbarButton(
                icon: bandCuePadVisible ? "megaphone.fill" : "megaphone",
                label: liveCompactToolbarTitle(full: String(localized: "Band Cues"), short: String(localized: "Cues")),
                accessibilityLabel: String(localized: "Band Cues")
            ) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                    bandCuePadVisible.toggle()
                }
            }
            .background {
                if bandCuePadVisible {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(AppTheme.accent.opacity(0.14))
                }
            }

            liveCompactToolbarButton(
                icon: "slider.horizontal.3",
                label: liveCompactToolbarTitle(full: String(localized: "More Tools"), short: String(localized: "Tools")),
                accessibilityLabel: String(localized: "More Tools")
            ) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                    liveToolsExpanded = true
                }
            }

            liveCompactToolbarButton(
                icon: "pianokeys",
                label: String(localized: "Piano"),
                accessibilityLabel: String(localized: "Piano")
            ) {
                showPianoOverlay = true
                viewModel.openPiano()
            }

            SessionDisplayModeMenu(viewModel: viewModel) {
                liveCompactToolbarLabel(
                    icon: "rectangle.on.rectangle",
                    label: String(localized: "View"),
                    accessibilityLabel: String(localized: "View")
                )
            }

            liveCompactToolbarButton(
                icon: "checklist",
                label: liveCompactToolbarTitle(full: String(localized: "Pre-Service"), short: String(localized: "Pre-Svc")),
                accessibilityLabel: String(localized: "Pre-Service")
            ) {
                showPreServiceChecklist = true
            }
        }
    }

    private func liveCompactToolbarTitle(full: String, short: String) -> String {
        #if os(iOS)
        if PlatformDevice.isPhone { return short }
        #endif
        return full
    }

    private func liveCompactToolbarButton(
        icon: String,
        label: String,
        accessibilityLabel: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            liveCompactToolbarLabel(icon: icon, label: label, accessibilityLabel: accessibilityLabel)
        }
        .buttonStyle(.plain)
    }

    private func liveCompactToolbarLabel(
        icon: String,
        label: String,
        accessibilityLabel: String? = nil
    ) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
            Text(label)
                .font(.caption2.weight(.medium))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.82)
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 2)
        .padding(.vertical, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel ?? label)
        .accessibilityAddTraits(.isButton)
    }

    private func presentPreServiceChecklistIfNeeded() {
        guard shouldOfferPreServiceChecklist else { return }
        showPreServiceChecklist = true
    }

    private func markPreServiceChecklistDismissedForSession() {
        GuestDisplaySettings.preServiceChecklistDismissedToken = viewModel.payload.sessionToken.uuidString
    }

    @ViewBuilder
    private func sessionHeader(maxHeight: CGFloat) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            sessionHeaderContent
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxHeight: maxHeight)
        .background {
            AppTheme.background
                .opacity(0.92)
                .ignoresSafeArea(edges: .top)
        }
    }

    private var sessionHeaderContent: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.payload.sessionName)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Label(
                        isPractice ? String(localized: "Practice") : (viewModel.role == .host ? String(localized: "Host") : String(localized: "Guest")),
                        systemImage: isPractice ? "metronome" : (viewModel.role == .host ? "star.fill" : "person.fill")
                    )
                    if let setlistName = viewModel.payload.setlistName,
                       let index = viewModel.payload.setlistSongIndex,
                       let count = viewModel.payload.setlistSongCount {
                        Text("·")
                        Label("\(setlistName) \(index + 1)/\(count)", systemImage: "list.bullet.rectangle")
                    }
                    if viewModel.payload.isLiveChordsOnly {
                        Text("·")
                        Label("Live Chords", systemImage: "dot.radiowaves.left.and.right")
                    } else if viewModel.isLiveProgressionSession {
                        Text("·")
                        Label("Live Progression", systemImage: "record.circle")
                    }
                    if isGuest {
                        Text("·")
                        Label(viewModel.effectiveSyncQuality.label, systemImage: viewModel.isRemoteLinkActive ? "icloud.fill" : "waveform.path.ecg")
                    }
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(AppTheme.textSecondary)
                .lineLimit(2)

                if viewModel.role == .host, !isPractice, !viewModel.sessionManager.pendingJoinRequests.isEmpty {
                    pendingJoinRequestsSection
                }

                if viewModel.activeSection != nil || !viewModel.payload.lyrics.isEmpty {
                    sectionLyricsSnippet
                }

                if viewModel.role == .host, !isPractice {
                    connectedMusiciansSection
                    if viewModel.payload.isRemoteBackupEnabled, let code = viewModel.payload.remoteJoinCode {
                        hostRemoteJoinCodeSection(code: code)
                    }
                } else if isGuest, viewModel.isRemoteLinkActive {
                    Label("Connected via Internet", systemImage: "icloud.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppTheme.accentSecondary)
                        .padding(.top, 4)
                } else if isGuest, let hostName = viewModel.sessionManager.connectedPeers.first?.displayName {
                    Label("Connected to \(hostName)", systemImage: "star.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppTheme.textSecondary)
                        .padding(.top, 4)
                }
            }

            leaveSessionButton(style: .header)
                .padding(.top, 2)
        }
        .padding(.horizontal, sessionHorizontalPadding)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }

    private var isSaved: Bool { viewModel.loadedProgressionID != nil }

    private func performSave(overwrite: Bool) {
        let trimmed = saveName.trimmingCharacters(in: .whitespaces)
        let finalName = trimmed.isEmpty ? L10n.untitledProgression : trimmed
        let snapshot = viewModel.snapshotForSaving(named: finalName, overwrite: overwrite)
        store.save(snapshot)

        if isHost {
            // Hosts keep the saved progression linked so further edits can update it.
            viewModel.markSaved(as: snapshot)
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                showSavedToast = true
            }
            Task {
                try? await Task.sleep(for: .seconds(1.8))
                withAnimation { showSavedToast = false }
            }
        } else {
            // Guests keep a personal copy and can spin up their own session from it.
            Task {
                try? await Task.sleep(for: .seconds(0.35))
                pendingHostProgression = snapshot
            }
        }
    }

    private var savedToast: some View {
        VStack {
            Spacer()
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(AppTheme.accent)
                Text("Progression saved")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
            }
            .padding(.horizontal, sessionHorizontalPadding)
            .padding(.vertical, 14)
            .background(AppTheme.surfaceElevated)
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
            .padding(.bottom, 110)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    @ViewBuilder
    private var pendingJoinRequestsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Join requests")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)
                .textCase(.uppercase)
            ForEach(viewModel.sessionManager.pendingJoinRequests) { request in
                HStack {
                    Text(request.peer.displayName)
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Button("Accept") {
                        viewModel.sessionManager.acceptJoinRequest(request)
                    }
                    .font(.caption.weight(.bold))
                    Button("Decline") {
                        viewModel.sessionManager.rejectJoinRequest(request)
                    }
                    .font(.caption)
                    .foregroundStyle(.red.opacity(0.9))
                }
                .padding(10)
                .background(AppTheme.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private var sectionLyricsSnippet: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let section = viewModel.activeSection {
                Text(section.name.uppercased())
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(AppTheme.accentSecondary)
            }
            if let line = viewModel.activeChord?.lyrics, !line.isEmpty {
                Text(line)
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(2)
            } else if !viewModel.payload.lyrics.isEmpty {
                Text(viewModel.payload.lyrics)
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(2)
            }
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private var connectedMusiciansSection: some View {
        if viewModel.sessionManager.connectedPeers.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Waiting for musicians to join…")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)

                    if isHost, let error = viewModel.sessionManager.lastError {
                        Text(error)
                            .font(.caption2)
                            .foregroundStyle(.red)
                    } else if isHost {
                        Text("Same Wi‑Fi works best. Share the Internet join code below for cellular backup.")
                            .font(.caption2)
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                }
                .padding(.top, 4)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Connected musicians (\(viewModel.sessionManager.connectedPeers.count))")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(AppTheme.textSecondary)
                        .textCase(.uppercase)
                        .tracking(0.6)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(viewModel.sessionManager.connectedPeers, id: \.displayName) { peer in
                                musicianChip(name: peer.displayName)
                            }
                        }
                    }
                }
                .padding(.top, 4)
            }
    }

    private func copyJoinCode(_ code: String) {
        RemoteJoinCode.copyToClipboard(code)
    }

    @ViewBuilder
    private func hostRemoteJoinCodeSection(code: String) -> some View {
        if showInternetJoinCode {
            HostRemoteJoinCodeBanner(
                code: code,
                cloudError: viewModel.cloudRelay.lastError,
                isCloudReady: viewModel.cloudRelay.isCloudKitConfigured,
                isRelayLive: viewModel.cloudRelay.isRelayLive,
                transportName: viewModel.cloudRelay.activeTransportName,
                onCopy: { copyJoinCode(code) },
                onHide: { showInternetJoinCode = false },
                onRetry: {
                    Task { await viewModel.cloudRelay.retryHostingNow() }
                }
            )
        } else {
            HostRemoteJoinCodeCollapsed {
                showInternetJoinCode = true
            }
        }
    }

    private func musicianChip(name: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "person.fill")
                .font(.caption2)
            Text(name)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(AppTheme.textPrimary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(AppTheme.surface)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.08), lineWidth: 1))
    }

    private var hostSharingPiano: Bool {
        viewModel.payload.isPianoActive
            || !viewModel.payload.pianoNotes.isEmpty
            || viewModel.payload.liveChordSymbol != nil
            || !viewModel.payload.freestyleChordSymbols.isEmpty
    }

    private func dismissPianoOverlay() {
        showPianoOverlay = false
        if isHost { viewModel.closePiano() }
    }

    private func dismissFretboardOverlay() {
        showFretboardOverlay = false
        if isHost { viewModel.closeFretboard() }
    }

    private enum LeaveButtonStyle {
        case header
        case prominent
    }

    @ViewBuilder
    private func leaveSessionButton(style: LeaveButtonStyle) -> some View {
        Button {
            showLeaveConfirmation = true
        } label: {
            switch style {
            case .header:
                if isGuest {
                    Label("Leave", systemImage: "rectangle.portrait.and.arrow.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textSecondary)
                } else {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(AppTheme.textSecondary)
                }
            case .prominent:
                Label("Leave Session", systemImage: "rectangle.portrait.and.arrow.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.red.opacity(0.9))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(AppTheme.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.red.opacity(0.25), lineWidth: 1)
                    )
            }
        }
        .accessibilityLabel("Leave Session")
    }

    private var liveProgressionBadge: some View {
        let chords = viewModel.sortedChords
        let activeIndex = chords.firstIndex { $0.id == viewModel.payload.activeChordID }

        return HStack(spacing: 8) {
            Text("LIVE")
                .font(.caption.weight(.bold))
                .foregroundStyle(AppTheme.background)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(AppTheme.accentSecondary)
                .clipShape(Capsule())

            if let index = activeIndex, index < chords.count {
                let active = chords[index]
                Text("\(index + 1) / \(chords.count)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.background)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(AppTheme.accent)
                    .clipShape(Capsule())

                active.chordText(for: viewModel.payload.notation, key: viewModel.payload.key, size: 15, weight: .semibold)
                    .foregroundStyle(AppTheme.textPrimary)
            } else {
                Text("\(chords.count) chords recorded")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
            }

            Spacer()

            if isHost {
                Text("Save when ready")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
    }

    private var inferredProgressionBadge: some View {
        let chords = viewModel.sortedChords
        let activeIndex = chords.firstIndex { $0.id == viewModel.payload.activeChordID }

        return HStack(spacing: 8) {
            Text(String(localized: "Progression detected"))
                .font(.caption.weight(.bold))
                .foregroundStyle(AppTheme.background)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(AppTheme.accent)
                .clipShape(Capsule())

            if let index = activeIndex, index < chords.count {
                Text("\(index + 1) / \(chords.count)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.background)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(AppTheme.accentSecondary)
                    .clipShape(Capsule())

                chords[index]
                    .chordText(for: viewModel.payload.notation, key: viewModel.payload.key, size: 15, weight: .semibold)
                    .foregroundStyle(AppTheme.textPrimary)
            } else {
                Text(chords.map(\.symbolName).joined(separator: " · "))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1)
            }

            Spacer()

            if isHost {
                Text(String(localized: "New Song to reset"))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "Progression detected"))
    }

    private var liveChordBadge: some View {
        HStack(spacing: 8) {
            Text("LIVE")
                .font(.caption.weight(.bold))
                .foregroundStyle(AppTheme.background)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(AppTheme.accentSecondary)
                .clipShape(Capsule())

            if let chord = viewModel.livePianoChordEntry() ?? viewModel.liveFreestyleChord {
                chord.chordText(
                    for: viewModel.displayNotation(isGuest: isGuest),
                    key: viewModel.payload.key,
                    size: 15,
                    weight: .semibold
                )
                .foregroundStyle(AppTheme.textPrimary)
            } else {
                Text("Host playing piano")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)
            }

            if viewModel.freestyleChordEntries.count > 1 {
                Text("· \(viewModel.freestyleChordEntries.count) top chords")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppTheme.textSecondary)
            }

            if viewModel.liveRingSongNumber > 1 {
                Text("· \(String(format: String(localized: "Song %lld"), viewModel.liveRingSongNumber))")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppTheme.textSecondary)
            }

            Spacer()

            if showsLiveRingSongControls {
                newLiveSongRingButton
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var progressionBadge: some View {
        if let summary = viewModel.activeSectionRingSummary {
            let chords = viewModel.chordsInActiveSection()
            let activeIndex = chords.firstIndex { $0.id == viewModel.payload.activeChordID }

            HStack(spacing: 8) {
                Label(summary.section.name, systemImage: summary.section.kind.icon)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.accentSecondary)

                Text("\(summary.index)/\(summary.count)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.background)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(AppTheme.accent)
                    .clipShape(Capsule())

                if let index = activeIndex, index < chords.count {
                    let active = chords[index]
                    active.chordText(for: viewModel.payload.notation, key: viewModel.payload.key, size: 15, weight: .semibold)
                        .foregroundStyle(AppTheme.textPrimary)

                    if index + 1 < chords.count {
                        let next = chords[index + 1]
                        Image(systemName: "arrow.right")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(AppTheme.textSecondary)
                        next.chordText(for: viewModel.payload.notation, key: viewModel.payload.key, size: 12, weight: .medium)
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
        } else {
            fullProgressionBadge
        }
    }

    private var fullProgressionBadge: some View {
        let chords = viewModel.sortedChords
        let activeIndex = chords.firstIndex { $0.id == viewModel.payload.activeChordID }

        return HStack(spacing: 8) {
            if let index = activeIndex, index < chords.count {
                let active = chords[index]
                Text("\(index + 1) / \(chords.count)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.background)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(AppTheme.accent)
                    .clipShape(Capsule())

                active.chordText(for: viewModel.payload.notation, key: viewModel.payload.key, size: 15, weight: .semibold)
                    .foregroundStyle(AppTheme.textPrimary)

                if let beats = active.durationBeats, beats > 0 {
                    Text("\(Int(beats))♩")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(AppTheme.accentSecondary)
                }

                if index + 1 < chords.count {
                    let next = chords[index + 1]
                    Image(systemName: "arrow.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(AppTheme.textSecondary)
                    HStack(spacing: 4) {
                        Text("then")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(AppTheme.textSecondary)
                        next.chordText(for: viewModel.payload.notation, key: viewModel.payload.key, size: 12, weight: .medium)
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                    .lineLimit(1)
                }
            } else {
                Text("\(chords.count) chords in progression")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppTheme.textSecondary)
            }

            Spacer()
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
    }

    private var isLastSetlistSong: Bool {
        guard let index = viewModel.payload.setlistSongIndex,
              let count = viewModel.payload.setlistSongCount else { return true }
        return index + 1 >= count
    }

    private var hostControlColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)
    }

    private var hostControls: some View {
        VStack(spacing: 14) {
            HStack {
                SessionFeaturesMenu(
                    viewModel: viewModel,
                    store: store,
                    showGuestRoles: $showGuestRoles,
                    showRehearsalList: $showRehearsalList,
                    showJoinQR: $showJoinQR,
                    showExtendedFeaturesHub: $showExtendedFeaturesHub,
                    showAdvancedFeaturesHub: $showAdvancedFeaturesHub
                )
                VocalKeyPicker(viewModel: viewModel)
                Spacer()
            }
            .padding(.horizontal, sessionHorizontalPadding)

            if isLivePerformance {
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                        liveToolsExpanded = false
                    }
                } label: {
                    Label(String(localized: "Back to Live View"), systemImage: "arrow.down.right.and.arrow.up.left")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(AppTheme.accent.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .foregroundStyle(AppTheme.accent)
                .padding(.horizontal, sessionHorizontalPadding)

                if viewModel.payload.isRemoteBackupEnabled, let code = viewModel.payload.remoteJoinCode {
                    HostRemoteJoinCodeCompactChip(
                        code: code,
                        isRelayLive: viewModel.cloudRelay.isRelayLive,
                        onCopy: { copyJoinCode(code) },
                        onShowQR: { showJoinQR = true }
                    )
                    .padding(.horizontal, sessionHorizontalPadding)
                }
            }

            if viewModel.payload.setlistName != nil {
                HStack(spacing: 10) {
                    Button {
                        viewModel.previousSetlistSong(store: store)
                    } label: {
                        Label("Previous", systemImage: "backward.fill")
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(AppTheme.surfaceElevated)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .disabled((viewModel.payload.setlistSongIndex ?? 0) == 0)

                    Button {
                        viewModel.nextSetlistSong(store: store)
                    } label: {
                        Label("Next Song", systemImage: "forward.fill")
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(AppTheme.surfaceElevated)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .disabled(isLastSetlistSong)
                }
                .padding(.horizontal, sessionHorizontalPadding)

                Toggle(isOn: Binding(
                    get: { viewModel.autoAdvanceSetlistSongs },
                    set: { viewModel.setAutoAdvanceSetlist($0) }
                )) {
                    Text("Auto-advance setlist at last chord")
                        .font(.caption.weight(.medium))
                }
                .tint(AppTheme.accent)
                .padding(.horizontal, sessionHorizontalPadding)
            }

            if !isLivePerformance {
                LiveCuePad(viewModel: viewModel)
                    .padding(.horizontal, sessionHorizontalPadding)
            }

            if viewModel.canDriveSession, !isLivePerformance {
                BackingTrackPanel(viewModel: viewModel, onImport: {
                    showBackingTrackImporter = true
                })
                .padding(.horizontal, sessionHorizontalPadding)
            }

            CoHostPicker(viewModel: viewModel)
                .padding(.horizontal, sessionHorizontalPadding)

            HStack(spacing: 10) {
                Toggle(isOn: Binding(
                    get: { viewModel.payload.isSectionLoopEnabled },
                    set: { _ in viewModel.toggleSectionLoop() }
                )) {
                    Label(String(localized: "Loop section"), systemImage: "repeat.circle")
                        .font(.caption.weight(.medium))
                }
                .tint(AppTheme.accent)

                Toggle(isOn: Binding(
                    get: { viewModel.payload.showBeatSyncHints },
                    set: { viewModel.setShowBeatSyncHints($0) }
                )) {
                    Label(String(localized: "Beat hints"), systemImage: "waveform.path")
                        .font(.caption.weight(.medium))
                }
                .tint(AppTheme.accent)
            }
            .padding(.horizontal, sessionHorizontalPadding)

            LazyVGrid(columns: hostControlColumns, spacing: 10) {
                keyControlMenu

                Button {
                    showPianoOverlay = true
                    viewModel.openPiano()
                } label: {
                    controlChip(icon: "pianokeys", title: "Piano", fillWidth: true)
                }

                Button {
                    showFretboardOverlay = true
                    viewModel.openFretboard()
                } label: {
                    controlChip(icon: "guitars", title: "Fretboard", fillWidth: true)
                }

                Button {
                    showProgressionEditor = true
                } label: {
                    controlChip(icon: "list.bullet", title: "Edit", fillWidth: true)
                }

                Button {
                    showMetadataEditor = true
                } label: {
                    controlChip(icon: "text.quote", title: "Lyrics", fillWidth: true)
                }

                Button {
                    showMIDISettings = true
                } label: {
                    controlChip(icon: "cable.connector", title: "MIDI", fillWidth: true)
                }

                Button {
                    viewModel.setRemoteBackupEnabled(!viewModel.payload.isRemoteBackupEnabled)
                } label: {
                    controlChip(
                        icon: "icloud.fill",
                        title: viewModel.payload.isRemoteBackupEnabled
                            ? String(localized: "Internet On")
                            : String(localized: "Internet Off"),
                        fillWidth: true
                    )
                }

                #if os(iOS)
                Button {
                    showLockScreenSettings = true
                } label: {
                    controlChip(icon: "lock.display", title: "Lock Screen", fillWidth: true)
                }
                #endif

                if let progressionID = viewModel.loadedProgressionID,
                   let progression = store.progression(with: progressionID),
                   store.pdfURL(for: progression) != nil {
                    Button {
                        showPDFChart = true
                    } label: {
                        controlChip(icon: "doc.richtext", title: "PDF", fillWidth: true)
                    }
                }

                Button {
                    saveName = viewModel.payload.sessionName
                    showSaveDialog = true
                } label: {
                    controlChip(
                        icon: isSaved ? "bookmark.fill" : "square.and.arrow.down",
                        title: "Save",
                        fillWidth: true
                    )
                }
                .disabled(viewModel.sortedChords.isEmpty)
                .opacity(viewModel.sortedChords.isEmpty ? 0.4 : 1)
            }
            .padding(.horizontal, sessionHorizontalPadding)
            .padding(.top, 12)
        }
    }

    private var macGuestControls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "waveform.path")
                    .font(.title3)
                    .foregroundStyle(AppTheme.accentSecondary)
                    .symbolEffect(.pulse)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Live Sync")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                    Text("Following the host's progression in real time")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                }

                Spacer()
            }
            .padding(12)
            .glassCard()

            HStack(spacing: 10) {
                #if os(iOS)
                Button {
                    showLockScreenSettings = true
                } label: {
                    Label("Lock Screen", systemImage: "lock.display")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.bordered)
                #endif

                Button {
                    showGuestSettings = true
                } label: {
                    Label("My Chart", systemImage: "person.text.rectangle")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.bordered)

                Button {
                    saveName = viewModel.payload.sessionName
                    showSaveDialog = true
                } label: {
                    Label("Save Copy", systemImage: "square.and.arrow.down")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.sortedChords.isEmpty)
                .opacity(viewModel.sortedChords.isEmpty ? 0.4 : 1)

                leaveSessionButton(style: .prominent)
            }
        }
        .padding(.horizontal, sessionHorizontalPadding)
        .padding(.top, 4)
    }

    private var guestBanner: some View {
        VStack(spacing: 10) {
            if viewModel.isCoHost {
                Label("You are co-host — you can advance chords", systemImage: "person.badge.key.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.accentSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, sessionHorizontalPadding)
            }

            Button {
                showGuestSettings = true
            } label: {
                Label("My Chart (transpose / capo)", systemImage: "person.text.rectangle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(AppTheme.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .padding(.horizontal, sessionHorizontalPadding)

            #if os(iOS)
            Button {
                showLockScreenSettings = true
            } label: {
                Label("Lock Screen", systemImage: "lock.display")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(AppTheme.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .padding(.horizontal, sessionHorizontalPadding)
            #endif

            HStack(spacing: 12) {
                Image(systemName: "waveform.path")
                    .font(.title3)
                    .foregroundStyle(AppTheme.accentSecondary)
                    .symbolEffect(.pulse)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Live Sync")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                    Text("Following the host's progression in real time")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                }

                Spacer()
            }
            .padding()
            .glassCard()

            Toggle(isOn: $beatFlashEnabled) {
                Label("Beat Flash", systemImage: "bolt.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
            }
            .tint(AppTheme.accent)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(AppTheme.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            Toggle(isOn: $guestMetronomeAudioEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Label("Metronome Click", systemImage: "speaker.wave.2.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                    Text("Hear the click on your phone — including when following the Mac host groove")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
            .tint(AppTheme.accent)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(AppTheme.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            Toggle(isOn: $showLiveChordsOnRing) {
                VStack(alignment: .leading, spacing: 2) {
                    Label("Live Chords on Ring", systemImage: "circle.grid.cross")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                    Text("Show chords the host plays on piano")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
            .tint(AppTheme.accent)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(AppTheme.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            if hostSharingPiano {
                Button {
                    showPianoOverlay = true
                } label: {
                    Label("View Piano", systemImage: "pianokeys")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(AppTheme.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }

            if viewModel.payload.isFretboardActive {
                Button {
                    showFretboardOverlay = true
                } label: {
                    Label("View Fretboard", systemImage: "guitars")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(AppTheme.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }

            Button {
                saveName = viewModel.payload.sessionName
                showSaveDialog = true
            } label: {
                Label("Save a Copy", systemImage: "square.and.arrow.down")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(AppTheme.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .disabled(viewModel.sortedChords.isEmpty)
            .opacity(viewModel.sortedChords.isEmpty ? 0.4 : 1)

            leaveSessionButton(style: .prominent)
                .padding(.top, 4)
        }
        .padding(.horizontal, sessionHorizontalPadding)
        .padding(.top, 4)
    }

    private func collapsedMetronomeBar(compact: Bool) -> some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                metronomePanelVisible = true
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "metronome")
                    .foregroundStyle(AppTheme.accentSecondary)

                Text("Metronome")
                    .font(compact ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)

                if guestDisplayMetronomePlaying {
                    Text("\(TempoMarking.caption(for: guestDisplayTempoBPM)) · \(viewModel.payload.beatsPerBar)/\(viewModel.payload.beatUnit)")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }

                Spacer()

                Image(systemName: "chevron.up")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .padding(.horizontal, compact ? 14 : 16)
            .padding(.vertical, compact ? 10 : 12)
            .glassCard()
        }
        .padding(.horizontal, sessionHorizontalPadding)
        .padding(.bottom, compact ? 0 : 12)
    }

    private var metronomeBar: some View {
        SessionMetronomePanel(
            viewModel: viewModel,
            isHost: isHost,
            metronomeVolume: $metronomeVolume,
            horizontalPadding: sessionHorizontalPadding,
            showsCollapseButton: true,
            onCollapse: {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    metronomePanelVisible = false
                }
            }
        )
        .padding(.bottom, 12)
    }

    private var keyControlMenu: some View {
        Button {
            isKeyMenuPresented = true
        } label: {
            controlChip(
                icon: viewModel.payload.autoDetectKey ? "wand.and.stars" : "arrow.up.arrow.down",
                title: keyControlTitle,
                fillWidth: true
            )
        }
        .buttonStyle(.plain)
        .platformSheet(isPresented: $isKeyMenuPresented) {
            SessionMusicalKeyPicker(viewModel: viewModel, isPresented: $isKeyMenuPresented)
        }
    }

    private func controlChip(icon: String, title: String, fillWidth: Bool = false) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(title)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(AppTheme.textPrimary)
        .frame(maxWidth: fillWidth ? .infinity : nil)
        .padding(.horizontal, fillWidth ? 10 : 14)
        .padding(.vertical, 10)
        .background(AppTheme.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
