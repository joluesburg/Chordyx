//
//  FeatureViews.swift
//  Chordyx
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Section map

struct SectionMapView: View {
    let sections: [SectionMarker]
    let chords: [ChordEntry]
    let activeSectionID: UUID?
    var onJump: (SectionMarker) -> Void

    private var sortedChords: [ChordEntry] {
        chords.sorted { $0.order < $1.order }
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(sectionsInOrder) { section in
                    Button {
                        onJump(section)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Label(section.name, systemImage: section.kind.icon)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(activeSectionID == section.id ? AppTheme.background : AppTheme.accent)
                            Text(chordSymbols(for: section))
                                .font(.caption2.monospaced())
                                .foregroundStyle(activeSectionID == section.id ? AppTheme.background.opacity(0.85) : AppTheme.textSecondary)
                                .lineLimit(2)
                        }
                        .padding(10)
                        .background(activeSectionID == section.id ? AppTheme.accent : AppTheme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 4)
        }
    }

    private var sectionsInOrder: [SectionMarker] {
        sections.sorted { lhs, rhs in
            let li = sortedChords.firstIndex(where: { $0.id == lhs.startChordID }) ?? 0
            let ri = sortedChords.firstIndex(where: { $0.id == rhs.startChordID }) ?? 0
            return li < ri
        }
    }

    private func chordSymbols(for section: SectionMarker) -> String {
        guard let start = sortedChords.firstIndex(where: { $0.id == section.startChordID }) else { return "" }
        let end: Int
        if let sectionIndex = sectionsInOrder.firstIndex(where: { $0.id == section.id }),
           sectionIndex + 1 < sectionsInOrder.count,
           let nextStart = sortedChords.firstIndex(where: { $0.id == sectionsInOrder[sectionIndex + 1].startChordID }) {
            end = nextStart
        } else {
            end = sortedChords.count
        }
        return sortedChords[start..<end].map(\.symbolName).joined(separator: " · ")
    }
}

// MARK: - Piano mismatch

struct PianoChartMismatchBanner: View {
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "pianokeys")
            Text(message)
                .font(.caption.weight(.medium))
        }
        .foregroundStyle(.orange)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.15))
        .clipShape(Capsule())
    }
}

// MARK: - Guest role assignment (host)

struct GuestRoleAssignmentView: View {
    @ObservedObject var viewModel: SessionViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if viewModel.sessionManager.connectedPeerReferences.isEmpty {
                    Text(String(localized: "Waiting for musicians to connect…"))
                        .foregroundStyle(AppTheme.textSecondary)
                } else {
                    ForEach(viewModel.sessionManager.connectedPeerReferences) { peer in
                        HStack {
                            Text(peer.displayName)
                            Spacer()
                            PlatformPopoverOptionPicker(
                                selection: binding(for: peer.displayName),
                                options: GuestViewRole.allCases.map { ($0, $0.label) },
                                arrowEdge: .bottom,
                                minWidth: 200
                            ) {
                                HStack(spacing: 6) {
                                    Text(binding(for: peer.displayName).wrappedValue.label)
                                        .foregroundStyle(AppTheme.textSecondary)
                                    PlatformDropdownChevron()
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(String(localized: "Role Presets"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done")) { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func binding(for peerName: String) -> Binding<GuestViewRole> {
        Binding(
            get: { viewModel.hostAssignedRole(for: peerName) ?? .auto },
            set: { viewModel.assignGuestRolePreset($0, to: peerName) }
        )
    }
}

// MARK: - Service templates

struct ServiceTemplatePickerView: View {
    @ObservedObject var store: ProgressionStore
    var onSelect: (ServiceTemplate) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var templates: [ServiceTemplate] = []

    var body: some View {
        NavigationStack {
            Group {
                if templates.isEmpty {
                    ContentUnavailableView {
                        Label(String(localized: "No Templates"), systemImage: "list.bullet.rectangle")
                    } description: {
                        Text(String(localized: "Built-in worship templates should appear here. Try restarting the app if this stays empty."))
                    }
                } else {
                    List(templates) { template in
                        Button {
                            onSelect(template)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(template.name)
                                    .font(.headline)
                                    .foregroundStyle(AppTheme.textPrimary)
                                Text("\(template.performanceMode.label) · \(Int(template.defaultTempoBPM)) BPM · \(template.countInBars) bar count-in")
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.textSecondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(AppTheme.surface.opacity(0.35))
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppTheme.background)
            .navigationTitle(String(localized: "Service Templates"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
            }
        }
        .onAppear {
            templates = ServiceTemplateStore.shared.ensureLoaded()
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Practice stats

struct PracticeStatsView: View {
    @Environment(\.dismiss) private var dismiss
    private let summary = PracticeStatsStore.shared.load()

    var body: some View {
        NavigationStack {
            List {
                Section(String(localized: "Overview")) {
                    LabeledContent(String(localized: "Total practice time")) {
                        Text(String(format: "%.0f min", summary.totalMinutes))
                    }
                    LabeledContent(String(localized: "Songs played")) {
                        Text("\(summary.totalSongs)")
                    }
                    LabeledContent(String(localized: "Sessions")) {
                        Text("\(summary.sessions.count)")
                    }
                }
                Section(String(localized: "Recent")) {
                    ForEach(summary.sessions.prefix(20)) { session in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(session.sessionName)
                                .font(.headline)
                            Text(session.date.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(AppTheme.textSecondary)
                            Text(String(format: String(localized: "%lld min · %lld songs"), Int(session.durationSeconds / 60), session.songsPlayed))
                                .font(.caption2)
                        }
                    }
                }
            }
            .navigationTitle(String(localized: "Practice Stats"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done")) { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Rehearsal recordings

struct RehearsalRecordingsView: View {
    @ObservedObject var viewModel: SessionViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var recordings = RehearsalTimelineStore.shared.loadAll()

    var body: some View {
        NavigationStack {
            List {
                if recordings.isEmpty {
                    Text(String(localized: "Record a rehearsal from the session menu to replay it later."))
                        .foregroundStyle(AppTheme.textSecondary)
                } else {
                    ForEach(recordings) { recording in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(recording.name)
                                    .font(.headline)
                                Text(recording.recordedAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.textSecondary)
                            }
                            Spacer()
                            Button(String(localized: "Replay")) {
                                viewModel.replayRecording(recording)
                                dismiss()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            RehearsalTimelineStore.shared.delete(recordings[index].id)
                        }
                        recordings = RehearsalTimelineStore.shared.loadAll()
                    }
                }
            }
            .navigationTitle(String(localized: "Rehearsal Timeline"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done")) { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Session feature menu (host)

struct SessionFeaturesMenu: View {
    @ObservedObject var viewModel: SessionViewModel
    @Binding var showGuestRoles: Bool
    @Binding var showRehearsalList: Bool
    @Binding var showJoinQR: Bool
    @Binding var showExtendedFeaturesHub: Bool
    @Binding var showAdvancedFeaturesHub: Bool
    var showBandChat: Binding<Bool>? = nil

    var body: some View {
        Menu {
            if let showBandChat {
                Button {
                    showBandChat.wrappedValue = true
                } label: {
                    Label(String(localized: "Band chat"), systemImage: "bubble.left.and.bubble.right.fill")
                }
            }

            Button {
                showExtendedFeaturesHub = true
            } label: {
                Label(String(localized: "Band tools hub"), systemImage: "square.grid.2x2")
            }

            Button {
                showAdvancedFeaturesHub = true
            } label: {
                Label(String(localized: "Advanced tools"), systemImage: "sparkles")
            }

            Button {
                viewModel.setDirectorMode()
            } label: {
                Label(String(localized: "Director mode"), systemImage: "rectangle.inset.filled")
            }

            Button {
                viewModel.setAudienceMode()
            } label: {
                Label(String(localized: "Audience display"), systemImage: "tv")
            }

            Button {
                viewModel.toggleRehearsalRecording()
            } label: {
                Label(
                    viewModel.isRecordingRehearsal
                        ? String(localized: "Stop Recording")
                        : String(localized: "Record Rehearsal"),
                    systemImage: viewModel.isRecordingRehearsal ? "stop.circle" : "record.circle"
                )
            }

            Button {
                showRehearsalList = true
            } label: {
                Label(String(localized: "Replay Recordings"), systemImage: "play.rectangle.on.rectangle")
            }

            Button {
                showGuestRoles = true
            } label: {
                Label(String(localized: "Assign Role Presets"), systemImage: "person.3")
            }

            Button {
                viewModel.toggleStageDisplayOnly()
            } label: {
                Label(
                    viewModel.payload.isStageDisplayOnly
                        ? String(localized: "Exit Stage Display")
                        : String(localized: "Stage Display Mode"),
                    systemImage: "tv"
                )
            }

            if viewModel.payload.remoteJoinCode != nil, viewModel.payload.isRemoteBackupEnabled {
                if let code = viewModel.payload.remoteJoinCode {
                    Button {
                        RemoteJoinCode.copyToClipboard(code)
                    } label: {
                        Label(String(localized: "Copy Join Code"), systemImage: "doc.on.doc")
                    }
                }
                Button {
                    showJoinQR = true
                } label: {
                    Label(String(localized: "Show Join QR"), systemImage: "qrcode")
                }
            }

            Button {
                viewModel.toggleMIDICueOut(!viewModel.payload.isMIDICueOutEnabled)
            } label: {
                Label(
                    viewModel.payload.isMIDICueOutEnabled
                        ? String(localized: "MIDI Cues On")
                        : String(localized: "MIDI Cues Off"),
                    systemImage: "pianokeys.inverse"
                )
            }

            if let peer = viewModel.sessionManager.connectedPeerReferences.first {
                Button {
                    viewModel.requestHostHandoff(to: peer)
                } label: {
                    Label(String(localized: "Offer Host Handoff"), systemImage: "arrow.triangle.2.circlepath")
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(AppTheme.textPrimary)
        }
        .accessibilityLabel(String(localized: "Session features"))
    }
}

// MARK: - Setlist export

struct SetlistExportSheet: View {
    let setlist: Setlist
    @ObservedObject var store: ProgressionStore
    @Environment(\.dismiss) private var dismiss
    @State private var exportURL: URL?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text(String(localized: "Export an offline pack your band can import before service — useful when Wi‑Fi is uncertain."))
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                if let exportURL {
                    ShareLink(item: exportURL) {
                        Label(String(localized: "Share Setlist Pack"), systemImage: "square.and.arrow.up")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(AppTheme.accent)
                            .foregroundStyle(AppTheme.background)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .padding(.horizontal)
                }
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red).font(.caption)
                }
                Spacer()
            }
            .padding(.top, 24)
            .navigationTitle(String(localized: "Offline Pack"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done")) { dismiss() }
                }
            }
            .onAppear(perform: prepareExport)
        }
        .preferredColorScheme(.dark)
    }

    private func prepareExport() {
        do {
            let data = try store.exportPack(setlist: setlist)
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(setlist.name.replacingOccurrences(of: " ", with: "_")).chordyxpack")
            try data.write(to: url)
            exportURL = url
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Stage display shell (projector)

struct StageDisplayShellView: View {
    @ObservedObject var viewModel: SessionViewModel
    let isGuest: Bool

    var body: some View {
        StageDisplayView(viewModel: viewModel, isGuest: isGuest, nowOnlyFocus: true)
            .ignoresSafeArea()
    }
}

#if os(iOS)
struct MetronomeRouteToggle: View {
    @ObservedObject var metronome: MetronomeEngine

    var body: some View {
        Toggle(String(localized: "Headphone click"), isOn: Binding(
            get: { metronome.preferHeadphoneOutput },
            set: { metronome.preferHeadphoneOutput = $0 }
        ))
    }
}
#endif
