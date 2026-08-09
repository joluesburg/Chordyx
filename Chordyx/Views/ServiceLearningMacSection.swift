//
//  ServiceLearningMacSection.swift
//  Chordyx
//
//  UI for capturing and replaying church band grooves locally.
//

#if os(macOS) || os(iOS)
import SwiftUI
#if os(macOS)
import CoreAudio
#endif

struct ServiceLearningMacSection: View {
    @Bindable var viewModel: SessionViewModel
    @Bindable var progressionStore: ProgressionStore
    @State private var showLibrary = false
    @State private var profileNameDraft: String = ""

    private var recentRecords: [ServiceLearningRecord] {
        Array(
            viewModel.serviceLearningRecords
                .filter { $0.profileName == viewModel.serviceLearningProfileName }
                .prefix(4)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            Toggle(isOn: Binding(
                get: { viewModel.serviceLearningEnabled },
                set: { viewModel.setServiceLearningEnabled($0) }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "Learn from service"))
                        .font(.subheadline.weight(.semibold))
                    Text(String(localized: "Builds a local library of tempo, groove, and chords from how your church plays."))
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
            .toggleStyle(.switch)

            if viewModel.serviceLearningEnabled {
                profileField

                Toggle(isOn: Binding(
                    get: { viewModel.serviceLearningAutoSaveOnLock },
                    set: { viewModel.setServiceLearningAutoSaveOnLock($0) }
                )) {
                    Text(String(localized: "Auto-save when drums lock"))
                        .font(.caption.weight(.medium))
                }
                .toggleStyle(.switch)

                #if os(macOS)
                stemLearningSection
                #endif

                saveActions

                if let message = viewModel.lastServiceLearningSaveMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(AppTheme.accent)
                        .onAppear {
                            Task {
                                try? await Task.sleep(for: .seconds(4))
                                viewModel.clearServiceLearningStatusMessage()
                            }
                        }
                }

                if !recentRecords.isEmpty {
                    recentList
                }

                Button(String(localized: "Open church library…")) {
                    showLibrary = true
                }
                .buttonStyle(.borderless)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.accentSecondary)
            }
        }
        .padding(10)
        .background(AppTheme.accentSecondary.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onAppear {
            profileNameDraft = viewModel.serviceLearningProfileName
            viewModel.refreshServiceLearningLibrary()
            viewModel.refreshAudioInputDevices()
        }
        .sheet(isPresented: $showLibrary) {
            ServiceLearningLibrarySheet(
                viewModel: viewModel,
                progressionStore: progressionStore
            )
        }
    }

    private var header: some View {
        HStack {
            Label(String(localized: "Church library"), systemImage: "building.columns.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)
                .textCase(.uppercase)
            Spacer()
            Text("\(viewModel.serviceLearningRecords.count)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(AppTheme.textSecondary)
        }
    }

    private var profileField: some View {
        HStack(spacing: 8) {
            Text(String(localized: "Profile"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)
            TextField(String(localized: "My church"), text: $profileNameDraft)
                .textFieldStyle(.roundedBorder)
                .font(.caption)
                .onSubmit {
                    viewModel.serviceLearningProfileName = profileNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                .onChange(of: profileNameDraft) { _, newValue in
                    let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    viewModel.serviceLearningProfileName = trimmed
                }
        }
    }

    private var stemLearningSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: Binding(
                get: { viewModel.bandStemLearningEnabled },
                set: { viewModel.setBandStemLearningEnabled($0) }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "Learn from band sends"))
                        .font(.caption.weight(.semibold))
                    Text(String(localized: "Route drum and bass aux sends from your mixer — Chordyx learns their parts."))
                        .font(.caption2)
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
            .toggleStyle(.switch)

            if viewModel.bandStemLearningEnabled {
                stemDevicePicker(
                    title: String(localized: "Drum send"),
                    selection: Binding(
                        get: { viewModel.bandDrumInputDeviceID },
                        set: { viewModel.bandDrumInputDeviceID = $0 }
                    )
                )
                stemLevelRow(
                    label: String(localized: "Drums"),
                    level: viewModel.bandStemLearning.drumInputLevel,
                    count: viewModel.bandStemLearning.drumOnsetCount
                )

                stemDevicePicker(
                    title: String(localized: "Bass send"),
                    selection: Binding(
                        get: { viewModel.bandBassInputDeviceID },
                        set: { viewModel.bandBassInputDeviceID = $0 }
                    )
                )
                stemLevelRow(
                    label: String(localized: "Bass"),
                    level: viewModel.bandStemLearning.bassInputLevel,
                    count: viewModel.bandStemLearning.bassNoteCount
                )

                if viewModel.bandStemLearning.isLearning {
                    Text(String(localized: "Listening to band — save when drums lock to capture learned parts"))
                        .font(.caption2)
                        .foregroundStyle(AppTheme.accentSecondary)
                }
                if let error = viewModel.bandStemLearning.lastError {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(8)
        .background(AppTheme.surfaceElevated.opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func stemDevicePicker(title: String, selection: Binding<AudioInputDeviceID?>) -> some View {
        Picker(title, selection: selection) {
            Text(String(localized: "Not connected")).tag(Optional<AudioInputDeviceID>.none)
            ForEach(viewModel.availableAudioInputDevices) { device in
                Text(device.name).tag(Optional(device.id))
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
    }

    private func stemLevelRow(label: String, level: Float, count: Int) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(AppTheme.textSecondary)
                .frame(width: 44, alignment: .leading)
            ProgressView(value: Double(min(1, level * 10)))
                .tint(AppTheme.accent)
            Text("\(count)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(AppTheme.textSecondary)
        }
    }

    private var saveActions: some View {
        HStack(spacing: 8) {
            Button {
                _ = viewModel.saveServiceLearningSnapshot(source: .manual)
            } label: {
                Label(String(localized: "Save now"), systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(AppTheme.accentSecondary)
            .disabled(!viewModel.soloAccompanimentAvailable)

            if viewModel.soloTempoLocked {
                Text(String(localized: "Drums locked — good time to capture"))
                    .font(.caption2)
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
    }

    private var recentList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "Recent"))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)
                .textCase(.uppercase)

            ForEach(recentRecords) { record in
                ServiceLearningRecordRow(
                    record: record,
                    onUse: { viewModel.applyServiceLearningRecord(record) },
                    onDelete: { viewModel.deleteServiceLearningRecord(record.id) }
                )
            }
        }
    }
}

private struct ServiceLearningRecordRow: View {
    let record: ServiceLearningRecord
    let onUse: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(record.songTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1)
                Text("\(Int(record.tempoBPM)) BPM · \(record.bandSummary)")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(1)
                if !record.chordSymbols.isEmpty {
                    Text(record.chordSummary)
                        .font(.caption2)
                        .foregroundStyle(AppTheme.textSecondary.opacity(0.85))
                        .lineLimit(1)
                }
                Text(record.recordedAtLabel)
                    .font(.caption2)
                    .foregroundStyle(AppTheme.textSecondary.opacity(0.7))
            }
            Spacer(minLength: 0)
            VStack(spacing: 4) {
                Button(String(localized: "Use")) { onUse() }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                Button(role: .destructive) { onDelete() } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .controlSize(.mini)
            }
        }
        .padding(8)
        .background(AppTheme.surfaceElevated.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct ServiceLearningLibrarySheet: View {
    @Bindable var viewModel: SessionViewModel
    @Bindable var progressionStore: ProgressionStore
    @Environment(\.dismiss) private var dismiss

    private var filteredRecords: [ServiceLearningRecord] {
        viewModel.serviceLearningRecords.filter { $0.profileName == viewModel.serviceLearningProfileName }
    }

    var body: some View {
        NavigationStack {
            List {
                if filteredRecords.isEmpty {
                    ContentUnavailableView(
                        String(localized: "No saved grooves yet"),
                        systemImage: "building.columns",
                        description: Text(String(localized: "Enable Learn from service and play — snapshots save when drums lock or when you tap Save now."))
                    )
                } else {
                    ForEach(filteredRecords) { record in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(record.songTitle)
                                    .font(.headline)
                                Spacer()
                                Text("\(Int(record.tempoBPM)) BPM")
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundStyle(AppTheme.accent)
                            }
                            Text(record.bandSummary)
                                .font(.caption)
                                .foregroundStyle(AppTheme.textSecondary)
                            Text("\(record.drumPattern.label) · \(record.bassStyle.label) · \(record.autoBandMode.label)")
                                .font(.caption2)
                                .foregroundStyle(AppTheme.textSecondary.opacity(0.85))
                            if !record.chordSymbols.isEmpty {
                                Text(record.chordSymbols.joined(separator: " · "))
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.textSecondary)
                            }
                            Text(record.recordedAtLabel)
                                .font(.caption2)
                                .foregroundStyle(AppTheme.textSecondary.opacity(0.8))

                            HStack(spacing: 8) {
                                Button(String(localized: "Use in session")) {
                                    viewModel.applyServiceLearningRecord(record)
                                    dismiss()
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)

                                if !record.chords.isEmpty {
                                    Button(String(localized: "Add to library")) {
                                        viewModel.promoteServiceLearningToLibrary(record, store: progressionStore)
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }

                                Spacer()

                                Button(role: .destructive) {
                                    viewModel.deleteServiceLearningRecord(record.id)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                            }
                            .padding(.top, 4)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle(String(localized: "Church library"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Done")) { dismiss() }
                }
            }
        }
        .frame(minWidth: 480, minHeight: 420)
    }
}
#endif
