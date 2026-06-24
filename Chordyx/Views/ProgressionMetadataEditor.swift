//
//  ProgressionMetadataEditor.swift
//  Chordyx
//

import SwiftUI

struct ProgressionMetadataEditor: View {
    @Bindable var viewModel: SessionViewModel
    @State private var lyricsText = ""
    @State private var newSectionName = ""
    @State private var loopEnabled = false
    @State private var loopStartID: UUID?
    @State private var loopEndID: UUID?
    @State private var rehearsalNotes = ""
    @State private var lyricsLines: [LyricsLine] = []

    private var chords: [ChordEntry] { viewModel.sortedChords }

    var body: some View {
        Form {
            Section("Lyrics Chart") {
                ForEach(viewModel.payload.lyricsLines) { line in
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("Lyric line", text: bindingLyricText(for: line))
                        TextField("Chord symbol", text: bindingLyricChord(for: line))
                            .font(.caption.monospaced())
                    }
                }
                Button("Add lyric line") {
                    var lines = viewModel.payload.lyricsLines
                    lines.append(LyricsLine(text: "", chordSymbol: viewModel.activeChord?.symbolName))
                    viewModel.setLyricsLines(lines)
                }
            }

            Section("Lyrics") {
                TextEditor(text: $lyricsText)
                    .frame(minHeight: 100)
                    .onChange(of: lyricsText) { _, newValue in
                        viewModel.setProgressionLyrics(newValue)
                    }
            }

            Section("Sections") {
                ForEach(viewModel.payload.sections) { section in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: section.kind.icon)
                            Text(section.name).font(.headline)
                            if section.repeatCount > 1 {
                                Text("×\(section.repeatCount)")
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.accentSecondary)
                            }
                        }
                        if !section.lyrics.isEmpty {
                            Text(section.lyrics).font(.caption).foregroundStyle(AppTheme.textSecondary)
                        }
                    }
                }
                Menu {
                    ForEach(WorshipSectionKind.allCases) { kind in
                        Button(kind.defaultName) {
                            addSection(kind: kind)
                        }
                    }
                } label: {
                    Label("Add worship section at live chord", systemImage: "plus")
                }
                .disabled(viewModel.activeChord == nil)
                HStack {
                    TextField("Custom section name", text: $newSectionName)
                    Button("Add") {
                        addSection(kind: .custom)
                    }
                    .disabled(newSectionName.trimmingCharacters(in: .whitespaces).isEmpty || viewModel.activeChord == nil)
                }
            }

            Section("Rehearsal Notes") {
                TextEditor(text: $rehearsalNotes)
                    .frame(minHeight: 80)
                    .onChange(of: rehearsalNotes) { _, newValue in
                        viewModel.setRehearsalNotes(newValue)
                    }
                Text("Visible to the band in rehearsal mode — capo reminders, dynamics, etc.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
            }

            Section("Loop") {
                Toggle("Loop section", isOn: $loopEnabled)
                    .onChange(of: loopEnabled) { _, enabled in
                        applyLoop(enabled: enabled)
                    }
                Picker("Loop start", selection: $loopStartID) {
                    Text("—").tag(Optional<UUID>.none)
                    ForEach(chords) { chord in
                        chord.chordText(for: viewModel.payload.notation, key: viewModel.payload.key, size: 17, weight: .semibold)
                            .tag(Optional(chord.id))
                    }
                }
                .onChange(of: loopStartID) { _, _ in applyLoop(enabled: loopEnabled) }
                Picker("Loop end", selection: $loopEndID) {
                    Text("—").tag(Optional<UUID>.none)
                    ForEach(chords) { chord in
                        chord.chordText(for: viewModel.payload.notation, key: viewModel.payload.key, size: 17, weight: .semibold)
                            .tag(Optional(chord.id))
                    }
                }
                .onChange(of: loopEndID) { _, _ in applyLoop(enabled: loopEnabled) }
            }

            Section("Chord Durations") {
                ForEach(chords) { chord in
                    HStack {
                        chord.chordText(for: viewModel.payload.notation, key: viewModel.payload.key, size: 17, weight: .semibold)
                        Spacer()
                        Stepper(
                            value: bindingDuration(for: chord),
                            in: 0...16,
                            step: 1
                        ) {
                            Text(durationLabel(for: chord))
                                .font(.caption)
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .onAppear {
            lyricsText = viewModel.payload.lyrics
            lyricsLines = viewModel.payload.lyricsLines
            loopEnabled = viewModel.payload.isLoopEnabled
            loopStartID = viewModel.payload.loopStartChordID
            loopEndID = viewModel.payload.loopEndChordID
            rehearsalNotes = viewModel.payload.rehearsalNotes
        }
    }

    private func bindingLyricText(for line: LyricsLine) -> Binding<String> {
        Binding(
            get: { line.text },
            set: { newValue in
                var lines = viewModel.payload.lyricsLines
                guard let index = lines.firstIndex(where: { $0.id == line.id }) else { return }
                lines[index].text = newValue
                viewModel.setLyricsLines(lines)
            }
        )
    }

    private func bindingLyricChord(for line: LyricsLine) -> Binding<String> {
        Binding(
            get: { line.chordSymbol ?? "" },
            set: { newValue in
                var lines = viewModel.payload.lyricsLines
                guard let index = lines.firstIndex(where: { $0.id == line.id }) else { return }
                lines[index].chordSymbol = newValue.isEmpty ? nil : newValue
                viewModel.setLyricsLines(lines)
            }
        )
    }

    private func durationLabel(for chord: ChordEntry) -> String {
        if let beats = chord.durationBeats, beats > 0 {
            return String(format: String(localized: "%lld beats"), Int(beats))
        }
        return String(localized: "Manual")
    }

    private func bindingDuration(for chord: ChordEntry) -> Binding<Double> {
        Binding(
            get: { chord.durationBeats ?? 0 },
            set: { newValue in
                var updated = viewModel.sortedChords
                guard let index = updated.firstIndex(where: { $0.id == chord.id }) else { return }
                updated[index] = chord.copying(durationBeats: newValue > 0 ? newValue : nil)
                viewModel.updateProgressionChords(updated)
            }
        )
    }

    private func addSection(kind: WorshipSectionKind) {
        guard let active = viewModel.activeChord else { return }
        let trimmed = newSectionName.trimmingCharacters(in: .whitespacesAndNewlines)
        let customName = trimmed.isEmpty ? nil : trimmed
        viewModel.addSection(kind: kind, at: active, customName: customName)
        newSectionName = ""
    }

    private func applyLoop(enabled: Bool) {
        let start = chords.first { $0.id == loopStartID }
        let end = chords.first { $0.id == loopEndID }
        viewModel.setLoopRange(start: start, end: end, enabled: enabled)
    }
}
