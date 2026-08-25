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
    @State private var didFinish = false

    var body: some View {
        ZStack {
            Color.clear.appShellBackground()

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
        .onAppear {
            // Prefer onAppear + GCD over `.task` — SwiftUI cancels `.task` when the
            // parent re-renders during launch, which left iPhone stuck on this logo.
            runAnimationAndFinish()
        }
    }

    private func runAnimationAndFinish() {
        guard !didFinish else { return }

        withAnimation(.easeOut(duration: 0.45)) {
            glowOpacity = 0.55
            markScale = 1
            orbProgress = [1, 1, 1, 1]
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            showTitle = true
            withAnimation(.easeOut(duration: 0.35)) {
                titleOpacity = 1
            }
        }

        // Hard deadline — always leave the splash, even if animation state stalls.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.35) {
            finishIfNeeded()
        }
    }

    private func finishIfNeeded() {
        guard !didFinish else { return }
        didFinish = true
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
                            AppTheme.accent.opacity(0.07 * glowOpacity),
                            AppTheme.accentSecondary.opacity(0.035 * glowOpacity),
                            .clear
                        ],
                        center: .center,
                        startRadius: 2,
                        endRadius: size * 0.42
                    )
                )
                .frame(width: size * 0.95, height: size * 0.95)

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
                        Color.white.opacity(0.96),
                        orb.colors[0].opacity(0.98),
                        orb.colors[0],
                        (orb.colors.last ?? orb.colors[0]).opacity(0.72),
                        Color.black.opacity(0.38)
                    ],
                    center: UnitPoint(x: 0.34, y: 0.30),
                    startRadius: 0,
                    endRadius: diameter * 0.78
                )
            )
            .frame(width: diameter, height: diameter)
            .overlay {
                // Specular highlight
                Ellipse()
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.88), .white.opacity(0.08), .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: diameter * 0.42, height: diameter * 0.30)
                    .rotationEffect(.degrees(-18))
                    .offset(x: -diameter * 0.10, y: -diameter * 0.18)
                    .blur(radius: 0.35)
            }
            .overlay {
                // Core shadow — gives the orb a rounded 3D read
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [.clear, .clear, Color.black.opacity(0.22), Color.black.opacity(0.48)],
                            center: UnitPoint(x: 0.58, y: 0.68),
                            startRadius: diameter * 0.08,
                            endRadius: diameter * 0.55
                        )
                    )
            }
            .overlay {
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(0.32), .white.opacity(0.06), .black.opacity(0.22)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: max(0.75, diameter * 0.045)
                    )
            }
            .shadow(color: .black.opacity(0.38), radius: max(2, diameter * 0.07), x: 0, y: diameter * 0.10)
            .shadow(color: orb.colors.first?.opacity(0.12) ?? .clear, radius: max(2, diameter * 0.08), x: 0, y: 0)
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
