//
//  PianoView.swift
//  Chordyx
//

import SwiftUI

struct PianoView: View {
    @Bindable var viewModel: SessionViewModel
    var onDismiss: (() -> Void)? = nil
    var onLeaveSession: (() -> Void)? = nil

    @AppStorage("guestViewInstrument") private var guestInstrumentRaw = ViewInstrument.piano.rawValue
    @AppStorage("guestBassStrings") private var guestBassStrings = 4
    @AppStorage(GuestDisplaySettings.beginnerPianoTriadsKey) private var beginnerPianoTriads = false
    @State private var showGuestPianoControls = false

    private var isHost: Bool { viewModel.role == .host }
    private var preferFlats: Bool { viewModel.payload.key.prefersFlats }

    /// Guests can simplify host MIDI voicings to maj/min triads locally without changing the session.
    private var usesBeginnerPianoTriads: Bool {
        !isHost && beginnerPianoTriads
    }

    /// Notes to light on the keyboard. Guests rebuild from the live chord symbol when
    /// piano note packets are empty or don't cover the chord tones (common with A/La sync glitches).
    private var activeNotes: [Int] {
        let raw = viewModel.payload.pianoNotes
            .map { PianoNote.normalizeToInternal($0) }
            .filter { PianoNote.keyboardRange.contains($0) }
        let symbol = viewModel.payload.liveChordSymbol

        if usesBeginnerPianoTriads,
           let simplified = ChordTheory.beginnerTriadNotes(from: raw, symbol: symbol) {
            return simplified
        }

        if !isHost, let symbol,
           let triad = ChordTheory.tones(for: symbol) {
            let rawPCs = Set(raw.map { PianoNote.pitchClass(of: $0) })
            let notesMissChord = raw.isEmpty || !triad.pitchClasses.isSubset(of: rawPCs)
            if notesMissChord,
               let rebuilt = ChordTheory.beginnerTriadNotes(
                from: raw.isEmpty ? [PianoNote.middleC] : raw,
                symbol: symbol
               ) {
                return rebuilt
            }
        }

        return raw
    }

    private var activeNoteSet: Set<Int> { Set(activeNotes) }

    // Guests render on the host's piano by default, but can switch locally.
    private var guestInstrument: ViewInstrument {
        ViewInstrument(rawValue: guestInstrumentRaw) ?? .piano
    }

    private var pitchClasses: Set<Int> {
        Set(activeNotes.map { PianoNote.pitchClass(forStored: $0) })
    }

    private var rootPitchClass: Int? {
        if let symbol = viewModel.payload.liveChordSymbol,
           let tones = ChordTheory.tones(for: symbol) {
            return tones.root
        }
        return activeNotes.min().map { PianoNote.pitchClass(forStored: $0) }
    }

    /// Bass guests only see the chord root; guitar gets full chord tones.
    private var fretboardPitchClasses: Set<Int> {
        if guestInstrument == .bass {
            if let root = rootPitchClass { return [root] }
            return []
        }
        return pitchClasses
    }

    private var showFretboardForGuest: Bool {
        !isHost && guestInstrument != .piano
    }

    private var displayNotation: ChordNotation {
        viewModel.displayNotation(isGuest: !isHost)
    }

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var showsFullPianoKeyboard: Bool {
        PlatformLayout.usesFullPianoKeyboard(horizontalSizeClass: horizontalSizeClass)
    }

    private var isCompactHeight: Bool {
        verticalSizeClass == .compact
    }

    /// Guest piano view fills the screen; dual-row keeps both hands visible.
    private var usesImmersiveGuestPiano: Bool {
        !isHost && guestInstrument == .piano
    }

    /// Classic board heights — dual-row stacks C3+ over A0–B2 without stretching keys tall.
    private var instrumentBoardHeight: CGFloat {
        if isCompactHeight { return 150 }
        if usesImmersiveGuestPiano { return 304 }
        return showsFullPianoKeyboard ? 280 : 308
    }

    private var forceDualPianoRows: Bool {
        usesImmersiveGuestPiano && !isCompactHeight
    }

    private var chordLabelSize: CGFloat {
        if usesImmersiveGuestPiano || isCompactHeight { return 28 }
        if PlatformDevice.isPhone { return 34 }
        return 44
    }

    private var keyboardHorizontalPadding: CGFloat {
        #if os(macOS)
        8
        #else
        usesImmersiveGuestPiano ? 8 : (showsFullPianoKeyboard ? 16 : 12)
        #endif
    }

    var body: some View {
        ZStack {
            AppTheme.backgroundGradient.ignoresSafeArea()

            if usesImmersiveGuestPiano {
                immersiveGuestPianoBody
            } else {
                standardPianoBody
            }
        }
        .preferredColorScheme(.dark)
    }

    /// Full-bleed guest piano: keyboards dominate; chord sits in a non-blocking orb.
    private var immersiveGuestPianoBody: some View {
        VStack(spacing: 10) {
            immersiveTopBar

            if showGuestPianoControls {
                guestInstrumentPicker
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Spacer(minLength: 4)

            instrumentBoard
                .frame(height: instrumentBoardHeight)
                .frame(maxWidth: .infinity)
                .layoutPriority(1)

            Spacer(minLength: 4)
        }
        .padding(.horizontal, keyboardHorizontalPadding)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var standardPianoBody: some View {
        VStack(spacing: isCompactHeight ? 8 : (PlatformDevice.isPhone ? 10 : 16)) {
            header

            if isHost {
                midiStatus
            } else {
                guestInstrumentPicker
            }

            noteDisplay

            instrumentBoard
                .frame(height: instrumentBoardHeight)
                .frame(maxWidth: .infinity)
                .layoutPriority(1)
                .padding(.horizontal, showFretboardForGuest ? 12 : keyboardHorizontalPadding)

            if isHost {
                Text("Tap keys to show the notes to everyone in the session")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, isCompactHeight ? 6 : (PlatformDevice.isPhone ? 10 : (showsFullPianoKeyboard ? 16 : 24)))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var immersiveTopBar: some View {
        HStack(alignment: .center, spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showGuestPianoControls.toggle()
                }
            } label: {
                Image(systemName: showGuestPianoControls ? "chevron.up.circle.fill" : "slider.horizontal.3")
                    .font(.title3)
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .accessibilityLabel(String(localized: "Piano options"))

            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.payload.sessionName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(1)
                if usesBeginnerPianoTriads {
                    Text(String(localized: "Beginner"))
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(AppTheme.accentSecondary)
                }
            }

            Spacer(minLength: 8)

            pianoChordOrb
                .frame(width: 88, height: 88)

            overlayHeaderActions
        }
        .padding(.horizontal, 4)
    }

    @ViewBuilder
    private var instrumentBoard: some View {
        if showFretboardForGuest, let fret = guestInstrument.fretInstrument {
            FretboardView(
                instrument: fret,
                bassStrings: guestBassStrings,
                pitchClasses: fretboardPitchClasses,
                rootPitchClass: rootPitchClass,
                preferFlats: preferFlats,
                isCompactHeight: isCompactHeight
            )
        } else {
            AdaptivePianoBoard(
                activeNotes: activeNoteSet,
                preferFlats: preferFlats,
                isInteractive: isHost,
                isCompactHeight: isCompactHeight,
                forceDualRow: forceDualPianoRows,
                onTap: { viewModel.playPianoNote($0) }
            )
        }
    }

    /// Large chord in a circle — top bar only, never covers the keyboards.
    private var pianoChordOrb: some View {
        let chord = displayedChordName
        return ZStack {
            Circle()
                .fill(AppTheme.surfaceElevated.opacity(0.92))
            Circle()
                .stroke(AppTheme.accent.opacity(chord == nil ? 0.2 : 0.55), lineWidth: 2)

            Group {
                if let chord {
                    chordOrbPrimaryText(chord)
                        .foregroundStyle(AppTheme.accent)
                        .minimumScaleFactor(0.4)
                        .lineLimit(1)
                } else {
                    Text("—")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
            .padding(10)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(chord.map { String(localized: "Chord \($0)") } ?? String(localized: "No chord"))
    }

    private var displayedChordName: String? {
        let sorted = activeNotes.sorted()
        let pitchClasses = Set(sorted.map { PianoNote.pitchClass(forStored: $0) })
        let bass = sorted.first.map { PianoNote.pitchClass(forStored: $0) }
        let recognizedFromKeys = ChordRecognizer.symbol(
            forPitchClasses: pitchClasses,
            bassPitchClass: bass,
            preferFlats: preferFlats
        ) ?? sorted.first.map { viewModel.singleNoteSymbol(for: $0) }
        let hostSymbol = viewModel.payload.liveChordSymbol ?? recognizedFromKeys
        let displaySymbol: String? = {
            guard let hostSymbol else { return nil }
            if usesBeginnerPianoTriads,
               let simple = ChordTheory.beginnerTriadSymbol(for: hostSymbol, preferFlats: preferFlats) {
                return simple
            }
            return hostSymbol
        }()
        return displaySymbol.map { symbol in
            switch displayNotation {
            case .latin: ChordCatalog.latinName(forSymbol: symbol)
            case .nashville: NashvilleConverter.number(for: symbol, in: viewModel.payload.key)
            case .symbol: symbol
            }
        }
    }

    @ViewBuilder
    private func chordOrbPrimaryText(_ chord: String) -> some View {
        if displayNotation == .latin || displayNotation == .nashville {
            SolfegeChordText.make(chord, notation: displayNotation, size: 26)
        } else {
            Text(chord)
                .font(.system(size: 26, weight: .bold, design: .rounded))
        }
    }

    private var guestGroup: String {
        switch guestInstrument {
        case .piano: "piano"
        case .acoustic, .electric: "guitar"
        case .bass: "bass"
        }
    }

    private var guestInstrumentPicker: some View {
        VStack(spacing: PlatformDevice.isPhone ? 8 : 10) {
            PlatformSegmentedPicker(
                "View as",
                selection: Binding(
                    get: { guestGroup },
                    set: { group in
                        switch group {
                        case "piano": guestInstrumentRaw = ViewInstrument.piano.rawValue
                        case "bass": guestInstrumentRaw = ViewInstrument.bass.rawValue
                        default:
                            if guestGroup != "guitar" {
                                guestInstrumentRaw = ViewInstrument.acoustic.rawValue
                            }
                        }
                    }
                ),
                stringOptions: [
                    ("piano", "Piano"),
                    ("guitar", "Guitar"),
                    ("bass", "Bass")
                ]
            )

            if guestInstrument == .piano {
                Toggle(isOn: $beginnerPianoTriads) {
                    if PlatformDevice.isPhone {
                        Text(String(localized: "Beginner triads"))
                            .font(.subheadline.weight(.semibold))
                    } else {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(localized: "Beginner triads"))
                                .font(.subheadline.weight(.semibold))
                            Text(String(localized: "Show only major/minor triads from the host (Cmaj9 → C)"))
                                .font(.caption2)
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                    }
                }
                .tint(AppTheme.accent)
                .padding(.horizontal, 4)
            }

            if guestGroup == "guitar" {
                PlatformSegmentedPicker(
                    "Type",
                    selection: Binding(
                        get: { guestInstrument },
                        set: { guestInstrumentRaw = $0.rawValue }
                    ),
                    stringOptions: [
                        (ViewInstrument.acoustic, "Acoustic"),
                        (ViewInstrument.electric, "Electric")
                    ]
                )
            }

            if guestInstrument == .bass {
                PlatformSegmentedPicker(
                    "Strings",
                    selection: Binding(
                        get: { guestBassStrings },
                        set: { guestBassStrings = $0 }
                    ),
                    stringOptions: [
                        (4, "4 strings"),
                        (5, "5 strings"),
                        (6, "6 strings")
                    ]
                )
            }
        }
        .padding(.horizontal, 20)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Piano")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(AppTheme.textPrimary)
                Text(viewModel.payload.sessionName)
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
            }

            Spacer()

            if isHost {
                Button {
                    viewModel.clearPianoNotes()
                } label: {
                    Label("Clear", systemImage: "xmark")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(AppTheme.surfaceElevated)
                        .clipShape(Capsule())
                }
                .disabled(activeNotes.isEmpty)
                .opacity(activeNotes.isEmpty ? 0.4 : 1)

                overlayHeaderActions
            } else {
                overlayHeaderActions
            }
        }
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private var overlayHeaderActions: some View {
        HStack(spacing: 10) {
            if !isHost, let onLeaveSession {
                Button(action: onLeaveSession) {
                    Label("Leave", systemImage: "rectangle.portrait.and.arrow.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.red.opacity(0.9))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(AppTheme.surfaceElevated)
                        .clipShape(Capsule())
                }
                .accessibilityLabel("Leave Session")
            }

            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "chevron.down.circle.fill")
                        .font(.title2)
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .accessibilityLabel("Back to Chords")
            }
        }
    }

    private var midiStatus: some View {
        let connected = !viewModel.midiSources.isEmpty
        return HStack(spacing: 10) {
            Image(systemName: connected ? "pianokeys.inverse" : "cable.connector")
                .foregroundStyle(connected ? AppTheme.accent : AppTheme.textSecondary)
            Text(connected
                 ? "MIDI: \(viewModel.midiSources.joined(separator: ", "))"
                 : "Connect a MIDI keyboard via USB to play it here")
                .font(.caption.weight(.medium))
                .foregroundStyle(connected ? AppTheme.textPrimary : AppTheme.textSecondary)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(AppTheme.surfaceElevated)
        .clipShape(Capsule())
        .padding(.horizontal, 20)
    }

    private var noteDisplay: some View {
        let sorted = activeNotes.sorted()
        let notation = displayNotation
        let names = sorted.map { index in
            switch notation {
            case .latin:
                PianoNote.latinName(forStored: index, preferFlats: preferFlats)
            case .nashville:
                NashvilleConverter.number(
                    for: viewModel.singleNoteSymbol(for: index),
                    in: viewModel.payload.key
                )
            case .symbol:
                PianoNote.name(forStored: index, preferFlats: preferFlats, includeOctave: true)
            }
        }

        let pitchClasses = Set(sorted.map { PianoNote.pitchClass(forStored: $0) })
        let bass = sorted.first.map { PianoNote.pitchClass(forStored: $0) }
        let recognizedFromKeys = ChordRecognizer.symbol(
            forPitchClasses: pitchClasses,
            bassPitchClass: bass,
            preferFlats: preferFlats
        ) ?? sorted.first.map { viewModel.singleNoteSymbol(for: $0) }
        // Prefer the stabilized session chord so brief finger lifts don't chop the label.
        let hostSymbol = viewModel.payload.liveChordSymbol ?? recognizedFromKeys
        let displaySymbol: String? = {
            guard let hostSymbol else { return nil }
            if usesBeginnerPianoTriads,
               let simple = ChordTheory.beginnerTriadSymbol(for: hostSymbol, preferFlats: preferFlats) {
                return simple
            }
            return hostSymbol
        }()
        let chordName = displaySymbol.map { symbol in
            switch notation {
            case .latin: ChordCatalog.latinName(forSymbol: symbol)
            case .nashville:
                NashvilleConverter.number(for: symbol, in: viewModel.payload.key)
            case .symbol: symbol
            }
        }

        let primary = chordName ?? (names.isEmpty ? "—" : names.joined(separator: "  ·  "))
        let secondary: String = {
            if names.isEmpty {
                return chordName != nil
                    ? String(localized: "Last chord")
                    : String(localized: "No note selected")
            }
            if chordName != nil { return names.joined(separator: "  ·  ") }
            return String(localized: "Now showing")
        }()

        let primaryText: Text = {
            if let chordName, notation == .latin || notation == .nashville {
                return SolfegeChordText.make(chordName, notation: notation, size: chordLabelSize)
            }
            return Text(primary).font(.system(size: chordLabelSize, weight: .bold, design: .rounded))
        }()

        return VStack(spacing: 4) {
            primaryText
                .foregroundStyle(AppTheme.accent)
                .minimumScaleFactor(0.35)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .transaction { transaction in
                    if isHost {
                        transaction.animation = nil
                    }
                }

            Text(secondary)
                .font(.caption.weight(.medium))
                .foregroundStyle(AppTheme.textSecondary)
                .textCase(chordName == nil ? .uppercase : nil)
                .tracking(chordName == nil ? 1.1 : 0)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, isCompactHeight ? 6 : (PlatformDevice.isPhone ? 8 : 14))
        .padding(.horizontal, 16)
        .glassCard()
        .padding(.horizontal, PlatformDevice.isPhone ? 12 : 20)
    }
}

/// Chooses the most usable piano layout for the available width:
/// 1) Fit all 88 keys in one row when keys stay comfortable
/// 2) Otherwise stack C3+ above A0–B2 so each board stays reachable
/// 3) Compact-height (landscape phone): single scrolling row
private struct AdaptivePianoBoard: View {
    let activeNotes: Set<Int>
    let preferFlats: Bool
    let isInteractive: Bool
    let isCompactHeight: Bool
    var forceDualRow: Bool = false
    let onTap: (Int) -> Void

    private enum Layout {
        case fittedSingle
        case dualRow
        case scrollSingle
    }

    private func layout(for width: CGFloat) -> Layout {
        if isCompactHeight { return .scrollSingle }
        if forceDualRow { return .dualRow }
        if PianoNote.canFitComfortably(range: PianoNote.keyboardRange, in: width) {
            return .fittedSingle
        }
        return .dualRow
    }

    var body: some View {
        GeometryReader { geo in
            let boardLayout = layout(for: geo.size.width)
            switch boardLayout {
            case .fittedSingle:
                // Full 88-key span scaled to the viewport — no horizontal scroll.
                let keyHeight = min(geo.size.height, 280)
                PianoKeyboard(
                    activeNotes: activeNotes,
                    preferFlats: preferFlats,
                    isInteractive: isInteractive,
                    noteRange: PianoNote.keyboardRange,
                    onTap: onTap
                )
                .frame(width: geo.size.width, height: keyHeight)

            case .dualRow:
                // Fixed classic row height (~150) — never stretch keys to fill the sheet.
                let rowHeight: CGFloat = 150
                VStack(spacing: 8) {
                    pianoRow(
                        range: PianoNote.upperKeyboardRange,
                        defaultScrollTarget: PianoNote.middleC,
                        width: geo.size.width,
                        height: rowHeight
                    )
                    pianoRow(
                        range: PianoNote.lowerKeyboardRange,
                        defaultScrollTarget: PianoNote.lowerMiddleC,
                        width: geo.size.width,
                        height: rowHeight
                    )
                }
                .frame(width: geo.size.width, height: rowHeight * 2 + 8, alignment: .top)

            case .scrollSingle:
                ScrollablePianoKeyboard(
                    activeNotes: activeNotes,
                    preferFlats: preferFlats,
                    isInteractive: isInteractive,
                    onTap: onTap
                )
                .frame(width: geo.size.width, height: min(geo.size.height, 150))
            }
        }
    }

    @ViewBuilder
    private func pianoRow(
        range: ClosedRange<Int>,
        defaultScrollTarget: Int,
        width: CGFloat,
        height: CGFloat
    ) -> some View {
        if PianoNote.canFitComfortably(range: range, in: width) {
            PianoKeyboard(
                activeNotes: activeNotes,
                preferFlats: preferFlats,
                isInteractive: isInteractive,
                noteRange: range,
                onTap: onTap
            )
            .frame(width: width, height: height)
        } else {
            ScrollablePianoKeyboard(
                activeNotes: activeNotes,
                preferFlats: preferFlats,
                isInteractive: isInteractive,
                noteRange: range,
                defaultScrollTarget: defaultScrollTarget,
                onTap: onTap
            )
            .frame(width: width, height: height)
        }
    }
}

/// Scrollable piano row. Keeps a comfortable key width and scrolls when the range is wider than the viewport.
struct ScrollablePianoKeyboard: View {
    let activeNotes: Set<Int>
    let preferFlats: Bool
    let isInteractive: Bool
    var noteRange: ClosedRange<Int> = PianoNote.keyboardRange
    var defaultScrollTarget: Int = PianoNote.middleC
    let onTap: (Int) -> Void

    private let whiteKeyWidth: CGFloat = PianoNote.preferredWhiteKeyWidth

    private var keyboardWidth: CGFloat {
        let whiteCount = PianoNote.whiteKeyCount(in: noteRange)
        return CGFloat(whiteCount) * whiteKeyWidth
    }

    private func scrollToActiveNotes(_ proxy: ScrollViewProxy, notes: Set<Int>, animated: Bool) {
        // Center on the chord span (not only the lowest note) so guests see all tones.
        // Always scroll to a white key — black keys use `.offset`, so ScrollViewReader
        // would jump to the leading edge and hide Amaj / other sharp chords.
        let inRange = notes.filter { noteRange.contains($0) }.sorted()
        guard let first = inRange.first, let last = inRange.last else { return }
        let mid = (first + last) / 2
        let preferred = inRange.min(by: { abs($0 - mid) < abs($1 - mid) }) ?? first
        let target = scrollAnchorNote(near: preferred, in: inRange)
        let action = { proxy.scrollTo(target, anchor: UnitPoint.center) }
        if animated {
            withAnimation(.easeInOut(duration: 0.25), action)
        } else {
            action()
        }
    }

    /// Prefer a white key id for ScrollViewReader (black keys are overlay-offset).
    private func scrollAnchorNote(near preferred: Int, in notes: [Int]) -> Int {
        if !PianoNote.isBlack(preferred) { return preferred }
        let whiteNearby = notes.filter { !PianoNote.isBlack($0) }
        if let closest = whiteNearby.min(by: { abs($0 - preferred) < abs($1 - preferred) }) {
            return closest
        }
        // Fall back to the white key under / beside the black note.
        let below = preferred - 1
        if noteRange.contains(below), !PianoNote.isBlack(below) { return below }
        let above = preferred + 1
        if noteRange.contains(above), !PianoNote.isBlack(above) { return above }
        return preferred
    }

    private func scrollToDefault(_ proxy: ScrollViewProxy) {
        let target = noteRange.contains(defaultScrollTarget)
            ? defaultScrollTarget
            : noteRange.lowerBound
        proxy.scrollTo(target, anchor: .center)
    }

    var body: some View {
        GeometryReader { geo in
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: true) {
                    PianoKeyboard(
                        activeNotes: activeNotes,
                        preferFlats: preferFlats,
                        isInteractive: isInteractive,
                        noteRange: noteRange,
                        onTap: onTap
                    )
                    .frame(width: max(keyboardWidth, geo.size.width), height: geo.size.height)
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .onAppear {
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(100))
                        if activeNotes.contains(where: { noteRange.contains($0) }) {
                            scrollToActiveNotes(proxy, notes: activeNotes, animated: false)
                        } else {
                            scrollToDefault(proxy)
                        }
                    }
                }
                .onChange(of: activeNotes) { _, newNotes in
                    scrollToActiveNotes(proxy, notes: newNotes, animated: false)
                }
            }
        }
    }
}

/// Piano keyboard using internal note indices (0 = C0). Full span A0 (9) … C8 (96).
struct PianoKeyboard: View {
    let activeNotes: Set<Int>
    let preferFlats: Bool
    let isInteractive: Bool
    var noteRange: ClosedRange<Int> = PianoNote.keyboardRange
    let onTap: (Int) -> Void

    init(
        activeNotes: Set<Int>,
        preferFlats: Bool,
        isInteractive: Bool,
        noteRange: ClosedRange<Int> = PianoNote.keyboardRange,
        onTap: @escaping (Int) -> Void
    ) {
        self.activeNotes = activeNotes
        self.preferFlats = preferFlats
        self.isInteractive = isInteractive
        self.noteRange = noteRange
        self.onTap = onTap
    }

    private var whiteIndices: [Int] {
        noteRange.filter { !PianoNote.isBlack($0) }
    }

    private struct BlackKeyPlacement: Identifiable {
        let index: Int
        let whiteSlot: Int
        var id: Int { index }
    }

    private var blackKeyPlacements: [BlackKeyPlacement] {
        whiteIndices.enumerated().compactMap { slot, whiteIndex in
            guard [0, 2, 5, 7, 9].contains(PianoNote.pitchClass(of: whiteIndex)) else { return nil }
            let blackIndex = whiteIndex + 1
            guard noteRange.contains(blackIndex) else { return nil }
            return BlackKeyPlacement(index: blackIndex, whiteSlot: slot)
        }
    }

    private func isActive(_ index: Int) -> Bool {
        activeNotes.contains(index)
    }

    private func resolveNote(
        at point: CGPoint,
        whiteWidth: CGFloat,
        blackWidth: CGFloat,
        blackHeight: CGFloat,
        height: CGFloat
    ) -> Int? {
        let hitPadding: CGFloat = 6

        if point.y <= blackHeight + hitPadding {
            for placement in blackKeyPlacements {
                let centerX = CGFloat(placement.whiteSlot + 1) * whiteWidth
                let minX = centerX - blackWidth / 2 - hitPadding
                let maxX = centerX + blackWidth / 2 + hitPadding
                if point.x >= minX, point.x <= maxX {
                    return placement.index
                }
            }
        }

        guard point.y >= blackHeight - hitPadding, point.y <= height else { return nil }

        let slot = Int(point.x / whiteWidth)
        guard slot >= 0, slot < whiteIndices.count else { return nil }
        return whiteIndices[slot]
    }

    var body: some View {
        GeometryReader { geo in
            let whiteCount = max(1, whiteIndices.count)
            let whiteWidth = geo.size.width / CGFloat(whiteCount)
            let blackWidth = min(whiteWidth * 0.64, whiteWidth - 2)
            let blackHeight = geo.size.height * 0.64
            let labelFontSize = min(13, max(10, whiteWidth * 0.38))
            let blackLabelFontSize = min(11, max(9, whiteWidth * 0.32))

            ZStack(alignment: .topLeading) {
                HStack(spacing: 0) {
                    ForEach(whiteIndices, id: \.self) { index in
                        WhiteKey(
                            label: PianoNote.keyboardLabel(for: index, preferFlats: preferFlats),
                            isActive: isActive(index),
                            labelFontSize: labelFontSize
                        )
                        .frame(width: whiteWidth, height: geo.size.height)
                        .id(index)
                    }
                }

        // Black keys are drawn with `.offset` (layout frame stays at leading edge).
        // Don't expose them as ScrollViewReader ids — scrolling to C#/F# jumped to x=0
        // and hid Amaj / other sharp chords on the guest piano.
        ForEach(blackKeyPlacements) { placement in
            BlackKey(
                label: PianoNote.keyboardLabel(for: placement.index, preferFlats: preferFlats),
                isActive: isActive(placement.index),
                labelFontSize: blackLabelFontSize
            )
            .frame(width: blackWidth, height: blackHeight)
            .offset(
                x: CGFloat(placement.whiteSlot + 1) * whiteWidth - blackWidth / 2,
                y: 0
            )
            .zIndex(1)
            .allowsHitTesting(false)
        }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .contentShape(Rectangle())
            .simultaneousGesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onEnded { value in
                        guard isInteractive else { return }
                        let travel = hypot(value.translation.width, value.translation.height)
                        guard travel < 12 else { return }
                        if let note = resolveNote(
                            at: value.location,
                            whiteWidth: whiteWidth,
                            blackWidth: blackWidth,
                            blackHeight: blackHeight,
                            height: geo.size.height
                        ) {
                            onTap(note)
                        }
                    }
            )
            .transaction { transaction in
                if isInteractive {
                    transaction.animation = .easeOut(duration: 0.04)
                }
            }
        }
    }
}

private struct WhiteKey: View {
    let label: String
    let isActive: Bool
    var labelFontSize: CGFloat = 11

    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(isActive ? AppTheme.accent : Color.white)
            .overlay(alignment: .bottom) {
                Text(label)
                    .font(.system(size: labelFontSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(isActive ? AppTheme.background : Color.black.opacity(0.5))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .padding(.horizontal, 1)
                    .padding(.bottom, max(4, labelFontSize * 0.6))
            }
            .shadow(color: isActive ? AppTheme.accent.opacity(0.5) : .clear, radius: 8)
            .padding(.horizontal, 1)
    }
}

private struct BlackKey: View {
    let label: String
    let isActive: Bool
    var labelFontSize: CGFloat = 8

    var body: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(isActive ? AppTheme.accentSecondary : Color(white: 0.08))
            .overlay(alignment: .bottom) {
                Text(label)
                    .font(.system(size: labelFontSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(isActive ? AppTheme.background : Color.white.opacity(0.72))
                    .minimumScaleFactor(0.45)
                    .lineLimit(1)
                    .padding(.horizontal, 1)
                    .padding(.bottom, max(3, labelFontSize * 0.45))
            }
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(Color.black.opacity(0.6), lineWidth: 1)
            )
            .shadow(color: isActive ? AppTheme.accentSecondary.opacity(0.6) : .black.opacity(0.4), radius: 5, y: 2)
    }
}
