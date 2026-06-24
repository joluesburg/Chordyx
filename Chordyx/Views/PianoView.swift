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
    private var activeNotes: [Int] { viewModel.payload.pianoNotes }

    // Guests render on the host's piano by default, but can switch locally.
    private var guestInstrument: ViewInstrument {
        ViewInstrument(rawValue: guestInstrumentRaw) ?? .piano
    }

    private var pitchClasses: Set<Int> {
        Set(activeNotes.map { PianoNote.pitchClass(of: $0) })
    }

    private var rootPitchClass: Int? {
        activeNotes.min().map { PianoNote.pitchClass(of: $0) }
    }

    private var showFretboardForGuest: Bool {
        !isHost && guestInstrument != .piano
    }

    private var displayNotation: ChordNotation {
        viewModel.displayNotation(isGuest: !isHost)
    }

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var showsFullPianoKeyboard: Bool {
        #if os(macOS)
        true
        #else
        horizontalSizeClass == .regular
        #endif
    }

    var body: some View {
        ZStack {
            AppTheme.backgroundGradient.ignoresSafeArea()

            VStack(spacing: 20) {
                header

                if isHost {
                    midiStatus
                } else {
                    guestInstrumentPicker
                }

                noteDisplay

                if !showsFullPianoKeyboard {
                    Spacer()
                }

                if showFretboardForGuest, let fret = guestInstrument.fretInstrument {
                    FretboardView(
                        instrument: fret,
                        bassStrings: guestBassStrings,
                        pitchClasses: pitchClasses,
                        rootPitchClass: rootPitchClass,
                        preferFlats: preferFlats
                    )
                    .frame(height: showsFullPianoKeyboard ? 280 : 240)
                    .frame(maxHeight: showsFullPianoKeyboard ? .infinity : 240)
                    .padding(.horizontal, showsFullPianoKeyboard ? 16 : 12)
                } else {
                    ScrollablePianoKeyboard(
                        activeNotes: Set(activeNotes),
                        preferFlats: preferFlats,
                        isInteractive: isHost,
                        onTap: { viewModel.playPianoNote($0) }
                    )
                    .frame(height: showsFullPianoKeyboard ? 280 : 240)
                    .frame(maxHeight: showsFullPianoKeyboard ? .infinity : 240)
                    .layoutPriority(showsFullPianoKeyboard ? 1 : 0)
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

                if showsFullPianoKeyboard {
                    Spacer(minLength: 12)
                } else {
                    Spacer(minLength: 8)
                }
            }
            .padding(.vertical, showsFullPianoKeyboard ? 16 : 24)
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
            Picker("View as", selection: Binding(
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
            )) {
                Text("Piano").tag("piano")
                Text("Guitar").tag("guitar")
                Text("Bass").tag("bass")
            }
            .pickerStyle(.segmented)

            if guestGroup == "guitar" {
                Picker("Type", selection: Binding(
                    get: { guestInstrument },
                    set: { guestInstrumentRaw = $0.rawValue }
                )) {
                    Text("Acoustic").tag(ViewInstrument.acoustic)
                    Text("Electric").tag(ViewInstrument.electric)
                }
                .pickerStyle(.segmented)
            }

            if guestInstrument == .bass {
                Picker("Strings", selection: Binding(
                    get: { guestBassStrings },
                    set: { guestBassStrings = $0 }
                )) {
                    ForEach([4, 5, 6], id: \.self) { count in
                        Text("\(count) strings").tag(count)
                    }
                }
                .pickerStyle(.segmented)
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
                PianoNote.latinName(of: index, preferFlats: preferFlats)
            case .nashville:
                NashvilleConverter.number(
                    for: viewModel.singleNoteSymbol(for: index),
                    in: viewModel.payload.key
                )
            case .symbol:
                PianoNote.name(of: index, preferFlats: preferFlats, includeOctave: true)
            }
        }

        let pitchClasses = Set(sorted.map { PianoNote.pitchClass(of: $0) })
        let bass = sorted.first.map { PianoNote.pitchClass(of: $0) }
        let recognized = ChordRecognizer.symbol(forPitchClasses: pitchClasses, bassPitchClass: bass, preferFlats: preferFlats)
            ?? sorted.first.map { viewModel.singleNoteSymbol(for: $0) }
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
            if names.isEmpty { return "No note selected" }
            if chordName != nil { return names.joined(separator: "  ·  ") }
            return "Now showing"
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
                .minimumScaleFactor(0.4)
                .lineLimit(1)
                .animation(.spring(response: 0.3, dampingFraction: 0.75), value: activeNotes)

            Text(secondary)
                .font(.caption.weight(.medium))
                .foregroundStyle(AppTheme.textSecondary)
                .textCase(chordName == nil ? .uppercase : nil)
                .tracking(chordName == nil ? 1.1 : 0)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, 20)
        .glassCard()
        .padding(.horizontal, 20)
    }
}

/// Full 88-key piano (A0–C8). On iPad and Mac the entire keyboard fits the width;
/// on iPhone it scrolls horizontally and auto-centers on active notes.
struct ScrollablePianoKeyboard: View {
    let activeNotes: Set<Int>
    let preferFlats: Bool
    let isInteractive: Bool
    let onTap: (Int) -> Void

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var showsFullKeyboard: Bool {
        #if os(macOS)
        true
        #else
        horizontalSizeClass == .regular
        #endif
    }

    private let whiteKeyWidth: CGFloat = 36

    private var keyboardWidth: CGFloat {
        CGFloat(PianoKeyboard.defaultRange.filter { !PianoNote.isBlack($0) }.count) * whiteKeyWidth
    }

    /// The white key nearest the center of the active notes, used as scroll target.
    private func scrollTarget(for notes: Set<Int>) -> Int? {
        guard let low = notes.min(), let high = notes.max() else { return nil }
        var center = (low + high) / 2
        center = min(max(center, PianoKeyboard.defaultRange.lowerBound), PianoKeyboard.defaultRange.upperBound)
        while PianoNote.isBlack(center) { center -= 1 }
        return center
    }

    var body: some View {
        if showsFullKeyboard {
            PianoKeyboard(
                activeNotes: activeNotes,
                preferFlats: preferFlats,
                isInteractive: isInteractive,
                onTap: onTap
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    PianoKeyboard(
                        activeNotes: activeNotes,
                        preferFlats: preferFlats,
                        isInteractive: isInteractive,
                        onTap: onTap
                    )
                    .frame(width: keyboardWidth)
                }
                .onAppear {
                    proxy.scrollTo(scrollTarget(for: activeNotes) ?? 48, anchor: .center)
                }
                .onChange(of: activeNotes) { _, newNotes in
                    guard let target = scrollTarget(for: newNotes) else { return }
                    withAnimation(.easeInOut(duration: 0.25)) {
                        proxy.scrollTo(target, anchor: .center)
                    }
                }
            }
        }
    }
}

/// A piano keyboard spanning a configurable note range. White keys are laid
/// out edge to edge; black keys are overlaid on the boundaries between them.
struct PianoKeyboard: View {
    /// A0 (index 9) through C8 (index 96) — the full 88-key piano range.
    static let defaultRange = 9...96

    let activeNotes: Set<Int>
    let preferFlats: Bool
    let isInteractive: Bool
    var noteRange: ClosedRange<Int> = defaultRange
    let onTap: (Int) -> Void

    init(
        activeNotes: Set<Int>,
        preferFlats: Bool,
        isInteractive: Bool,
        noteRange: ClosedRange<Int> = defaultRange,
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

    /// Black keys with the number of white keys that precede them (for x placement).
    private var blackPlacements: [(index: Int, whiteCountBefore: Int)] {
        var result: [(Int, Int)] = []
        var whiteCount = 0
        for index in noteRange {
            if PianoNote.isBlack(index) {
                result.append((index, whiteCount))
            } else {
                whiteCount += 1
            }
        }
        return result
    }

    var body: some View {
        GeometryReader { geo in
            let whiteCount = whiteIndices.count
            let whiteWidth = geo.size.width / CGFloat(whiteCount)
            let blackWidth = whiteWidth * 0.62
            let blackHeight = geo.size.height * 0.62

            ZStack(alignment: .topLeading) {
                HStack(spacing: 0) {
                    ForEach(whiteIndices, id: \.self) { index in
                        WhiteKey(
                            label: PianoNote.name(of: index, preferFlats: preferFlats, includeOctave: PianoNote.pitchClass(of: index) == 0),
                            isActive: activeNotes.contains(index),
                            labelFontSize: min(11, max(7, whiteWidth * 0.42))
                        )
                        .frame(width: whiteWidth)
                        .id(index)
                        .onTapGesture { if isInteractive { onTap(index) } }
                    }
                }

                ForEach(blackPlacements, id: \.index) { placement in
                    BlackKey(isActive: activeNotes.contains(placement.index))
                        .frame(width: blackWidth, height: blackHeight)
                        .position(
                            x: CGFloat(placement.whiteCountBefore) * whiteWidth,
                            y: blackHeight / 2
                        )
                        .onTapGesture { if isInteractive { onTap(placement.index) } }
                }
            }
            .animation(.easeOut(duration: 0.12), value: activeNotes)
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
    let isActive: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(isActive ? AppTheme.accentSecondary : Color(white: 0.08))
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(Color.black.opacity(0.6), lineWidth: 1)
            )
            .shadow(color: isActive ? AppTheme.accentSecondary.opacity(0.6) : .black.opacity(0.4), radius: 5, y: 2)
    }
}
