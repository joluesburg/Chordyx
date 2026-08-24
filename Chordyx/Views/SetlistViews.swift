//
//  SetlistViews.swift
//  Chordyx
//

import SwiftUI

struct SetlistEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: ProgressionStore
    @ObservedObject var viewModel: SessionViewModel

    @State private var name = ""
    @State private var selectedIDs: [UUID] = []
    var existing: Setlist?

    var body: some View {
        NavigationStack {
            Form {
                Section("Setlist Name") {
                    TextField("Name", text: $name)
                }
                Section("Songs (in order)") {
                    if store.progressions.isEmpty {
                        Text("Save progressions first.")
                            .foregroundStyle(AppTheme.textSecondary)
                    } else {
                        ForEach(store.sortedProgressions) { progression in
                            Button {
                                toggle(progression.id)
                            } label: {
                                HStack {
                                    Text(progression.name)
                                        .foregroundStyle(AppTheme.textPrimary)
                                    Spacer()
                                    if selectedIDs.contains(progression.id) {
                                        if let order = selectedIDs.firstIndex(of: progression.id) {
                                            Text("#\(order + 1)")
                                                .font(.caption.weight(.bold))
                                                .foregroundStyle(AppTheme.accent)
                                        }
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(AppTheme.accent)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .navigationTitle(existing == nil ? "New Setlist" : "Edit Setlist")
            .platformInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || selectedIDs.isEmpty)
                }
            }
            .onAppear {
                if let existing {
                    name = existing.name
                    selectedIDs = existing.progressionIDs
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func toggle(_ id: UUID) {
        if let index = selectedIDs.firstIndex(of: id) {
            selectedIDs.remove(at: index)
        } else {
            selectedIDs.append(id)
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let setlist = Setlist(
            id: existing?.id ?? UUID(),
            name: trimmed,
            progressionIDs: selectedIDs,
            savedAt: Date()
        )
        store.saveSetlist(setlist)
        dismiss()
    }
}

struct SetlistPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: ProgressionStore
    @ObservedObject var viewModel: SessionViewModel
    @State private var showEditor = false

    var body: some View {
        NavigationStack {
            List {
                if store.setlists.isEmpty {
                    ContentUnavailableView(
                        "No Setlists",
                        systemImage: "list.bullet.rectangle",
                        description: Text("Create a setlist to play multiple songs in one session.")
                    )
                } else {
                    ForEach(store.sortedSetlists) { setlist in
                        Button {
                            viewModel.hostSession(from: setlist, store: store)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(setlist.name)
                                    .foregroundStyle(AppTheme.textPrimary)
                                    .font(.headline)
                                Text("\(setlist.progressionIDs.count) songs")
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.textSecondary)
                            }
                        }
                        .listRowBackground(AppTheme.surface)
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            store.deleteSetlist(store.sortedSetlists[index])
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .navigationTitle("Setlists")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showEditor = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showEditor) {
                SetlistEditorView(store: store, viewModel: viewModel)
            }
        }
        .preferredColorScheme(.dark)
    }
}
