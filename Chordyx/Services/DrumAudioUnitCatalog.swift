//
//  DrumAudioUnitCatalog.swift
//  Chordyx
//
//  Discovers Audio Unit instruments suitable for drum MIDI playback.
//

#if os(macOS)
import AVFoundation
import Foundation

enum DrumAudioUnitCatalog {
    @MainActor
    static func discoverMusicDevices() -> [DrumAUComponentRef] {
        let description = AudioComponentDescription(
            componentType: kAudioUnitType_MusicDevice,
            componentSubType: 0,
            componentManufacturer: 0,
            componentFlags: 0,
            componentFlagsMask: 0
        )

        let components = AVAudioUnitComponentManager.shared().components(matching: description)
        var refs = components.map(DrumAUComponentRef.init(component:))
        refs.sort { lhs, rhs in
            if lhs.isLikelyDrumRelated != rhs.isLikelyDrumRelated {
                return lhs.isLikelyDrumRelated && !rhs.isLikelyDrumRelated
            }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
        return refs
    }

    static func drumRelatedUnits(from all: [DrumAUComponentRef]) -> [DrumAUComponentRef] {
        all.filter(\.isLikelyDrumRelated)
    }
}
#endif
