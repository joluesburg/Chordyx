//
//  SessionView.swift
//  Chordyx
//

import SwiftUI
import MultipeerConnectivity
import UniformTypeIdentifiers

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
    @State private var tapTimes: [Date] = []
    @State private var beatFlashEnabled = true
    @State private var flashOpacity: Double = 0
    @State private var flashColor: Color = AppTheme.accent
    @State private var showPianoOverlay = false
    @State private var showFretboardOverlay = false
    @AppStorage("metronomeVolume") private var metronomeVolume: Double = 0.8
    @AppStorage("metronomePanelVisible") private var metronomePanelVisible = true
    @AppStorage("guestShowLiveChordsOnRing") private var showLiveChordsOnRing = false
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
    @AppStorage(GuestDisplaySettings.transposeKey) private var guestTranspose = 0
    @AppStorage(GuestDisplaySettings.capoKey) private var guestCapo = 0

    private var isHost: Bool { viewModel.role == .host || viewModel.isPracticeMode }
    private var isGuest: Bool { viewModel.role == .guest }
    private var isPractice: Bool { viewModel.isPracticeMode }

    private var isLivePerformance: Bool {
        viewModel.payload.performanceMode == .live && !isPractice
    }

    private var isLiveCompactHost: Bool {
        isHost && isLivePerformance && !liveToolsExpanded
    }

    private var isCountInActive: Bool {
        viewModel.payload.isCountingIn || viewModel.metronome.isCountingIn
    }

    private var shouldOfferPreServiceChecklist: Bool {
        isHost && !isPractice && isLivePerformance
            && GuestDisplaySettings.preServiceChecklistDismissedToken != viewModel.payload.sessionToken.uuidString
    }

    private var effectiveDisplayMode: SessionDisplayMode {
        viewModel.effectiveDisplayMode(isGuest: isGuest)
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

    /// Keep session controls iPhone-sized on iPad instead of stretching edge to edge.
    private var sessionPanelMaxWidth: CGFloat {
        horizontalSizeClass == .regular ? 400 : .infinity
    }

    private var sessionHorizontalPadding: CGFloat {
        horizontalSizeClass == .regular ? 24 : 20
    }

    private func maxBottomPanelHeight(for viewportHeight: CGFloat) -> CGFloat {
        let isRingHero = effectiveDisplayMode == .ring
        #if os(macOS)
        if isGuest && isRingHero {
            return min(240, viewportHeight * 0.30)
        }
        #endif
        let fraction: CGFloat
        if horizontalSizeClass == .regular {
            fraction = isRingHero ? 0.28 : 0.36
        } else if isGuest {
            if isRingHero {
                fraction = verticalSizeClass == .compact ? 0.36 : 0.32
            } else {
                fraction = verticalSizeClass == .compact ? 0.50 : 0.46
            }
        } else if isHost {
            if isLivePerformance && !liveToolsExpanded {
                fraction = verticalSizeClass == .compact ? 0.26 : 0.24
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
        if effectiveDisplayMode == .ring {
            return horizontalSizeClass == .regular ? 92 : 80
        }
        return horizontalSizeClass == .regular ? 220 : min(200, viewportHeight * 0.24)
    }

    private func effectiveStageHeight(
        viewportHeight: CGFloat,
        bottomMaxHeight: CGFloat,
        headerMaxHeight: CGFloat
    ) -> CGFloat {
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
        let centerDiameter = min(centerCap, clearance * 2)
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
        isHost ? viewModel.payload.ringShowsLiveChords : showLiveChordsOnRing
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
        if ringShowsLiveChords {
            let live = viewModel.freestyleChordEntries
            return live.isEmpty ? resolvedRingSectionChords : live
        }
        return resolvedRingSectionChords
    }

    private var resolvedRingSectionChords: [ChordEntry] {
        let sectionChords = viewModel.ringSectionChords
        if !sectionChords.isEmpty { return sectionChords }
        return viewModel.sortedChords
    }

    private var centerChord: ChordEntry? {
        if centerShowsLivePiano {
            return viewModel.livePianoChordEntry() ?? viewModel.activeChord
        }
        if ringShowsLiveChords {
            return viewModel.liveFreestyleChord ?? viewModel.activeChord
        }
        return viewModel.activeChord
    }

    private var ringNotation: ChordNotation {
        viewModel.displayNotation(isGuest: isGuest)
    }

    var body: some View {
        sessionWithAlerts
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppTheme.backgroundGradient.ignoresSafeArea())
    }

    private var sessionLayout: some View {
        GeometryReader { geometry in
            let bottomMaxHeight = maxBottomPanelHeight(for: geometry.size.height)
            let headerMaxHeight = maxHeaderHeight(for: geometry.size.height)
            let stageHeight = effectiveStageHeight(
                viewportHeight: geometry.size.height,
                bottomMaxHeight: bottomMaxHeight,
                headerMaxHeight: headerMaxHeight
            )

            sessionContent(stageHeight: stageHeight)
                .safeAreaInset(edge: .top, spacing: 0) {
                    if effectiveDisplayMode == .ring {
                        ringModeHeader
                    } else if viewModel.payload.performanceMode == .rehearsal {
                        sessionHeader(maxHeight: headerMaxHeight)
                    } else {
                        compactSessionHeader(maxHeight: headerMaxHeight)
                    }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    bottomPanel(maxHeight: bottomMaxHeight)
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var sessionWithOverlays: some View {
        sessionLayout
            .onAppear {
                if isGuest {
                    viewModel.setGuestMetronomeAudioEnabled(guestMetronomeAudioEnabled)
                } else {
                    viewModel.refreshMetronomeAudioPolicy()
                }
                presentPreServiceChecklistIfNeeded()
            }
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
            .overlay { cueOverlayContent }
            .overlay { countInOverlayContent }
            .overlay { chordChangeWarningOverlayContent }
            .overlay { transitionOverlayContent }
            .overlay { beatFlashOverlayContent }
            .overlay { songEndingOverlayContent }
            .overlay { reconnectOverlayContent }
            .onChange(of: viewModel.metronome.currentBeat) { _, newBeat in
                guard newBeat >= 0 else { return }

                if isCountInActive {
                    pulseBeatFlash(color: newBeat == 0 ? AppTheme.accent : AppTheme.accentSecondary, intensity: newBeat == 0 ? 1.0 : 0.7)
                    return
                }

                if viewModel.shouldShowChordChangeWarning {
                    pulseBeatFlash(color: AppTheme.accentSecondary, intensity: newBeat == 0 ? 1.0 : 0.55)
                    if newBeat == 0 {
                        viewModel.triggerChordChangeWarningHaptic()
                    }
                    return
                }

                guard isGuest, beatFlashEnabled, viewModel.payload.isMetronomePlaying else { return }
                pulseBeatFlash(
                    color: newBeat == 0 ? AppTheme.accent : AppTheme.accentSecondary,
                    intensity: newBeat == 0 ? 1.0 : 0.6
                )
            }
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
            VStack {
                ChordChangeWarningBanner(beatsRemaining: remaining)
                    .padding(.top, 72)
                Spacer()
            }
            .allowsHitTesting(false)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    @ViewBuilder
    private var cueOverlayContent: some View {
        if let cue = viewModel.payload.activeCue {
            VStack {
                LiveCueBanner(
                    cue: cue,
                    isAutoAdvancePaused: viewModel.payload.isAutoAdvancePaused,
                    isVampActive: viewModel.payload.isVampActive
                )
                    .padding(.top, 80)
                Spacer()
            }
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var transitionOverlayContent: some View {
        if let title = viewModel.payload.transitionTitle {
            SetlistTransitionOverlay(title: title, countdown: viewModel.payload.transitionCountdown)
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
    private var reconnectOverlayContent: some View {
        if viewModel.showReconnectBanner, isGuest {
            VStack {
                ReconnectBanner(
                    sessionName: viewModel.payload.sessionName,
                    onReconnect: { viewModel.tryAutoReconnectIfPossible() },
                    onLeave: { showLeaveConfirmation = true }
                )
                .padding(.horizontal, sessionHorizontalPadding)
                .padding(.top, 8)
                Spacer()
            }
        }
    }

    @ViewBuilder
    private var beatFlashOverlayContent: some View {
        let shouldFlash = isCountInActive
            || viewModel.shouldShowChordChangeWarning
            || (isGuest && beatFlashEnabled && viewModel.payload.isMetronomePlaying)
        if shouldFlash {
            RoundedRectangle(cornerRadius: 0)
                .stroke(flashColor, lineWidth: isCountInActive ? 14 : 10)
                .padding(6)
                .opacity(flashOpacity)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var sessionWithSheets: some View {
        sessionWithOverlays
            .sheet(isPresented: $showMIDISettings) {
                MIDISettingsView(viewModel: viewModel)
            }
            .sheet(isPresented: $showGuestSettings, onDismiss: {
                if isGuest {
                    viewModel.setGuestMetronomeAudioEnabled(guestMetronomeAudioEnabled)
                }
                viewModel.refreshMetronomeAudioPolicy()
            }) {
                GuestMusicianSettingsView()
            }
            .sheet(isPresented: $showLockScreenSettings) {
                LockScreenActivitySettingsView()
            }
            .sheet(isPresented: $showPDFChart) {
                pdfChartSheet
            }
            .sheet(isPresented: $showMetadataEditor) {
                metadataEditorSheet
            }
            .sheet(isPresented: $showProgressionEditor) {
                ProgressionEditorView(viewModel: viewModel)
            }
            .sheet(isPresented: $showPreServiceChecklist) {
                PreServiceChecklistView(viewModel: viewModel) {
                    GuestDisplaySettings.preServiceChecklistDismissedToken = viewModel.payload.sessionToken.uuidString
                    showPreServiceChecklist = false
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
                        isPlaying: viewModel.payload.isBackingTrackPlaying
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

                if !GuestDisplaySettings.externalDisplayGuideDismissed,
                   (isHost || isPractice),
                   !isLivePerformance {
                    ExternalDisplayGuide {
                        GuestDisplaySettings.externalDisplayGuideDismissed = true
                    }
                    .padding(.horizontal, sessionHorizontalPadding)
                    .padding(.top, 4)
                }

                if effectiveDisplayMode == .ring {
                    chordRingContent()
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
                            guestCapo: isGuest ? guestCapo : 0
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

            VStack {
                Spacer()
                HStack {
                    Spacer()
                    NotationCycleButton(viewModel: viewModel, isGuest: isGuest)
                }
                .padding(.trailing, sessionHorizontalPadding)
                .padding(.bottom, 8)
                // Match the centered session panel on iPad/Mac so the button sits above the control grid.
                .frame(maxWidth: sessionPanelMaxWidth)
                .frame(maxWidth: .infinity)
            }
            .allowsHitTesting(true)
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
        if viewModel.isLiveProgressionSession && !viewModel.sortedChords.isEmpty && !ringShowsLiveChords {
            liveProgressionBadge
        } else if ringShowsLiveChords {
            liveChordBadge
        } else if centerShowsLivePiano {
            liveChordBadge
        } else if !viewModel.sortedChords.isEmpty {
            progressionBadge
        }
    }

    private func chordRingContent() -> some View {
        GeometryReader { geo in
            let layout = ringLayout(in: geo.size, chordCount: ringChords.count)

            if ringChords.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "circle.grid.cross")
                        .font(.system(size: 44))
                        .foregroundStyle(AppTheme.accent.opacity(0.8))
                    Text("Waiting for chords")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                    Text(isGuest
                         ? String(localized: "The host's progression will appear here in real time.")
                         : String(localized: "Add chords or load a saved progression."))
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
                        activeChordID: ringShowsLiveChords ? nil : viewModel.payload.activeChordID,
                        activeChordSymbol: ringShowsLiveChords
                            ? viewModel.payload.liveChordSymbol
                            : nil,
                        isInteractive: isHost,
                        containerSize: geo.size,
                        radius: layout.radius,
                        bubbleSize: layout.bubbleSize,
                        beatChangeHint: shouldPulseBeatHint,
                        onTap: { viewModel.setActiveChord($0) }
                    )

                    CurrentChordDisplay(
                        chord: centerChord,
                        upcoming: viewModel.payload.isLiveChordsOnly || ringShowsLiveChords
                            ? nil
                            : viewModel.upcomingChord,
                        notation: ringNotation,
                        key: viewModel.payload.key,
                        emphasized: isGuest,
                        isEmptyProgression: isHost
                            && viewModel.sortedChords.isEmpty
                            && !viewModel.isLiveProgressionSession,
                        onAddChords: isHost ? { showProgressionEditor = true } : nil,
                        isLiveFreestyle: centerShowsLivePiano
                            || ringShowsLiveChords
                            || (isHost && viewModel.isLiveProgressionSession && viewModel.sortedChords.isEmpty),
                        isListeningForChord: ringShowsLiveChords
                            && centerChord == nil
                            && (isHost ? !viewModel.payload.pianoNotes.isEmpty : hostSharingPiano),
                        diameter: layout.centerDiameter
                    )
                    .frame(width: layout.centerDiameter, height: layout.centerDiameter)
                    .clipped()
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
                }
                .overlay(alignment: .bottom) {
                    ringStatusBadge
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .padding(.horizontal, sessionHorizontalPadding)
                        .padding(.bottom, 8)
                }
            }
        }
        .frame(minHeight: ringContentMinHeight)
        .padding(.horizontal, sessionHorizontalPadding)
    }

    private var ringContentMinHeight: CGFloat {
        #if os(macOS)
        isGuest ? 360 : 320
        #else
        isGuest ? 280 : 240
        #endif
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
                        if isGuest, let host = viewModel.sessionManager.connectedPeers.first?.displayName {
                            Text("Following \(host)")
                        } else {
                            Label(
                                isPractice ? String(localized: "Practice") : (isHost ? String(localized: "Host") : String(localized: "Guest")),
                                systemImage: isPractice ? "metronome" : (isHost ? "star.fill" : "person.fill")
                            )
                        }
                        Text("·")
                        Text("Key of \(viewModel.payload.key.displayName)")
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(1)
                }

                Spacer(minLength: 8)

                leaveSessionButton(style: .header)
            }

            RingSourcePicker(showsLiveChords: ringSourceBinding)
        }
        .padding(.horizontal, sessionHorizontalPadding)
        .padding(.vertical, 8)
        .background {
            AppTheme.background
                .opacity(0.92)
                .ignoresSafeArea(edges: .top)
        }
    }

    private func compactSessionHeader(maxHeight: CGFloat) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.payload.sessionName)
                    .font(.headline.weight(.bold))
                    .lineLimit(1)
                if isGuest, let host = viewModel.sessionManager.connectedPeers.first?.displayName {
                    Text("Following \(host)")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
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
        .padding(.horizontal, sessionHorizontalPadding)
        .padding(.vertical, 8)
        .background {
            AppTheme.background.opacity(0.92).ignoresSafeArea(edges: .top)
        }
    }

    @ViewBuilder
    private func bottomPanel(maxHeight: CGFloat) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                if (viewModel.canDriveSession || viewModel.isCoHost), !viewModel.payload.isLiveChordsOnly {
                    ChordAdvanceBar(viewModel: viewModel)
                        .padding(.horizontal, sessionHorizontalPadding)
                        .padding(.top, 8)
                }

                if isHost || isPractice, !viewModel.payload.isLiveChordsOnly, !isLiveCompactHost {
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
                    collapsedMetronomeBar
                }

                if isLiveCompactHost {
                    liveCompactHostPanel
                } else if isHost {
                    hostControls
                } else if isGuest {
                    #if os(macOS)
                    macGuestControls
                    #else
                    guestBanner
                    #endif
                }
            }
            .padding(.bottom, 8)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxHeight: maxHeight)
        .frame(maxWidth: sessionPanelMaxWidth)
        .frame(maxWidth: .infinity)
        .safeAreaPadding(.bottom, 4)
        .background {
            AppTheme.background
                .opacity(0.92)
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private var liveCompactHostPanel: some View {
        VStack(spacing: 14) {
            if viewModel.canDriveSession {
                BackingTrackPanel(viewModel: viewModel) {
                    showBackingTrackImporter = true
                }
                .padding(.horizontal, sessionHorizontalPadding)
            }

            LiveCuePad(viewModel: viewModel)
                .padding(.horizontal, sessionHorizontalPadding)

            HStack(spacing: 10) {
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                        liveToolsExpanded = true
                    }
                } label: {
                    Label(String(localized: "More Tools"), systemImage: "slider.horizontal.3")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(AppTheme.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                Button {
                    showPianoOverlay = true
                    viewModel.openPiano()
                } label: {
                    Label(String(localized: "Piano"), systemImage: "pianokeys")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(AppTheme.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            .foregroundStyle(AppTheme.textPrimary)
            .padding(.horizontal, sessionHorizontalPadding)

            HStack(spacing: 10) {
                Menu {
                    Picker("View", selection: Binding(
                        get: { viewModel.payload.displayMode },
                        set: { viewModel.setDisplayMode($0) }
                    )) {
                        ForEach(SessionDisplayMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                } label: {
                    Label(String(localized: "View"), systemImage: "rectangle.on.rectangle")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(AppTheme.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                Button {
                    showPreServiceChecklist = true
                } label: {
                    Label(String(localized: "Pre-Service"), systemImage: "checklist")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(AppTheme.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            .foregroundStyle(AppTheme.textPrimary)
            .padding(.horizontal, sessionHorizontalPadding)
        }
        .padding(.top, 8)
    }

    private func presentPreServiceChecklistIfNeeded() {
        guard shouldOfferPreServiceChecklist else { return }
        showPreServiceChecklist = true
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
                        Label(viewModel.sessionManager.syncQuality.label, systemImage: "waveform.path.ecg")
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
                        Text("iPhone/iPad must be on the same Wi‑Fi and allow Local Network for Chordyx.")
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
        viewModel.payload.isPianoActive || !viewModel.payload.pianoNotes.isEmpty
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
                Text("· \(viewModel.freestyleChordEntries.count) chords")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppTheme.textSecondary)
            }

            Spacer()
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

            LiveCuePad(viewModel: viewModel)
                .padding(.horizontal, sessionHorizontalPadding)

            if viewModel.canDriveSession {
                BackingTrackPanel(viewModel: viewModel) {
                    showBackingTrackImporter = true
                }
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
                Menu {
                    Picker("Notation", selection: Binding(
                        get: { viewModel.payload.notation },
                        set: { viewModel.updateNotation($0) }
                    )) {
                        ForEach(ChordNotation.allCases) { notation in
                            Text(notation.label).tag(notation)
                        }
                    }
                } label: {
                    controlChip(icon: "textformat", title: viewModel.payload.notation.chipLabel, fillWidth: true)
                }

                Menu {
                    Section("Transpose to") {
                        Picker("Key", selection: Binding(
                            get: { viewModel.payload.key },
                            set: { viewModel.transpose(to: $0) }
                        )) {
                            ForEach(MusicalKey.allCases) { key in
                                Text(key.displayName).tag(key)
                            }
                        }
                    }
                } label: {
                    controlChip(icon: "arrow.up.arrow.down", title: "Key \(viewModel.payload.key.displayName)", fillWidth: true)
                }

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
                Label("Metronome Click", systemImage: "speaker.wave.2.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
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

    private var collapsedMetronomeBar: some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                metronomePanelVisible = true
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "metronome")
                    .foregroundStyle(AppTheme.accentSecondary)

                Text("Metronome")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)

                if viewModel.payload.isMetronomePlaying {
                    Text("\(Int(viewModel.payload.tempoBPM)) BPM · \(viewModel.payload.beatsPerBar)/\(viewModel.payload.beatUnit)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppTheme.textSecondary)
                }

                Spacer()

                Image(systemName: "chevron.up")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .glassCard()
        }
        .padding(.horizontal, sessionHorizontalPadding)
        .padding(.bottom, 12)
    }

    private var metronomeBar: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                Button {
                    viewModel.toggleMetronome()
                } label: {
                    Image(systemName: viewModel.payload.isMetronomePlaying ? "pause.fill" : "play.fill")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(AppTheme.background)
                        .frame(width: 48, height: 48)
                        .background(viewModel.payload.isMetronomePlaying ? AppTheme.accent : AppTheme.accentSecondary)
                        .clipShape(Circle())
                }
                .disabled(!isHost)
                .opacity(isHost ? 1 : 0.5)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(Int(viewModel.payload.tempoBPM))")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.textPrimary)
                            .contentTransition(.numericText())
                        Text("BPM")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.textSecondary)
                    }

                    beatDots
                }

                Spacer(minLength: 0)

                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        metronomePanelVisible = false
                    }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppTheme.textSecondary)
                        .frame(width: 32, height: 32)
                        .background(AppTheme.surfaceElevated)
                        .clipShape(Circle())
                }
                .accessibilityLabel("Hide metronome")
            }

            if isHost {
                HStack(spacing: 10) {
                    tapTempoButton
                    timeSignatureMenu
                    Spacer(minLength: 0)
                }

                Stepper(value: Binding(
                    get: { viewModel.payload.countInBars },
                    set: { viewModel.setCountInBars($0) }
                ), in: 0...4) {
                    Text("Count-in: \(viewModel.payload.countInBars) bar\(viewModel.payload.countInBars == 1 ? "" : "s")")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppTheme.textSecondary)
                }

                HStack(spacing: 12) {
                    Button {
                        viewModel.setTempo(viewModel.payload.tempoBPM - 1)
                    } label: {
                        stepperIcon("minus")
                    }

                    Slider(
                        value: Binding(
                            get: { viewModel.payload.tempoBPM },
                            set: { viewModel.setTempo($0) }
                        ),
                        in: SessionViewModel.minBPM...SessionViewModel.maxBPM,
                        step: 1
                    )
                    .tint(AppTheme.accent)

                    Button {
                        viewModel.setTempo(viewModel.payload.tempoBPM + 1)
                    } label: {
                        stepperIcon("plus")
                    }
                }
            }

            volumeRow
        }
        .padding(16)
        .glassCard()
        .padding(.horizontal, sessionHorizontalPadding)
        .padding(.bottom, 12)
        .onAppear { viewModel.metronome.volume = Float(metronomeVolume) }
        .onChange(of: metronomeVolume) { _, newValue in
            viewModel.metronome.volume = Float(newValue)
        }
    }

    private var volumeRow: some View {
        HStack(spacing: 12) {
            Button {
                metronomeVolume = metronomeVolume > 0 ? 0 : 0.8
            } label: {
                Image(systemName: volumeIcon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)
                    .frame(width: 24)
            }

            Slider(value: $metronomeVolume, in: 0...1)
                .tint(AppTheme.accentSecondary)

            Text("\(Int(metronomeVolume * 100))%")
                .font(.caption.weight(.medium))
                .foregroundStyle(AppTheme.textSecondary)
                .frame(width: 40, alignment: .trailing)
        }
    }

    private var volumeIcon: String {
        if metronomeVolume == 0 { return "speaker.slash.fill" }
        if metronomeVolume < 0.4 { return "speaker.fill" }
        if metronomeVolume < 0.75 { return "speaker.wave.1.fill" }
        return "speaker.wave.2.fill"
    }

    private var beatDots: some View {
        HStack(spacing: 6) {
            ForEach(0..<max(1, viewModel.payload.beatsPerBar), id: \.self) { index in
                let isCurrent = viewModel.payload.isMetronomePlaying && viewModel.metronome.currentBeat == index
                Circle()
                    .fill(isCurrent ? (index == 0 ? AppTheme.accent : AppTheme.accentSecondary) : AppTheme.chordInactive)
                    .frame(width: isCurrent ? 12 : 8, height: isCurrent ? 12 : 8)
                    .animation(.easeOut(duration: 0.1), value: viewModel.metronome.currentBeat)
            }
        }
        .frame(height: 14)
    }

    private var tapTempoButton: some View {
        Button {
            registerTap()
        } label: {
            controlChip(icon: "hand.tap.fill", title: "Tap Tempo")
        }
    }

    private func registerTap() {
        let now = Date()
        // A long gap means a fresh count-in, so start over.
        if let last = tapTimes.last, now.timeIntervalSince(last) > 2 {
            tapTimes.removeAll()
        }
        tapTimes.append(now)
        if tapTimes.count > 5 {
            tapTimes.removeFirst(tapTimes.count - 5)
        }
        guard tapTimes.count >= 2 else { return }

        var intervals: [TimeInterval] = []
        for i in 1..<tapTimes.count {
            intervals.append(tapTimes[i].timeIntervalSince(tapTimes[i - 1]))
        }
        let average = intervals.reduce(0, +) / Double(intervals.count)
        guard average > 0 else { return }
        viewModel.setTempo(60.0 / average)
    }

    private var timeSignatureMenu: some View {
        Menu {
            Picker("Time Signature", selection: Binding(
                get: { "\(viewModel.payload.beatsPerBar)/\(viewModel.payload.beatUnit)" },
                set: { id in
                    if let signature = TimeSignature.presets.first(where: { $0.id == id }) {
                        viewModel.setTimeSignature(beats: signature.beats, unit: signature.unit)
                    }
                }
            )) {
                ForEach(TimeSignature.presets) { signature in
                    Text(signature.label).tag(signature.id)
                }
            }
        } label: {
            controlChip(icon: "metronome", title: "\(viewModel.payload.beatsPerBar)/\(viewModel.payload.beatUnit)")
        }
    }

    private func stepperIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(AppTheme.textPrimary)
            .frame(width: 38, height: 38)
            .background(AppTheme.surfaceElevated)
            .clipShape(Circle())
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
