//
//  ProgressionLibraryView.swift
//  Chordyx
//

import SwiftUI
import UniformTypeIdentifiers

struct ProgressionLibraryView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: SessionViewModel
    @Bindable var store: ProgressionStore

    @State private var renameTarget: SavedProgression?
    @State private var renameText = ""
    @State private var showCreateProgression = false
    @State private var showSetlistEditor = false
    @State private var showImportPicker = false
    @State private var showSongImport = false
    @State private var importError: String?
    @State private var qrShareProgression: SavedProgression?
    @AppStorage("iCloudBackupEnabled") private var iCloudBackupEnabled = false

    var body: some View {
        NavigationStack {
            Group {
                if store.progressions.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(store.sortedProgressions) { progression in
                            Button {
                                viewModel.hostSession(from: progression)
                                dismiss()
                            } label: {
                                progressionRow(progression)
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(AppTheme.surface)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    store.delete(progression)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                Button {
                                    renameTarget = progression
                                    renameText = progression.name
                                } label: {
                                    Label("Rename", systemImage: "pencil")
                                }
                                .tint(AppTheme.accentSecondary)
                            }
                            .swipeActions(edge: .leading) {
                                Button {
                                    store.duplicate(progression)
                                } label: {
                                    Label("Duplicate", systemImage: "plus.square.on.square")
                                }
                                .tint(AppTheme.accent)
                            }
                            .contextMenu {
                                Button {
                                    qrShareProgression = progression
                                } label: {
                                    Label("Share QR / AirDrop", systemImage: "qrcode")
                                }
                                ShareLink(
                                    item: exportURL(for: progression),
                                    preview: SharePreview(progression.name)
                                )
                                Button {
                                    viewModel.startPractice(from: progression)
                                    dismiss()
                                } label: {
                                    Label("Practice", systemImage: "metronome")
                                }
                                Button {
                                    viewModel.hostSession(from: progression)
                                    dismiss()
                                } label: {
                                    Label("Host This Progression", systemImage: "play.fill")
                                }
                                Button {
                                    store.duplicate(progression)
                                } label: {
                                    Label("Duplicate", systemImage: "plus.square.on.square")
                                }
                                Button {
                                    renameTarget = progression
                                    renameText = progression.name
                                } label: {
                                    Label("Rename", systemImage: "pencil")
                                }
                                Button(role: .destructive) {
                                    store.delete(progression)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                    #if os(macOS)
                    .listStyle(.inset)
                    #endif
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppTheme.background)
            .navigationTitle("My Progressions")
            .platformInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(AppTheme.accent)
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            showCreateProgression = true
                        } label: {
                            Label("New Progression", systemImage: "plus")
                        }
                        Button {
                            showSetlistEditor = true
                        } label: {
                            Label("New Setlist", systemImage: "list.bullet.rectangle")
                        }
                        Toggle("iCloud Backup", isOn: $iCloudBackupEnabled)
                            .onChange(of: iCloudBackupEnabled) { _, enabled in
                                store.iCloudBackupEnabled = enabled
                            }
                        Button {
                            showSongImport = true
                        } label: {
                            Label("Import from Web or Camera", systemImage: "arrow.down.doc.fill")
                        }
                        Button {
                            showImportPicker = true
                        } label: {
                            Label("Import File", systemImage: "square.and.arrow.down")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .foregroundStyle(AppTheme.accent)
                }
            }
            .onAppear {
                iCloudBackupEnabled = store.iCloudBackupEnabled
            }
            .sheet(isPresented: $showSetlistEditor) {
                SetlistEditorView(store: store, viewModel: viewModel)
            }
            .sheet(isPresented: $showSongImport) {
                SongImportView(viewModel: viewModel, store: store)
            }
            .fileImporter(isPresented: $showImportPicker, allowedContentTypes: [.json, .chordyxProgression, .chordyxPack]) { result in
                switch result {
                case .success(let url):
                    if url.startAccessingSecurityScopedResource() {
                        defer { url.stopAccessingSecurityScopedResource() }
                        if let data = try? Data(contentsOf: url) {
                            do {
                                if (try? store.importPack(from: data)) != nil {
                                    return
                                }
                                _ = try store.importProgression(from: data)
                            } catch {
                                importError = error.localizedDescription
                            }
                        }
                    }
                case .failure(let error):
                    importError = error.localizedDescription
                }
            }
            .alert("Import Failed", isPresented: Binding(
                get: { importError != nil },
                set: { if !$0 { importError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(importError ?? "")
            }
            .sheet(isPresented: $showCreateProgression) {
                CreateProgressionView(viewModel: viewModel, store: store) {
                    showCreateProgression = false
                    dismiss()
                }
            }
            .sheet(item: $qrShareProgression) { progression in
                if let data = try? store.exportData(for: progression) {
                    ProgressionQRShareSheet(title: progression.name, payloadData: data)
                }
            }
            .alert("Rename Progression", isPresented: Binding(
                get: { renameTarget != nil },
                set: { if !$0 { renameTarget = nil } }
            )) {
                TextField("Name", text: $renameText)
                Button("Cancel", role: .cancel) { renameTarget = nil }
                Button("Save") {
                    if let target = renameTarget {
                        let trimmed = renameText.trimmingCharacters(in: .whitespaces)
                        if !trimmed.isEmpty {
                            store.rename(target, to: trimmed)
                        }
                    }
                    renameTarget = nil
                }
            }
        }
        .preferredColorScheme(.dark)
        .platformLibrarySheetFrame()
    }

    private func exportURL(for progression: SavedProgression) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(progression.name).chordyx.json")
        if let data = try? store.exportData(for: progression) {
            try? data.write(to: url)
        }
        return url
    }

    private func progressionRow(_ progression: SavedProgression) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(AppTheme.surfaceElevated)
                    .frame(width: 46, height: 46)
                Text("\(progression.chords.count)")
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .foregroundStyle(AppTheme.accent)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(progression.name)
                    .font(.headline)
                    .foregroundStyle(AppTheme.textPrimary)

                Text(progression.summary.isEmpty ? "Empty progression" : progression.summary)
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Label(progression.key.displayName, systemImage: "key.fill")
                    Text("·")
                    Text(progression.notation.label)
                }
                .font(.caption2)
                .foregroundStyle(AppTheme.textSecondary.opacity(0.8))
            }

            Spacer()

            Image(systemName: "play.circle.fill")
                .font(.title2)
                .foregroundStyle(AppTheme.accent)
        }
        .padding(.vertical, 6)
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "bookmark.slash")
                .font(.system(size: 44))
                .foregroundStyle(AppTheme.textSecondary)

            Text("No saved progressions yet")
                .font(.headline)
                .foregroundStyle(AppTheme.textPrimary)

            Text("Create a progression here, or save one from a live session.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button {
                showCreateProgression = true
            } label: {
                Label("Create Progression", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .foregroundStyle(AppTheme.background)
                    .frame(maxWidth: 280)
                    .padding(.vertical, 14)
                    .background(AppTheme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }
}
