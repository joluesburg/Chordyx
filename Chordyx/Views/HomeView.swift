//
//  HomeView.swift
//  Chordyx
//

import SwiftUI
import MultipeerConnectivity

struct HomeView: View {
    @Bindable var viewModel: SessionViewModel
    @Bindable var store: ProgressionStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @AppStorage(SessionManager.displayNameKey) private var displayName = ""
    @State private var showHostSetup = false
    @State private var showJoinList = false
    @State private var showLibrary = false
    @State private var showRenameDevice = false
    @State private var showPracticePicker = false
    @State private var showSetlistPicker = false
    @State private var showSongImport = false
    @State private var renameText = ""
    @State private var recentSessionRecords = RecentSessionStore.records

    private var effectiveDeviceName: String {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? PlatformDevice.defaultDisplayName : trimmed
    }

    private var progressionsSubtitle: String {
        let count = store.progressions.count
        if count == 0 { return L10n.createAndSaveSetlists }
        if count == 1 { return L10n.oneSavedProgression }
        return String(format: L10n.savedProgressionsCount, count)
    }

    private var homeHorizontalPadding: CGFloat {
        PlatformLayout.homeHorizontalPadding(horizontalSizeClass: horizontalSizeClass)
    }

    private var gridSpacing: CGFloat {
        PlatformLayout.usesWideHomeLayout(horizontalSizeClass: horizontalSizeClass) ? 20 : 16
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.backgroundGradient.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: PlatformLayout.usesWideHomeLayout(horizontalSizeClass: horizontalSizeClass) ? 36 : (verticalSizeClass == .compact ? 16 : 24)) {
                        homeActionMenu
                            .padding(.top, PlatformLayout.usesWideHomeLayout(horizontalSizeClass: horizontalSizeClass) ? 16 : 8)

                        VStack(spacing: 12) {
                            deviceNameRow

                            if !recentSessionRecords.isEmpty {
                                RecentSessionsSection(
                                    records: recentSessionRecords,
                                    onRehost: { record in
                                        viewModel.rehostRecent(record, store: store)
                                    },
                                    onReconnect: { record in
                                        viewModel.attemptReconnect(to: record)
                                        showJoinList = true
                                    },
                                    onDelete: { record in
                                        RecentSessionStore.delete(record)
                                        recentSessionRecords = RecentSessionStore.records
                                    },
                                    onClearAll: {
                                        RecentSessionStore.deleteAll()
                                        recentSessionRecords = RecentSessionStore.records
                                    }
                                )
                            }

                            Text("Nearby devices on the same Wi‑Fi or Bluetooth")
                                .font(.caption)
                                .foregroundStyle(AppTheme.textSecondary)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: PlatformLayout.usesWideHomeLayout(horizontalSizeClass: horizontalSizeClass) ? 520 : .infinity)
                        }
                        .padding(.top, 8)
                    }
                    .platformHomeContentWidth()
                    .padding(.horizontal, homeHorizontalPadding)
                    .padding(.bottom, 32)
                }
            }
            .platformNavigationBarHidden()
            .onAppear {
                recentSessionRecords = RecentSessionStore.records
            }
            .onChange(of: viewModel.isInSession) { _, inSession in
                if !inSession {
                    recentSessionRecords = RecentSessionStore.records
                }
            }
            .alert("Device Name", isPresented: $showRenameDevice) {
                TextField("Name", text: $renameText)
                Button("Cancel", role: .cancel) {}
                Button("Save") {
                    displayName = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            } message: {
                Text("This is the name other musicians see when you host or join a session.")
            }
            .platformHomeCover(isPresented: $showSongImport) {
                SongImportView(viewModel: viewModel, store: store)
            }
            .platformHomeCover(isPresented: $showHostSetup) {
                HostSetupView(viewModel: viewModel)
            }
            .platformHomeCover(isPresented: $showJoinList, onDismiss: {
                if !viewModel.isInSession {
                    viewModel.sessionManager.disconnect()
                }
            }) {
                JoinSessionView(viewModel: viewModel)
            }
            .platformHomeCover(isPresented: $showLibrary) {
                ProgressionLibraryView(viewModel: viewModel, store: store)
            }
            .platformHomeCover(isPresented: $showPracticePicker) {
                PracticePickerView(viewModel: viewModel, store: store)
            }
            .platformHomeCover(isPresented: $showSetlistPicker) {
                SetlistPickerView(store: store, viewModel: viewModel)
            }
            .platformFullScreenCover(isPresented: Binding(
                get: { viewModel.isInSession },
                set: { _ in }
            )) {
                SessionView(viewModel: viewModel, store: store)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var deviceNameRow: some View {
        Button {
            renameText = effectiveDeviceName
            showRenameDevice = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "person.crop.circle")
                Text("You appear as")
                    .foregroundStyle(AppTheme.textSecondary)
                Text(effectiveDeviceName)
                    .foregroundStyle(AppTheme.textPrimary)
                    .fontWeight(.semibold)
                Image(systemName: "pencil")
                    .font(.caption2)
            }
            .font(.footnote)
            .foregroundStyle(AppTheme.textSecondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(AppTheme.surface)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.08), lineWidth: 1))
        }
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var homeActionMenu: some View {
        ViewThatFits(in: .horizontal) {
            homeLayoutExpanded
                .frame(minWidth: 980)

            homeLayoutGrid(columns: 2)
                .frame(minWidth: 620)

            homeLayoutStack
        }
    }

    private var homeLayoutExpanded: some View {
        VStack(alignment: .leading, spacing: 28) {
            homeSectionHeader("Live Session")
            HStack(spacing: gridSpacing) {
                homeHostButton(style: .card)
                homeJoinButton(style: .card)
            }

            homeSectionHeader("Library")
            HStack(spacing: gridSpacing) {
                homeProgressionsButton(style: .card)
                homeImportButton(style: .card)
            }

            homeMoreSection(style: .card)
        }
    }

    private func homeLayoutGrid(columns: Int) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            homeSectionHeader("Live Session")

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: gridSpacing), count: columns),
                spacing: gridSpacing
            ) {
                homeHostButton(style: .card)
                homeJoinButton(style: .card)
            }

            homeSectionHeader("Library")

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: gridSpacing), count: columns),
                spacing: gridSpacing
            ) {
                homeProgressionsButton(style: .card)
                homeImportButton(style: .card)
            }

            homeMoreSection(style: .card)
        }
    }

    private var homeLayoutStack: some View {
        VStack(spacing: gridSpacing) {
            homeHostButton(style: .list)
            homeJoinButton(style: .list)
            homeProgressionsButton(style: .list)
            homeImportButton(style: .list)
            homeMoreSection(style: .list)
        }
    }

    @ViewBuilder
    private func homeMoreSection(style: HomeActionStyle) -> some View {
        VStack(alignment: .leading, spacing: style == .list ? gridSpacing : 12) {
            homeSectionHeader("More")

            switch style {
            case .card:
                HStack(spacing: gridSpacing) {
                    homePracticeButton(style: .compact)
                    homeSetlistButton(style: .compact)
                }
            case .list, .compact:
                VStack(spacing: gridSpacing) {
                    homePracticeButton(style: .compact)
                    homeSetlistButton(style: .compact)
                }
            }
        }
    }

    private func homeHostButton(style: HomeActionStyle) -> some View {
        actionButton(
            title: "Host a Session",
            subtitle: String(localized: "Invite musicians — chord ring or live piano"),
            icon: "music.mic",
            style: style
        ) { showHostSetup = true }
    }

    private func homeJoinButton(style: HomeActionStyle) -> some View {
        actionButton(
            title: "Join a Session",
            subtitle: String(localized: "Connect to a nearby host"),
            icon: "person.2.wave.2",
            style: style
        ) {
            viewModel.beginJoining()
            showJoinList = true
        }
    }

    private func homeProgressionsButton(style: HomeActionStyle) -> some View {
        actionButton(
            title: "My Progressions",
            subtitle: progressionsSubtitle,
            icon: "bookmark.fill",
            style: style
        ) { showLibrary = true }
    }

    private func homeImportButton(style: HomeActionStyle) -> some View {
        actionButton(
            title: "Import Song",
            subtitle: String(localized: "Search by title — chords and lyrics from the web"),
            icon: "arrow.down.doc.fill",
            style: style
        ) { showSongImport = true }
    }

    private func homePracticeButton(style: HomeActionStyle) -> some View {
        actionButton(
            title: "Practice Solo",
            subtitle: String(localized: "Rehearse with the ring and metronome"),
            icon: "metronome",
            style: style
        ) { showPracticePicker = true }
    }

    private func homeSetlistButton(style: HomeActionStyle) -> some View {
        actionButton(
            title: "Host a Setlist",
            subtitle: String(localized: "Play multiple songs in one session"),
            icon: "list.bullet.rectangle",
            style: style
        ) { showSetlistPicker = true }
    }

    private func homeSectionHeader(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(AppTheme.textSecondary)
            .textCase(.uppercase)
            .tracking(0.8)
            .padding(.leading, 4)
    }

    private enum HomeActionStyle {
        case list
        case card
        case compact
    }

    private func actionButton(
        title: LocalizedStringKey,
        subtitle: String,
        icon: String,
        style: HomeActionStyle,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Group {
                switch style {
                case .list:
                    listActionContent(title: title, subtitle: subtitle, icon: icon)
                case .card:
                    cardActionContent(title: title, subtitle: subtitle, icon: icon)
                case .compact:
                    compactActionContent(title: title, subtitle: subtitle, icon: icon)
                }
            }
            .foregroundStyle(AppTheme.textPrimary)
            .frame(maxWidth: .infinity, alignment: style == .list ? .leading : .center)
            .padding(padding(for: style))
            .background(AppTheme.surface.opacity(style == .compact ? 0.72 : 1))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius(for: style), style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius(for: style), style: .continuous)
                    .stroke(Color.white.opacity(style == .compact ? 0.05 : 0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func padding(for style: HomeActionStyle) -> CGFloat {
        switch style {
        case .list: 20
        case .card: 22
        case .compact: 14
        }
    }

    private func cornerRadius(for style: HomeActionStyle) -> CGFloat {
        style == .compact ? 14 : 20
    }

    private func compactActionContent(title: LocalizedStringKey, subtitle: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(AppTheme.accentSecondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.caption2.weight(.bold))
                .foregroundStyle(AppTheme.textSecondary.opacity(0.7))
        }
    }

    private func listActionContent(title: LocalizedStringKey, subtitle: String, icon: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .frame(width: 44)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .opacity(0.8)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .opacity(0.6)
        }
    }

    private func cardActionContent(title: LocalizedStringKey, subtitle: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(AppTheme.accent)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                    .multilineTextAlignment(.leading)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .frame(minHeight: 148, alignment: .topLeading)
    }

}

struct HostSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: SessionViewModel

    @State private var sessionName = ""
    @State private var selectedKey: MusicalKey = .C
    @State private var selectedNotation: ChordNotation = .symbol
    @State private var sessionKind: HostSessionKind = .liveChords
    @State private var performanceMode: SessionPerformanceMode = .live
    @State private var keySelectionMode: SessionKeySelectionMode = .auto
    @AppStorage(SessionManager.requireHostApprovalKey) private var requireHostApproval = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()

                Form {
                    Section {
                        Picker("Session Type", selection: $sessionKind) {
                            ForEach(HostSessionKind.allCases) { kind in
                                Text(kind.label).tag(kind)
                            }
                        }
                        .pickerStyle(.segmented)

                        Text(sessionKind.description)
                            .font(.caption)
                            .foregroundStyle(AppTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } header: {
                        Text("What are you sharing?")
                    }

                    Section("Session") {
                        TextField("Session name", text: $sessionName)
                        Toggle("Approve guests before joining", isOn: $requireHostApproval)
                    }

                    if sessionKind == .progression {
                        Section("Performance Mode") {
                            Picker("Performance Mode", selection: $performanceMode) {
                                ForEach(SessionPerformanceMode.allCases) { mode in
                                    Text(mode.label).tag(mode)
                                }
                            }
                            Text(performanceMode.subtitle)
                                .font(.caption)
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                    }

                    Section("Musical Key") {
                        HostSetupMusicalKeyCard(
                            mode: $keySelectionMode,
                            manualKey: $selectedKey,
                            showsSpellingHint: sessionKind == .liveChords
                        )
                    }

                    Section("Chord Notation") {
                        ForEach(ChordNotation.allCases) { notation in
                            Button {
                                selectedNotation = notation
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(notation.label)
                                            .foregroundStyle(AppTheme.textPrimary)
                                        Text(notation.subtitle)
                                            .font(.caption)
                                            .foregroundStyle(AppTheme.textSecondary)
                                    }
                                    Spacer()
                                    if selectedNotation == notation {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(AppTheme.accent)
                                    }
                                }
                            }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("New Session")
            .platformInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") {
                        startSession()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .preferredColorScheme(.dark)
        .platformLibrarySheetFrame()
    }

    private func startSession() {
        viewModel.sessionManager.requireHostApproval = requireHostApproval
        let name = sessionName.trimmingCharacters(in: .whitespaces)
        let autoDetectKey = keySelectionMode == .auto
        // Auto AI: don't lock a manual chart key — start neutral (C) until detection from playing.
        let key = autoDetectKey ? MusicalKey.C : selectedKey

        switch sessionKind {
        case .progression:
            viewModel.hostSession(
                name: name.isEmpty ? L10n.jamSession : name,
                key: key,
                notation: selectedNotation,
                performanceMode: performanceMode,
                autoDetectKey: autoDetectKey
            )
        case .liveChords:
            viewModel.hostLiveChordsSession(
                name: name.isEmpty ? String(localized: "Live Chords") : name,
                key: key,
                notation: selectedNotation,
                autoDetectKey: autoDetectKey
            )
        }
        dismiss()
    }
}

private enum HostSessionKind: String, CaseIterable, Identifiable {
    case liveChords
    case progression

    var id: String { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .progression: "Progression"
        case .liveChords: "Live Piano"
        }
    }

    var description: String {
        switch self {
        case .progression:
            String(localized: "Chord ring with next-chord preview. Add chords as you go or load a saved song.")
        case .liveChords:
            String(localized: "Play on piano or MIDI — guests see only the current chord, no next-chord preview.")
        }
    }
}

struct PracticePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: SessionViewModel
    @Bindable var store: ProgressionStore

    var body: some View {
        NavigationStack {
            List {
                Button {
                    viewModel.startPractice(from: nil)
                    dismiss()
                } label: {
                    Label("Empty Practice Session", systemImage: "metronome")
                }
                .listRowBackground(AppTheme.surface)

                if !store.progressions.isEmpty {
                    Section("Saved Progressions") {
                        ForEach(store.sortedProgressions) { progression in
                            Button {
                                viewModel.startPractice(from: progression)
                                dismiss()
                            } label: {
                                Text(progression.name)
                                    .foregroundStyle(AppTheme.textPrimary)
                            }
                            .listRowBackground(AppTheme.surface)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .navigationTitle("Practice Solo")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

struct JoinSessionView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: SessionViewModel

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.sessionManager.discoveredHosts.isEmpty {
                    searchingState
                } else {
                    List(viewModel.sessionManager.discoveredHosts) { host in
                        Button {
                            viewModel.join(host: host)
                            dismiss()
                        } label: {
                            HStack {
                                Image(systemName: "music.note.house.fill")
                                    .foregroundStyle(AppTheme.accent)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(host.sessionName)
                                        .foregroundStyle(AppTheme.textPrimary)
                                        .font(.headline)
                                    Text(host.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(AppTheme.textSecondary)
                                }
                                Spacer()
                                Image(systemName: "arrow.right.circle.fill")
                                    .foregroundStyle(AppTheme.accentSecondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(AppTheme.surface)
                    }
                    .scrollContentBackground(.hidden)
                    #if os(macOS)
                    .listStyle(.inset)
                    #endif
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppTheme.background)
            .navigationTitle("Join Session")
            .platformInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .platformLibrarySheetFrame()
        .onChange(of: viewModel.sessionManager.discoveredHosts.count) { _, _ in
            viewModel.tryAutoReconnectIfPossible()
        }
    }

    private var searchingState: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(AppTheme.accent)
            Text("Searching for nearby sessions…")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)

            if let error = viewModel.sessionManager.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            Text("Use the same Wi‑Fi on both devices and allow Local Network access for Chordyx in Settings.")
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
        }
        .padding(24)
    }
}
