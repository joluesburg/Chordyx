//
//  ChordRingView.swift
//  Chordyx
//

import SwiftUI

struct ChordRingView: View {
    let chords: [ChordEntry]
    let notation: ChordNotation
    let key: MusicalKey
    let activeChordID: UUID?
    var activeChordSymbol: String? = nil
    let isInteractive: Bool
    let containerSize: CGSize
    let radius: CGFloat
    let bubbleSize: CGFloat
    var beatChangeHint: Bool = false
    let onTap: (ChordEntry) -> Void

    var body: some View {
        let center = CGPoint(x: containerSize.width / 2, y: containerSize.height / 2)

        ZStack {
            Circle()
                .stroke(AppTheme.ringStroke.opacity(0.35), lineWidth: radius * 0.04)
                .frame(width: radius * 2.08, height: radius * 2.08)
                .position(center)

            Circle()
                .stroke(
                    LinearGradient(
                        colors: [
                            AppTheme.ringStroke.opacity(0.85),
                            AppTheme.accentSecondary.opacity(0.45)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: max(2.5, bubbleSize * 0.04)
                )
                .frame(width: radius * 2, height: radius * 2)
                .position(center)
                .shadow(color: AppTheme.accent.opacity(0.12), radius: 12)

            ForEach(Array(chords.enumerated()), id: \.element.id) { index, chord in
                let angle = angleForIndex(index, total: chords.count)
                let x = center.x + radius * cos(angle)
                let y = center.y + radius * sin(angle)
                let isActive = activeChordSymbol.map { chord.symbolName == $0 }
                    ?? (chord.id == activeChordID)

                ChordBubble(
                    label: chord.displayName(for: notation, key: key),
                    notation: notation,
                    order: index + 1,
                    isActive: isActive,
                    pulseHint: isActive && beatChangeHint,
                    size: bubbleSize
                )
                .position(x: x, y: y)
                .onTapGesture {
                    if isInteractive {
                        onTap(chord)
                    }
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.72), value: activeChordSymbol ?? activeChordID?.uuidString)
            }
        }
        .frame(width: containerSize.width, height: containerSize.height)
    }

    private func angleForIndex(_ index: Int, total: Int) -> CGFloat {
        guard total > 0 else { return 0 }
        let startAngle = -CGFloat.pi / 2
        let step = (2 * CGFloat.pi) / CGFloat(total)
        return startAngle + step * CGFloat(index)
    }
}

struct ChordBubble: View {
    let label: String
    let notation: ChordNotation
    let order: Int
    let isActive: Bool
    var pulseHint: Bool = false
    let size: CGFloat

    var body: some View {
        ZStack {
            if isActive {
                Circle()
                    .fill(AppTheme.chordActive.opacity(0.22))
                    .frame(width: size * 1.18, height: size * 1.18)
                    .blur(radius: 8)

                if pulseHint {
                    Circle()
                        .stroke(AppTheme.accent, lineWidth: 3)
                        .frame(width: size * 1.12, height: size * 1.12)
                        .scaleEffect(1.08)
                        .opacity(0.9)
                        .animation(.easeInOut(duration: 0.35).repeatForever(autoreverses: true), value: pulseHint)
                }
            }

            Circle()
                .fill(isActive ? AppTheme.chordActive : AppTheme.chordInactive)
                .frame(width: size, height: size)
                .overlay {
                    Circle()
                        .stroke(
                            isActive ? AppTheme.background.opacity(0.18) : AppTheme.ringStroke.opacity(0.25),
                            lineWidth: 1.5
                        )
                }
                .shadow(
                    color: isActive ? AppTheme.chordActive.opacity(0.55) : AppTheme.background.opacity(0.25),
                    radius: isActive ? 16 : 4,
                    y: isActive ? 4 : 2
                )

            VStack(spacing: 2) {
                SolfegeChordText.make(label, notation: notation, size: size * 0.30)
                    .foregroundStyle(isActive ? AppTheme.background : AppTheme.textPrimary)
                    .minimumScaleFactor(0.35)
                    .lineLimit(1)
                    .frame(maxWidth: size - 10)

                Text("\(order)")
                    .font(.system(size: size * 0.15, weight: .semibold, design: .rounded))
                    .foregroundStyle(isActive ? AppTheme.background.opacity(0.75) : AppTheme.textSecondary)
            }
            .padding(.horizontal, 4)
        }
        .scaleEffect(isActive ? 1.10 : 1.0)
        .animation(.spring(response: 0.32, dampingFraction: 0.72), value: isActive)
    }
}

struct CurrentChordDisplay: View {
    let chord: ChordEntry?
    var upcoming: ChordEntry? = nil
    let notation: ChordNotation
    let key: MusicalKey
    var emphasized: Bool = false
    var isEmptyProgression: Bool = false
    var onAddChords: (() -> Void)? = nil
    var isLiveFreestyle: Bool = false
    var isListeningForChord: Bool = false
    /// When set, scales typography and gradient to fit the allotted center circle.
    var diameter: CGFloat? = nil
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var effectiveDiameter: CGFloat {
        diameter ?? (horizontalSizeClass == .regular ? 240 : 200)
    }

    private var chordFontSize: CGFloat {
        let scale = emphasized ? 0.46 : 0.40
        return max(38, effectiveDiameter * scale)
    }

    private var centerGradientEndRadius: CGFloat {
        effectiveDiameter * 0.48
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            AppTheme.surfaceElevated,
                            AppTheme.surface
                        ],
                        center: .center,
                        startRadius: 20,
                        endRadius: centerGradientEndRadius
                    )
                )
                .overlay(
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [AppTheme.accent.opacity(0.6), AppTheme.accentSecondary.opacity(0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: emphasized ? 4 : 3
                        )
                )
                .shadow(color: AppTheme.accent.opacity(0.22), radius: min(32, effectiveDiameter * 0.12))

            if let chord {
                VStack(spacing: 6) {
                    Text(isLiveFreestyle ? "Live Chord" : "Next Chord")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppTheme.textSecondary)
                        .textCase(.uppercase)
                        .tracking(1.2)

                    chord.chordText(for: notation, key: key, size: chordFontSize)
                        .foregroundStyle(AppTheme.accent)
                        .minimumScaleFactor(0.4)
                        .lineLimit(1)
                        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: chord.id)

                    if let upcoming {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.right")
                                .font(.caption2.weight(.bold))
                            Text("then")
                                .font(.caption.weight(.semibold))
                            upcoming.chordText(for: notation, key: key, size: 13, weight: .semibold)
                                .lineLimit(1)
                        }
                        .foregroundStyle(AppTheme.accentSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(AppTheme.surface.opacity(0.7))
                        .clipShape(Capsule())
                    } else {
                        Text("Key of \(key.displayName)")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                }
                .padding()
            } else if isLiveFreestyle && isListeningForChord {
                VStack(spacing: 10) {
                    Image(systemName: "pianokeys")
                        .font(.system(size: 36))
                        .foregroundStyle(AppTheme.accentSecondary)
                        .symbolEffect(.pulse)

                    Text("Listening…")
                        .font(.headline)
                        .foregroundStyle(AppTheme.textPrimary)

                    Text("Host is playing — chord will appear when recognized")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
            } else if isEmptyProgression, let onAddChords {
                VStack(spacing: 12) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 32))
                        .foregroundStyle(AppTheme.textSecondary)

                    Text("No chords yet")
                        .font(.headline)
                        .foregroundStyle(AppTheme.textPrimary)

                    Text("Build your progression in Edit")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.textSecondary)
                        .multilineTextAlignment(.center)

                    Button(action: onAddChords) {
                        Label("Edit Progression", systemImage: "plus.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.background)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(AppTheme.accent)
                            .clipShape(Capsule())
                    }
                    .padding(.top, 4)
                }
                .padding()
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "music.note")
                        .font(.system(size: 36))
                        .foregroundStyle(AppTheme.textSecondary)

                    Text(emphasized ? "Waiting for host" : "Tap a chord")
                        .font(.headline)
                        .foregroundStyle(AppTheme.textSecondary)

                    Text(emphasized ? "The next chord will appear here" : "to show what's next")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.textSecondary.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
                .padding()
            }
        }
    }
}
