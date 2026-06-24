//
//  SplashView.swift
//  Chordyx
//

import SwiftUI

struct SplashView: View {
    var onFinish: () -> Void

    @State private var bubbleProgress: [CGFloat]
    @State private var showTitle = false
    @State private var titleOpacity: Double = 0
    @State private var ringOpacity: Double = 0

    private let bubbles: [SplashBubble]

    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
        let bubbles = SplashBubble.cShape
        self.bubbles = bubbles
        _bubbleProgress = State(initialValue: Array(repeating: 0, count: bubbles.count))
    }

    var body: some View {
        ZStack {
            AppTheme.backgroundGradient.ignoresSafeArea()

            VStack(spacing: 28) {
                ZStack {
                    SplashCShapeGuide()
                        .opacity(ringOpacity * 0.35)

                    ForEach(Array(bubbles.enumerated()), id: \.element.id) { index, bubble in
                        let progress = bubbleProgress[index]
                        SplashBubbleView(bubble: bubble, progress: progress)
                    }
                }
                .frame(width: 240, height: 240)

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
        withAnimation(.easeOut(duration: 0.6)) {
            ringOpacity = 1
        }

        for index in bubbles.indices {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.74)) {
                bubbleProgress[index] = 1
            }
            try? await Task.sleep(for: .milliseconds(55))
        }

        try? await Task.sleep(for: .milliseconds(280))

        showTitle = true
        withAnimation(.easeOut(duration: 0.45)) {
            titleOpacity = 1
        }

        try? await Task.sleep(for: .milliseconds(900))
        onFinish()
    }
}

// MARK: - Bubble model

private struct SplashBubble: Identifiable {
    let id: Int
    let start: CGPoint
    let target: CGPoint
    let colors: [Color]
    let sizeScale: CGFloat

    static let cShape: [SplashBubble] = {
        var specs: [(CGPoint, [Color], CGFloat)] = []

        let center = CGPoint(x: -12, y: 0)
        let accent = [AppTheme.accent, AppTheme.accent.opacity(0.88)]
        let accentAlt = [AppTheme.accentSecondary, AppTheme.accentSecondary.opacity(0.88)]
        let accentDim = [AppTheme.accent.opacity(0.55), AppTheme.accentSecondary.opacity(0.45)]

        // Outer C — arc from top horn through left to bottom horn (open to the right)
        let outerRadius: CGFloat = 82
        let outerStart = Double.pi * 5 / 4   // top of C
        let outerEnd = Double.pi * 3 / 4     // bottom of C
        let outerCount = 16
        for i in 0..<outerCount {
            let t = Double(i) / Double(outerCount - 1)
            let angle = outerStart + (outerEnd - outerStart) * t
            let point = polarPoint(center: center, radius: outerRadius, angle: angle)
            specs.append((point, i.isMultiple(of: 2) ? accent : accentAlt, 1.0))
        }

        // Inner arc — depth layer inset from the outer stroke
        let innerRadius: CGFloat = 56
        let innerInset = 0.14
        let innerStart = outerStart - innerInset
        let innerEnd = outerEnd + innerInset
        let innerCount = 11
        for i in 0..<innerCount {
            let t = Double(i) / Double(innerCount - 1)
            let angle = innerStart + (innerEnd - innerStart) * t
            let point = polarPoint(center: center, radius: innerRadius, angle: angle)
            specs.append((point, accentDim, 0.56))
        }

        // Opening terminals — accent nodes at the tips of the C
        let terminalSpecs: [(Double, CGFloat, [Color])] = [
            (outerStart + 0.06, outerRadius + 8, accent),
            (outerEnd - 0.06, outerRadius + 8, accentAlt)
        ]
        for (angle, radius, colors) in terminalSpecs {
            specs.append((polarPoint(center: center, radius: radius, angle: angle), colors, 0.94))
        }

        // Micro nodes on the open edge — subtle tech sparkle
        let microAngles: [Double] = [-0.55, 0.55]
        for angle in microAngles {
            let point = polarPoint(center: center, radius: 48, angle: angle)
            specs.append((point, accentDim, 0.4))
        }

        return specs.enumerated().map { index, spec in
            let angle = Double(index) / Double(specs.count) * .pi * 2
            let spread: CGFloat = 200 + CGFloat(index % 3) * 18
            let start = CGPoint(
                x: spec.0.x + cos(angle) * spread,
                y: spec.0.y + sin(angle) * spread
            )
            return SplashBubble(
                id: index,
                start: start,
                target: spec.0,
                colors: spec.1,
                sizeScale: spec.2
            )
        }
    }()

    private static func polarPoint(center: CGPoint, radius: CGFloat, angle: Double) -> CGPoint {
        CGPoint(
            x: center.x + radius * cos(angle),
            y: center.y + radius * sin(angle)
        )
    }
}

// MARK: - Views

private struct SplashBubbleView: View {
    let bubble: SplashBubble
    let progress: CGFloat

    private var diameter: CGFloat { 30 * bubble.sizeScale }

    private var position: CGPoint {
        CGPoint(
            x: bubble.start.x + (bubble.target.x - bubble.start.x) * progress,
            y: bubble.start.y + (bubble.target.y - bubble.start.y) * progress
        )
    }

    var body: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: bubble.colors + [bubble.colors.last?.opacity(0.2) ?? .clear],
                    center: .topLeading,
                    startRadius: 0,
                    endRadius: diameter * 0.9
                )
            )
            .frame(width: diameter, height: diameter)
            .overlay {
                Circle()
                    .fill(.white.opacity(0.38))
                    .frame(width: diameter * 0.28, height: diameter * 0.28)
                    .offset(x: -diameter * 0.18, y: -diameter * 0.18)
            }
            .overlay {
                Circle()
                    .stroke(.white.opacity(0.12), lineWidth: 1)
            }
            .shadow(color: bubble.colors.first?.opacity(0.5) ?? .clear, radius: 8, y: 2)
            .shadow(color: bubble.colors.first?.opacity(0.25) ?? .clear, radius: 16, y: 0)
            .scaleEffect(0.3 + 0.7 * progress)
            .opacity(Double(0.15 + 0.85 * progress))
            .offset(x: position.x, y: position.y)
    }
}

/// Faint arc hint behind the bubbles — reads as a futuristic C frame.
private struct SplashCShapeGuide: View {
    var body: some View {
        Circle()
            .trim(from: 0.17, to: 0.83)
            .stroke(
                AngularGradient(
                    colors: [
                        AppTheme.accent.opacity(0.55),
                        AppTheme.accentSecondary.opacity(0.4),
                        AppTheme.accent.opacity(0.12),
                        AppTheme.accentSecondary.opacity(0.4),
                        AppTheme.accent.opacity(0.55)
                    ],
                    center: .center
                ),
                style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [3, 6])
            )
            .rotationEffect(.degrees(90))
            .frame(width: 172, height: 172)
            .offset(x: -12)
            .blur(radius: 0.5)
    }
}
