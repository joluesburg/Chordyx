//
//  AdvancedFeatureViews.swift
//  Chordyx
//

import SwiftUI

// MARK: - Chord presence strip

struct ChordPresenceStrip: View {
    let presence: [String: PeerPresenceInfo]
    let activeChordID: UUID?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(presence.keys.sorted(), id: \.self) { name in
                    if let info = presence[name] {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(info.isOnCurrentChord ? Color.green : Color.orange)
                                .frame(width: 8, height: 8)
                            Text(name)
                                .font(.caption2.weight(.semibold))
                            Image(systemName: info.instrument.iconName)
                                .font(.caption2)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(AppTheme.surface)
                        .clipShape(Capsule())
                    }
                }
            }
        }
    }
}

private extension MusicianInstrument {
    var iconName: String {
        switch self {
        case .guitar: "guitars.fill"
        case .bass: "waveform.path"
        case .keys: "pianokeys"
        case .vocal: "music.mic"
        case .other: "person.fill"
        }
    }
}

// MARK: - Silent nudge pad

struct SilentNudgePad: View {
    @ObservedObject var viewModel: SessionViewModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SilentNudgeKind.allCases) { kind in
                    Button {
                        viewModel.sendSilentNudge(kind)
                    } label: {
                        Label(kind.label, systemImage: "hand.tap.fill")
                            .font(.caption.weight(.semibold))
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

// MARK: - Tempo ramp control

struct TempoRampControl: View {
    @ObservedObject var viewModel: SessionViewModel
    @State private var targetBPM: Double = 80
    @State private var bars: Double = 4

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "Tempo ramp"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)
            HStack {
                Text(String(format: String(localized: "→ %.0f BPM"), targetBPM))
                    .font(.caption.monospacedDigit())
                Slider(value: $targetBPM, in: 40...200, step: 1)
            }
            HStack {
                Text(String(format: String(localized: "over %lld bars"), Int(bars)))
                    .font(.caption.monospacedDigit())
                Slider(value: $bars, in: 1...8, step: 1)
            }
            HStack {
                Button(String(localized: "Start ramp")) {
                    viewModel.startTempoRamp(to: targetBPM, overBars: Int(bars))
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.accent)
                if viewModel.payload.tempoRampBarsRemaining > 0 {
                    Button(String(localized: "Cancel")) {
                        viewModel.cancelTempoRamp()
                    }
                    .buttonStyle(.bordered)
                }
            }
            .font(.caption)
        }
        .padding(12)
        .background(AppTheme.surface.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Click track lanes

struct ClickTrackLanePicker: View {
    @ObservedObject var viewModel: SessionViewModel
    let peerName: String

    var body: some View {
        Picker(String(localized: "Click track"), selection: binding) {
            ForEach(ClickTrackLane.allCases) { lane in
                Text(lane.label).tag(lane)
            }
        }
        .pickerStyle(.menu)
    }

    private var binding: Binding<ClickTrackLane> {
        Binding(
            get: {
                let raw = viewModel.payload.clickTrackLanes[peerName] ?? ClickTrackLane.full.rawValue
                return ClickTrackLane(rawValue: raw) ?? .full
            },
            set: { viewModel.setClickTrackLane($0, for: peerName) }
        )
    }
}

// MARK: - Readiness score

struct ReadinessScoreBanner: View {
    let report: ReadinessReport

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(String(localized: "Readiness"))
                    .font(.subheadline.weight(.bold))
                Spacer()
                Text("\(report.score)%")
                    .font(.title3.weight(.bold).monospacedDigit())
                    .foregroundStyle(colorForLevel)
                Text(report.level.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(colorForLevel)
            }
            ForEach(report.items) { item in
                HStack(spacing: 8) {
                    Image(systemName: item.isAutoSatisfied ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .foregroundStyle(item.isAutoSatisfied ? .green : .orange)
                        .font(.caption)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title).font(.caption.weight(.semibold))
                        Text(item.detail).font(.caption2).foregroundStyle(AppTheme.textSecondary)
                    }
                }
            }
        }
        .padding(12)
        .background(AppTheme.surface.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var colorForLevel: Color {
        switch report.level {
        case .ready: .green
        case .caution: .yellow
        case .notReady: .red
        }
    }
}

// MARK: - Voicing hint banner

struct VoicingHintBanner: View {
    let hint: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "lightbulb.fill")
                .foregroundStyle(AppTheme.accentSecondary)
            Text(hint)
                .font(.caption.weight(.medium))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.surface.opacity(0.8))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - Vocal range banner

struct VocalRangeBanner: View {
    let suggestion: VocalRangeSuggestion
    let onApply: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(suggestion.reason)
                    .font(.caption.weight(.semibold))
                Text(String(format: String(localized: "Try %@"), suggestion.suggestedKey.displayName))
                    .font(.caption2)
                    .foregroundStyle(AppTheme.textSecondary)
            }
            Spacer()
            Button(String(localized: "Apply"), action: onApply)
                .font(.caption.weight(.semibold))
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.accent)
        }
        .padding(12)
        .background(AppTheme.surface.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Congregation display

struct CongregationDisplayView: View {
    @ObservedObject var viewModel: SessionViewModel

    private var simpleChords: [String] {
        let symbols = viewModel.sortedChords.map(\.symbolName)
        return Array(Set(symbols)).sorted()
    }

    var body: some View {
        VStack(spacing: 24) {
            if let active = viewModel.activeChord {
                Text(active.symbolName)
                    .font(.system(size: 72, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.accent)
            }

            if let section = viewModel.activeSection {
                Text(section.name)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)
            }

            if !viewModel.payload.lyricsLines.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(viewModel.payload.lyricsLines) { line in
                            Text(line.text)
                                .font(.title3)
                                .foregroundStyle(AppTheme.textPrimary)
                        }
                    }
                    .padding()
                }
            }

            if !simpleChords.isEmpty {
                Text(String(localized: "Song chords"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)
                Text(simpleChords.joined(separator: " · "))
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            if let token = viewModel.payload.congregationJoinToken {
                Text(String(format: String(localized: "Join code: %@"), token))
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

// MARK: - AirPlay / external display guide

struct AirPlayAudienceGuide: View {
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(String(localized: "Audience display"), systemImage: "airplayvideo")
                .font(.caption.weight(.bold))
            Text(String(localized: "Use AirPlay or HDMI to mirror congregation mode to a projector. Enable congregation mode from Band Tools."))
                .font(.caption2)
                .foregroundStyle(AppTheme.textSecondary)
            Button(String(localized: "Got it"), action: onDismiss)
                .font(.caption.weight(.semibold))
        }
        .padding(12)
        .background(AppTheme.surface.opacity(0.8))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Practice queue

struct PracticeQueueView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var items: [PracticeQueueItem] = []

    var body: some View {
        NavigationStack {
            List {
                if items.isEmpty {
                    ContentUnavailableView(
                        String(localized: "No practice items"),
                        systemImage: "checkmark.circle",
                        description: Text(String(localized: "Mark mistakes during rehearsal recording to build your practice queue."))
                    )
                } else {
                    ForEach(items) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.recordingName).font(.headline)
                            if let song = item.songTitle {
                                Text(song).font(.subheadline).foregroundStyle(AppTheme.textSecondary)
                            }
                            Text(item.addedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(AppTheme.textSecondary)
                            if item.isResolved {
                                Label(String(localized: "Resolved"), systemImage: "checkmark")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            }
                        }
                        .swipeActions {
                            Button(String(localized: "Resolve")) {
                                PracticeQueueStore.shared.markResolved(item.id)
                                reload()
                            }
                            .tint(.green)
                        }
                    }
                }
            }
            .navigationTitle(String(localized: "Practice Queue"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done")) { dismiss() }
                }
            }
            .onAppear(perform: reload)
        }
        .preferredColorScheme(.dark)
    }

    private func reload() {
        items = PracticeQueueStore.shared.loadAll()
    }
}

// MARK: - Arrangement variants

struct ArrangementVariantsSheet: View {
    @ObservedObject var store: ProgressionStore
    let progressionID: UUID
    @ObservedObject var viewModel: SessionViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var newVariantName = ""

    private var progression: SavedProgression? {
        store.progressions.first { $0.id == progressionID }
    }

    var body: some View {
        NavigationStack {
            List {
                if let progression {
                    Section(String(localized: "Current")) {
                        Text(progression.name).font(.headline)
                        Text(progression.summary).font(.caption).foregroundStyle(AppTheme.textSecondary)
                    }

                    Section(String(localized: "Saved variants")) {
                        ForEach(progression.arrangementVariants) { variant in
                            Button {
                                viewModel.applyArrangementVariant(variant)
                                dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(variant.name).font(.subheadline.weight(.semibold))
                                    Text(variant.chords.map(\.symbolName).joined(separator: " · "))
                                        .font(.caption2)
                                        .foregroundStyle(AppTheme.textSecondary)
                                        .lineLimit(2)
                                }
                            }
                        }
                    }

                    Section(String(localized: "Save current as")) {
                        TextField(String(localized: "Variant name"), text: $newVariantName)
                        Button(String(localized: "Save variant")) {
                            guard var copy = store.progressions.first(where: { $0.id == progressionID }) else { return }
                            let name = newVariantName.isEmpty ? String(localized: "Variant") : newVariantName
                            viewModel.saveArrangementVariant(named: name, to: &copy)
                            store.save(copy)
                            newVariantName = ""
                        }
                        .disabled(newVariantName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .navigationTitle(String(localized: "Arrangements"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done")) { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Service timeline editor

struct ServiceTimelineEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var template: ServiceTemplate
    let onSave: (ServiceTemplate) -> Void

    init(template: ServiceTemplate, onSave: @escaping (ServiceTemplate) -> Void) {
        _template = State(initialValue: template)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach($template.timelineBlocks) { $block in
                    VStack(alignment: .leading, spacing: 8) {
                        TextField(String(localized: "Title"), text: $block.title)
                        Stepper(String(format: String(localized: "Starts +%lld min"), block.offsetMinutes), value: $block.offsetMinutes, in: 0...180)
                        Stepper(String(format: String(localized: "Duration %lld min"), block.estimatedMinutes), value: $block.estimatedMinutes, in: 1...60)
                    }
                }
                .onDelete { indices in
                    template.timelineBlocks.remove(atOffsets: indices)
                }

                Button {
                    let offset = (template.timelineBlocks.last?.offsetMinutes ?? 0)
                        + (template.timelineBlocks.last?.estimatedMinutes ?? 0)
                    template.timelineBlocks.append(ServiceTimelineBlock(
                        title: String(localized: "New block"),
                        offsetMinutes: offset,
                        estimatedMinutes: 10
                    ))
                } label: {
                    Label(String(localized: "Add block"), systemImage: "plus")
                }
            }
            .navigationTitle(String(localized: "Edit Timeline"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Save")) {
                        onSave(template)
                        dismiss()
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Team pack subscriptions

struct TeamPackSubscriptionsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var subscriptions: [TeamPackSubscription] = []

    var body: some View {
        NavigationStack {
            List {
                if subscriptions.isEmpty {
                    ContentUnavailableView(
                        String(localized: "No subscriptions"),
                        systemImage: "bell",
                        description: Text(String(localized: "Subscribe to team packs from the Team Library to get update notifications."))
                    )
                } else {
                    ForEach($subscriptions) { $sub in
                        Toggle(isOn: $sub.notifyOnUpdate) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(sub.packName).font(.headline)
                                Text(sub.teamName).font(.caption).foregroundStyle(AppTheme.textSecondary)
                                if !sub.lastRevisionLabel.isEmpty {
                                    Text(sub.lastRevisionLabel).font(.caption2)
                                }
                            }
                        }
                        .onChange(of: sub.notifyOnUpdate) { _, enabled in
                            TeamPackSubscriptionStore.shared.toggleNotifications(for: sub.id, enabled: enabled)
                        }
                    }
                }
            }
            .navigationTitle(String(localized: "Pack Subscriptions"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done")) { dismiss() }
                }
            }
            .onAppear {
                subscriptions = TeamPackSubscriptionStore.shared.loadAll()
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Chart delivery modes

struct ChartDeliveryAssignmentView: View {
    @ObservedObject var viewModel: SessionViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(viewModel.sessionManager.connectedPeerReferences) { peer in
                VStack(alignment: .leading, spacing: 8) {
                    Text(peer.displayName).font(.headline)
                    Picker(String(localized: "Chart view"), selection: binding(for: peer.displayName)) {
                        ForEach(ChartDeliveryMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    ClickTrackLanePicker(viewModel: viewModel, peerName: peer.displayName)
                }
            }
            .navigationTitle(String(localized: "Role Charts"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done")) { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func binding(for peerName: String) -> Binding<ChartDeliveryMode> {
        Binding(
            get: {
                let raw = viewModel.payload.chartDeliveryModes[peerName] ?? ChartDeliveryMode.full.rawValue
                return ChartDeliveryMode(rawValue: raw) ?? .full
            },
            set: { viewModel.setChartDeliveryMode($0, for: peerName) }
        )
    }
}

// MARK: - Stage layout presets

struct StageLayoutPresetsView: View {
    @ObservedObject var viewModel: SessionViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var presets: [StageLayoutPreset] = []

    var body: some View {
        NavigationStack {
            List(presets) { preset in
                Button {
                    viewModel.applyStageLayoutPreset(preset)
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(preset.name).font(.headline)
                        Text(preset.displayMode.label).font(.caption).foregroundStyle(AppTheme.textSecondary)
                    }
                }
            }
            .navigationTitle(String(localized: "Stage Layouts"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done")) { dismiss() }
                }
            }
            .onAppear {
                presets = StageLayoutStore.shared.loadAll()
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Sunday folder

struct SundayFolderView: View {
    @ObservedObject var store: ProgressionStore
    @ObservedObject var viewModel: SessionViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var entries: [SundayFolderEntry] = []

    var body: some View {
        NavigationStack {
            List {
                if entries.isEmpty {
                    ContentUnavailableView(
                        String(localized: "No offline folders"),
                        systemImage: "folder",
                        description: Text(String(localized: "Cache a setlist before Sunday for offline access."))
                    )
                } else {
                    ForEach(entries) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.setlistName).font(.headline)
                            Text(entry.songTitles.joined(separator: " · "))
                                .font(.caption)
                                .foregroundStyle(AppTheme.textSecondary)
                                .lineLimit(2)
                            Text(entry.cachedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption2)
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                    }
                    .onDelete { indices in
                        for index in indices {
                            SundayFolderStore.shared.remove(entries[index].id)
                        }
                        reload()
                    }
                }
            }
            .navigationTitle(String(localized: "Sunday Folder"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done")) { dismiss() }
                }
            }
            .onAppear(perform: reload)
        }
        .preferredColorScheme(.dark)
    }

    private func reload() {
        entries = SundayFolderStore.shared.loadAll()
    }
}

// MARK: - Weekly digest

struct WeeklyDigestView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: SessionViewModel
    @State private var digest: TeamDigestEntry?

    var body: some View {
        NavigationStack {
            Group {
                if let digest {
                    List {
                        Section(String(localized: "This week")) {
                            LabeledContent(String(localized: "Minutes"), value: String(format: "%.0f", digest.totalMinutes))
                            LabeledContent(String(localized: "Sessions"), value: "\(digest.sessionsHosted)")
                            LabeledContent(String(localized: "Songs played"), value: "\(digest.songsPlayed)")
                        }
                        if !digest.topHosts.isEmpty {
                            Section(String(localized: "Top sessions")) {
                                ForEach(digest.topHosts, id: \.self) { host in
                                    Text(host)
                                }
                            }
                        }
                    }
                } else {
                    ProgressView()
                }
            }
            .navigationTitle(String(localized: "Team Digest"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done")) { dismiss() }
                }
            }
            .onAppear {
                digest = viewModel.buildWeeklyDigest()
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Import quality coach

struct ImportQualityCoachView: View {
    let quality: SongImportQuality
    let tips: [ImportQualityCoachTip]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(quality.readiness.label, systemImage: quality.readiness.icon)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(quality.readiness == .ready ? .green : .orange)

            ForEach(tips) { tip in
                VStack(alignment: .leading, spacing: 4) {
                    Text(tip.title).font(.caption.weight(.semibold))
                    Text(tip.detail).font(.caption2).foregroundStyle(AppTheme.textSecondary)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppTheme.surface.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }
}

// MARK: - CarPlay rehearsal

struct CarPlayRehearsalView: View {
    let items: [CarPlayRehearsalItem]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(items) { item in
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title).font(.headline)
                    Text(item.chordSummary).font(.caption).foregroundStyle(AppTheme.textSecondary).lineLimit(2)
                    Text(String(format: String(localized: "%.0f BPM"), item.tempoBPM))
                        .font(.caption2).foregroundStyle(AppTheme.textSecondary)
                }
            }
            .navigationTitle(String(localized: "Commute Rehearsal"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done")) { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Advanced features hub (expanded)

struct AdvancedFeaturesHubView: View {
    @ObservedObject var viewModel: SessionViewModel
    @ObservedObject var store: ProgressionStore
    @Environment(\.dismiss) private var dismiss

    @State private var showPracticeQueue = false
    @State private var showTimelineEditor = false
    @State private var showSubscriptions = false
    @State private var showChartDelivery = false
    @State private var showStageLayouts = false
    @State private var showSundayFolder = false
    @State private var showDigest = false
    @State private var showCarPlay = false
    @State private var selectedTemplate: ServiceTemplate?

    var body: some View {
        NavigationStack {
            List {
                Section(String(localized: "Live performance")) {
                    hubRow(String(localized: "Congregation mode"), icon: "person.3.fill") {
                        viewModel.setCongregationMode(enabled: true)
                        dismiss()
                    }
                    hubRow(String(localized: "Lock section map"), icon: "lock.fill") {
                        viewModel.toggleSectionMapLock()
                    }
                    hubRow(String(localized: "Silent nudges"), icon: "hand.tap") {
                        viewModel.sendSilentNudge(.nextSection)
                    }
                    hubRow(String(localized: "Role chart delivery"), icon: "person.text.rectangle") {
                        showChartDelivery = true
                    }
                    hubRow(String(localized: "Voicing hints"), icon: "lightbulb") {
                        viewModel.setVoicingHintsEnabled(true)
                    }
                }

                Section(String(localized: "Rehearsal")) {
                    hubRow(String(localized: "Practice queue"), icon: "list.bullet.clipboard") {
                        showPracticeQueue = true
                    }
                    hubRow(String(localized: "Section loop count-in"), icon: "repeat.circle") {
                        viewModel.setSectionLoopCountInBars(1)
                    }
                }

                Section(String(localized: "Planning & team")) {
                    hubRow(String(localized: "Edit service timeline"), icon: "clock.badge.checkmark") {
                        selectedTemplate = ServiceTemplateStore.shared.load().first
                        showTimelineEditor = true
                    }
                    hubRow(String(localized: "Pack subscriptions"), icon: "bell.badge") {
                        showSubscriptions = true
                    }
                    hubRow(String(localized: "Sunday folder (offline)"), icon: "folder.fill") {
                        showSundayFolder = true
                    }
                    hubRow(String(localized: "Weekly team digest"), icon: "envelope") {
                        showDigest = true
                    }
                }

                Section(String(localized: "Hardware & display")) {
                    hubRow(String(localized: "Stage Manager layouts"), icon: "macwindow.on.rectangle") {
                        showStageLayouts = true
                    }
                    hubRow(String(localized: "AirPlay audience"), icon: "airplayvideo") {
                        viewModel.setAudienceMode()
                        dismiss()
                    }
                    hubRow(String(localized: "CarPlay rehearsal"), icon: "car.fill") {
                        showCarPlay = true
                    }
                }

                Section(String(localized: "Tempo & click")) {
                    TempoRampControl(viewModel: viewModel)
                        .listRowBackground(Color.clear)
                }
            }
            .navigationTitle(String(localized: "Advanced Tools"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done")) { dismiss() }
                }
            }
            .sheet(isPresented: $showPracticeQueue) { PracticeQueueView() }
            .sheet(isPresented: $showTimelineEditor) {
                if let template = selectedTemplate {
                    ServiceTimelineEditorView(template: template) { updated in
                        ServiceTemplateStore.shared.save(updated)
                    }
                }
            }
            .sheet(isPresented: $showSubscriptions) { TeamPackSubscriptionsView() }
            .sheet(isPresented: $showChartDelivery) { ChartDeliveryAssignmentView(viewModel: viewModel) }
            .sheet(isPresented: $showStageLayouts) { StageLayoutPresetsView(viewModel: viewModel) }
            .sheet(isPresented: $showSundayFolder) { SundayFolderView(store: store, viewModel: viewModel) }
            .sheet(isPresented: $showDigest) { WeeklyDigestView(viewModel: viewModel) }
            .sheet(isPresented: $showCarPlay) {
                CarPlayRehearsalView(items: viewModel.carPlayRehearsalItems(from: store, progressionIDs: store.progressions.map(\.id)))
            }
        }
        .preferredColorScheme(.dark)
    }

    private func hubRow(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
        }
    }
}

// MARK: - Live section roadmap (enhanced section map)

struct LiveSectionRoadmap: View {
    let sections: [SectionMarker]
    let chords: [ChordEntry]
    let activeSectionID: UUID?
    let isLocked: Bool
    var onJump: (SectionMarker) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(String(localized: "Song roadmap"))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.textSecondary)
                if isLocked {
                    Label(String(localized: "Locked"), systemImage: "lock.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
            SectionMapView(
                sections: sections,
                chords: chords,
                activeSectionID: activeSectionID,
                onJump: { section in
                    guard !isLocked else { return }
                    onJump(section)
                }
            )
        }
    }
}
