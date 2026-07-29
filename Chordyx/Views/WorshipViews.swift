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
    var nowOnlyFocus: Bool = false

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
        guard !nowOnlyFocus else { return nil }
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

    private var isLiveChordMoment: Bool {
        viewModel.payload.isLiveChordsOnly
            || viewModel.hasFreestyleActivity
            || !viewModel.payload.pianoNotes.isEmpty
    }

    var body: some View {
        VStack(spacing: nowOnlyFocus ? 28 : 20) {
            if isLiveChordMoment {
                Text("LIVE")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.background)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(AppTheme.accentSecondary)
                    .clipShape(Capsule())
            } else if let section = viewModel.activeSection {
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
                .font(.system(size: nowOnlyFocus ? 104 : 88, weight: .bold, design: .rounded))
                .foregroundStyle(currentName == "—" ? AppTheme.textSecondary : AppTheme.accent)
                .minimumScaleFactor(0.35)
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: nowOnlyFocus ? 120 : 96)
                .contentTransition(.numericText())
                .animation(.spring(response: 0.35, dampingFraction: 0.72), value: currentName)
                .animation(.spring(response: 0.35, dampingFraction: 0.72), value: notation)

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

            if viewModel.displayedMetronomePlaying {
                HStack(spacing: 6) {
                    ForEach(0..<max(1, viewModel.payload.beatsPerBar), id: \.self) { index in
                        Circle()
                            .fill(viewModel.metronome.currentBeat == index ? AppTheme.accent : AppTheme.chordInactive)
                            .frame(width: 10, height: 10)
                    }
                    Text(TempoMarking.caption(for: viewModel.displayedSessionTempoBPM))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, nowOnlyFocus ? 24 : 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                .opacity(isActive ? 1.0 : 0.55)

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
    var usesWideLayout = false
    var style: Style = .grid

    enum Style {
        case grid
        /// Two-row grid for live bottom deck — all cues visible without horizontal scroll.
        case liveCompact
    }

    var body: some View {
        switch style {
        case .grid:
            gridBody(compact: false)
        case .liveCompact:
            gridBody(compact: true)
        }
    }

    /// Column count that keeps every cue on-screen without horizontal scrolling.
    private var gridColumnCount: Int {
        switch style {
        case .liveCompact:
            return 4
        case .grid:
            return usesWideLayout ? 4 : 3
        }
    }

    private func gridBody(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: usesWideLayout ? 14 : (compact ? 8 : 10)) {
            sectionHeader

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: gridColumnCount),
                spacing: 8
            ) {
                ForEach(LiveCue.presets, id: \.0) { text, symbol in
                    cueButton(text: text, symbol: symbol, compact: compact)
                }
            }
        }
    }

    private var sectionHeader: some View {
        Text("Band Cues")
            .font(.caption.weight(.semibold))
            .foregroundStyle(AppTheme.textSecondary)
            .textCase(.uppercase)
    }

    private func cueButton(text: String, symbol: String, compact: Bool) -> some View {
        Button {
            viewModel.sendLiveCue(text, symbol: symbol)
        } label: {
            VStack(spacing: compact ? 3 : (usesWideLayout ? 6 : 4)) {
                Image(systemName: symbol)
                    .font(compact ? .caption.weight(.semibold) : (usesWideLayout ? .body.weight(.semibold) : .body))
                Text(String(localized: String.LocalizationValue(text)))
                    .font(compact ? .caption2.weight(.semibold) : (usesWideLayout ? .caption.weight(.semibold) : .caption2.weight(.semibold)))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, compact ? 8 : (usesWideLayout ? 14 : 10))
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
                        PlatformWorshipSectionPicker {
                            viewModel.addSection(kind: $0, at: chord)
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
    @State private var liveNowOnly = GuestDisplaySettings.liveNowOnlyMode
    @State private var beginnerPianoTriads = GuestDisplaySettings.beginnerPianoTriadsEnabled
    @State private var haptics = GuestDisplaySettings.watchHapticsEnabled
    @State private var cueHaptics = GuestDisplaySettings.cueHapticsEnabled
    @State private var liveActivity = GuestDisplaySettings.liveActivityEnabled
    @State private var hideSongTitle = GuestDisplaySettings.hideSongTitleOnLockScreen
    @State private var silentNudges = GuestDisplaySettings.silentNudgesEnabled
    @State private var chartLanguage = GuestDisplaySettings.chartLanguage
    @State private var chromaticToneNames = GuestDisplaySettings.chromaticToneNames
    @State private var voicingHints = GuestDisplaySettings.voicingHintsEnabled
    @State private var clickLane = GuestDisplaySettings.clickTrackLane

    var body: some View {
        NavigationStack {
            Form {
                Section("Your Role") {
                    PlatformFormDropdown(
                        title: "View role",
                        selection: $viewRole,
                        options: GuestViewRole.allCases.map { ($0, $0.label) }
                    )
                    PlatformFormDropdown(
                        title: "Instrument",
                        selection: $instrument,
                        options: MusicianInstrument.allCases.map { ($0, $0.label) }
                    )
                }
                Section("Personal Chart") {
                    Stepper(String(format: String(localized: "Transpose: %@"), transposeDisplay), value: $transpose, in: -6...6)
                    Stepper(String(format: String(localized: "Capo: %lld"), capo), value: $capo, in: 0...11)
                    Text("Only changes what you see — the host chart stays the same.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                }
                Section("Stage Tools") {
                    Toggle(String(localized: "Live Now view (current chord only)"), isOn: $liveNowOnly)
                    Toggle(String(localized: "Beginner piano triads"), isOn: $beginnerPianoTriads)
                    Text(String(localized: "On piano view, show only major/minor triads from the host MIDI (Cmaj9 → C, Cm9 → Cm)."))
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                    Toggle("Stage Monitor (minimal view)", isOn: $stageMonitor)
                    Toggle("Scale hints for soloing", isOn: $scaleHints)
                    Toggle("Beat-sync change hints", isOn: $beatHints)
                    Toggle(String(localized: "Haptic band cues (Hold, Break…)"), isOn: $cueHaptics)
                    Toggle("Acoustic room mode (visual metronome)", isOn: $acousticRoom)
                    Toggle("Auto-scroll lyrics in chart", isOn: Binding(
                        get: { GuestDisplaySettings.lyricsAutoScrollEnabled },
                        set: { GuestDisplaySettings.lyricsAutoScrollEnabled = $0 }
                    ))
                }
                Section(String(localized: "Band communication")) {
                    Toggle(String(localized: "Silent MD nudges (haptic)"), isOn: $silentNudges)
                    Toggle(String(localized: "Voicing hints"), isOn: $voicingHints)
                    PlatformFormDropdown(
                        title: "Click track mix",
                        selection: $clickLane,
                        options: ClickTrackLane.allCases.map { ($0, $0.label) }
                    )
                }
                Section(String(localized: "Band chat")) {
                    Toggle(
                        String(localized: "Unread badge"),
                        isOn: Binding(
                            get: { GuestDisplaySettings.bandChatBadgesEnabled },
                            set: { GuestDisplaySettings.bandChatBadgesEnabled = $0 }
                        )
                    )
                    Toggle(
                        String(localized: "In-app banner"),
                        isOn: Binding(
                            get: { GuestDisplaySettings.bandChatInAppAlertsEnabled },
                            set: { GuestDisplaySettings.bandChatInAppAlertsEnabled = $0 }
                        )
                    )
                    Toggle(
                        String(localized: "Haptic pulse"),
                        isOn: Binding(
                            get: { GuestDisplaySettings.bandChatHapticsEnabled },
                            set: { GuestDisplaySettings.bandChatHapticsEnabled = $0 }
                        )
                    )
                    Toggle(
                        String(localized: "Sound"),
                        isOn: Binding(
                            get: { GuestDisplaySettings.bandChatSoundsEnabled },
                            set: { GuestDisplaySettings.bandChatSoundsEnabled = $0 }
                        )
                    )
                    Toggle(
                        String(localized: "Quiet during Live"),
                        isOn: Binding(
                            get: { GuestDisplaySettings.bandChatQuietDuringLive },
                            set: { GuestDisplaySettings.bandChatQuietDuringLive = $0 }
                        )
                    )
                    Toggle(
                        String(localized: "Compact chat"),
                        isOn: Binding(
                            get: { GuestDisplaySettings.bandChatCompactEnabled },
                            set: { GuestDisplaySettings.bandChatCompactEnabled = $0 }
                        )
                    )
                    Text(String(localized: "Also available from Band chat → gear icon. Only changes what you hear on this device."))
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                    Text(String(localized: "Compact chat opens as a side panel (iPad/Mac) or half sheet (iPhone) so the chord stage stays visible."))
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                }
                Section(String(localized: "Chart language")) {
                    PlatformFormDropdown(
                        title: "Chord names",
                        selection: $chartLanguage,
                        options: ChartLanguage.allCases.map { ($0, $0.label) }
                    )
                    ChromaticToneNamesFormSection(toneNames: $chromaticToneNames)
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
                        GuestDisplaySettings.liveNowOnlyMode = liveNowOnly
                        GuestDisplaySettings.beginnerPianoTriadsEnabled = beginnerPianoTriads
                        GuestDisplaySettings.watchHapticsEnabled = haptics
                        GuestDisplaySettings.cueHapticsEnabled = cueHaptics
                        GuestDisplaySettings.liveActivityEnabled = liveActivity
                        GuestDisplaySettings.hideSongTitleOnLockScreen = hideSongTitle
                        GuestDisplaySettings.silentNudgesEnabled = silentNudges
                        GuestDisplaySettings.chartLanguage = chartLanguage
                        GuestDisplaySettings.chromaticToneNames = chromaticToneNames
                        GuestDisplaySettings.voicingHintsEnabled = voicingHints
                        GuestDisplaySettings.clickTrackLane = clickLane
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

/// Editable chromatic spelling used by piano keys and Latin chord roots.
struct ChromaticToneNamesFormSection: View {
    @Binding var toneNames: ChromaticToneNames

    private let referenceLabels = ChromaticTonePreset.englishSharps.names

    var body: some View {
        PlatformFormDropdown(
            title: "Chromatic spelling",
            selection: Binding(
                get: { toneNames.preset },
                set: { newValue in
                    if newValue == .custom {
                        toneNames.preset = .custom
                    } else {
                        toneNames.apply(preset: newValue)
                    }
                }
            ),
            options: ChromaticTonePreset.allCases.map { ($0, $0.label) }
        )
        Text(String(localized: "Used on piano keys and Spanish/solfège chord names. Only changes what you see."))
            .font(.caption)
            .foregroundStyle(AppTheme.textSecondary)

        ForEach(0..<ChromaticToneNames.count, id: \.self) { pitchClass in
            HStack(spacing: 12) {
                Text(referenceLabels[pitchClass])
                    .font(.body.monospaced())
                    .foregroundStyle(AppTheme.textSecondary)
                    .frame(width: 36, alignment: .leading)
                TextField(
                    String(localized: "Name"),
                    text: Binding(
                        get: { toneNames.names[pitchClass] },
                        set: { toneNames.setName($0, forPitchClass: pitchClass) }
                    )
                )
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                #endif
            }
        }

        Button(String(localized: "Restore preset")) {
            let target = toneNames.preset == .custom ? ChromaticTonePreset.latinMixed : toneNames.preset
            toneNames.apply(preset: target)
        }
    }
}

/// Standalone editor opened from Piano Keys options.
struct ChromaticToneNamesSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var toneNames = GuestDisplaySettings.chromaticToneNames

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "Chromatic names")) {
                    ChromaticToneNamesFormSection(toneNames: $toneNames)
                }
            }
            .navigationTitle(String(localized: "Note names"))
            .platformInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done")) {
                        GuestDisplaySettings.chromaticToneNames = toneNames
                        dismiss()
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - MIDI settings

struct MIDISettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: SessionViewModel

    private var advancePedalLabel: String {
        let note = viewModel.midi.advanceTriggerNote
        if note < 0 { return String(localized: "Next chord note: Off") }
        return String(format: String(localized: "Next chord note: %lld"), note)
    }

    private var previousPedalLabel: String {
        let note = viewModel.midi.previousTriggerNote
        if note < 0 { return String(localized: "Previous chord note: Off") }
        return String(format: String(localized: "Previous chord note: %lld"), note)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Connect your piano or MainStage MIDI output. Played notes appear on the live piano — including C2 and C♯2. Optionally assign foot-pedal trigger notes below, or use CC 116/117 for hands-free chord changes.")
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
                    Text("Off by default so bass keys (C2, C♯2) show on the piano. Set custom MIDI note numbers only if your foot pedal sends specific keys.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                    Stepper(advancePedalLabel, value: Binding(
                        get: { max(0, viewModel.midi.advanceTriggerNote) },
                        set: { viewModel.midi.advanceTriggerNote = $0 }
                    ), in: 0...127)
                    Stepper(previousPedalLabel, value: Binding(
                        get: { max(0, viewModel.midi.previousTriggerNote) },
                        set: { viewModel.midi.previousTriggerNote = $0 }
                    ), in: 0...127)
                    Button("Turn Off Foot Pedal Notes") {
                        viewModel.midi.advanceTriggerNote = MIDIInputManager.pedalTriggerDisabled
                        viewModel.midi.previousTriggerNote = MIDIInputManager.pedalTriggerDisabled
                    }
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
    @State private var isMenuPresented = false

    var body: some View {
        if viewModel.role == .host, !viewModel.sessionManager.connectedPeers.isEmpty {
            Button {
                isMenuPresented = true
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
            .buttonStyle(.plain)
            .foregroundStyle(AppTheme.textPrimary)
            .liquidGlassMenuPresentation(
                isPresented: $isMenuPresented,
                sheetTitle: "Co-Host",
                arrowEdge: .bottom,
                minWidth: 260
            ) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(viewModel.sessionManager.connectedPeers, id: \.displayName) { peer in
                        LiquidGlassMenuRow(
                            title: String(format: String(localized: "Pass control to %@"), peer.displayName),
                            icon: "person.badge.key.fill"
                        ) {
                            viewModel.passControl(to: peer)
                            isMenuPresented = false
                        }
                    }
                    if viewModel.payload.coHostPeerName != nil {
                        LiquidGlassMenuRow(
                            title: String(localized: "Remove Co-Host"),
                            icon: "person.badge.minus",
                            isDestructive: true
                        ) {
                            viewModel.demoteCoHost()
                            isMenuPresented = false
                        }
                    }
                }
            }
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
        .buttonStyle(.plain)
    }
}

/// Prev/next chord transport for live performance — sits in the bottom deck, not over the ring.
struct LiveChordTransportCompact: View {
    @Bindable var viewModel: SessionViewModel

    private var sortedChords: [ChordEntry] { viewModel.sortedChords }
    private var activeIndex: Int? {
        sortedChords.firstIndex { $0.id == viewModel.payload.activeChordID }
    }

    var body: some View {
        HStack(spacing: 10) {
            transportButton(systemName: "backward.fill", prominent: false) {
                viewModel.requestControlAction(.previousChord)
            }

            if let index = activeIndex, index < sortedChords.count {
                Text("\(index + 1)/\(sortedChords.count)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .frame(minWidth: 44)
            }

            transportButton(systemName: "forward.fill", prominent: true) {
                viewModel.requestControlAction(.advanceChord)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        }
    }

    private func transportButton(systemName: String, prominent: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.body.weight(.bold))
                .frame(width: 52, height: 40)
                .background(prominent ? AppTheme.accent.opacity(0.28) : AppTheme.surfaceElevated.opacity(0.9))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .foregroundStyle(AppTheme.textPrimary)
        .buttonStyle(.plain)
        .accessibilityLabel(
            systemName == "backward.fill"
                ? String(localized: "Previous chord")
                : String(localized: "Next chord")
        )
    }
}

/// Combined progression position + prev/next for live host thumb workflow.
struct LiveChordTransportBar: View {
    @Bindable var viewModel: SessionViewModel

    private var sortedChords: [ChordEntry] { viewModel.sortedChords }
    private var activeIndex: Int? {
        sortedChords.firstIndex { $0.id == viewModel.payload.activeChordID }
    }

    var body: some View {
        VStack(spacing: 10) {
            progressionSummary

            HStack(spacing: 10) {
                transportButton(systemName: "backward.fill", prominent: false) {
                    viewModel.requestControlAction(.previousChord)
                }

                transportButton(systemName: "forward.fill", prominent: true) {
                    viewModel.requestControlAction(.advanceChord)
                }
            }
        }
        .padding(12)
        .glassCard()
    }

    @ViewBuilder
    private var progressionSummary: some View {
        if let index = activeIndex, index < sortedChords.count {
            let active = sortedChords[index]
            HStack(spacing: 8) {
                Text("\(index + 1)/\(sortedChords.count)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.background)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(AppTheme.accent)
                    .clipShape(Capsule())

                active.chordText(
                    for: viewModel.payload.notation,
                    key: viewModel.payload.key,
                    size: 16,
                    weight: .semibold
                )
                .foregroundStyle(AppTheme.textPrimary)

                if index + 1 < sortedChords.count {
                    let next = sortedChords[index + 1]
                    Image(systemName: "arrow.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(AppTheme.textSecondary)
                    HStack(spacing: 4) {
                        Text(String(localized: "then"))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(AppTheme.textSecondary)
                        next.chordText(
                            for: viewModel.payload.notation,
                            key: viewModel.payload.key,
                            size: 12,
                            weight: .medium
                        )
                        .foregroundStyle(AppTheme.textSecondary)
                    }
                    .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
        } else if !sortedChords.isEmpty {
            Text(String(format: String(localized: "%lld chords in progression"), sortedChords.count))
                .font(.caption.weight(.medium))
                .foregroundStyle(AppTheme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func transportButton(systemName: String, prominent: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.headline.weight(.bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(prominent ? AppTheme.accent.opacity(0.28) : AppTheme.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .foregroundStyle(AppTheme.textPrimary)
        .buttonStyle(.plain)
    }
}

// MARK: - Ring source picker

struct RingSourcePicker: View {
    @Binding var showsLiveChords: Bool

    var body: some View {
        PlatformSegmentedPicker("Ring", selection: $showsLiveChords, options: [
            (false, "Progression"),
            (true, "Live")
        ])
    }
}

/// Guest control during Live sessions: full ring vs current chord only.
struct GuestLiveViewStylePicker: View {
    @Binding var nowOnly: Bool

    var body: some View {
        PlatformSegmentedPicker("View", selection: $nowOnly, options: [
            (false, "Ring"),
            (true, "Now")
        ])
        .accessibilityLabel(String(localized: "Live view style"))
    }
}

// MARK: - Display mode picker

struct SessionDisplayModePicker: View {
    @Bindable var viewModel: SessionViewModel

    var body: some View {
        PlatformSegmentedPicker(
            "View",
            selection: Binding(
                get: { viewModel.payload.displayMode },
                set: { viewModel.setDisplayMode($0) }
            ),
            options: SessionDisplayMode.allCases.map { ($0, LocalizedStringKey($0.label)) }
        )
    }
}

struct SessionDisplayModeMenu<Label: View>: View {
    @Bindable var viewModel: SessionViewModel
    @ViewBuilder var label: () -> Label

    var body: some View {
        PlatformPopoverOptionPicker(
            selection: Binding(
                get: { viewModel.payload.displayMode },
                set: { viewModel.setDisplayMode($0) }
            ),
            options: SessionDisplayMode.allCases.map { ($0, $0.label) },
            sheetTitle: "View",
            arrowEdge: .bottom,
            label: label
        )
    }
}

struct PerformanceModePicker: View {
    @Bindable var viewModel: SessionViewModel

    var body: some View {
        PlatformSegmentedPicker(
            "Mode",
            selection: Binding(
                get: { viewModel.payload.performanceMode },
                set: { viewModel.setPerformanceMode($0) }
            ),
            options: SessionPerformanceMode.allCases.map { ($0, LocalizedStringKey($0.label)) }
        )
    }
}
