//
//  GuestDisplaySettings.swift
//  Chordyx
//

import SwiftUI

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
    static let externalDisplayGuideKey = "externalDisplayGuideDismissed"
    static let lyricsAutoScrollKey = "lyricsAutoScrollEnabled"
    static let preServiceDismissedTokenKey = "preServiceChecklistDismissedToken"

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

    static func effectiveDisplayMode(hostMode: SessionDisplayMode, isGuest: Bool) -> SessionDisplayMode {
        guard isGuest else { return hostMode }
        if stageMonitorMode { return .stage }
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
        if let preferred = viewRole.preferredNotation { return preferred }
        switch instrument {
        case .bass: return .nashville
        default:
            let raw = UserDefaults.standard.string(forKey: "preferredNotation") ?? hostNotation.rawValue
            return ChordNotation(rawValue: raw) ?? hostNotation
        }
    }
}
