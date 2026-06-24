//
//  ChordyxSessionLiveActivity.swift
//  ChordyxWidgets
//

import ActivityKit
import SwiftUI
import WidgetKit

private enum LiveActivityTheme {
    static let accent = Color(red: 0.98, green: 0.72, blue: 0.28)
    static let accentSecondary = Color(red: 0.45, green: 0.55, blue: 0.98)
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.65)
    static let surface = Color(red: 0.11, green: 0.12, blue: 0.18)
    static let surfaceElevated = Color(red: 0.16, green: 0.17, blue: 0.24)
    static let chordInactive = Color(red: 0.20, green: 0.22, blue: 0.30)

    static let heroGradient = LinearGradient(
        colors: [
            Color(red: 0.98, green: 0.72, blue: 0.28).opacity(0.22),
            Color(red: 0.45, green: 0.55, blue: 0.98).opacity(0.12),
            Color.clear
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

struct ChordyxSessionLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ChordyxSessionAttributes.self) { context in
            ChordyxSessionLockScreenView(state: context.state, roleLabel: context.attributes.roleLabel)
                .activityBackgroundTint(LiveActivityTheme.surface)
                .activitySystemActionForegroundColor(LiveActivityTheme.accent)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 6) {
                        LiveActivitySectionBadge(name: context.state.sectionName)
                        Text(context.state.currentChord)
                            .font(.system(size: 44, weight: .heavy, design: .rounded))
                            .foregroundStyle(LiveActivityTheme.accent)
                            .minimumScaleFactor(0.4)
                            .lineLimit(1)
                            .contentTransition(.numericText())
                            .animation(.spring(response: 0.35, dampingFraction: 0.72), value: context.state.chordChangeToken)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 8) {
                        if !context.state.nextChord.isEmpty {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("NEXT")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(LiveActivityTheme.textSecondary)
                                Text(context.state.nextChord)
                                    .font(.headline.weight(.semibold))
                                    .foregroundStyle(LiveActivityTheme.textPrimary)
                                    .lineLimit(1)
                            }
                        }
                        if context.state.isMetronomePlaying || context.state.isCountingIn {
                            LiveActivityBeatDots(
                                beatsPerBar: context.state.beatsPerBar,
                                currentBeat: context.state.currentBeat,
                                dotSize: 7,
                                spacing: 5
                            )
                        }
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 8) {
                        HStack(spacing: 8) {
                            Text(context.state.hideSongTitle ? context.state.sessionName : displayTitle(for: context.state))
                                .font(.caption.weight(.medium))
                                .foregroundStyle(LiveActivityTheme.textSecondary)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            if !context.state.chordPosition.isEmpty {
                                Text(context.state.chordPosition)
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(LiveActivityTheme.textSecondary)
                            }
                            if !context.state.setlistProgress.isEmpty {
                                Text(context.state.setlistProgress)
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(LiveActivityTheme.accentSecondary)
                            }
                        }
                        if !context.state.cueText.isEmpty {
                            LiveActivityCueStrip(text: context.state.cueText, symbol: context.state.cueSymbol, compact: true)
                        } else {
                            LiveActivityProgressBar(positionLabel: context.state.chordPosition)
                        }
                    }
                }
            } compactLeading: {
                Text(chordAbbrev(context.state.currentChord))
                    .font(.body.weight(.heavy))
                    .foregroundStyle(LiveActivityTheme.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            } compactTrailing: {
                if !context.state.nextChord.isEmpty {
                    Text(chordAbbrev(context.state.nextChord))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(LiveActivityTheme.textSecondary)
                        .lineLimit(1)
                } else if context.state.isMetronomePlaying {
                    Text("\(context.state.tempoBPM)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(LiveActivityTheme.accentSecondary)
                } else {
                    Image(systemName: "music.note")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(LiveActivityTheme.accentSecondary)
                }
            } minimal: {
                Text(chordAbbrev(context.state.currentChord))
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(LiveActivityTheme.accent)
            }
        }
    }

    private func displayTitle(for state: ChordyxSessionAttributes.ContentState) -> String {
        state.songTitle.isEmpty ? state.sessionName : state.songTitle
    }
}

// MARK: - Lock Screen

private struct ChordyxSessionLockScreenView: View {
    let state: ChordyxSessionAttributes.ContentState
    let roleLabel: String

    var body: some View {
        VStack(spacing: 10) {
            connectionBanner
            compactMetadata

            if state.currentChord == "—" {
                Text(state.statusLine)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(LiveActivityTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            } else {
                Text(state.currentChord)
                    .font(.system(size: 80, weight: .heavy, design: .rounded))
                    .foregroundStyle(LiveActivityTheme.accent)
                    .shadow(color: LiveActivityTheme.accent.opacity(0.35), radius: 8, y: 2)
                    .minimumScaleFactor(0.25)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.35, dampingFraction: 0.72), value: state.chordChangeToken)
            }

            if !state.nextChord.isEmpty {
                nextChordRow
            }

            if !state.cueText.isEmpty {
                LiveActivityCueStrip(text: state.cueText, symbol: state.cueSymbol, compact: true)
            }

            compactStatusLine

            LiveActivityProgressBar(positionLabel: state.chordPosition)
                .frame(height: 3)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var connectionBanner: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(state.isConnected ? Color.green : Color.orange)
                .frame(width: 7, height: 7)
            Text(state.statusLine)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(state.isConnected ? LiveActivityTheme.textSecondary : Color.orange.opacity(0.95))
        .frame(maxWidth: .infinity, alignment: .center)
    }

    @ViewBuilder
    private var compactMetadata: some View {
        let parts = metadataParts
        if !parts.isEmpty {
            Text(parts.joined(separator: " · "))
                .font(.caption2.weight(.medium))
                .foregroundStyle(LiveActivityTheme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private var metadataParts: [String] {
        var parts: [String] = []
        if !state.hideSongTitle {
            parts.append(displayTitle)
        }
        if !state.sectionName.isEmpty {
            parts.append(state.sectionName)
        }
        if !state.chordPosition.isEmpty {
            parts.append(state.chordPosition)
        }
        if !state.setlistProgress.isEmpty {
            parts.append(state.setlistProgress)
        }
        return parts
    }

    private var nextChordRow: some View {
        HStack(spacing: 6) {
            Text("NEXT")
                .font(.caption2.weight(.bold))
                .foregroundStyle(LiveActivityTheme.textSecondary)
            Text(state.nextChord)
                .font(.callout.weight(.semibold))
                .foregroundStyle(LiveActivityTheme.textPrimary)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var compactStatusLine: some View {
        let parts = statusParts
        if !parts.isEmpty {
            HStack(spacing: 6) {
                if state.isMetronomePlaying || state.isCountingIn {
                    LiveActivityBeatDots(
                        beatsPerBar: state.beatsPerBar,
                        currentBeat: state.currentBeat,
                        dotSize: 6,
                        spacing: 3
                    )
                }
                Text(parts.joined(separator: " · "))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .font(.caption2.weight(.medium))
            .foregroundStyle(LiveActivityTheme.textSecondary)
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private var statusParts: [String] {
        var parts: [String] = [state.keyName]
        if state.isCountingIn {
            parts.append(String(localized: "Count-in"))
        } else if state.isMetronomePlaying {
            parts.append("\(state.tempoBPM) BPM")
        }
        if !state.personalChartNote.isEmpty {
            parts.append(state.personalChartNote)
        }
        if !roleLabel.isEmpty {
            parts.append(roleLabel)
        }
        if state.isLiveChord {
            parts.append(String(localized: "Live"))
        }
        if state.isConnected, state.currentChord != "—" {
            parts.append(state.statusLine)
        }
        return parts
    }

    private var displayTitle: String {
        state.songTitle.isEmpty ? state.sessionName : state.songTitle
    }
}

// MARK: - Components

private struct LiveActivitySectionBadge: View {
    let name: String

    var body: some View {
        if name.isEmpty {
            EmptyView()
        } else {
            Text(name.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(LiveActivityTheme.accentSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(LiveActivityTheme.accentSecondary.opacity(0.16))
                .clipShape(Capsule())
        }
    }
}

private struct LiveActivityBeatDots: View {
    let beatsPerBar: Int
    let currentBeat: Int
    var dotSize: CGFloat = 8
    var spacing: CGFloat = 6

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(0..<max(1, beatsPerBar), id: \.self) { index in
                Circle()
                    .fill(index == currentBeat ? LiveActivityTheme.accent : LiveActivityTheme.chordInactive)
                    .frame(width: dotSize, height: dotSize)
                    .overlay {
                        if index == currentBeat && index == 0 {
                            Circle()
                                .stroke(LiveActivityTheme.accent.opacity(0.45), lineWidth: 1)
                                .frame(width: dotSize + 4, height: dotSize + 4)
                        }
                    }
            }
        }
        .animation(.easeOut(duration: 0.12), value: currentBeat)
    }
}

private struct LiveActivityProgressBar: View {
    let positionLabel: String

    var body: some View {
        let progress = parseProgress(from: positionLabel)
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(LiveActivityTheme.chordInactive.opacity(0.55))
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [LiveActivityTheme.accent, LiveActivityTheme.accentSecondary],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(8, proxy.size.width * progress))
            }
        }
        .frame(height: 3)
        .opacity(progress > 0 ? 1 : 0)
    }

    private func parseProgress(from label: String) -> CGFloat {
        let parts = label.split(separator: "/")
        guard parts.count == 2,
              let current = Int(parts[0]),
              let total = Int(parts[1]),
              total > 0 else { return 0 }
        return CGFloat(current) / CGFloat(total)
    }
}

private struct LiveActivityCueStrip: View {
    let text: String
    let symbol: String
    let compact: Bool

    var body: some View {
        HStack(spacing: compact ? 6 : 10) {
            Image(systemName: symbol)
                .font(compact ? .caption.weight(.bold) : .subheadline.weight(.bold))
            Text(text.uppercased())
                .font(compact ? .caption2.weight(.black) : .caption.weight(.black))
                .tracking(compact ? 0.5 : 1)
                .lineLimit(1)
        }
        .foregroundStyle(LiveActivityTheme.surface)
        .padding(.horizontal, compact ? 10 : 14)
        .padding(.vertical, compact ? 5 : 8)
        .frame(maxWidth: .infinity, alignment: .center)
        .background(LiveActivityTheme.accentSecondary)
        .clipShape(Capsule())
    }
}

private func chordAbbrev(_ chord: String) -> String {
    guard chord != "—" else { return "—" }
    let base = chord.split(separator: "/").first.map(String.init) ?? chord
    return String(base.prefix(4))
}
