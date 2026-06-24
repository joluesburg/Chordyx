//
//  AddChordView.swift
//  Chordyx
//

import SwiftUI

struct AddChordView: View {
    @Environment(\.dismiss) private var dismiss

    let notation: ChordNotation
    /// When true, each tap adds a chord but keeps this screen open until Done.
    var staysOpenUntilDone: Bool = false
    /// Live progression while adding — supports add and delete without leaving this screen.
    var progression: Binding<[ChordEntry]>? = nil
    var onAdd: (String, String) -> Void = { _, _ in }

    @State private var searchText = ""
    @State private var customSymbol = ""

    private var currentChords: [ChordEntry] {
        progression?.wrappedValue ?? []
    }

    private var progressionCountLabel: String {
        let count = currentChords.count
        return count == 1 ? "1 chord in progression" : "\(count) chords in progression"
    }

    private var filteredChords: [(symbol: String, latin: String)] {
        let catalog = ChordCatalog.chords(for: notation)
        guard !searchText.isEmpty else { return catalog }
        return catalog.filter {
            $0.symbol.localizedCaseInsensitiveContains(searchText) ||
            $0.latin.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        notationBanner

                        customEntrySection(
                            title: "Custom Chord",
                            placeholder: notation == .symbol ? "e.g. C#m7" : "e.g. Do#m7 (type C#m7)",
                            text: $customSymbol,
                            actionLabel: staysOpenUntilDone ? "Add" : "Add Chord"
                        ) {
                            let trimmed = customSymbol.trimmingCharacters(in: .whitespaces)
                            guard !trimmed.isEmpty else { return }
                            addChord(trimmed, ChordCatalog.latinName(forSymbol: trimmed))
                            customSymbol = ""
                        }

                        Text("Quick Pick")
                            .font(.headline)
                            .foregroundStyle(AppTheme.textPrimary)

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 12)], spacing: 12) {
                            ForEach(filteredChords, id: \.symbol) { item in
                                Button {
                                    addChord(item.symbol, item.latin)
                                } label: {
                                    SolfegeChordText.make(
                                        notation == .symbol ? item.symbol : item.latin,
                                        notation: notation,
                                        size: 17,
                                        weight: .semibold
                                    )
                                    .foregroundStyle(AppTheme.textPrimary)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 14)
                                        .background(AppTheme.surfaceElevated)
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                }
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle(staysOpenUntilDone ? "Add Chords" : "Add Chord")
            .platformInlineNavigationTitle()
            .searchable(text: $searchText, prompt: "Search chords")
            .safeAreaInset(edge: .top, spacing: 0) {
                if staysOpenUntilDone {
                    progressionPreviewBar
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(AppTheme.accent)
                }
                if staysOpenUntilDone {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                            .fontWeight(.semibold)
                            .foregroundStyle(AppTheme.accent)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if staysOpenUntilDone {
                    VStack(spacing: 6) {
                        if !currentChords.isEmpty {
                            Text(progressionCountLabel)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                        Button {
                            dismiss()
                        } label: {
                            Text(currentChords.isEmpty ? "Done" : "Done Adding Chords")
                                .font(.headline)
                                .foregroundStyle(AppTheme.background)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(AppTheme.accent)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(AppTheme.background.opacity(0.95))
                }
            }
            .platformToolbarBackground(AppTheme.surface)
        }
        .preferredColorScheme(.dark)
    }

    private func addChord(_ symbol: String, _ latin: String) {
        if let progression {
            let entry = ChordEntry(
                symbolName: symbol,
                latinName: latin,
                order: progression.wrappedValue.count
            )
            progression.wrappedValue.append(entry)
        } else {
            onAdd(symbol, latin)
        }
        if !staysOpenUntilDone {
            dismiss()
        }
    }

    private func removeChord(at index: Int) {
        guard let progression, progression.wrappedValue.indices.contains(index) else { return }
        var updated = progression.wrappedValue
        updated.remove(at: index)
        progression.wrappedValue = reindexed(updated)
    }

    private func reindexed(_ chords: [ChordEntry]) -> [ChordEntry] {
        chords.enumerated().map { index, chord in
            ChordEntry(
                id: chord.id,
                symbolName: chord.symbolName,
                latinName: chord.latinName,
                order: index
            )
        }
    }

    private var progressionPreviewBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Your Progression")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                Spacer()
                if !currentChords.isEmpty {
                    Text("\(currentChords.count)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppTheme.background)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(AppTheme.accent)
                        .clipShape(Capsule())
                }
            }

            if currentChords.isEmpty {
                Text("Each chord you tap will appear here. Tap ✕ to remove one.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(Array(currentChords.enumerated()), id: \.element.id) { index, chord in
                                let isLatest = index == currentChords.count - 1
                                ZStack(alignment: .topTrailing) {
                                    VStack(spacing: 6) {
                                        Text("\(index + 1)")
                                            .font(.caption2.weight(.bold))
                                            .foregroundStyle(isLatest ? AppTheme.background : AppTheme.textSecondary)

                                        chord.chordText(for: notation, size: 16, weight: .bold)
                                            .foregroundStyle(isLatest ? AppTheme.background : AppTheme.textPrimary)
                                            .lineLimit(1)
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                    .background(isLatest ? AppTheme.accent : AppTheme.surfaceElevated)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                                    Button {
                                        removeChord(at: index)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.body)
                                            .symbolRenderingMode(.palette)
                                            .foregroundStyle(AppTheme.textPrimary, AppTheme.surface)
                                    }
                                    .offset(x: 8, y: -8)
                                    .accessibilityLabel("Remove \(chord.displayName(for: notation))")
                                }
                                .id(chord.id)
                            }
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 2)
                    }
                    .onChange(of: currentChords.count) { _, _ in
                        guard let last = currentChords.last else { return }
                        withAnimation(.easeOut(duration: 0.25)) {
                            proxy.scrollTo(last.id, anchor: .trailing)
                        }
                    }
                }

                Text("Tap ✕ on any chord to remove it")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(AppTheme.surface.opacity(0.98))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)
        }
    }

    private var notationBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: notation == .symbol ? "textformat.abc" : "character.textbox")
                .font(.title3)
                .foregroundStyle(AppTheme.accent)

            VStack(alignment: .leading, spacing: 2) {
                Text(notation.label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                Text(notation.subtitle)
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
            }

            Spacer()
        }
        .padding()
        .glassCard()
    }

    private func customEntrySection(
        title: String,
        placeholder: String,
        text: Binding<String>,
        actionLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .foregroundStyle(AppTheme.textPrimary)

            HStack(spacing: 10) {
                TextField(placeholder, text: text)
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(AppTheme.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .foregroundStyle(AppTheme.textPrimary)
                    .autocorrectionDisabled()

                Button(actionLabel, action: action)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.background)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(AppTheme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }
}
