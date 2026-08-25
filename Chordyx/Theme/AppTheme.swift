//
//  AppTheme.swift
//  Chordyx
//
//  iOS 27 Liquid Glass design tokens — lighter dark surfaces, defined glass borders,
//  and shared modifiers so feature views inherit the refresh automatically.
//

import SwiftUI

enum AppTheme {
    // MARK: - Palette (iOS 27 — lighter dark mode, higher legibility)

    static let background = Color(red: 0.10, green: 0.11, blue: 0.17)
    static let surface = Color(red: 0.15, green: 0.16, blue: 0.23)
    static let surfaceElevated = Color(red: 0.21, green: 0.22, blue: 0.30)
    static let accent = Color(red: 0.98, green: 0.74, blue: 0.32)
    static let accentSecondary = Color(red: 0.52, green: 0.62, blue: 1.0)
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.68)
    static let ringStroke = Color.white.opacity(0.16)
    static let chordInactive = Color(red: 0.24, green: 0.26, blue: 0.34)
    static let chordActive = Color(red: 0.98, green: 0.74, blue: 0.32)

    /// iOS 27 tab / segment selection — darker fill on dark mode (system convention).
    static let glassSelectionFill = Color(red: 0.08, green: 0.09, blue: 0.14).opacity(0.72)

    static let glassBorderHighlight = Color.white.opacity(0.24)
    static let glassBorderShadow = Color.black.opacity(0.38)

    static let backgroundGradient = LinearGradient(
        colors: [
            Color(red: 0.13, green: 0.14, blue: 0.22),
            Color(red: 0.07, green: 0.08, blue: 0.13)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let ambientGlow = RadialGradient(
        colors: [
            accent.opacity(0.14),
            accentSecondary.opacity(0.06),
            Color.clear
        ],
        center: .topLeading,
        startRadius: 20,
        endRadius: 420
    )

    // MARK: - Layout tokens

    enum Radius {
        static let chip: CGFloat = 12
        static let card: CGFloat = 20
        static let sheet: CGFloat = 24
        static let dockTab: CGFloat = 10
    }

    enum Spacing {
        static let chipVertical: CGFloat = 9
        static let chipHorizontal: CGFloat = 14
        static let cardPadding: CGFloat = 16
    }
}

// MARK: - Typography

extension View {
    func appSectionHeader() -> some View {
        font(.caption.weight(.semibold))
            .foregroundStyle(AppTheme.textSecondary)
            .textCase(.uppercase)
            .tracking(0.75)
    }
}

// MARK: - Shell background

extension View {
    /// App canvas — gradient plus soft accent glow (iOS 27 depth).
    func appShellBackground() -> some View {
        background {
            ZStack {
                AppTheme.backgroundGradient
                AppTheme.ambientGlow
            }
            .ignoresSafeArea()
        }
    }
}

// MARK: - Liquid Glass surfaces

enum LiquidGlassShape {
    case roundedRect(cornerRadius: CGFloat)
    case capsule

    @ViewBuilder
    func clip(_ content: some View) -> some View {
        switch self {
        case .roundedRect(let radius):
            content.clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        case .capsule:
            content.clipShape(Capsule())
        }
    }

    @ViewBuilder
    func borderOverlay(lineWidth: CGFloat = 1) -> some View {
        switch self {
        case .roundedRect(let radius):
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(glassBorderGradient, lineWidth: lineWidth)
        case .capsule:
            Capsule()
                .strokeBorder(glassBorderGradient, lineWidth: lineWidth)
        }
    }

    private var glassBorderGradient: LinearGradient {
        LinearGradient(
            colors: [
                AppTheme.glassBorderHighlight,
                AppTheme.glassBorderShadow
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

struct LiquidGlassSurfaceModifier: ViewModifier {
    var cornerRadius: CGFloat = AppTheme.Radius.card
    var tintOpacity: Double = 0.55
    var useCapsule = false

    func body(content: Content) -> some View {
        let shape: LiquidGlassShape = useCapsule ? .capsule : .roundedRect(cornerRadius: cornerRadius)
        content
            .background { glassBackground(shape: shape) }
            .modifier(GlassShapeClip(shape: shape))
            .overlay { shape.borderOverlay() }
    }

    @ViewBuilder
    private func glassBackground(shape: LiquidGlassShape) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            glassEffectBackground(shape: shape)
        } else {
            legacyGlassBackground(shape: shape)
        }
    }

    @available(iOS 26.0, macOS 26.0, *)
    @ViewBuilder
    private func glassEffectBackground(shape: LiquidGlassShape) -> some View {
        switch shape {
        case .roundedRect(let radius):
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(.clear)
                .glassEffect(.regular, in: .rect(cornerRadius: radius, style: .continuous))
        case .capsule:
            Capsule()
                .fill(.clear)
                .glassEffect(.regular, in: .capsule)
        }
    }

    @ViewBuilder
    private func legacyGlassBackground(shape: LiquidGlassShape) -> some View {
        switch shape {
        case .roundedRect(let radius):
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(AppTheme.surface.opacity(tintOpacity))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
        case .capsule:
            Capsule()
                .fill(AppTheme.surface.opacity(tintOpacity))
                .background(.ultraThinMaterial, in: Capsule())
        }
    }
}

private struct GlassShapeClip: ViewModifier {
    let shape: LiquidGlassShape

    func body(content: Content) -> some View {
        shape.clip(content)
    }
}

struct GlassCard: ViewModifier {
    var cornerRadius: CGFloat = AppTheme.Radius.card

    func body(content: Content) -> some View {
        content.modifier(LiquidGlassSurfaceModifier(cornerRadius: cornerRadius))
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = AppTheme.Radius.card) -> some View {
        modifier(GlassCard(cornerRadius: cornerRadius))
    }

    func liquidGlassCapsule(tintOpacity: Double = 0.5) -> some View {
        modifier(LiquidGlassSurfaceModifier(tintOpacity: tintOpacity, useCapsule: true))
    }

    /// iOS 27 scroll chrome — hard edge with separator (system default on iOS 27).
    @ViewBuilder
    func platformScrollEdgeEffect() -> some View {
        #if os(iOS)
        if #available(iOS 26.0, *) {
            scrollEdgeEffectStyle(.hard, for: .all)
        } else {
            self
        }
        #else
        self
        #endif
    }

    /// Sheet / menu chrome aligned with Liquid Glass sheets.
    @ViewBuilder
    func liquidGlassSheetBackground() -> some View {
        #if os(iOS)
        if #available(iOS 26.0, *) {
            presentationBackground(.ultraThinMaterial)
                .presentationCornerRadius(AppTheme.Radius.sheet)
        } else {
            background(AppTheme.background)
        }
        #else
        background(AppTheme.backgroundGradient.ignoresSafeArea())
        #endif
    }
}

// MARK: - Buttons

struct GlassProminentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.semibold))
            .foregroundStyle(AppTheme.background)
            .padding(.vertical, 15)
            .frame(maxWidth: .infinity)
            .background {
                if configuration.isPressed {
                    AppTheme.accent.opacity(0.82)
                } else {
                    AppTheme.accent
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.chip + 4, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.Radius.chip + 4, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.28), lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == GlassProminentButtonStyle {
    static var chordyxProminent: GlassProminentButtonStyle { GlassProminentButtonStyle() }
}

// MARK: - Musical key accents

extension MusicalKey {
    /// Hue on the chromatic wheel (0–1) from pitch class — used for key-aware accents.
    var accentHue: Double { Double(pitchClass) / 12.0 }

    var keyTint: Color {
        Color(hue: accentHue, saturation: 0.68, brightness: 0.94)
    }

    var keyTintFill: Color {
        keyTint.opacity(0.28)
    }

    var keyTintStroke: Color {
        keyTint.opacity(0.62)
    }
}
