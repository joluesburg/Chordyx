//
//  ProgressionEditorView.swift
//  Chordyx
//

import SwiftUI

/// Full progression list for the host — review order, jump to a chord, or remove
/// mistakes without cluttering the live performance screen.
struct ProgressionEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: SessionViewModel
    @State private var showAddChord = false

    private var chords: [ChordEntry] { viewModel.sortedChords }

    private var progressionBinding: Binding<[ChordEntry]> {
        Binding(
            get: { viewModel.sortedChords },
            set: { viewModel.updateProgressionChords($0) }
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()

                if chords.isEmpty {
                    VStack(spacing: 20) {
                        ContentUnavailableView(
                            "No Chords Yet",
                            systemImage: "music.note.list",
                            description: Text("Add chords here, then tap any chord to make it live.")
                        )
                        .foregroundStyle(AppTheme.textSecondary)

                        Button {
                            showAddChord = true
                        } label: {
                            Label("Add Chords", systemImage: "plus.circle.fill")
                                .font(.headline)
                                .foregroundStyle(AppTheme.background)
                                .frame(maxWidth: 280)
                                .padding(.vertical, 14)
                                .background(AppTheme.accent)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }
                } else {
                    List {
                        ForEach(chords) { chord in
                            let isActive = chord.id == viewModel.payload.activeChordID
                            Button {
                                viewModel.setActiveChord(chord)
                            } label: {
                                HStack(spacing: 14) {
                                    Text("\(chord.order + 1)")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(isActive ? AppTheme.background : AppTheme.textSecondary)
                                        .frame(width: 28, height: 28)
                                        .background(isActive ? AppTheme.accent : AppTheme.surfaceElevated)
                                        .clipShape(Circle())

                                    chord.chordText(for: viewModel.payload.notation, size: 17, weight: .semibold)
                                        .foregroundStyle(AppTheme.textPrimary)

                                    Spacer()

                                    if isActive {
                                        Label("Live", systemImage: "dot.radiowaves.left.and.right")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(AppTheme.accent)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                            .listRowBackground(AppTheme.surface)
                        }
                        .onDelete { offsets in
                            for index in offsets {
                                viewModel.removeChord(chords[index])
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Edit Progression")
            .platformInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(AppTheme.accent)
                }
                ToolbarItem(placement: .primaryAction) {
                    if chords.isEmpty {
                        Button {
                            showAddChord = true
                        } label: {
                            Image(systemName: "plus")
                        }
                        .foregroundStyle(AppTheme.accent)
                    } else {
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
                    }
                }
            }
        }
        .sheet(isPresented: $showAddChord) {
            AddChordView(
                notation: viewModel.payload.notation,
                staysOpenUntilDone: true,
                progression: progressionBinding
            )
        }
        .onAppear {
            if chords.isEmpty {
                showAddChord = true
            }
        }
        .preferredColorScheme(.dark)
    }
}
