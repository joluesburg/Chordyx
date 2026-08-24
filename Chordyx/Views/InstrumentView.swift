//
//  InstrumentView.swift
//  Chordyx
//

import SwiftUI

struct InstrumentView: View {
    @ObservedObject var viewModel: SessionViewModel
    var onDismiss: (() -> Void)? = nil
    var onLeaveSession: (() -> Void)? = nil

    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var isHost: Bool { viewModel.role == .host }
    private var preferFlats: Bool { viewModel.payload.key.prefersFlats }
    private var instrument: FretInstrument { viewModel.payload.fretInstrument }

    private var activeFretChord: ChordEntry? { viewModel.fretChord }

    /// iPhone landscape (and similar short heights) — keep chrome thin so the board stays readable.
    private var isCompactHeight: Bool {
        verticalSizeClass == .compact
    }

    private var chordTones: (root: Int, pitchClasses: Set<Int>)? {
        guard let symbol = viewModel.fretChord?.symbolName else { return nil }
        return ChordTheory.tones(for: symbol)
    }

    /// Bass shows only the chord root; guitar shows full chord tones.
    private var fretboardPitchClasses: Set<Int> {
        guard let tones = chordTones else { return [] }
        if instrument.isBass { return [tones.root] }
        return tones.pitchClasses
    }

    var body: some View {
        ZStack {
            AppTheme.backgroundGradient.ignoresSafeArea()

            if isCompactHeight {
                compactLandscapeLayout
            } else {
                portraitLayout
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Portrait

    private var portraitLayout: some View {
        VStack(spacing: 18) {
            header

            if isHost {
                instrumentPicker
                if instrument.isBass {
                    bassStringPicker
                } else {
                    guitarTypePicker
                }
                chordPicker
            } else {
                guestInstrumentLabel
            }

            chordTitle(size: 34)

            fretboard
                .frame(maxHeight: .infinity)
                .layoutPriority(1)
                .padding(.horizontal, 16)

            legend

            if !isHost {
                followingHostLabel
            }
        }
        .padding(.vertical, 24)
    }

    // MARK: - Landscape / compact height

    private var compactLandscapeLayout: some View {
        VStack(spacing: 8) {
            header

            HStack(alignment: .top, spacing: 12) {
                compactControlsColumn
                    .frame(width: compactControlsWidth, alignment: .top)

                VStack(spacing: 6) {
                    HStack(alignment: .center, spacing: 12) {
                        chordTitle(size: 22)
                        Spacer(minLength: 0)
                        legend
                    }
                    .padding(.horizontal, 4)

                    fretboard
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .layoutPriority(1)

                    if !isHost {
                        followingHostLabel
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    private var compactControlsWidth: CGFloat {
        if horizontalSizeClass == .regular { return 260 }
        return 168
    }

    private var compactControlsColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isHost {
                instrumentPicker
                if instrument.isBass {
                    bassStringPicker
                } else {
                    guitarTypePicker
                }
                compactChordPicker
            } else {
                guestInstrumentLabel
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer(minLength: 0)
        }
    }

    private var compactChordPicker: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                if viewModel.sortedChords.isEmpty {
                    Text("Add chords to your progression to show them here")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(viewModel.sortedChords) { chord in
                        let isSelected = chord.id == viewModel.payload.fretChordID
                        Button {
                            viewModel.setFretChord(chord)
                        } label: {
                            chord.chordText(for: viewModel.payload.notation, size: 14, weight: .bold)
                                .foregroundStyle(isSelected ? AppTheme.background : AppTheme.textPrimary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .padding(.horizontal, 10)
                                .background(isSelected ? AppTheme.accent : AppTheme.surfaceElevated)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.trailing, 2)
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Shared pieces

    private var fretboard: some View {
        FretboardView(
            instrument: instrument,
            bassStrings: viewModel.payload.bassStrings,
            pitchClasses: fretboardPitchClasses,
            rootPitchClass: chordTones?.root,
            preferFlats: preferFlats,
            isCompactHeight: isCompactHeight
        )
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: isCompactHeight ? 0 : 2) {
                Text("Fretboard")
                    .font(isCompactHeight ? .headline.weight(.bold) : .title2.weight(.bold))
                    .foregroundStyle(AppTheme.textPrimary)
                if !isCompactHeight {
                    Text(viewModel.payload.sessionName)
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
            Spacer()
            overlayHeaderActions
        }
        .padding(.horizontal, isCompactHeight ? 12 : 20)
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
                        .font(isCompactHeight ? .title3 : .title2)
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .accessibilityLabel("Back to Chords")
            }
        }
    }

    private var instrumentPicker: some View {
        PlatformSegmentedPicker(
            "Instrument",
            selection: Binding(
                get: { instrument.isBass ? "bass" : "guitar" },
                set: { group in
                    if group == "bass" {
                        viewModel.setFretInstrument(.bass)
                    } else if instrument.isBass {
                        viewModel.setFretInstrument(.acoustic)
                    }
                }
            ),
            stringOptions: [
                ("guitar", "Guitar"),
                ("bass", "Bass")
            ]
        )
        .padding(.horizontal, isCompactHeight ? 0 : 20)
    }

    private var guitarTypePicker: some View {
        PlatformSegmentedPicker(
            "Type",
            selection: Binding(
                get: { instrument },
                set: { viewModel.setFretInstrument($0) }
            ),
            stringOptions: [
                (FretInstrument.acoustic, "Acoustic"),
                (FretInstrument.electric, "Electric")
            ]
        )
        .padding(.horizontal, isCompactHeight ? 0 : 20)
    }

    private var bassStringPicker: some View {
        PlatformSegmentedPicker(
            "Strings",
            selection: Binding(
                get: { viewModel.payload.bassStrings },
                set: { viewModel.setBassStrings($0) }
            ),
            stringOptions: isCompactHeight
                ? [(4, "4"), (5, "5"), (6, "6")]
                : [(4, "4 strings"), (5, "5 strings"), (6, "6 strings")]
        )
        .padding(.horizontal, isCompactHeight ? 0 : 20)
    }

    private var chordPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                if viewModel.sortedChords.isEmpty {
                    Text("Add chords to your progression to show them here")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                } else {
                    ForEach(viewModel.sortedChords) { chord in
                        let isSelected = chord.id == viewModel.payload.fretChordID
                        Button {
                            viewModel.setFretChord(chord)
                        } label: {
                            chord.chordText(for: viewModel.payload.notation, size: 15, weight: .bold)
                                .foregroundStyle(isSelected ? AppTheme.background : AppTheme.textPrimary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(isSelected ? AppTheme.accent : AppTheme.surfaceElevated)
                                .clipShape(Capsule())
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func chordTitle(size: CGFloat) -> some View {
        VStack(spacing: 2) {
            Group {
                if let chord = activeFretChord {
                    chord.chordText(for: viewModel.payload.notation, size: size)
                } else {
                    Text("—")
                        .font(.system(size: size, weight: .bold, design: .rounded))
                }
            }
            .foregroundStyle(AppTheme.accent)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: viewModel.payload.fretChordID)

            if !isCompactHeight {
                Text(instrument.isBass
                      ? String(localized: "Root note on the bass")
                      : String(localized: "Chord tones on the \(instrument.label.lowercased())"))
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
    }

    private var guestInstrumentLabel: some View {
        Text(instrument.isBass
             ? "Bass · \(viewModel.payload.bassStrings) strings"
             : "Guitar · \(instrument.label)")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(AppTheme.textSecondary)
            .padding(.horizontal, isCompactHeight ? 0 : 20)
    }

    private var followingHostLabel: some View {
        Label("Following the host's fretboard", systemImage: "dot.radiowaves.left.and.right")
            .font(.footnote.weight(.medium))
            .foregroundStyle(AppTheme.accentSecondary)
    }

    private var legend: some View {
        HStack(spacing: isCompactHeight ? 12 : 18) {
            legendDot(color: AppTheme.accent, label: String(localized: "Root"))
            if !instrument.isBass {
                legendDot(color: AppTheme.accentSecondary, label: String(localized: "Chord tone"))
            }
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(AppTheme.textSecondary)
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: isCompactHeight ? 10 : 12, height: isCompactHeight ? 10 : 12)
            Text(label)
        }
    }
}

/// A horizontal fretboard that marks every position where one of the given
/// pitch classes falls across the first frets. Works for any tuning and
/// string count, driven either by a chord or by live notes.
struct FretboardView: View {
    let instrument: FretInstrument
    let bassStrings: Int
    let pitchClasses: Set<Int>
    let rootPitchClass: Int?
    let preferFlats: Bool
    var isCompactHeight: Bool = false

    private let fretCount = 12

    private var tuning: [Int] {
        InstrumentTuning.pitchClasses(for: instrument, bassStrings: bassStrings)
    }

    private var woodColor: Color {
        switch instrument {
        case .acoustic: Color(red: 0.45, green: 0.30, blue: 0.16)
        case .electric: Color(red: 0.20, green: 0.21, blue: 0.26)
        case .bass: Color(red: 0.16, green: 0.13, blue: 0.22)
        }
    }

    var body: some View {
        GeometryReader { geo in
            let stringCount = max(tuning.count, 1)
            let openColumn = max(28, min(geo.size.width * (isCompactHeight ? 0.07 : 0.10), 56))
            let boardWidth = max(geo.size.width - openColumn, 1)
            let fretWidth = boardWidth / CGFloat(fretCount)
            // Cap row height so a tall full-screen container doesn't stretch strings.
            let maxRowHeight = max(fretWidth * (isCompactHeight ? 0.95 : 1.15), isCompactHeight ? 22 : 28)
            let rowHeight = min(geo.size.height / CGFloat(stringCount), maxRowHeight)
            let boardHeight = rowHeight * CGFloat(stringCount)
            let yOffset = max(0, (geo.size.height - boardHeight) / 2)
            let maxDot: CGFloat = isCompactHeight ? 26 : 34
            let minDot: CGFloat = isCompactHeight ? 12 : 16
            let dotSize = min(max(minDot, min(rowHeight * 0.72, fretWidth * 0.78)), maxDot)
            let openLabelSize: CGFloat = isCompactHeight ? 9 : 10
            let inlaySize: CGFloat = isCompactHeight ? 6 : 8

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: isCompactHeight ? 8 : 10)
                    .fill(woodColor)
                    .frame(width: boardWidth, height: boardHeight)
                    .offset(x: openColumn, y: yOffset)

                // Nut
                Rectangle()
                    .fill(Color.white.opacity(0.85))
                    .frame(width: isCompactHeight ? 4 : 5, height: boardHeight)
                    .offset(x: openColumn, y: yOffset)

                // Fret lines
                ForEach(1...fretCount, id: \.self) { fret in
                    Rectangle()
                        .fill(Color.white.opacity(0.25))
                        .frame(width: 1.5, height: boardHeight)
                        .offset(x: openColumn + CGFloat(fret) * fretWidth, y: yOffset)
                }

                // Inlay markers (frets 3,5,7,9,12)
                ForEach([3, 5, 7, 9, 12], id: \.self) { fret in
                    Circle()
                        .fill(Color.white.opacity(0.12))
                        .frame(width: inlaySize, height: inlaySize)
                        .position(
                            x: openColumn + (CGFloat(fret) - 0.5) * fretWidth,
                            y: yOffset + boardHeight / 2
                        )
                }

                // Strings (rows) - lowest string at the bottom
                ForEach(0..<stringCount, id: \.self) { stringIndex in
                    let y = yOffset + rowHeight * (CGFloat(stringCount - 1 - stringIndex) + 0.5)
                    let thickness = (isCompactHeight ? 0.8 : 1.0) + Double(stringCount - 1 - stringIndex) * (isCompactHeight ? 0.45 : 0.6)

                    Rectangle()
                        .fill(Color.white.opacity(0.55))
                        .frame(width: boardWidth + openColumn, height: thickness)
                        .position(x: geo.size.width / 2, y: y)
                }

                // Open-string note labels
                ForEach(0..<stringCount, id: \.self) { stringIndex in
                    let y = yOffset + rowHeight * (CGFloat(stringCount - 1 - stringIndex) + 0.5)
                    openMarker(
                        stringIndex: stringIndex,
                        x: openColumn / 2,
                        y: y,
                        dotSize: dotSize,
                        openLabelSize: openLabelSize
                    )
                }

                // Fretted chord tones — markers only; never change board geometry.
                if !pitchClasses.isEmpty {
                    ForEach(0..<stringCount, id: \.self) { stringIndex in
                        let y = yOffset + rowHeight * (CGFloat(stringCount - 1 - stringIndex) + 0.5)
                        ForEach(1...fretCount, id: \.self) { fret in
                            frettedMarker(
                                stringIndex: stringIndex,
                                fret: fret,
                                x: openColumn + (CGFloat(fret) - 0.5) * fretWidth,
                                y: y,
                                dotSize: dotSize
                            )
                        }
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
            // Chord tone updates should not animate board layout.
            .transaction { $0.animation = nil }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func openMarker(
        stringIndex: Int,
        x: CGFloat,
        y: CGFloat,
        dotSize: CGFloat,
        openLabelSize: CGFloat
    ) -> some View {
        let pc = tuning[stringIndex] % 12
        if pitchClasses.contains(pc) {
            noteDot(pc: pc, isRoot: pc == rootPitchClass, size: dotSize)
                .position(x: x, y: y)
        } else {
            Text((preferFlats ? Transposer.flatNames : Transposer.sharpNames)[pc])
                .font(.system(size: openLabelSize, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.textSecondary)
                .position(x: x, y: y)
        }
    }

    @ViewBuilder
    private func frettedMarker(stringIndex: Int, fret: Int, x: CGFloat, y: CGFloat, dotSize: CGFloat) -> some View {
        let pc = (tuning[stringIndex] + fret) % 12
        if pitchClasses.contains(pc) {
            noteDot(pc: pc, isRoot: pc == rootPitchClass, size: dotSize)
                .position(x: x, y: y)
        }
    }

    private func noteDot(pc: Int, isRoot: Bool, size: CGFloat) -> some View {
        Circle()
            .fill(isRoot ? AppTheme.accent : AppTheme.accentSecondary)
            .frame(width: size, height: size)
            .overlay(
                Text((preferFlats ? Transposer.flatNames : Transposer.sharpNames)[pc])
                    .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
                    .foregroundStyle(isRoot ? AppTheme.background : Color.white)
                    .minimumScaleFactor(0.5)
            )
            .shadow(color: .black.opacity(0.3), radius: isCompactHeight ? 2 : 3, y: 1)
    }
}
