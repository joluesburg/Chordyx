//
//  GuestDisplaySettings.swift
//  Chordyx
//

import SwiftUI

/// Guest Live view style — local preference (not synced by the host).
enum GuestLiveViewStyle: String, CaseIterable, Identifiable, Hashable, Sendable {
    case ring
    case now
    case clock

    var id: String { rawValue }

    var label: String {
        switch self {
        case .ring: String(localized: "Ring")
        case .now: String(localized: "Now")
        case .clock: String(localized: "Clock")
        }
    }

    /// Styles shown in the Live picker. Clock is iPhone-only.
    static var pickerCases: [GuestLiveViewStyle] {
        #if os(iOS)
        if PlatformDevice.isPhone { return [.ring, .now, .clock] }
        #endif
        return [.ring, .now]
    }
}

enum GuestDisplaySettings {
    static let transposeKey = "guestTransposeSemitones"
    static let capoKey = "guestCapoFret"
    static let instrumentKey = "guestMusicianInstrument"
    static let hapticsKey = "guestWatchHapticsEnabled"
    static let liveActivityKey = "guestLiveActivityEnabled"
    static let hideSongTitleKey = "guestHideSongTitleOnLockScreen"
    static let viewRoleKey = "guestViewRole"
    static let scaleHintsKey = "guestScaleHintsEnabled"
    static let beatSyncHintsKey = "guestBeatSyncHintsEnabled"
    static let acousticRoomModeKey = "guestAcousticRoomMode"
    static let stageMonitorKey = "guestStageMonitorMode"
    static let liveNowOnlyKey = "guestLiveNowOnlyMode"
    static let liveViewStyleKey = "guestLiveViewStyle"
    static let beginnerPianoTriadsKey = "guestBeginnerPianoTriads"
    static let pianoKeysLayoutModeKey = "pianoKeysLayoutMode"
    static let externalDisplayGuideKey = "externalDisplayGuideDismissed"
    static let lyricsAutoScrollKey = "lyricsAutoScrollEnabled"
    static let preServiceDismissedTokenKey = "preServiceChecklistDismissedToken"
    static let preServiceAutoShowKey = "preServiceChecklistAutoShowEnabled"
    static let cueHapticsKey = "guestCueHapticsEnabled"
    static let silentNudgesKey = "guestSilentNudgesEnabled"
    static let chartLanguageKey = "guestChartLanguage"
    static let chromaticToneNamesKey = "chromaticToneNames"
    static let chromaticToneNamesVersionKey = "chromaticToneNamesVersion"
    static let voicingHintsKey = "guestVoicingHintsEnabled"
    static let clickTrackLaneKey = "guestClickTrackLane"
    static let bandCuePadVisibleKey = "hostBandCuePadVisible"
    static let bandChatBadgesKey = "bandChatBadgesEnabled"
    static let bandChatHapticsKey = "bandChatHapticsEnabled"
    static let bandChatSoundsKey = "bandChatSoundsEnabled"
    static let bandChatQuietDuringLiveKey = "bandChatQuietDuringLive"
    static let bandChatInAppAlertsKey = "bandChatInAppAlertsEnabled"
    static let bandChatCompactKey = "bandChatCompactEnabled"

    /// Host live view: show the Band Cues grid (off by default — enable from the toolbar when needed).
    static var bandCuePadVisible: Bool {
        get { UserDefaults.standard.bool(forKey: bandCuePadVisibleKey) }
        set { UserDefaults.standard.set(newValue, forKey: bandCuePadVisibleKey) }
    }

    /// Unread badge on the band chat entry button.
    static var bandChatBadgesEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: bandChatBadgesKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: bandChatBadgesKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: bandChatBadgesKey) }
    }

    /// Light haptic when a new band chat message arrives.
    static var bandChatHapticsEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: bandChatHapticsKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: bandChatHapticsKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: bandChatHapticsKey) }
    }

    /// Short system sound for new band chat messages (off by default).
    static var bandChatSoundsEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: bandChatSoundsKey) }
        set { UserDefaults.standard.set(newValue, forKey: bandChatSoundsKey) }
    }

    /// Suppress haptic / sound / toast during Live performance mode.
    static var bandChatQuietDuringLive: Bool {
        get {
            if UserDefaults.standard.object(forKey: bandChatQuietDuringLiveKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: bandChatQuietDuringLiveKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: bandChatQuietDuringLiveKey) }
    }

    /// Brief in-app banner when chat is closed and a new message arrives.
    static var bandChatInAppAlertsEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: bandChatInAppAlertsKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: bandChatInAppAlertsKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: bandChatInAppAlertsKey) }
    }

    /// Open chat as a narrow side panel (iPad/Mac) or medium sheet (iPhone) so the chord stage stays visible.
    /// Off by default — keeps the full large sheet behavior.
    static var bandChatCompactEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: bandChatCompactKey) }
        set { UserDefaults.standard.set(newValue, forKey: bandChatCompactKey) }
    }

    static var silentNudgesEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: silentNudgesKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: silentNudgesKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: silentNudgesKey) }
    }

    static var chartLanguage: ChartLanguage {
        get {
            ChartLanguage(rawValue: UserDefaults.standard.string(forKey: chartLanguageKey) ?? "") ?? .english
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: chartLanguageKey) }
    }

    /// Local 12-tone spellings for piano key labels and Latin chord roots.
    static var chromaticToneNames: ChromaticToneNames {
        get {
            guard let data = UserDefaults.standard.data(forKey: chromaticToneNamesKey),
                  let decoded = try? JSONDecoder().decode(ChromaticToneNames.self, from: data) else {
                return .default
            }
            return decoded
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: chromaticToneNamesKey)
            }
            let next = UserDefaults.standard.integer(forKey: chromaticToneNamesVersionKey) &+ 1
            UserDefaults.standard.set(next, forKey: chromaticToneNamesVersionKey)
        }
    }

    static var chromaticToneNamesVersion: Int {
        UserDefaults.standard.integer(forKey: chromaticToneNamesVersionKey)
    }

    static var voicingHintsEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: voicingHintsKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: voicingHintsKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: voicingHintsKey) }
    }

    static var clickTrackLane: ClickTrackLane {
        get {
            ClickTrackLane(rawValue: UserDefaults.standard.string(forKey: clickTrackLaneKey) ?? "") ?? .full
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: clickTrackLaneKey) }
    }

    static var cueHapticsEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: cueHapticsKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: cueHapticsKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: cueHapticsKey) }
    }

    static var transposeSemitones: Int {
        get { UserDefaults.standard.integer(forKey: transposeKey) }
        set { UserDefaults.standard.set(newValue, forKey: transposeKey) }
    }

    static var capoFret: Int {
        get { UserDefaults.standard.integer(forKey: capoKey) }
        set { UserDefaults.standard.set(max(0, min(newValue, 11)), forKey: capoKey) }
    }

    static var instrument: MusicianInstrument {
        get {
            MusicianInstrument(rawValue: UserDefaults.standard.string(forKey: instrumentKey) ?? "") ?? .keys
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: instrumentKey) }
    }

    static var viewRole: GuestViewRole {
        get {
            GuestViewRole(rawValue: UserDefaults.standard.string(forKey: viewRoleKey) ?? "") ?? .auto
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: viewRoleKey) }
    }

    static var scaleHintsEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: scaleHintsKey) }
        set { UserDefaults.standard.set(newValue, forKey: scaleHintsKey) }
    }

    static var beatSyncHintsEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: beatSyncHintsKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: beatSyncHintsKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: beatSyncHintsKey) }
    }

    static var acousticRoomMode: Bool {
        get { UserDefaults.standard.bool(forKey: acousticRoomModeKey) }
        set { UserDefaults.standard.set(newValue, forKey: acousticRoomModeKey) }
    }

    static var stageMonitorMode: Bool {
        get { UserDefaults.standard.bool(forKey: stageMonitorKey) }
        set { UserDefaults.standard.set(newValue, forKey: stageMonitorKey) }
    }

    /// Guest Live view: Ring / Now / Clock (Clock is iPhone-oriented).
    static var liveViewStyle: GuestLiveViewStyle {
        get {
            if let raw = UserDefaults.standard.string(forKey: liveViewStyleKey),
               let style = GuestLiveViewStyle(rawValue: raw) {
                return style
            }
            // Migrate legacy bool.
            return UserDefaults.standard.bool(forKey: liveNowOnlyKey) ? .now : .ring
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: liveViewStyleKey)
            UserDefaults.standard.set(newValue == .now, forKey: liveNowOnlyKey)
        }
    }

    /// Guest-only: during Live sessions, show the current chord full-screen (no ring).
    /// Kept for older call sites; backed by `liveViewStyle`.
    static var liveNowOnlyMode: Bool {
        get { liveViewStyle == .now }
        set {
            if newValue {
                liveViewStyle = .now
            } else if liveViewStyle == .now {
                liveViewStyle = .ring
            }
        }
    }

    /// Guest-only piano: show major/minor triads instead of full host voicings (e.g. Cmaj9 → C–E–G).
    static var beginnerPianoTriadsEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: beginnerPianoTriadsKey) }
        set { UserDefaults.standard.set(newValue, forKey: beginnerPianoTriadsKey) }
    }

    /// Piano Keys layout: Auto (smart dual), always 2 hands, or one scrolling keyboard.
    /// Separate from Beginner (on/off triad simplification).
    static var pianoKeysLayoutMode: PianoNote.KeysLayoutMode {
        get {
            let raw = UserDefaults.standard.string(forKey: pianoKeysLayoutModeKey) ?? PianoNote.KeysLayoutMode.auto.rawValue
            if raw == "beginner" { return .auto }
            return PianoNote.KeysLayoutMode(rawValue: raw) ?? .auto
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: pianoKeysLayoutModeKey) }
    }

    static var externalDisplayGuideDismissed: Bool {
        get { UserDefaults.standard.bool(forKey: externalDisplayGuideKey) }
        set { UserDefaults.standard.set(newValue, forKey: externalDisplayGuideKey) }
    }

    static var lyricsAutoScrollEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: lyricsAutoScrollKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: lyricsAutoScrollKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: lyricsAutoScrollKey) }
    }

    static var preServiceChecklistDismissedToken: String {
        get { UserDefaults.standard.string(forKey: preServiceDismissedTokenKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: preServiceDismissedTokenKey) }
    }

    /// When false, the pre-service sheet is not shown automatically at the start of live hosting.
    static var preServiceChecklistAutoShowEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: preServiceAutoShowKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: preServiceAutoShowKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: preServiceAutoShowKey) }
    }

    static var watchHapticsEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: hapticsKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: hapticsKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: hapticsKey) }
    }

    static var liveActivityEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: liveActivityKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: liveActivityKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: liveActivityKey) }
    }

    static var hideSongTitleOnLockScreen: Bool {
        get { UserDefaults.standard.bool(forKey: hideSongTitleKey) }
        set { UserDefaults.standard.set(newValue, forKey: hideSongTitleKey) }
    }

    static func effectiveDisplayMode(
        hostMode: SessionDisplayMode,
        isGuest: Bool,
        isLivePerformance: Bool = false,
        isLiveChordsOnly: Bool = false
    ) -> SessionDisplayMode {
        guard isGuest else { return hostMode }
        if stageMonitorMode { return .stage }
        // Guest Live picker: Now = stage hero; Ring / Clock = ring layout (Clock branches in SessionView).
        if isLivePerformance || isLiveChordsOnly {
            return liveViewStyle == .now ? .stage : .ring
        }
        if let preferred = viewRole.preferredDisplayMode { return preferred }
        switch instrument {
        case .vocal: return .chart
        case .bass: return .stage
        case .keys: return .ring
        default: return hostMode
        }
    }

    static func effectiveNotation(hostNotation: ChordNotation, isGuest: Bool) -> ChordNotation {
        guard isGuest else { return hostNotation }
        let languageNotation = chartLanguage.preferredNotation
        if let preferred = viewRole.preferredNotation { return preferred }
        switch instrument {
        case .bass: return .nashville
        default:
            if chartLanguage != .english { return languageNotation }
            let raw = UserDefaults.standard.string(forKey: "preferredNotation") ?? hostNotation.rawValue
            return ChordNotation(rawValue: raw) ?? hostNotation
        }
    }
}
