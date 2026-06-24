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
                    ForEach(Array(bubbles.enumerated()), id: \.element.id) { index, bubble in
                        let progress = bubbleProgress[index]
                        SplashBubbleView(bubble: bubble, progress: progress)
                    }
                }
                .frame(width: 200, height: 200)

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
        for index in bubbles.indices {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.72)) {
                bubbleProgress[index] = 1
            }
            try? await Task.sleep(for: .milliseconds(120))
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

private struct SplashBubble: Identifiable {
    let id: Int
    let start: CGPoint
    let target: CGPoint
    let colors: [Color]

    static let cShape: [SplashBubble] = {
        let targets: [(CGPoint, [Color])] = [
            (CGPoint(x: 28, y: -72), [AppTheme.accent, AppTheme.accent.opacity(0.85)]),
            (CGPoint(x: -62, y: -48), [AppTheme.accentSecondary, AppTheme.accentSecondary.opacity(0.85)]),
            (CGPoint(x: -82, y: 8), [AppTheme.accent, AppTheme.accent.opacity(0.85)]),
            (CGPoint(x: -58, y: 58), [AppTheme.accentSecondary, AppTheme.accentSecondary.opacity(0.85)]),
            (CGPoint(x: 18, y: 78), [AppTheme.accent, AppTheme.accent.opacity(0.85)]),
        ]

        return targets.enumerated().map { index, item in
            let angle = Double(index) / Double(targets.count) * .pi * 2
            let start = CGPoint(
                x: item.0.x + cos(angle) * 220,
                y: item.0.y + sin(angle) * 220
            )
            return SplashBubble(id: index, start: start, target: item.0, colors: item.1)
        }
    }()
}

private struct SplashBubbleView: View {
    let bubble: SplashBubble
    let progress: CGFloat

    private var position: CGPoint {
        CGPoint(
            x: bubble.start.x + (bubble.target.x - bubble.start.x) * progress,
            y: bubble.start.y + (bubble.target.y - bubble.start.y) * progress
        )
    }

    var body: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: bubble.colors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 34, height: 34)
            .overlay {
                Circle()
                    .fill(.white.opacity(0.35))
                    .frame(width: 10, height: 10)
                    .offset(x: -6, y: -6)
            }
            .shadow(color: bubble.colors.first?.opacity(0.45) ?? .clear, radius: 10, y: 3)
            .scaleEffect(0.35 + 0.65 * progress)
            .opacity(Double(0.2 + 0.8 * progress))
            .offset(x: position.x, y: position.y)
    }
}
