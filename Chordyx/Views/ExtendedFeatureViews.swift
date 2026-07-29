//
//  ExtendedFeatureViews.swift
//  Chordyx
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Session overlays

struct SectionCountdownOverlay: View {
    let sectionName: String
    let beatsRemaining: Int

    var body: some View {
        VStack(spacing: 8) {
            Text(String(localized: "Next section"))
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
            Text(sectionName)
                .font(.title2.weight(.bold))
            Text(String(format: String(localized: "%lld beats"), beatsRemaining))
                .font(.headline.monospacedDigit())
        }
        .foregroundStyle(AppTheme.background)
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(AppTheme.accentSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(radius: 16)
    }
}

struct TempoDriftBanner: View {
    let driftBPM: Double

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: driftBPM > 0 ? "hare.fill" : "tortoise.fill")
            Text(driftText)
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(.orange)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.15))
        .clipShape(Capsule())
    }

    private var driftText: String {
        let amount = Int(abs(driftBPM).rounded())
        if driftBPM > 1 {
            return String(format: String(localized: "~%lld BPM ahead"), amount)
        }
        if driftBPM < -1 {
            return String(format: String(localized: "~%lld BPM behind"), amount)
        }
        return String(localized: "On tempo")
    }
}

struct QuickMessageBar: View {
    @Bindable var viewModel: SessionViewModel
    var canSend: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !viewModel.payload.quickMessages.isEmpty {
                ForEach(viewModel.payload.quickMessages.prefix(2)) { message in
                    HStack(spacing: 8) {
                        Image(systemName: message.symbol)
                        Text("\(message.senderName): \(message.text)")
                            .lineLimit(1)
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppTheme.textPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(AppTheme.surfaceElevated)
                    .clipShape(Capsule())
                }
            }

            if canSend {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(SessionQuickMessage.presets, id: \.0) { text, symbol in
                            Button {
                                viewModel.sendQuickMessage(text, symbol: symbol)
                            } label: {
                                Label(text, systemImage: symbol)
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(AppTheme.surface)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }
}

struct PeerPresenceStrip: View {
    let presence: [String: PeerPresenceInfo]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(sortedPeers, id: \.0) { name, info in
                    HStack(spacing: 6) {
                        Image(systemName: icon(for: info.instrument))
                        Text(name)
                            .lineLimit(1)
                        Circle()
                            .fill(info.isLagging ? Color.orange : Color.green)
                            .frame(width: 6, height: 6)
                    }
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(AppTheme.surfaceElevated)
                    .clipShape(Capsule())
                }
            }
        }
    }

    private var sortedPeers: [(String, PeerPresenceInfo)] {
        presence.sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
    }

    private func icon(for instrument: MusicianInstrument) -> String {
        switch instrument {
        case .guitar: "guitars.fill"
        case .bass: "waveform"
        case .keys: "pianokeys"
        case .vocal: "music.mic"
        case .other: "person.fill"
        }
    }
}

struct HandoffCountdownBanner: View {
    let fromPeer: String?
    let seconds: Int

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.triangle.2.circlepath")
            Text(String(format: String(localized: "%@ passes control in %lld…"), fromPeer ?? String(localized: "Host"), seconds))
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(AppTheme.accent)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(AppTheme.accent.opacity(0.15))
        .clipShape(Capsule())
    }
}

struct RoleLiveNoteBanner: View {
    let note: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "person.text.rectangle")
            Text(note)
                .font(.caption.weight(.medium))
                .lineLimit(2)
        }
        .foregroundStyle(AppTheme.textSecondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct CapoSuggestionBanner: View {
    let suggestion: CapoSuggestion
    var onApply: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "guitars.fill")
            Text(suggestion.summary)
                .font(.caption.weight(.medium))
            Spacer(minLength: 8)
            Button(String(localized: "Apply"), action: onApply)
                .font(.caption.weight(.bold))
        }
        .foregroundStyle(AppTheme.textPrimary)
        .padding(12)
        .background(AppTheme.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct GhostBandReplayBanner: View {
    var onStop: () -> Void

    var body: some View {
        HStack {
            Label(String(localized: "Ghost band replay"), systemImage: "person.3.sequence.fill")
                .font(.caption.weight(.semibold))
            Spacer()
            Button(String(localized: "Stop"), action: onStop)
                .font(.caption.weight(.bold))
        }
        .foregroundStyle(AppTheme.accentSecondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(AppTheme.accentSecondary.opacity(0.15))
        .clipShape(Capsule())
    }
}

// MARK: - Director & audience layouts

struct DirectorModePanel: View {
    @Bindable var viewModel: SessionViewModel
    @Bindable var store: ProgressionStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(String(localized: "Director"))
                .font(.caption.weight(.bold))
                .foregroundStyle(AppTheme.textSecondary)
                .textCase(.uppercase)

            if let setlist = viewModel.payload.setlistName {
                SetlistTimelineBanner(
                    titles: viewModel.payload.setlistSongTitles,
                    currentIndex: viewModel.payload.setlistSongIndex ?? 0
                )
                Text(setlist)
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
            }

            LiveCuePad(viewModel: viewModel, style: .liveCompact)

            HStack(spacing: 10) {
                Button {
                    viewModel.scheduleNextSectionCountdown()
                } label: {
                    Label(String(localized: "Countdown"), systemImage: "timer")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(AppTheme.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                Button {
                    viewModel.cancelSectionCountdown()
                } label: {
                    Label(String(localized: "Cancel"), systemImage: "xmark")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(AppTheme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppTheme.textPrimary)

            QuickMessageBar(viewModel: viewModel, canSend: viewModel.canDriveSession)
        }
        .padding(14)
        .glassCard()
    }
}

struct AudienceLyricsDisplay: View {
    @Bindable var viewModel: SessionViewModel
    var guestTranspose: Int
    var guestCapo: Int

    var body: some View {
        VStack(spacing: 16) {
            if let chord = viewModel.activeChord {
                Text(chord.displayName(
                    for: viewModel.displayNotation(isGuest: true),
                    key: viewModel.payload.key
                ))
                .font(.system(size: 56, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.accent)
            }

            ScrollView {
                if !viewModel.payload.lyricsLines.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(viewModel.payload.lyricsLines) { line in
                            Text(line.text)
                                .font(.title3.weight(.medium))
                                .foregroundStyle(AppTheme.textPrimary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else if !viewModel.payload.lyrics.isEmpty {
                    Text(viewModel.payload.lyrics)
                        .font(.title3)
                        .foregroundStyle(AppTheme.textPrimary)
                        .multilineTextAlignment(.leading)
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Hub & tools

struct ExtendedFeaturesHubView: View {
    @Bindable var viewModel: SessionViewModel
    @Bindable var store: ProgressionStore
    @Environment(\.dismiss) private var dismiss

    @State private var showStats = false
    @State private var showChartDiff = false
    @State private var showPlanningCenter = false
    @State private var showTimeline = false
    @State private var showAdvancedHub = false
    @State private var leftProgressionID: UUID?
    @State private var rightProgressionID: UUID?

    var body: some View {
        NavigationStack {
            List {
                Section(String(localized: "Live tools")) {
                    hubButton(String(localized: "Director mode"), icon: "rectangle.inset.filled") {
                        viewModel.setDirectorMode()
                        dismiss()
                    }
                    hubButton(String(localized: "Audience / projector"), icon: "tv") {
                        viewModel.setAudienceMode()
                        dismiss()
                    }
                    hubButton(String(localized: "Acoustic / small group"), icon: "person.3") {
                        viewModel.setAcousticMode()
                        dismiss()
                    }
                    hubButton(String(localized: "Mark rehearsal mistake"), icon: "exclamationmark.triangle") {
                        viewModel.markRehearsalError()
                    }
                }

                Section(String(localized: "Planning")) {
                    Button {
                        showTimeline = true
                    } label: {
                        Label(String(localized: "Service timeline"), systemImage: "clock")
                    }
                    Button {
                        showPlanningCenter = true
                    } label: {
                        Label {
                            HStack {
                                Text(String(localized: "Import Planning Center"))
                                Spacer()
                                Text(String(localized: "Paste-only beta"))
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(AppTheme.textSecondary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(AppTheme.surfaceElevated)
                                    .clipShape(Capsule())
                            }
                        } icon: {
                            Image(systemName: "calendar")
                        }
                    }
                    Button {
                        showChartDiff = true
                    } label: {
                        Label(String(localized: "Compare chart versions"), systemImage: "doc.on.doc")
                    }
                }

                Section(String(localized: "History")) {
                    Button {
                        showStats = true
                    } label: {
                        Label(String(localized: "Service statistics"), systemImage: "chart.bar")
                    }
                    // Full audio analysis is not ready — keep discoverable but clearly gated.
                    Label {
                        HStack {
                            Text(String(localized: "Audio chord detection"))
                            Spacer()
                            Text(String(localized: "Coming soon"))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(AppTheme.textSecondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(AppTheme.surfaceElevated)
                                .clipShape(Capsule())
                        }
                    } icon: {
                        Image(systemName: "waveform")
                    }
                    .foregroundStyle(AppTheme.textSecondary)
                    .accessibilityLabel(String(localized: "Audio chord detection"))
                    .accessibilityValue(String(localized: "Coming soon"))

                    if let recording = RehearsalTimelineStore.shared.loadAll().first {
                        Button {
                            viewModel.startGhostBandReplay(recording)
                            dismiss()
                        } label: {
                            Label(String(localized: "Ghost band replay"), systemImage: "person.3.sequence")
                        }
                    }
                }

                Section(String(localized: "More")) {
                    Button {
                        showAdvancedHub = true
                    } label: {
                        Label(String(localized: "Advanced tools (25 features)"), systemImage: "sparkles")
                    }
                }

                Section(String(localized: "Team library")) {
                    ForEach(TeamLibraryStore.shared.loadAll()) { revision in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(revision.packName)
                                .font(.subheadline.weight(.semibold))
                            Text("\(revision.revisionLabel) · \(revision.songCount) songs")
                                .font(.caption)
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                    }
                }
            }
            .navigationTitle(String(localized: "Band Tools"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done")) { dismiss() }
                }
            }
            .sheet(isPresented: $showStats) {
                ServiceStatsView()
            }
            .sheet(isPresented: $showChartDiff) {
                ChartDiffSheet(store: store, leftID: $leftProgressionID, rightID: $rightProgressionID)
            }
            .sheet(isPresented: $showPlanningCenter) {
                PlanningCenterImportView(store: store, viewModel: viewModel)
            }
            .sheet(isPresented: $showTimeline) {
                ServiceTimelineSheet()
            }
            .sheet(isPresented: $showAdvancedHub) {
                AdvancedFeaturesHubView(viewModel: viewModel, store: store)
            }
        }
        .preferredColorScheme(.dark)
    }

    private func hubButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
        }
    }
}

struct ServiceStatsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var stats = ServiceStatsStore.shared.loadAll()

    var body: some View {
        NavigationStack {
            List(stats) { item in
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.sessionName)
                        .font(.headline)
                    Text(item.endedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                    Text(String(format: String(localized: "%lld songs · %lld cues · %.0f min"),
                                item.songsPlayed, item.cueCount, item.durationSeconds / 60))
                    .font(.caption)
                }
            }
            .navigationTitle(String(localized: "Service Stats"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done")) { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

struct ChartDiffSheet: View {
    @Bindable var store: ProgressionStore
    @Binding var leftID: UUID?
    @Binding var rightID: UUID?
    @Environment(\.dismiss) private var dismiss

    private var result: ChartDiffResult? {
        guard let leftID, let rightID,
              let left = store.progression(with: leftID),
              let right = store.progression(with: rightID) else { return nil }
        return ChartDiffEngine.compare(left, right)
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker(String(localized: "Saved chart"), selection: $leftID) {
                    Text("—").tag(Optional<UUID>.none)
                    ForEach(store.progressions) { p in
                        Text(p.name).tag(Optional(p.id))
                    }
                }
                Picker(String(localized: "Compare to"), selection: $rightID) {
                    Text("—").tag(Optional<UUID>.none)
                    ForEach(store.progressions) { p in
                        Text(p.name).tag(Optional(p.id))
                    }
                }
                if let result {
                    if result.hasDifferences {
                        ForEach(result.lines.filter { $0.kind != .same }) { line in
                            HStack {
                                Text(line.left)
                                Image(systemName: "arrow.right")
                                Text(line.right)
                            }
                            .font(.caption.monospaced())
                        }
                    } else {
                        Text(String(localized: "Charts match"))
                            .foregroundStyle(AppTheme.accent)
                    }
                }
            }
            .navigationTitle(String(localized: "Chart Diff"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done")) { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

struct PlanningCenterImportView: View {
    @Bindable var store: ProgressionStore
    @Bindable var viewModel: SessionViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var pastedText = ""
    @State private var apiURL = ""
    @State private var draft: PlanningCenterImportDraft?
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "Planning Center / ChurchApps API")) {
                    TextField(String(localized: "API URL"), text: $apiURL)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .autocorrectionDisabled()
                    Button(String(localized: "Fetch plan")) {
                        isLoading = true
                        Task {
                            draft = await viewModel.importPlanningCenterFromAPI(urlString: apiURL)
                            isLoading = false
                        }
                    }
                    .disabled(apiURL.trimmingCharacters(in: .whitespaces).isEmpty || isLoading)
                }

                Section(String(localized: "Paste plan (one song per line)")) {
                    TextEditor(text: $pastedText)
                        .frame(minHeight: 120)
                    Button(String(localized: "Parse")) {
                        draft = PlanningCenterImporter.importFromPlainText(pastedText)
                    }
                }
                if let draft {
                    Section(draft.planTitle) {
                        ForEach(draft.items) { item in
                            Text("\(item.sequence). \(item.title)")
                        }
                    }
                }
            }
            .navigationTitle(String(localized: "Planning Center"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done")) { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

struct ServiceTimelineSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var templates = ServiceTemplateStore.shared.load()
    @State private var editingTemplate: ServiceTemplate?

    var body: some View {
        NavigationStack {
            List(templates) { template in
                Section(template.name) {
                    if template.timelineBlocks.isEmpty {
                        Text(String(localized: "No timeline blocks yet"))
                            .font(.caption)
                            .foregroundStyle(AppTheme.textSecondary)
                    } else {
                        ForEach(template.timelineBlocks) { block in
                            HStack {
                                Text(block.title)
                                Spacer()
                                Text("+\(block.offsetMinutes)m · \(block.estimatedMinutes)m")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(AppTheme.textSecondary)
                            }
                        }
                    }
                    Button(String(localized: "Edit timeline")) {
                        editingTemplate = template
                    }
                    .font(.caption.weight(.semibold))
                }
            }
            .navigationTitle(String(localized: "Service Timeline"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done")) { dismiss() }
                }
            }
            .sheet(item: $editingTemplate) { template in
                ServiceTimelineEditorView(template: template) { updated in
                    ServiceTemplateStore.shared.save(updated)
                    templates = ServiceTemplateStore.shared.load()
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

struct SmartSetlistChecklistSection: View {
    let items: [SmartChecklistItem]

    var body: some View {
        if !items.isEmpty {
            Section(String(localized: "Setlist intelligence")) {
                ForEach(items) { item in
                    HStack(spacing: 12) {
                        Image(systemName: item.icon)
                            .foregroundStyle(color(for: item.severity))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(.subheadline.weight(.semibold))
                            Text(item.detail)
                                .font(.caption)
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                    }
                }
            }
        }
    }

    private func color(for severity: SmartChecklistSeverity) -> Color {
        switch severity {
        case .info: AppTheme.textSecondary
        case .warning: .orange
        case .critical: .red
        }
    }
}

struct VocalKeyPicker: View {
    @Bindable var viewModel: SessionViewModel

    var body: some View {
        Menu {
            ForEach(MusicalKey.allCases) { key in
                Button(key.displayName) {
                    viewModel.setVocalTargetKey(key)
                }
            }
        } label: {
            Label(
                viewModel.payload.vocalTargetKeyName ?? String(localized: "Vocal key"),
                systemImage: "music.note"
            )
            .font(.caption.weight(.semibold))
        }
    }
}

struct AudioChordDetectionSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "waveform.circle")
                    .font(.system(size: 48))
                    .foregroundStyle(AppTheme.accentSecondary)
                Text(AudioChordDetectionDraft.unavailable.note)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding()
            }
            .navigationTitle(String(localized: "Audio Chords"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done")) { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

extension SessionPerformanceMode {
    var usesCompactStageUI: Bool {
        self == .live || self == .acoustic
    }
}
