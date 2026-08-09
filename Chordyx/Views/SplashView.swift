//
//  SplashView.swift
//  Chordyx
//
//  Launch mark: the classic four glossy orbs (same identity as the app icon).
//

import SwiftUI

struct SplashView: View {
    var onFinish: () -> Void

    @State private var orbProgress: [CGFloat] = [0, 0, 0, 0]
    @State private var showTitle = false
    @State private var titleOpacity: Double = 0
    @State private var markScale: CGFloat = 0.86
    @State private var glowOpacity: Double = 0

    var body: some View {
        ZStack {
            AppTheme.backgroundGradient.ignoresSafeArea()

            VStack(spacing: 32) {
                ChordyxBrandMark(
                    size: 168,
                    orbProgress: orbProgress,
                    glowOpacity: glowOpacity
                )
                .scaleEffect(markScale)

                Text("Chordyx")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.textPrimary)
                    .opacity(titleOpacity)
                    .scaleEffect(showTitle ? 1 : 0.92)
            }
        }
        .preferredColorScheme(.dark)
        .task {
            await runAnimation()
        }
    }

    @MainActor
    private func runAnimation() async {
        withAnimation(.easeOut(duration: 0.55)) {
            glowOpacity = 1
            markScale = 1
        }

        for index in orbProgress.indices {
            withAnimation(.spring(response: 0.52, dampingFraction: 0.76)) {
                orbProgress[index] = 1
            }
            try? await Task.sleep(for: .milliseconds(90))
        }

        try? await Task.sleep(for: .milliseconds(220))

        showTitle = true
        withAnimation(.easeOut(duration: 0.4)) {
            titleOpacity = 1
        }

        try? await Task.sleep(for: .milliseconds(850))
        onFinish()
    }
}

/// Classic four-orb Chordyx mark (splash, home, and other brand surfaces).
struct ChordyxBrandMark: View {
    var size: CGFloat = 52
    /// 0…1 per orb; pass `[1,1,1,1]` for a static mark.
    var orbProgress: [CGFloat] = [1, 1, 1, 1]
    var glowOpacity: Double = 1
    var animatedEntry: Bool = false

    private var orbs: [ChordyxMarkOrb] { ChordyxMarkOrb.diamond(spacing: size * 0.22) }
    private var orbDiameter: CGFloat { size * 0.31 }

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            AppTheme.accent.opacity(0.22 * glowOpacity),
                            AppTheme.accentSecondary.opacity(0.12 * glowOpacity),
                            .clear
                        ],
                        center: .center,
                        startRadius: 2,
                        endRadius: size * 0.55
                    )
                )
                .frame(width: size * 1.15, height: size * 1.15)

            ForEach(Array(orbs.enumerated()), id: \.element.id) { index, orb in
                let progress = orbProgress.indices.contains(index) ? orbProgress[index] : 1
                ChordyxMarkOrbView(
                    orb: orb,
                    progress: progress,
                    diameter: orbDiameter,
                    flyInScale: animatedEntry ? 3.2 : 1
                )
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - Four-orb geometry

private struct ChordyxMarkOrb: Identifiable {
    let id: Int
    let target: CGPoint
    let colors: [Color]

    static func diamond(spacing: CGFloat) -> [ChordyxMarkOrb] {
        let accent = [AppTheme.accent, AppTheme.accent.opacity(0.88)]
        let accentAlt = [AppTheme.accentSecondary, AppTheme.accentSecondary.opacity(0.88)]
        let targets: [(CGPoint, [Color])] = [
            (CGPoint(x: 0, y: -spacing), accent),
            (CGPoint(x: -spacing, y: 0), accent),
            (CGPoint(x: spacing, y: 0), accentAlt),
            (CGPoint(x: 0, y: spacing), accentAlt)
        ]
        return targets.enumerated().map { index, item in
            ChordyxMarkOrb(id: index, target: item.0, colors: item.1)
        }
    }
}

private struct ChordyxMarkOrbView: View {
    let orb: ChordyxMarkOrb
    let progress: CGFloat
    let diameter: CGFloat
    var flyInScale: CGFloat = 3.2

    private var start: CGPoint {
        CGPoint(x: orb.target.x * flyInScale, y: orb.target.y * flyInScale)
    }

    private var position: CGPoint {
        CGPoint(
            x: start.x + (orb.target.x - start.x) * progress,
            y: start.y + (orb.target.y - start.y) * progress
        )
    }

    var body: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        Color.white.opacity(0.92),
                        orb.colors[0],
                        orb.colors.last ?? orb.colors[0]
                    ],
                    center: UnitPoint(x: 0.32, y: 0.28),
                    startRadius: 0,
                    endRadius: diameter * 0.72
                )
            )
            .frame(width: diameter, height: diameter)
            .overlay {
                Circle()
                    .fill(.white.opacity(0.42))
                    .frame(width: diameter * 0.28, height: diameter * 0.22)
                    .blur(radius: 0.5)
                    .offset(x: -diameter * 0.14, y: -diameter * 0.16)
            }
            .overlay {
                Circle()
                    .stroke(.white.opacity(0.14), lineWidth: 1)
            }
            .shadow(color: orb.colors.first?.opacity(0.55) ?? .clear, radius: max(4, diameter * 0.18), y: 1)
            .shadow(color: orb.colors.first?.opacity(0.28) ?? .clear, radius: max(8, diameter * 0.32), y: 0)
            .scaleEffect(0.35 + 0.65 * progress)
            .opacity(Double(0.2 + 0.8 * progress))
            .offset(x: position.x, y: position.y)
    }
}

#if DEBUG
#Preview {
    SplashView(onFinish: {})
}
#endif
