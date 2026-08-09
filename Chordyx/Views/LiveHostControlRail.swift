//
//  LiveHostControlRail.swift
//  Chordyx
//
//  Tabbed live host controls — side rail or bottom dock (Mac / iPad wide).
//

import SwiftUI

enum LiveHostControlRailStyle {
    case sideRail
    case bottomDock(maxHeight: CGFloat)
}

struct LiveHostControlRail: View {
    @Bindable var viewModel: SessionViewModel
    @Bindable var store: ProgressionStore
    var style: LiveHostControlRailStyle
    var isHost: Bool
    var horizontalPadding: CGFloat

    @Binding var selectedTab: LiveHostDockTab
    @Binding var layoutMode: LiveDockLayoutMode
    @Binding var heightPresetRaw: String
    @Binding var sideRailVisible: Bool
    @Binding var bandCuePadVisible: Bool
    @Binding var metronomePanelVisible: Bool
    @Binding var metronomeVolume: Double

    @Binding var showPianoOverlay: Bool
    @Binding var showFretboardOverlay: Bool
    @Binding var showProgressionEditor: Bool
    @Binding var showMetadataEditor: Bool
    @Binding var showMIDISettings: Bool
    @Binding var showPreServiceChecklist: Bool
    @Binding var showExtendedFeaturesHub: Bool
    @Binding var showAdvancedFeaturesHub: Bool
    @Binding var showGuestRoles: Bool
    @Binding var showRehearsalList: Bool
    @Binding var showJoinQR: Bool
    @Binding var showBandChat: Bool
    @Binding var showBackingTrackImporter: Bool
    @Binding var showSaveDialog: Bool
    @Binding var saveName: String
    @Binding var isKeyMenuPresented: Bool
    @Binding var showPDFChart: Bool

    var needsLiveChordTransport: Bool
    var keyControlTitle: String
    var isSaved: Bool
    var isLastSetlistSong: Bool
    var onCopyJoinCode: (String) -> Void

    private var isSideRail: Bool {
        if case .sideRail = style { return true }
        return false
    }

    private var bottomMaxHeight: CGFloat? {
        if case .bottomDock(let maxHeight) = style { return maxHeight }
        return nil
    }

    var body: some View {
        Group {
            if isSideRail {
                sideRailBody
            } else {
                bottomDockBody
            }
        }
        .background {
            AppTheme.background
                .opacity(0.96)
                .ignoresSafeArea()
        }
    }

    private var sideRailBody: some View {
        HStack(spacing: 0) {
            tabIconColumn
                .frame(width: 54)
                .padding(.vertical, 10)
                .background(AppTheme.surfaceElevated.opacity(0.55))

            Divider()

            VStack(spacing: 0) {
                dockHeader
                Divider()
                tabContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var bottomDockBody: some View {
        VStack(spacing: 0) {
            dockHeader
            tabIconRow
                .padding(.horizontal, horizontalPadding)
                .padding(.bottom, 6)
            Divider()
            tabContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(height: bottomMaxHeight, alignment: .top)
        #if os(macOS)
        .clipped()
        #endif
    }

    private var dockHeader: some View {
        HStack(spacing: 10) {
            Label(String(localized: "Live Controls"), systemImage: "slider.horizontal.3")
                .font(.caption.weight(.bold))
                .foregroundStyle(AppTheme.textSecondary)
                .textCase(.uppercase)

            Spacer(minLength: 0)

            if isSideRail {
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                        sideRailVisible = false
                    }
                } label: {
                    Image(systemName: "sidebar.right")
                        .font(.caption.weight(.bold))
                }
                .buttonStyle(.plain)
                .help(String(localized: "Hide side panel"))
            } else {
                heightPresetPicker
            }

            Picker(String(localized: "Layout"), selection: $layoutMode) {
                ForEach(LiveDockLayoutMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
        .padding(.horizontal, isSideRail ? 12 : horizontalPadding)
        .padding(.vertical, 8)
    }

    private var heightPresetPicker: some View {
        HStack(spacing: 0) {
            ForEach(LiveDockHeightPreset.allCases) { preset in
                let isSelected = heightPresetRaw == preset.rawValue
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                        heightPresetRaw = preset.rawValue
                    }
                } label: {
                    Text(preset.label)
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(isSelected ? AppTheme.surfaceElevated : Color.clear)
                        .foregroundStyle(isSelected ? AppTheme.textPrimary : AppTheme.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(AppTheme.surface.opacity(0.8))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .frame(maxWidth: 180)
        .accessibilityLabel(String(localized: "Dock height"))
    }

    private var tabIconColumn: some View {
        VStack(spacing: 6) {
            ForEach(LiveHostDockTab.allCases) { tab in
                tabButton(tab, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private var tabIconRow: some View {
        HStack(spacing: 4) {
            ForEach(LiveHostDockTab.allCases) { tab in
                tabButton(tab, vertical: false)
            }
        }
        .padding(4)
        .glassCard()
    }

    private var shouldAnimateDockTabSwitch: Bool {
        #if os(macOS) || os(iOS)
        // Spring-animating heavy Solo / metronome panels while a locked groove plays
        // stalls the main thread and audibly hiccups the drum clock.
        !(viewModel.soloAccompanimentEnabled && viewModel.soloTempoLocked)
        #else
        true
        #endif
    }

    private func selectDockTab(_ tab: LiveHostDockTab) {
        guard selectedTab != tab else { return }
        if shouldAnimateDockTabSwitch {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                selectedTab = tab
            }
        } else {
            selectedTab = tab
        }
    }

    private func tabButton(_ tab: LiveHostDockTab, vertical: Bool) -> some View {
        let isSelected = selectedTab == tab
        return Button {
            selectDockTab(tab)
        } label: {
            Group {
                if vertical {
                    VStack(spacing: 4) {
                        Image(systemName: tab.icon)
                            .font(.body.weight(.semibold))
                        Text(tab.label)
                            .font(.caption2.weight(.medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                } else {
                    VStack(spacing: 3) {
                        Image(systemName: tab.icon)
                            .font(.subheadline.weight(.semibold))
                        Text(tab.label)
                            .font(.caption2.weight(.medium))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
            }
            .foregroundStyle(isSelected ? AppTheme.accent : AppTheme.textSecondary)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(AppTheme.accent.opacity(0.14))
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.label)
    }

    @ViewBuilder
    private var tabContent: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 14) {
                switch selectedTab {
                case .quick:
                    quickTab
                case .metronome:
                    metronomeTab
                case .audio:
                    audioTab
                case .cues:
                    cuesTab
                case .session:
                    sessionTab
                }
            }
            .padding(.horizontal, isSideRail ? 12 : horizontalPadding)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var quickTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            if needsLiveChordTransport {
                LiveChordTransportCompact(viewModel: viewModel)
            }

            Text(String(localized: "Quick Actions"))
                .font(.caption.weight(.bold))
                .foregroundStyle(AppTheme.textSecondary)
                .textCase(.uppercase)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                quickAction(icon: "pianokeys", title: String(localized: "Piano")) {
                    showPianoOverlay = true
                    viewModel.openPiano()
                }
                quickAction(icon: "guitars", title: String(localized: "Fretboard")) {
                    showFretboardOverlay = true
                    viewModel.openFretboard()
                }
                quickAction(icon: "list.bullet", title: String(localized: "Edit")) {
                    showProgressionEditor = true
                }
                quickAction(icon: "text.quote", title: String(localized: "Lyrics")) {
                    showMetadataEditor = true
                }
                quickAction(icon: "cable.connector", title: String(localized: "MIDI")) {
                    showMIDISettings = true
                }
                quickAction(icon: "checklist", title: String(localized: "Pre-Service")) {
                    showPreServiceChecklist = true
                }
                quickAction(
                    icon: bandCuePadVisible ? "megaphone.fill" : "megaphone",
                    title: String(localized: "Band Cues")
                ) {
                    let showCues = {
                        bandCuePadVisible.toggle()
                        if bandCuePadVisible { selectDockTab(.cues) }
                    }
                    if shouldAnimateDockTabSwitch {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.86), showCues)
                    } else {
                        showCues()
                    }
                }
                quickAction(icon: "metronome", title: String(localized: "Metronome")) {
                    selectDockTab(.metronome)
                }
                #if os(macOS) || os(iOS)
                if viewModel.soloAccompanimentAvailable {
                    quickAction(icon: "figure.wave", title: String(localized: "Solo Drums")) {
                        selectDockTab(.audio)
                    }
                }
                #endif
            }

            SessionDisplayModeMenu(viewModel: viewModel) {
                LiveHostDockChip(icon: "rectangle.on.rectangle", title: String(localized: "View"), fillWidth: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var metronomeTab: some View {
        SessionMetronomePanel(
            viewModel: viewModel,
            isHost: isHost,
            metronomeVolume: $metronomeVolume,
            horizontalPadding: 0,
            showsCollapseButton: false
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var audioTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            BackingTrackPanel(viewModel: viewModel, onImport: {
                showBackingTrackImporter = true
            }, style: .compact)
            .frame(maxWidth: .infinity, alignment: .leading)

            #if os(macOS) || os(iOS)
            if viewModel.soloAccompanimentAvailable {
                SoloAccompanimentMacPanel(viewModel: viewModel, progressionStore: store)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            #endif
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var cuesTab: some View {
        LiveCuePad(viewModel: viewModel, usesWideLayout: isSideRail)
    }

    private var sessionTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                SessionFeaturesMenu(
                    viewModel: viewModel,
                    store: store,
                    showGuestRoles: $showGuestRoles,
                    showRehearsalList: $showRehearsalList,
                    showJoinQR: $showJoinQR,
                    showExtendedFeaturesHub: $showExtendedFeaturesHub,
                    showAdvancedFeaturesHub: $showAdvancedFeaturesHub,
                    showBandChat: $showBandChat
                )
                VocalKeyPicker(viewModel: viewModel)
                Spacer(minLength: 0)
            }

            if viewModel.payload.isRemoteBackupEnabled, let code = viewModel.payload.remoteJoinCode {
                HostRemoteJoinCodeCompactChip(
                    code: code,
                    isRelayLive: viewModel.cloudRelay.isRelayLive,
                    onCopy: { onCopyJoinCode(code) },
                    onShowQR: { showJoinQR = true }
                )
            }

            if viewModel.payload.setlistName != nil {
                setlistControls
            }

            CoHostPicker(viewModel: viewModel)

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

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                Button { isKeyMenuPresented = true } label: {
                    LiveHostDockChip(
                        icon: viewModel.payload.autoDetectKey ? "wand.and.stars" : "arrow.up.arrow.down",
                        title: keyControlTitle,
                        fillWidth: true
                    )
                }
                .buttonStyle(.plain)
                .platformSheet(isPresented: $isKeyMenuPresented) {
                    SessionMusicalKeyPicker(viewModel: viewModel, isPresented: $isKeyMenuPresented)
                }

                quickAction(
                    icon: viewModel.payload.isRemoteBackupEnabled ? "icloud.fill" : "icloud",
                    title: viewModel.payload.isRemoteBackupEnabled
                        ? String(localized: "Internet On")
                        : String(localized: "Internet Off")
                ) {
                    viewModel.setRemoteBackupEnabled(!viewModel.payload.isRemoteBackupEnabled)
                }

                quickAction(
                    icon: isSaved ? "bookmark.fill" : "square.and.arrow.down",
                    title: String(localized: "Save")
                ) {
                    saveName = viewModel.payload.sessionName
                    showSaveDialog = true
                }
                .disabled(viewModel.sortedChords.isEmpty)
                .opacity(viewModel.sortedChords.isEmpty ? 0.4 : 1)

                if let progressionID = viewModel.loadedProgressionID,
                   let progression = store.progression(with: progressionID),
                   store.pdfURL(for: progression) != nil {
                    quickAction(icon: "doc.richtext", title: String(localized: "PDF")) {
                        showPDFChart = true
                    }
                }
            }
        }
    }

    private var setlistControls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    viewModel.previousSetlistSong(store: store)
                } label: {
                    Label(String(localized: "Previous"), systemImage: "backward.fill")
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
                    Label(String(localized: "Next Song"), systemImage: "forward.fill")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(AppTheme.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .disabled(isLastSetlistSong)
            }

            Toggle(isOn: Binding(
                get: { viewModel.autoAdvanceSetlistSongs },
                set: { viewModel.setAutoAdvanceSetlist($0) }
            )) {
                Text(String(localized: "Auto-advance setlist at last chord"))
                    .font(.caption.weight(.medium))
            }
            .tint(AppTheme.accent)
        }
    }

    private func quickAction(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            LiveHostDockChip(icon: icon, title: title, fillWidth: true)
        }
        .buttonStyle(.plain)
    }
}

struct LiveHostTransportStrip: View {
    @Bindable var viewModel: SessionViewModel
    @Binding var selectedTab: LiveHostDockTab
    @Binding var sideRailVisible: Bool
    @Binding var bandCuePadVisible: Bool
    var needsLiveChordTransport: Bool
    var usesSideRail: Bool
    var horizontalPadding: CGFloat
    var onPiano: () -> Void
    var onToggleDock: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            if needsLiveChordTransport {
                LiveChordTransportCompact(viewModel: viewModel)
                    .padding(.horizontal, horizontalPadding)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    transportButton(
                        icon: viewModel.payload.isMetronomePlaying ? "pause.fill" : "play.fill",
                        label: String(localized: "Metro")
                    ) {
                        viewModel.toggleMetronome()
                    }

                    VStack(alignment: .leading, spacing: 0) {
                        Text("\(Int(viewModel.payload.tempoBPM))")
                            .font(.headline.weight(.bold).monospacedDigit())
                        Text("BPM")
                            .font(.caption2)
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                    .frame(minWidth: 44)

                    Divider().frame(height: 28)

                    transportButton(
                        icon: bandCuePadVisible ? "megaphone.fill" : "megaphone",
                        label: String(localized: "Cues")
                    ) {
                        bandCuePadVisible.toggle()
                        selectedTab = .cues
                        if usesSideRail { sideRailVisible = true }
                        onToggleDock()
                    }

                    transportButton(icon: "waveform", label: String(localized: "Audio")) {
                        selectedTab = .audio
                        if usesSideRail { sideRailVisible = true }
                        onToggleDock()
                    }

                    transportButton(icon: "pianokeys", label: String(localized: "Piano"), action: onPiano)

                    if usesSideRail {
                        Button(action: onToggleDock) {
                            HStack(spacing: 6) {
                                Image(systemName: sideRailVisible ? "sidebar.right" : "sidebar.left")
                                    .font(.caption.weight(.semibold))
                                Text(sideRailVisible ? String(localized: "Hide Panel") : String(localized: "Controls"))
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                                    .fixedSize(horizontal: true, vertical: false)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(AppTheme.surfaceElevated)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, 6)
        }
        .background {
            AppTheme.background.opacity(0.94)
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private func transportButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.subheadline.weight(.semibold))
                Text(label)
                    .font(.caption2.weight(.medium))
                    .lineLimit(1)
            }
            .foregroundStyle(AppTheme.textPrimary)
            .frame(minWidth: 52)
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}
