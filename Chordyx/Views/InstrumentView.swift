//
//  InstrumentView.swift
//  Chordyx
//

import SwiftUI

struct InstrumentView: View {
    @Bindable var viewModel: SessionViewModel
    var onDismiss: (() -> Void)? = nil
    var onLeaveSession: (() -> Void)? = nil

    private var isHost: Bool { viewModel.role == .host }
    private var preferFlats: Bool { viewModel.payload.key.prefersFlats }
    private var instrument: FretInstrument { viewModel.payload.fretInstrument }

    private var activeFretChord: ChordEntry? { viewModel.fretChord }

    private var chordTones: (root: Int, pitchClasses: Set<Int>)? {
        guard let symbol = viewModel.fretChord?.symbolName else { return nil }
        return ChordTheory.tones(for: symbol)
    }

    var body: some View {
        ZStack {
            AppTheme.backgroundGradient.ignoresSafeArea()

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
                    Text(instrument.isBass
                         ? "Bass · \(viewModel.payload.bassStrings) strings"
                         : "Guitar · \(instrument.label)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textSecondary)
                }

                chordTitle

                FretboardView(
                    instrument: instrument,
                    bassStrings: viewModel.payload.bassStrings,
                    pitchClasses: chordTones?.pitchClasses ?? [],
                    rootPitchClass: chordTones?.root,
                    preferFlats: preferFlats
                )
                .frame(maxHeight: .infinity)
                .padding(.horizontal, 16)

                legend

                if !isHost {
                    Label("Following the host's fretboard", systemImage: "dot.radiowaves.left.and.right")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(AppTheme.accentSecondary)
                }
            }
            .padding(.vertical, 24)
        }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Fretboard")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(AppTheme.textPrimary)
                Text(viewModel.payload.sessionName)
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
            }
            Spacer()
            overlayHeaderActions
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

    private var instrumentPicker: some View {
        Picker("Instrument", selection: Binding(
            get: { instrument.isBass ? "bass" : "guitar" },
            set: { group in
                if group == "bass" {
                    viewModel.setFretInstrument(.bass)
                } else if instrument.isBass {
                    viewModel.setFretInstrument(.acoustic)
                }
            }
        )) {
            Text("Guitar").tag("guitar")
            Text("Bass").tag("bass")
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 20)
    }

    private var guitarTypePicker: some View {
        Picker("Type", selection: Binding(
            get: { instrument },
            set: { viewModel.setFretInstrument($0) }
        )) {
            Text("Acoustic").tag(FretInstrument.acoustic)
            Text("Electric").tag(FretInstrument.electric)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 20)
    }

    private var bassStringPicker: some View {
        Picker("Strings", selection: Binding(
            get: { viewModel.payload.bassStrings },
            set: { viewModel.setBassStrings($0) }
        )) {
            ForEach([4, 5, 6], id: \.self) { count in
                Text("\(count) strings").tag(count)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 20)
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

    private var chordTitle: some View {
        VStack(spacing: 2) {
            Group {
                if let chord = activeFretChord {
                    chord.chordText(for: viewModel.payload.notation, size: 34)
                } else {
                    Text("—")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                }
            }
            .foregroundStyle(AppTheme.accent)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: viewModel.payload.fretChordID)
            Text("Chord tones on the \(instrument.label.lowercased())")
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
        }
    }

    private var legend: some View {
        HStack(spacing: 18) {
            legendDot(color: AppTheme.accent, label: "Root")
            legendDot(color: AppTheme.accentSecondary, label: "Chord tone")
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(AppTheme.textSecondary)
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 12, height: 12)
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
            let stringCount = tuning.count
            let openColumn = geo.size.width * 0.10
            let boardWidth = geo.size.width - openColumn
            let fretWidth = boardWidth / CGFloat(fretCount)
            let rowHeight = geo.size.height / CGFloat(stringCount)
            let dotSize = min(rowHeight * 0.7, fretWidth * 0.8, 34)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(woodColor)
                    .frame(width: boardWidth, height: geo.size.height)
                    .offset(x: openColumn)

                // Nut
                Rectangle()
                    .fill(Color.white.opacity(0.85))
                    .frame(width: 5, height: geo.size.height)
                    .offset(x: openColumn)

                // Fret lines
                ForEach(1...fretCount, id: \.self) { fret in
                    Rectangle()
                        .fill(Color.white.opacity(0.25))
                        .frame(width: 1.5, height: geo.size.height)
                        .offset(x: openColumn + CGFloat(fret) * fretWidth)
                }

                // Inlay markers (frets 3,5,7,9,12)
                ForEach([3, 5, 7, 9, 12], id: \.self) { fret in
                    Circle()
                        .fill(Color.white.opacity(0.12))
                        .frame(width: 8, height: 8)
                        .position(
                            x: openColumn + (CGFloat(fret) - 0.5) * fretWidth,
                            y: geo.size.height / 2
                        )
                }

                // Strings (rows) - lowest string at the bottom
                ForEach(0..<stringCount, id: \.self) { stringIndex in
                    let y = rowHeight * (CGFloat(stringCount - 1 - stringIndex) + 0.5)
                    let thickness = 1.0 + Double(stringCount - 1 - stringIndex) * 0.6

                    Rectangle()
                        .fill(Color.white.opacity(0.55))
                        .frame(height: thickness)
                        .frame(maxWidth: .infinity)
                        .position(x: geo.size.width / 2, y: y)
                }

                // Open-string note labels
                ForEach(0..<stringCount, id: \.self) { stringIndex in
                    let y = rowHeight * (CGFloat(stringCount - 1 - stringIndex) + 0.5)
                    openMarker(stringIndex: stringIndex, x: openColumn / 2, y: y, dotSize: dotSize)
                }

                // Fretted chord tones
                if !pitchClasses.isEmpty {
                    ForEach(0..<stringCount, id: \.self) { stringIndex in
                        let y = rowHeight * (CGFloat(stringCount - 1 - stringIndex) + 0.5)
                        ForEach(1...fretCount, id: \.self) { fret in
                            frettedMarker(stringIndex: stringIndex, fret: fret, x: openColumn + (CGFloat(fret) - 0.5) * fretWidth, y: y, dotSize: dotSize)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func openMarker(stringIndex: Int, x: CGFloat, y: CGFloat, dotSize: CGFloat) -> some View {
        let pc = tuning[stringIndex] % 12
        if pitchClasses.contains(pc) {
            noteDot(pc: pc, isRoot: pc == rootPitchClass, size: dotSize)
                .position(x: x, y: y)
        } else {
            Text((preferFlats ? Transposer.flatNames : Transposer.sharpNames)[pc])
                .font(.system(size: 10, weight: .semibold, design: .rounded))
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
            .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
    }
}
