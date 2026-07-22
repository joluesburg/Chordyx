//
//  CreateProgressionView.swift
//  Chordyx
//

import SwiftUI

/// Build and save a chord progression from the library — no live session required.
struct CreateProgressionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.usesHomeDestinationShell) private var usesHomeDestinationShell
    @Bindable var viewModel: SessionViewModel
    @Bindable var store: ProgressionStore

    /// Called after Save & Host so the library sheet can close too.
    var onHosted: (() -> Void)? = nil

    @State private var name = ""
    @State private var key: MusicalKey = .C
    @State private var notation: ChordNotation = .symbol
    @State private var chords: [ChordEntry] = []
    @State private var showAddChord = false

    private var canSave: Bool { !chords.isEmpty }

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()

                Form {
                    Section("Progression") {
                        TextField("Name", text: $name)
                            .foregroundStyle(AppTheme.textPrimary)
                    }

                    Section("Musical Key") {
                        Picker("Key", selection: $key) {
                            ForEach(MusicalKey.allCases) { musicalKey in
                                Text(musicalKey.displayName).tag(musicalKey)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    Section("Chord Notation") {
                        Picker("Notation", selection: $notation) {
                            ForEach(ChordNotation.allCases) { item in
                                Text(item.label).tag(item)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    Section {
                        if chords.isEmpty {
                            VStack(spacing: 16) {
                                Text("Add chords to build your progression")
                                    .font(.subheadline)
                                    .foregroundStyle(AppTheme.textSecondary)
                                    .frame(maxWidth: .infinity, alignment: .center)

                                Button {
                                    showAddChord = true
                                } label: {
                                    Label("Add Chords", systemImage: "plus.circle.fill")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(AppTheme.background)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(AppTheme.accent)
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                            .listRowBackground(AppTheme.surface)
                        } else {
                            ForEach(chords) { chord in
                                HStack(spacing: 14) {
                                    Text("\(chord.order + 1)")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(AppTheme.textSecondary)
                                        .frame(width: 28, height: 28)
                                        .background(AppTheme.surfaceElevated)
                                        .clipShape(Circle())

                                    chord.chordText(for: notation, size: 17, weight: .semibold)
                                        .foregroundStyle(AppTheme.textPrimary)
                                }
                                .listRowBackground(AppTheme.surface)
                            }
                            .onDelete { offsets in
                                removeChords(at: offsets)
                            }
                        }
                    } header: {
                        HStack {
                            Text("Chords")
                            Spacer()
                            if !chords.isEmpty {
                                Text("\(chords.count)")
                                    .foregroundStyle(AppTheme.textSecondary)
                            }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("New Progression")
            .platformInlineNavigationTitle()
            .toolbar {
                if !usesHomeDestinationShell {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                            .foregroundStyle(AppTheme.accent)
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    if !chords.isEmpty {
                        HStack(spacing: 16) {
                            Button {
                                showAddChord = true
                            } label: {
                                Image(systemName: "plus")
                            }
                            .foregroundStyle(AppTheme.accent)

                            PlatformEditButton()
                                .foregroundStyle(AppTheme.accent)
                        }
                    } else {
                        Button {
                            showAddChord = true
                        } label: {
                            Image(systemName: "plus")
                        }
                        .foregroundStyle(AppTheme.accent)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 10) {
                    Button {
                        saveAndHost()
                    } label: {
                        Label("Save & Host Session", systemImage: "play.fill")
                            .font(.headline)
                            .foregroundStyle(AppTheme.background)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(canSave ? AppTheme.accent : AppTheme.surfaceElevated)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .disabled(!canSave)

                    Button {
                        save()
                        dismiss()
                    } label: {
                        Text("Save to Library")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(canSave ? AppTheme.textPrimary : AppTheme.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(AppTheme.surfaceElevated)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .disabled(!canSave)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(AppTheme.background.opacity(0.95))
            }
        }
        .sheet(isPresented: $showAddChord) {
            AddChordView(
                notation: notation,
                staysOpenUntilDone: true,
                progression: $chords
            )
        }
        .onAppear {
            if chords.isEmpty {
                showAddChord = true
            }
        }
        .preferredColorScheme(.dark)
    }

    private func addChord(symbolName: String, latinName: String) {
        let chord = ChordEntry(
            symbolName: symbolName,
            latinName: latinName,
            order: chords.count
        )
        chords.append(chord)
    }

    private func removeChords(at offsets: IndexSet) {
        chords.remove(atOffsets: offsets)
        reindexChords()
    }

    private func reindexChords() {
        chords = chords.enumerated().map { index, chord in
            ChordEntry(
                id: chord.id,
                symbolName: chord.symbolName,
                latinName: chord.latinName,
                order: index
            )
        }
    }

    @discardableResult
    private func save() -> SavedProgression {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmed.isEmpty ? L10n.untitledProgression : trimmed
        let progression = SavedProgression(
            name: finalName,
            key: key,
            notation: notation,
            chords: chords
        )
        store.save(progression)
        return progression
    }

    private func saveAndHost() {
        let progression = save()
        viewModel.hostSession(from: progression)
        dismiss()
        onHosted?()
    }
}
