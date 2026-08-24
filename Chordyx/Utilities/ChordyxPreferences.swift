//
//  ChordyxPreferences.swift
//  Chordyx
//
//  Central preference keys for MIDI, click, setlist handoff, and stage UI.
//

import Foundation

enum ChordyxPreferences {
    // MARK: - Keys

    static let separateClickVolumeKey = "prefs.separateClickVolume"
    static let clickVolumeKey = "prefs.clickVolume"
    static let showBandCuePadByDefaultKey = "prefs.showBandCuePadByDefault"
    static let showRingCuesKey = "prefs.showRingCues"
    static let midiOutputEnabledKey = "prefs.midiOutputEnabled"

    // MARK: - Metronome / click

    static var separateClickVolume: Bool {
        get { UserDefaults.standard.bool(forKey: separateClickVolumeKey) }
        set { UserDefaults.standard.set(newValue, forKey: separateClickVolumeKey) }
    }

    static var clickVolume: Float {
        get {
            let value = UserDefaults.standard.object(forKey: clickVolumeKey) as? Float
            return value ?? 0.85
        }
        set { UserDefaults.standard.set(min(1, max(0, newValue)), forKey: clickVolumeKey) }
    }

    // MARK: - Stage / guest

    static var showBandCuePadByDefault: Bool {
        get { UserDefaults.standard.bool(forKey: showBandCuePadByDefaultKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: showBandCuePadByDefaultKey)
            if newValue {
                GuestDisplaySettings.bandCuePadVisible = true
            }
        }
    }

    /// Compact cue chips under the chord ring (host / practice).
    static var showRingCues: Bool {
        get {
            if UserDefaults.standard.object(forKey: showRingCuesKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: showRingCuesKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: showRingCuesKey) }
    }

    // MARK: - MIDI / practice

    static var midiOutputEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: midiOutputEnabledKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: midiOutputEnabledKey)
            MIDIOutputManager.shared.setEnabled(newValue)
        }
    }
}
