//
//  AppTheme.swift
//  Chordyx
//

import SwiftUI

enum AppTheme {
    static let background = Color(red: 0.06, green: 0.07, blue: 0.12)
    static let surface = Color(red: 0.11, green: 0.12, blue: 0.18)
    static let surfaceElevated = Color(red: 0.16, green: 0.17, blue: 0.24)
    static let accent = Color(red: 0.98, green: 0.72, blue: 0.28)
    static let accentSecondary = Color(red: 0.45, green: 0.55, blue: 0.98)
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.65)
    static let ringStroke = Color.white.opacity(0.12)
    static let chordInactive = Color(red: 0.20, green: 0.22, blue: 0.30)
    static let chordActive = Color(red: 0.98, green: 0.72, blue: 0.28)

    static let backgroundGradient = LinearGradient(
        colors: [
            Color(red: 0.08, green: 0.09, blue: 0.16),
            Color(red: 0.04, green: 0.05, blue: 0.10)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

struct GlassCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(AppTheme.surface.opacity(0.85))
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
    }
}

extension View {
    func glassCard() -> some View {
        modifier(GlassCard())
    }
}

extension MusicalKey {
    /// Hue on the chromatic wheel (0–1) from pitch class — used for key-aware accents.
    var accentHue: Double { Double(pitchClass) / 12.0 }

    var keyTint: Color {
        Color(hue: accentHue, saturation: 0.68, brightness: 0.92)
    }

    var keyTintFill: Color {
        keyTint.opacity(0.26)
    }

    var keyTintStroke: Color {
        keyTint.opacity(0.58)
    }
}
