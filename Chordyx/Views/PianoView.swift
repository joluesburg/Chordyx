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

    private var isHost: Bool { viewModel.role == .host }
    private var preferFlats: Bool { viewModel.payload.key.prefersFlats }
    private var activeNotes: [Int] {
        viewModel.payload.pianoNotes.map { PianoNote.normalizeToInternal($0) }
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

    private var instrumentBoardHeight: CGFloat {
        if isCompactHeight { return 150 }
        return showsFullPianoKeyboard ? 280 : 240
    }

    var body: some View {
        ZStack {
            AppTheme.backgroundGradient.ignoresSafeArea()

            VStack(spacing: isCompactHeight ? 10 : 20) {
                header

                if isHost {
                    midiStatus
                } else {
                    guestInstrumentPicker
                }

                noteDisplay

                if !showsFullPianoKeyboard && !isCompactHeight {
                    Spacer()
                }

                if showFretboardForGuest, let fret = guestInstrument.fretInstrument {
                    FretboardView(
                        instrument: fret,
                        bassStrings: guestBassStrings,
                        pitchClasses: fretboardPitchClasses,
                        rootPitchClass: rootPitchClass,
                        preferFlats: preferFlats,
                        isCompactHeight: isCompactHeight
                    )
                    .frame(height: instrumentBoardHeight)
                    .frame(maxHeight: isCompactHeight ? instrumentBoardHeight : (showsFullPianoKeyboard ? .infinity : 240))
                    .layoutPriority(1)
                    .padding(.horizontal, showsFullPianoKeyboard || isCompactHeight ? 12 : 12)
                } else {
                    ScrollablePianoKeyboard(
                        activeNotes: activeNoteSet,
                        preferFlats: preferFlats,
                        isInteractive: isHost,
                        onTap: { viewModel.playPianoNote($0) }
                    )
                    .frame(height: instrumentBoardHeight)
                    .frame(maxHeight: isCompactHeight ? instrumentBoardHeight : (showsFullPianoKeyboard ? .infinity : 240))
                    .layoutPriority(showsFullPianoKeyboard || isCompactHeight ? 1 : 0)
                    .padding(.horizontal, showsFullPianoKeyboard ? 16 : 12)
                }

                if isHost {
                    Text("Tap keys to show the notes to everyone in the session")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.textSecondary)
                        .multilineTextAlignment(.center)
                } else {
                    Label("Following the host · your view", systemImage: "dot.radiowaves.left.and.right")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(AppTheme.accentSecondary)
                }

                if showsFullPianoKeyboard && !isCompactHeight {
                    Spacer(minLength: 12)
                } else if !isCompactHeight {
                    Spacer(minLength: 8)
                }
            }
            .padding(.vertical, isCompactHeight ? 8 : (showsFullPianoKeyboard ? 16 : 24))
        }
        .preferredColorScheme(.dark)
    }

    private var guestGroup: String {
        switch guestInstrument {
        case .piano: "piano"
        case .acoustic, .electric: "guitar"
        case .bass: "bass"
        }
    }

    private var guestInstrumentPicker: some View {
        VStack(spacing: 10) {
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
        let recognized = viewModel.payload.liveChordSymbol ?? recognizedFromKeys
        let chordName = recognized.map { symbol in
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
                return SolfegeChordText.make(chordName, notation: notation, size: 44)
            }
            return Text(primary).font(.system(size: 44, weight: .bold, design: .rounded))
        }()

        return VStack(spacing: 6) {
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
        .padding(.vertical, isCompactHeight ? 12 : 24)
        .padding(.horizontal, 20)
        .glassCard()
        .padding(.horizontal, 20)
    }
}

/// Full 88-key piano (A0–C8). Scrolls horizontally on every platform.
struct ScrollablePianoKeyboard: View {
    let activeNotes: Set<Int>
    let preferFlats: Bool
    let isInteractive: Bool
    let onTap: (Int) -> Void

    private let whiteKeyWidth: CGFloat = 46
    private let noteRange = PianoNote.keyboardRange

    private var keyboardWidth: CGFloat {
        let whiteCount = noteRange.filter { !PianoNote.isBlack($0) }.count
        return CGFloat(whiteCount) * whiteKeyWidth
    }

    private func scrollTarget(for notes: Set<Int>) -> Int {
        if let lowest = notes.filter({ noteRange.contains($0) }).min() {
            return lowest
        }
        return PianoNote.middleC
    }

    private func scrollToActiveNotes(_ proxy: ScrollViewProxy, notes: Set<Int>, animated: Bool) {
        let target = scrollTarget(for: notes)
        let action = { proxy.scrollTo(target, anchor: .center) }
        if animated {
            withAnimation(.easeInOut(duration: 0.25), action)
        } else {
            action()
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: true) {
                PianoKeyboard(
                    activeNotes: activeNotes,
                    preferFlats: preferFlats,
                    isInteractive: isInteractive,
                    noteRange: noteRange,
                    onTap: onTap
                )
                .frame(width: max(keyboardWidth, 320))
            }
            .onAppear {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(100))
                    scrollToActiveNotes(proxy, notes: activeNotes, animated: false)
                }
            }
            .onChange(of: activeNotes) { _, newNotes in
                scrollToActiveNotes(proxy, notes: newNotes, animated: false)
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
                    .id(placement.index)
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
