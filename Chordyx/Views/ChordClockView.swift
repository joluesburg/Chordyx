//
//  ChordClockView.swift
//  Chordyx
//
//  iPhone guest Live view — watch-face dial: beats on the rim, progression around
//  the chapter ring, huge current chord in the center, NEXT / section / tempo complications.
//

import SwiftUI

struct ChordClockView: View {
    @ObservedObject var viewModel: SessionViewModel
    @ObservedObject private var metronome: MetronomeEngine
    var isGuest: Bool = true
    var chords: [ChordEntry]
    var guestTranspose: Int = 0
    var guestCapo: Int = 0

    init(
        viewModel: SessionViewModel,
        isGuest: Bool = true,
        chords: [ChordEntry],
        guestTranspose: Int = 0,
        guestCapo: Int = 0
    ) {
        _viewModel = ObservedObject(wrappedValue: viewModel)
        _metronome = ObservedObject(wrappedValue: viewModel.metronome)
        self.isGuest = isGuest
        self.chords = chords
        self.guestTranspose = guestTranspose
        self.guestCapo = guestCapo
    }

    private let maxDialChords = 12

    private var notation: ChordNotation {
        viewModel.displayNotation(isGuest: isGuest)
    }

    private var dialChords: [ChordEntry] {
        guard !chords.isEmpty else { return [] }
        if chords.count <= maxDialChords { return chords }
        // Window centered on the active chord so long progressions still fit a watch dial.
        let activeIndex = chords.firstIndex(where: isActive(chord:)) ?? 0
        let half = maxDialChords / 2
        let start = max(0, min(activeIndex - half, chords.count - maxDialChords))
        return Array(chords[start..<(start + maxDialChords)])
    }

    private var currentChord: ChordEntry? {
        viewModel.guestVisibleChord(preferLivePiano: true)
            ?? chords.first(where: isActive(chord:))
            ?? viewModel.activeChord
    }

    private var currentName: String {
        guard let chord = currentChord else { return "—" }
        return displayName(for: chord)
    }

    private var nextName: String? {
        guard !viewModel.payload.isLiveChordsOnly else { return nil }
        guard viewModel.payload.pianoNotes.isEmpty else { return nil }
        guard let chord = viewModel.upcomingChord else { return nil }
        return displayName(for: chord)
    }

    private var activeDialIndex: Int? {
        dialChords.firstIndex(where: isActive(chord:))
    }

    private var handAngle: Angle {
        guard let index = activeDialIndex, !dialChords.isEmpty else {
            return .degrees(-90)
        }
        // 12 o'clock start, clockwise — same as a watch.
        let step = 360.0 / Double(dialChords.count)
        return .degrees(-90 + Double(index) * step)
    }

    private var beatsPerBar: Int {
        max(1, viewModel.payload.beatsPerBar)
    }

    private var currentBeat: Int {
        metronome.currentBeat
    }

    private var metronomePlaying: Bool {
        viewModel.displayedMetronomePlaying
    }

    private var tempoLabel: String {
        let bpm = Int(viewModel.displayedSessionTempoBPM.rounded())
        return "\(bpm)"
    }

    private var sectionLabel: String? {
        if let cue = viewModel.payload.activeCue {
            return cue.text.uppercased()
        }
        return viewModel.activeSection?.name.uppercased()
    }

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let outerRadius = side * 0.46
            let dialRadius = side * 0.38
            let handLength = dialRadius * 0.72

            ZStack {
                // Soft face
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                AppTheme.surfaceElevated.opacity(0.9),
                                AppTheme.background.opacity(0.2)
                            ],
                            center: .center,
                            startRadius: 20,
                            endRadius: outerRadius
                        )
                    )
                    .frame(width: outerRadius * 2.05, height: outerRadius * 2.05)
                    .position(center)

                // Outer chapter ring stroke
                Circle()
                    .stroke(AppTheme.ringStroke.opacity(0.55), lineWidth: max(2, side * 0.008))
                    .frame(width: dialRadius * 2, height: dialRadius * 2)
                    .position(center)

                beatRim(center: center, radius: outerRadius, side: side)

                chordDial(center: center, radius: dialRadius, side: side)

                hand(center: center, length: handLength)
                    .animation(.spring(response: 0.42, dampingFraction: 0.78), value: activeDialIndex)
                    .animation(.spring(response: 0.42, dampingFraction: 0.78), value: currentName)

                centerFace(side: side)
                    .position(center)

                complications(center: center, outerRadius: outerRadius, side: side)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilitySummary)
        }
    }

    private var accessibilitySummary: String {
        var parts = [String(format: String(localized: "Current chord %@"), currentName)]
        if metronomePlaying {
            parts.append(String(format: String(localized: "Beat %lld of %lld"), currentBeat + 1, beatsPerBar))
        }
        if let nextName {
            parts.append(String(format: String(localized: "Next %@"), nextName))
        }
        return parts.joined(separator: ". ")
    }

    // MARK: - Layers

    @ViewBuilder
    private func beatRim(center: CGPoint, radius: CGFloat, side: CGFloat) -> some View {
        ForEach(0..<beatsPerBar, id: \.self) { beat in
            let angle = Angle.degrees(-90 + Double(beat) * (360.0 / Double(beatsPerBar)))
            let isCurrent = metronomePlaying && currentBeat == beat
            let tickLength = isCurrent ? side * 0.045 : side * 0.028
            let tickWidth = isCurrent ? max(3, side * 0.012) : max(2, side * 0.007)
            let mid = radius - tickLength / 2

            Capsule()
                .fill(isCurrent ? AppTheme.accent : AppTheme.chordInactive.opacity(0.85))
                .frame(width: tickWidth, height: tickLength)
                .scaleEffect(isCurrent ? 1.15 : 1)
                .shadow(color: isCurrent ? AppTheme.accent.opacity(0.45) : .clear, radius: 6)
                .position(
                    x: center.x + mid * CGFloat(cos(angle.radians)),
                    y: center.y + mid * CGFloat(sin(angle.radians))
                )
                .rotationEffect(angle + .degrees(90))
                .animation(.easeOut(duration: 0.12), value: currentBeat)
        }
    }

    @ViewBuilder
    private func chordDial(center: CGPoint, radius: CGFloat, side: CGFloat) -> some View {
        let labels = dialChords
        ForEach(Array(labels.enumerated()), id: \.element.id) { index, chord in
            let step = 360.0 / Double(max(1, labels.count))
            let angle = Angle.degrees(-90 + Double(index) * step)
            let active = isActive(chord: chord)
            let label = shortLabel(for: chord)

            Text(label)
                .font(.system(size: active ? side * 0.055 : side * 0.042, weight: active ? .bold : .semibold, design: .rounded))
                .foregroundStyle(active ? AppTheme.accent : AppTheme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(width: side * 0.16)
                .position(
                    x: center.x + radius * CGFloat(cos(angle.radians)),
                    y: center.y + radius * CGFloat(sin(angle.radians))
                )
                .shadow(color: active ? AppTheme.accent.opacity(0.35) : .clear, radius: 8)
        }
    }

    @ViewBuilder
    private func hand(center: CGPoint, length: CGFloat) -> some View {
        let angle = handAngle
        ZStack {
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [AppTheme.accent, AppTheme.accent.opacity(0.35)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 4, height: length)
                .offset(y: -length / 2)

            Circle()
                .fill(AppTheme.accent)
                .frame(width: 10, height: 10)
        }
        .position(center)
        .rotationEffect(angle + .degrees(90))
    }

    @ViewBuilder
    private func centerFace(side: CGFloat) -> some View {
        VStack(spacing: 4) {
            Text("NOW")
                .font(.system(size: side * 0.032, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.textSecondary)
                .tracking(2)

            Text(currentName)
                .font(.system(size: side * 0.22, weight: .bold, design: .rounded))
                .foregroundStyle(currentName == "—" ? AppTheme.textSecondary : AppTheme.textPrimary)
                .minimumScaleFactor(0.28)
                .lineLimit(1)
                .contentTransition(.numericText())
                .animation(.spring(response: 0.35, dampingFraction: 0.72), value: currentName)
        }
        .frame(maxWidth: side * 0.52)
        .padding(.vertical, 8)
        .background(
            Circle()
                .fill(AppTheme.background.opacity(0.55))
                .frame(width: side * 0.48, height: side * 0.48)
        )
    }

    @ViewBuilder
    private func complications(center: CGPoint, outerRadius: CGFloat, side: CGFloat) -> some View {
        // 12 o'clock — section / cue
        if let sectionLabel {
            Text(sectionLabel)
                .font(.system(size: side * 0.034, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.accentSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: side * 0.55)
                .position(x: center.x, y: center.y - outerRadius * 0.62)
        }

        // 9 o'clock — tempo
        VStack(spacing: 1) {
            Text(tempoLabel)
                .font(.system(size: side * 0.05, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.textPrimary)
                .monospacedDigit()
            Text("BPM")
                .font(.system(size: side * 0.024, weight: .semibold))
                .foregroundStyle(AppTheme.textSecondary)
        }
        .position(x: center.x - outerRadius * 0.72, y: center.y)

        // 6 o'clock — NEXT
        if let nextName {
            VStack(spacing: 2) {
                Text("NEXT")
                    .font(.system(size: side * 0.028, weight: .bold))
                    .foregroundStyle(AppTheme.textSecondary)
                    .tracking(1.5)
                Text(nextName)
                    .font(.system(size: side * 0.07, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.accent)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
            }
            .frame(maxWidth: side * 0.5)
            .position(x: center.x, y: center.y + outerRadius * 0.68)
        }
    }

    // MARK: - Helpers

    private func isActive(chord: ChordEntry) -> Bool {
        if let symbol = viewModel.payload.liveChordSymbol,
           LiveRing.matches(chord.symbolName, symbol) {
            return true
        }
        return chord.id == viewModel.payload.activeChordID
    }

    private func displayName(for chord: ChordEntry) -> String {
        ChordDisplayHelper.displayName(
            for: chord,
            notation: notation,
            songKey: viewModel.payload.key,
            transposeSemitones: guestTranspose,
            capoFret: guestCapo
        )
    }

    private func shortLabel(for chord: ChordEntry) -> String {
        let full = displayName(for: chord)
        if full.count <= 5 { return full }
        return String(full.prefix(5))
    }
}
