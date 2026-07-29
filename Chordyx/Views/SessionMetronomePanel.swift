//
//  SessionMetronomePanel.swift
//  Chordyx
//

import SwiftUI
#if os(iOS)
import UIKit
#endif

struct SessionMetronomePanel: View {
    @Bindable var viewModel: SessionViewModel
    var isHost: Bool
    @Binding var metronomeVolume: Double
    var horizontalPadding: CGFloat = 16
    var showsCollapseButton = true
    var onCollapse: (() -> Void)?

    @AppStorage("guestMetronomeAudioEnabled") private var guestMetronomeAudioEnabled = true
    @State private var tapTimes: [Date] = []

    private var currentTimeSignature: TimeSignature {
        TimeSignature(
            beats: viewModel.payload.beatsPerBar,
            unit: viewModel.payload.beatUnit
        )
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                Button {
                    viewModel.toggleMetronome()
                } label: {
                    Image(systemName: viewModel.payload.isMetronomePlaying ? "pause.fill" : "play.fill")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(AppTheme.background)
                        .frame(width: 48, height: 48)
                        .background(viewModel.payload.isMetronomePlaying ? AppTheme.accent : AppTheme.accentSecondary)
                        .clipShape(Circle())
                }
                .disabled(!isHost)
                .opacity(isHost ? 1 : 0.5)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(Int(viewModel.displayedSessionTempoBPM.rounded()))")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.textPrimary)
                            .contentTransition(.numericText())
                        Text("BPM")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                    if !isHost, viewModel.payload.hostLiveGrooveActive {
                        Text(TempoMarking.forBPM(viewModel.displayedSessionTempoBPM).label)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(AppTheme.accentSecondary)
                    }

                    beatDots
                }

                Spacer(minLength: 0)

                if showsCollapseButton, let onCollapse {
                    Button(action: onCollapse) {
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(AppTheme.textSecondary)
                            .frame(width: 32, height: 32)
                            .background(AppTheme.surfaceElevated)
                            .clipShape(Circle())
                    }
                    .accessibilityLabel(String(localized: "Hide metronome"))
                }
            }

            if isHost {
                HStack(spacing: 10) {
                    tapTempoButton
                    timeSignatureMenu
                    Spacer(minLength: 0)
                }

                Stepper(value: Binding(
                    get: { viewModel.payload.countInBars },
                    set: { viewModel.setCountInBars($0) }
                ), in: 0...4) {
                    Text("Count-in: \(viewModel.payload.countInBars) bar\(viewModel.payload.countInBars == 1 ? "" : "s")")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppTheme.textSecondary)
                }

                #if os(iOS)
                MetronomeRouteToggle(metronome: viewModel.metronome)
                #endif

                HStack(spacing: 12) {
                    Button {
                        viewModel.setTempo(viewModel.payload.tempoBPM - 1)
                    } label: {
                        stepperIcon("minus")
                    }

                    Slider(
                        value: Binding(
                            get: { viewModel.payload.tempoBPM },
                            set: { viewModel.setTempo($0) }
                        ),
                        in: SessionViewModel.minBPM...SessionViewModel.maxBPM,
                        step: 1
                    )
                    .tint(AppTheme.accent)

                    Button {
                        viewModel.setTempo(viewModel.payload.tempoBPM + 1)
                    } label: {
                        stepperIcon("plus")
                    }
                }
            } else {
                guestMetronomeControls
            }

            volumeRow
        }
        .padding(16)
        .glassCard()
        .padding(.horizontal, horizontalPadding)
        .onAppear {
            viewModel.metronome.volume = Float(metronomeVolume)
            if !isHost {
                viewModel.reapplyGuestMetronomeAudioPreference()
            }
        }
        .onChange(of: metronomeVolume) { _, newValue in
            viewModel.metronome.volume = Float(newValue)
        }
    }

    private var guestMetronomeControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            if viewModel.payload.hostLiveGrooveActive {
                Text(String(localized: "Tempo follows the Mac host's live groove. You can still hear the click on your phone."))
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
            } else if viewModel.displayedMetronomePlaying {
                Text(String(localized: "Following the host's metronome."))
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
            } else {
                Text(String(localized: "When the host starts tempo, you can hear the click here."))
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
            }

            Toggle(isOn: $guestMetronomeAudioEnabled) {
                Label(String(localized: "Hear metronome click"), systemImage: "speaker.wave.2.fill")
                    .font(.subheadline.weight(.medium))
            }
            .tint(AppTheme.accent)
            .onChange(of: guestMetronomeAudioEnabled) { _, enabled in
                viewModel.setGuestMetronomeAudioEnabled(enabled)
            }
        }
    }

    private var volumeRow: some View {
        HStack(spacing: 12) {
            Button {
                metronomeVolume = metronomeVolume > 0 ? 0 : 0.8
            } label: {
                Image(systemName: volumeIcon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)
                    .frame(width: 24)
            }

            Slider(value: $metronomeVolume, in: 0...1)
                .tint(AppTheme.accentSecondary)

            Text("\(Int(metronomeVolume * 100))%")
                .font(.caption.weight(.medium))
                .foregroundStyle(AppTheme.textSecondary)
                .frame(width: 40, alignment: .trailing)
        }
    }

    private var volumeIcon: String {
        if metronomeVolume == 0 { return "speaker.slash.fill" }
        if metronomeVolume < 0.4 { return "speaker.fill" }
        if metronomeVolume < 0.75 { return "speaker.wave.1.fill" }
        return "speaker.wave.2.fill"
    }

    private var beatDots: some View {
        HStack(spacing: 6) {
            ForEach(0..<max(1, viewModel.payload.beatsPerBar), id: \.self) { index in
                let isCurrent = viewModel.displayedMetronomePlaying && viewModel.metronome.currentBeat == index
                Circle()
                    .fill(isCurrent ? (index == 0 ? AppTheme.accent : AppTheme.accentSecondary) : AppTheme.chordInactive)
                    .frame(width: isCurrent ? 12 : 8, height: isCurrent ? 12 : 8)
                    .animation(.easeOut(duration: 0.1), value: viewModel.metronome.currentBeat)
            }
        }
        .frame(height: 14)
    }

    private var tapTempoButton: some View {
        Button {
            registerTap()
        } label: {
            LiveHostDockChip(icon: "hand.tap.fill", title: String(localized: "Tap Tempo"))
        }
        .buttonStyle(.plain)
    }

    private func registerTap() {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif

        let now = Date()
        if let last = tapTimes.last, now.timeIntervalSince(last) > 2 {
            tapTimes.removeAll()
        }
        tapTimes.append(now)
        if tapTimes.count > 5 {
            tapTimes.removeFirst(tapTimes.count - 5)
        }
        guard tapTimes.count >= 2 else { return }

        var intervals: [TimeInterval] = []
        for index in 1..<tapTimes.count {
            intervals.append(tapTimes[index].timeIntervalSince(tapTimes[index - 1]))
        }
        let average = intervals.reduce(0, +) / Double(intervals.count)
        guard average > 0 else { return }
        viewModel.setTempo(60.0 / average)
    }

    private var timeSignatureMenu: some View {
        PlatformPopoverOptionPicker(
            selection: Binding(
                get: { currentTimeSignature },
                set: { signature in
                    viewModel.setTimeSignature(beats: signature.beats, unit: signature.unit)
                }
            ),
            options: TimeSignature.presets.map { ($0, $0.label) },
            sheetTitle: "Time signature",
            arrowEdge: .top,
            minWidth: 180
        ) {
            LiveHostDockChip(
                icon: "metronome",
                title: "\(viewModel.payload.beatsPerBar)/\(viewModel.payload.beatUnit)"
            )
        }
    }

    private func stepperIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(AppTheme.textPrimary)
            .frame(width: 38, height: 38)
            .background(AppTheme.surfaceElevated)
            .clipShape(Circle())
    }
}

struct LiveHostDockChip: View {
    let icon: String
    let title: String
    var fillWidth = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(title)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(AppTheme.textPrimary)
        .frame(maxWidth: fillWidth ? .infinity : nil)
        .padding(.horizontal, fillWidth ? 10 : 14)
        .padding(.vertical, 10)
        .background(AppTheme.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
