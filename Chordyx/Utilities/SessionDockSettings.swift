//
//  SessionDockSettings.swift
//  Chordyx
//
//  Live session control dock layout preferences (Mac / iPad wide).
//

import SwiftUI

enum LiveHostDockTab: String, CaseIterable, Identifiable {
    case quick
    case metronome
    case audio
    case cues
    case session

    var id: String { rawValue }

    var label: String {
        switch self {
        case .quick: String(localized: "Quick")
        case .metronome: String(localized: "Metro")
        case .audio: String(localized: "Audio")
        case .cues: String(localized: "Cues")
        case .session: String(localized: "Session")
        }
    }

    var icon: String {
        switch self {
        case .quick: "square.grid.2x2"
        case .metronome: "metronome"
        case .audio: "waveform"
        case .cues: "megaphone"
        case .session: "slider.horizontal.3"
        }
    }
}

enum LiveDockLayoutMode: String, CaseIterable, Identifiable {
    case automatic
    case sideRail
    case bottomDock

    var id: String { rawValue }

    var label: String {
        switch self {
        case .automatic: String(localized: "Auto")
        case .sideRail: String(localized: "Side panel")
        case .bottomDock: String(localized: "Bottom dock")
        }
    }
}

enum LiveDockHeightPreset: String, CaseIterable, Identifiable {
    case compact
    case standard
    case expanded
    case maximum

    var id: String { rawValue }

    var label: String {
        switch self {
        case .compact: String(localized: "S")
        case .standard: String(localized: "M")
        case .expanded: String(localized: "L")
        case .maximum: String(localized: "XL")
        }
    }

    var heightFraction: CGFloat {
        switch self {
        case .compact: 0.22
        case .standard: 0.32
        case .expanded: 0.42
        case .maximum: 0.52
        }
    }
}

enum SessionDockSettings {
    static let layoutModeKey = "chordyxLiveDockLayoutMode"
    static let heightPresetKey = "chordyxLiveDockHeightPreset"
    static let selectedTabKey = "chordyxLiveDockSelectedTab"
    static let sideRailWidthKey = "chordyxLiveSideRailWidth"
    static let sideRailVisibleKey = "chordyxLiveSideRailVisible"

    static let sideRailMinWidth: CGFloat = 320
    static let sideRailDefaultWidth: CGFloat = 400
    static let sideRailMaxWidth: CGFloat = 480
    static let sideRailAutoThreshold: CGFloat = 860

    static func resolvedLayoutMode(
        viewportWidth: CGFloat,
        stored: LiveDockLayoutMode
    ) -> LiveDockLayoutMode {
        switch stored {
        case .automatic:
            return viewportWidth >= sideRailAutoThreshold ? .sideRail : .bottomDock
        case .sideRail, .bottomDock:
            return stored
        }
    }

    static func bottomPanelHeight(
        viewportHeight: CGFloat,
        preset: LiveDockHeightPreset,
        bandCuePadVisible: Bool
    ) -> CGFloat {
        var fraction = preset.heightFraction
        if bandCuePadVisible, preset != .maximum {
            fraction = min(0.56, fraction + 0.08)
        }
        return viewportHeight * fraction
    }
}
