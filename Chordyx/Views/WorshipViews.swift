//
//  WorshipViews.swift
//  Chordyx
//

import SwiftUI
import MultipeerConnectivity
#if canImport(PDFKit)
import PDFKit
#endif

// MARK: - Stage display

struct NotationCycleButton: View {
    @Bindable var viewModel: SessionViewModel
    var isGuest: Bool

    private var notation: ChordNotation {
        viewModel.displayNotation(isGuest: isGuest)
    }

    private var songKey: MusicalKey {
        viewModel.payload.key
    }

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                viewModel.cycleDisplayNotation(isGuest: isGuest)
            }
        } label: {
            Text(notation.cycleGlyph(for: songKey))
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.55)
                .lineLimit(1)
                .foregroundStyle(songKey.keyTint)
                .frame(width: 38, height: 38)
                .background {
                    ZStack {
                        Circle()
                            .fill(songKey.keyTintFill)
                        Circle()
                            .fill(.ultraThinMaterial.opacity(0.55))
                    }
                }
                .overlay(
                    Circle()
                        .stroke(songKey.keyTintStroke, lineWidth: 1.5)
                )
                .shadow(color: songKey.keyTint.opacity(0.22), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.25), value: songKey)
        .animation(.easeInOut(duration: 0.18), value: notation)
        .accessibilityLabel(notation.label)
        .accessibilityHint(String(localized: "Tap to change chord notation"))
    }
}

struct StageDisplayView: View {
    @Bindable var viewModel: SessionViewModel
    var isGuest: Bool = false
    var guestTranspose: Int = 0
    var guestCapo: Int = 0

    private var notation: ChordNotation {
        viewModel.displayNotation(isGuest: isGuest)
    }

    private var currentName: String {
        guard let chord = viewModel.guestVisibleChord(preferLivePiano: true) else { return "—" }
        return ChordDisplayHelper.displayName(
            for: chord,
            notation: notation,
            songKey: viewModel.payload.key,
            transposeSemitones: guestTranspose,
            capoFret: guestCapo
        )
    }

    private var nextName: String? {
        guard !viewModel.payload.isLiveChordsOnly else { return nil }
        guard viewModel.payload.pianoNotes.isEmpty else { return nil }
        guard let chord = viewModel.upcomingChord else { return nil }
        return ChordDisplayHelper.displayName(
            for: chord,
            notation: notation,
            songKey: viewModel.payload.key,
            transposeSemitones: guestTranspose,
            capoFret: guestCapo
        )
    }

    var body: some View {
        VStack(spacing: 20) {
            if let section = viewModel.activeSection {
                HStack(spacing: 8) {
                    Image(systemName: section.kind.icon)
                    Text(section.name.uppercased())
                    if section.repeatCount > 1 {
                        Text("×\(section.repeatCount)")
                            .foregroundStyle(AppTheme.accentSecondary)
                    }
                }
                .font(.headline.weight(.bold))
                .foregroundStyle(AppTheme.accentSecondary)
            }

            Text("NOW")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)
                .tracking(2)

            Text(currentName)
                .font(.system(size: 88, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.accent)
                .minimumScaleFactor(0.35)
                .lineLimit(1)
                .frame(maxWidth: .infinity)

            if let nextName {
                HStack(spacing: 8) {
                    Text("NEXT")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppTheme.textSecondary)
                    Text(nextName)
                        .font(.title.weight(.bold))
                        .foregroundStyle(AppTheme.textPrimary)
                }
            }

            if viewModel.payload.isMetronomePlaying {
                HStack(spacing: 6) {
                    ForEach(0..<max(1, viewModel.payload.beatsPerBar), id: \.self) { index in
                        Circle()
                            .fill(viewModel.metronome.currentBeat == index ? AppTheme.accent : AppTheme.chordInactive)
                            .frame(width: 10, height: 10)
                    }
                    Text("\(Int(viewModel.payload.tempoBPM)) BPM")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }
}

// MARK: - Lyrics chart

struct LyricsChartView: View {
    @Bindable var viewModel: SessionViewModel
    var isGuest: Bool = false
    var guestTranspose: Int = 0
    var guestCapo: Int = 0

    @AppStorage(GuestDisplaySettings.lyricsAutoScrollKey) private var autoScrollEnabled = true

    private var notation: ChordNotation {
        viewModel.displayNotation(isGuest: isGuest)
    }

    private var lines: [LyricsLine] {
        if !viewModel.payload.lyricsLines.isEmpty {
            return viewModel.payload.lyricsLines
        }
        return viewModel.sortedChords.compactMap { chord in
            guard let text = chord.lyrics, !text.isEmpty else { return nil }
            return LyricsLine(text: text, chordSymbol: chord.symbolName)
        }
    }

    private var activeLineID: UUID? {
        guard let active = viewModel.activeChord else { return nil }
        let matches = lines.enumerated().filter { $0.element.chordSymbol == active.symbolName }
        guard !matches.isEmpty else { return nil }
        if matches.count == 1 { return matches[0].element.id }

        let chordIndex = viewModel.sortedChords.firstIndex { $0.id == active.id } ?? 0
        let occurrence = viewModel.sortedChords.prefix(chordIndex).filter { $0.symbolName == active.symbolName }.count
        let pick = min(occurrence, matches.count - 1)
        return matches[pick].element.id
    }

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                if !lines.isEmpty {
                    Toggle(isOn: $autoScrollEnabled) {
                        Label(String(localized: "Auto-scroll lyrics"), systemImage: "arrow.up.and.down.text.horizontal")
                            .font(.caption.weight(.semibold))
                    }
                    .tint(AppTheme.accent)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
                }

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        if let liveChord = viewModel.livePianoChordEntry() {
                            HStack(spacing: 10) {
                                Text("LIVE")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(AppTheme.background)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(AppTheme.accentSecondary)
                                    .clipShape(Capsule())
                                liveChord.chordText(
                                    for: notation,
                                    key: viewModel.payload.key,
                                    size: 28,
                                    weight: .bold
                                )
                                .foregroundStyle(AppTheme.accent)
                            }
                            .padding(.bottom, 4)
                        }

                        if lines.isEmpty, !viewModel.payload.lyrics.isEmpty {
                            Text(viewModel.payload.lyrics)
                                .font(.title3)
                                .foregroundStyle(AppTheme.textPrimary)
                                .padding(.vertical, 8)
                        } else if lines.isEmpty {
                            Text("Add lyrics in the Lyrics editor to show a chart here.")
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.textSecondary)
                        } else {
                            ForEach(lines) { line in
                                lyricsRow(line, isActive: line.id == activeLineID)
                                    .id(line.id)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                }
            }
            .onAppear { scrollToActiveLine(in: proxy, animated: false) }
            .onChange(of: viewModel.payload.activeChordID) { _, _ in
                scrollToActiveLine(in: proxy, animated: true)
            }
            .onChange(of: viewModel.payload.activeSectionID) { _, _ in
                scrollToActiveLine(in: proxy, animated: true)
            }
            .onChange(of: viewModel.payload.beatsOnActiveChord) { _, _ in
                scrollToActiveLine(in: proxy, animated: autoScrollEnabled)
            }
            .onChange(of: viewModel.metronome.currentBeat) { _, newBeat in
                guard autoScrollEnabled, newBeat == 0 else { return }
                scrollToActiveLine(in: proxy, animated: true)
            }
        }
    }

    private func lyricsRow(_ line: LyricsLine, isActive: Bool) -> some View {
        let progress = chordProgress(for: line, isActive: isActive)

        return VStack(alignment: .leading, spacing: 6) {
            if let symbol = line.chordSymbol {
                ChordEntry(
                    symbolName: symbol,
                    latinName: ChordCatalog.latinName(forSymbol: symbol),
                    order: 0
                )
                .chordText(
                    for: notation,
                    key: viewModel.payload.key,
                    size: 22,
                    weight: .bold
                )
                .foregroundStyle(isActive ? AppTheme.accent : AppTheme.accentSecondary)
            }
            Text(line.text)
                .font(.title3.weight(isActive ? .semibold : .regular))
                .foregroundStyle(isActive ? AppTheme.textPrimary : AppTheme.textSecondary)

            if isActive, let progress {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(AppTheme.chordInactive.opacity(0.35))
                        Capsule()
                            .fill(AppTheme.accent)
                            .frame(width: geo.size.width * progress)
                    }
                }
                .frame(height: 4)
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(isActive ? AppTheme.surfaceElevated : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func chordProgress(for line: LyricsLine, isActive: Bool) -> CGFloat? {
        guard isActive,
              let active = viewModel.activeChord,
              line.chordSymbol == active.symbolName,
              let duration = active.durationBeats,
              duration > 0,
              viewModel.payload.isMetronomePlaying else { return nil }
        let total = max(1, Int(duration.rounded()))
        return min(1, CGFloat(viewModel.payload.beatsOnActiveChord) / CGFloat(total))
    }

    private func scrollToActiveLine(in proxy: ScrollViewProxy, animated: Bool) {
        guard autoScrollEnabled, let id = activeLineID else { return }
        if animated {
            withAnimation(.easeInOut(duration: 0.35)) {
                proxy.scrollTo(id, anchor: .center)
            }
        } else {
            proxy.scrollTo(id, anchor: .center)
        }
    }
}

// MARK: - Live cues

struct LiveCueBanner: View {
    let cue: LiveCue
    var isAutoAdvancePaused: Bool = false
    var isVampActive: Bool = false

    private var actionHint: String? {
        switch cue.text {
        case "Hold" where isAutoAdvancePaused:
            return String(localized: "Auto-advance paused")
        case "Vamp" where isVampActive:
            return String(localized: "Repeating this chord")
        default:
            return nil
        }
    }

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 10) {
                Image(systemName: cue.symbol)
                    .font(.title3.weight(.bold))
                Text(String(localized: String.LocalizationValue(cue.text)).uppercased())
                    .font(.headline.weight(.bold))
                    .tracking(1)
            }
            if let actionHint {
                Text(actionHint)
                    .font(.caption.weight(.semibold))
            }
        }
        .foregroundStyle(AppTheme.background)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(AppTheme.accentSecondary)
        .clipShape(Capsule())
        .shadow(radius: 12)
    }
}

struct LiveCuePad: View {
    @Bindable var viewModel: SessionViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Band Cues")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)
                .textCase(.uppercase)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(LiveCue.presets, id: \.0) { text, symbol in
                    Button {
                        viewModel.sendLiveCue(text, symbol: symbol)
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: symbol)
                            Text(String(localized: String.LocalizationValue(text)))
                                .font(.caption2.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(isCueActive(text) ? AppTheme.accent.opacity(0.28) : AppTheme.surfaceElevated)
                        .overlay {
                            if isCueActive(text) {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(AppTheme.accent, lineWidth: 2)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .foregroundStyle(isCueActive(text) ? AppTheme.accent : AppTheme.textPrimary)
                }
            }
        }
    }

    private func isCueActive(_ text: String) -> Bool {
        switch text {
        case "Hold": viewModel.payload.isAutoAdvancePaused
        case "Vamp": viewModel.payload.isVampActive
        default: false
        }
    }
}

// MARK: - Section jumps

struct SectionJumpBar: View {
    @Bindable var viewModel: SessionViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !viewModel.payload.sections.isEmpty {
                Text("Section rings")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(AppTheme.textSecondary)
                    .textCase(.uppercase)
                    .tracking(1)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(viewModel.sectionsInOrder) { section in
                        sectionButton(section)
                    }

                    if viewModel.canDriveSession, let chord = viewModel.activeChord {
                        Menu {
                            ForEach(WorshipSectionKind.allCases) { kind in
                                Button(kind.defaultName) {
                                    viewModel.addSection(kind: kind, at: chord)
                                }
                            }
                        } label: {
                            Label("Add Section", systemImage: "plus")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(AppTheme.surface)
                                .clipShape(Capsule())
                        }
                        .foregroundStyle(AppTheme.accent)
                    }
                }
            }
        }
    }

    private func sectionButton(_ section: SectionMarker) -> some View {
        let chordCount = viewModel.chords(for: section).count
        let isActive = viewModel.activeSection?.id == section.id

        return Button {
            viewModel.jumpToSection(section)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: section.kind.icon)
                    Text(section.name)
                        .lineLimit(1)
                }
                .font(.caption.weight(.semibold))

                Text("\(chordCount) chords")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(isActive ? AppTheme.background.opacity(0.85) : AppTheme.textSecondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isActive ? AppTheme.accent.opacity(0.9) : AppTheme.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .foregroundStyle(isActive ? AppTheme.background : AppTheme.textPrimary)
    }
}

// MARK: - Lock Screen settings

struct LockScreenActivitySettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var liveActivity = GuestDisplaySettings.liveActivityEnabled
    @State private var hideSongTitle = GuestDisplaySettings.hideSongTitleOnLockScreen

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Show chords on Lock Screen", isOn: $liveActivity)
                    Toggle("Hide song title on Lock Screen", isOn: $hideSongTitle)
                } header: {
                    Text("Live Activity")
                } footer: {
                    Text("Keeps chords updating on your Lock Screen and Dynamic Island while Chordyx runs in the background during a session. Leave this on and keep Wi‑Fi active.")
                }
            }
            .navigationTitle("Lock Screen")
            .platformInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        GuestDisplaySettings.liveActivityEnabled = liveActivity
                        GuestDisplaySettings.hideSongTitleOnLockScreen = hideSongTitle
                        dismiss()
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Guest musician settings

struct GuestMusicianSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var transpose = GuestDisplaySettings.transposeSemitones
    @State private var capo = GuestDisplaySettings.capoFret
    @State private var instrument = GuestDisplaySettings.instrument
    @State private var viewRole = GuestDisplaySettings.viewRole
    @State private var scaleHints = GuestDisplaySettings.scaleHintsEnabled
    @State private var beatHints = GuestDisplaySettings.beatSyncHintsEnabled
    @State private var acousticRoom = GuestDisplaySettings.acousticRoomMode
    @State private var stageMonitor = GuestDisplaySettings.stageMonitorMode
    @State private var haptics = GuestDisplaySettings.watchHapticsEnabled
    @State private var liveActivity = GuestDisplaySettings.liveActivityEnabled
    @State private var hideSongTitle = GuestDisplaySettings.hideSongTitleOnLockScreen

    var body: some View {
        NavigationStack {
            Form {
                Section("Your Role") {
                    Picker("View role", selection: $viewRole) {
                        ForEach(GuestViewRole.allCases) { role in
                            Text(role.label).tag(role)
                        }
                    }
                    Picker("Instrument", selection: $instrument) {
                        ForEach(MusicianInstrument.allCases) { item in
                            Text(item.label).tag(item)
                        }
                    }
                }
                Section("Personal Chart") {
                    Stepper(String(format: String(localized: "Transpose: %@"), transposeDisplay), value: $transpose, in: -6...6)
                    Stepper(String(format: String(localized: "Capo: %lld"), capo), value: $capo, in: 0...11)
                    Text("Only changes what you see — the host chart stays the same.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                }
                Section("Stage Tools") {
                    Toggle("Stage Monitor (minimal view)", isOn: $stageMonitor)
                    Toggle("Scale hints for soloing", isOn: $scaleHints)
                    Toggle("Beat-sync change hints", isOn: $beatHints)
                    Toggle("Acoustic room mode (visual metronome)", isOn: $acousticRoom)
                    Toggle("Auto-scroll lyrics in chart", isOn: Binding(
                        get: { GuestDisplaySettings.lyricsAutoScrollEnabled },
                        set: { GuestDisplaySettings.lyricsAutoScrollEnabled = $0 }
                    ))
                }
                Section("Apple Watch") {
                    Toggle("Haptic cues on chord changes", isOn: $haptics)
                }
                Section("Lock Screen") {
                    Toggle("Show chords on Lock Screen", isOn: $liveActivity)
                    Toggle("Hide song title on Lock Screen", isOn: $hideSongTitle)
                    Text("Keeps chords updating on Lock Screen and Dynamic Island while the session runs in the background.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
            .navigationTitle("My Chart")
            .platformInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        GuestDisplaySettings.transposeSemitones = transpose
                        GuestDisplaySettings.capoFret = capo
                        GuestDisplaySettings.instrument = instrument
                        GuestDisplaySettings.viewRole = viewRole
                        GuestDisplaySettings.scaleHintsEnabled = scaleHints
                        GuestDisplaySettings.beatSyncHintsEnabled = beatHints
                        GuestDisplaySettings.acousticRoomMode = acousticRoom
                        GuestDisplaySettings.stageMonitorMode = stageMonitor
                        GuestDisplaySettings.watchHapticsEnabled = haptics
                        GuestDisplaySettings.liveActivityEnabled = liveActivity
                        GuestDisplaySettings.hideSongTitleOnLockScreen = hideSongTitle
                        dismiss()
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var transposeDisplay: String {
        if transpose == 0 { return String(localized: "None") }
        return transpose > 0 ? "+\(transpose)" : "\(transpose)"
    }
}

// MARK: - MIDI settings

struct MIDISettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: SessionViewModel

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Connect your piano or MainStage MIDI output. Use foot pedal notes C1 (36) / C♯1 (37) or CC 116/117 to change chords hands-free.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                }

                Section("MIDI Sources") {
                    if viewModel.midiAvailableSources.isEmpty {
                        Text("No MIDI sources detected")
                            .foregroundStyle(AppTheme.textSecondary)
                    } else {
                        ForEach(viewModel.midiAvailableSources) { source in
                            Toggle(source.name, isOn: Binding(
                                get: { source.isConnected },
                                set: { viewModel.midiSetSourceConnected(id: source.id, connected: $0) }
                            ))
                        }
                    }
                    Button("Connect All Sources") {
                        viewModel.midiConnectAllSources()
                    }
                }

                Section("Foot Pedal Notes") {
                    Stepper("Next chord note: \(viewModel.midi.advanceTriggerNote)", value: Binding(
                        get: { viewModel.midi.advanceTriggerNote },
                        set: { viewModel.midi.advanceTriggerNote = $0 }
                    ), in: 0...127)
                    Stepper("Previous chord note: \(viewModel.midi.previousTriggerNote)", value: Binding(
                        get: { viewModel.midi.previousTriggerNote },
                        set: { viewModel.midi.previousTriggerNote = $0 }
                    ), in: 0...127)
                }

                Section("Keyboard Shortcuts (Mac)") {
                    Text("← Previous chord · → Next chord · Space toggles metronome")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
            .navigationTitle("MIDI Setup")
            .platformInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Setlist transition

struct SetlistTransitionOverlay: View {
    let title: String
    let countdown: Int?

    var body: some View {
        ZStack {
            Color.black.opacity(0.72).ignoresSafeArea()
            VStack(spacing: 16) {
                Text("Next Song")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)
                Text(title)
                    .font(.title.weight(.bold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .multilineTextAlignment(.center)
                if let countdown {
                    Text("\(countdown)")
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.accent)
                }
            }
            .padding(32)
        }
    }
}

// MARK: - PDF chart

#if canImport(PDFKit)
struct PDFChartView: View {
    let url: URL

    var body: some View {
        PDFKitRepresentedView(url: url)
            .background(AppTheme.background)
    }
}

#if os(macOS)
private struct PDFKitRepresentedView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.document = PDFDocument(url: url)
        return view
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        nsView.document = PDFDocument(url: url)
    }
}
#else
private struct PDFKitRepresentedView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.document = PDFDocument(url: url)
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        uiView.document = PDFDocument(url: url)
    }
}
#endif
#else
struct PDFChartView: View {
    let url: URL
    var body: some View {
        Text("PDF preview unavailable")
    }
}
#endif

// MARK: - Co-host picker

struct CoHostPicker: View {
    @Bindable var viewModel: SessionViewModel

    var body: some View {
        if viewModel.role == .host, !viewModel.sessionManager.connectedPeers.isEmpty {
            Menu {
                ForEach(viewModel.sessionManager.connectedPeers, id: \.displayName) { peer in
                    Button(String(format: String(localized: "Pass control to %@"), peer.displayName)) {
                        viewModel.passControl(to: peer)
                    }
                }
                if viewModel.payload.coHostPeerName != nil {
                    Button("Remove Co-Host", role: .destructive) {
                        viewModel.demoteCoHost()
                    }
                }
            } label: {
                Label(
                    viewModel.payload.coHostPeerName ?? "Co-Host",
                    systemImage: "person.badge.key.fill"
                )
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(AppTheme.surfaceElevated)
                .clipShape(Capsule())
            }
            .foregroundStyle(AppTheme.textPrimary)
        }
    }
}

// MARK: - Advance controls

struct ChordAdvanceBar: View {
    @Bindable var viewModel: SessionViewModel

    var body: some View {
        HStack(spacing: 12) {
            Button { viewModel.requestControlAction(.previousChord) } label: {
                Image(systemName: "backward.fill")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .background(AppTheme.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            Button { viewModel.requestControlAction(.advanceChord) } label: {
                Image(systemName: "forward.fill")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .background(AppTheme.accent.opacity(0.25))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .foregroundStyle(AppTheme.textPrimary)
        .font(.headline)
    }
}

// MARK: - Ring source picker

struct RingSourcePicker: View {
    @Binding var showsLiveChords: Bool

    var body: some View {
        Picker("Ring", selection: $showsLiveChords) {
            Text("Progression").tag(false)
            Text("Live").tag(true)
        }
        .pickerStyle(.segmented)
    }
}

// MARK: - Display mode picker

struct SessionDisplayModePicker: View {
    @Bindable var viewModel: SessionViewModel

    var body: some View {
        Picker("View", selection: Binding(
            get: { viewModel.payload.displayMode },
            set: { viewModel.setDisplayMode($0) }
        )) {
            ForEach(SessionDisplayMode.allCases) { mode in
                Text(mode.label).tag(mode)
            }
        }
        .pickerStyle(.segmented)
    }
}

struct PerformanceModePicker: View {
    @Bindable var viewModel: SessionViewModel

    var body: some View {
        Picker("Mode", selection: Binding(
            get: { viewModel.payload.performanceMode },
            set: { viewModel.setPerformanceMode($0) }
        )) {
            ForEach(SessionPerformanceMode.allCases) { mode in
                Text(mode.label).tag(mode)
            }
        }
        .pickerStyle(.segmented)
    }
}
