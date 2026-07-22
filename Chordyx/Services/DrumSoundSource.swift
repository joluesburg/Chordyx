//
//  DrumSoundSource.swift
//  Chordyx
//
//  Drum sound backends: Apple GM, user soundfonts, AU plugins, synthesis.
//

#if os(macOS) || os(iOS)
import AVFoundation
import Foundation

enum DrumSoundSourceKind: String, CaseIterable, Identifiable, Codable, Sendable {
    case systemGM
    case userSoundFont
    case audioUnit
    case synthesis

    var id: String { rawValue }

    var label: String {
        switch self {
        case .systemGM: String(localized: "Apple GM drums")
        case .userSoundFont: String(localized: "My soundfont (.sf2 / .dls)")
        case .audioUnit: String(localized: "AU plugin")
        case .synthesis: String(localized: "Studio kit")
        }
    }

    var subtitle: String {
        switch self {
        case .systemGM:
            String(localized: "Built-in General MIDI kit — no extra install.")
        case .userSoundFont:
            String(localized: "Load your own licensed drum soundfont.")
        case .audioUnit:
            String(localized: "Use a drum or sampler plugin installed on this Mac.")
        case .synthesis:
            String(localized: "Fallback kit — use Apple GM for best quality.")
        }
    }
}

struct DrumAUComponentRef: Identifiable, Equatable, Codable, Sendable {
    let name: String
    let manufacturerName: String
    let componentType: UInt32
    let componentSubType: UInt32
    let componentManufacturer: UInt32

    var id: String {
        "\(componentType)-\(componentSubType)-\(componentManufacturer)-\(name)"
    }

    var displayName: String {
        if manufacturerName.isEmpty { return name }
        return "\(name) · \(manufacturerName)"
    }

    var isLikelyDrumRelated: Bool {
        let haystack = displayName.lowercased()
        let keywords = [
            "drum", "perc", "kit", "sampler", "sample", "battery", "superior",
            "addictive", "groove", "batter", "studio", "tamb", "conga", "latin"
        ]
        return keywords.contains { haystack.contains($0) }
    }

    var audioComponentDescription: AudioComponentDescription {
        AudioComponentDescription(
            componentType: componentType,
            componentSubType: componentSubType,
            componentManufacturer: componentManufacturer,
            componentFlags: 0,
            componentFlagsMask: 0
        )
    }

    @MainActor
    init(component: AVAudioUnitComponent) {
        name = component.name
        manufacturerName = component.manufacturerName
        let desc = component.audioComponentDescription
        componentType = desc.componentType
        componentSubType = desc.componentSubType
        componentManufacturer = desc.componentManufacturer
    }
}

struct DrumSoundSourceSelection: Equatable, Codable, Sendable {
    var kind: DrumSoundSourceKind = .systemGM
    var soundFontBookmark: Data?
    var soundFontDisplayName: String?
    var audioUnit: DrumAUComponentRef?

    static let `default` = DrumSoundSourceSelection()
}

enum DrumSoundSourceStore {
    private static let defaultsKey = "soloDrumSoundSourceSelection"
    private static let qualityVersionKey = "soloDrumSoundSourceQualityVersion"
    private static let currentQualityVersion = 2

    static func load() -> DrumSoundSourceSelection {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              var selection = try? JSONDecoder().decode(DrumSoundSourceSelection.self, from: data) else {
            return .default
        }
        if UserDefaults.standard.integer(forKey: qualityVersionKey) < currentQualityVersion {
            if selection.kind == .synthesis {
                selection.kind = .systemGM
            }
            save(selection)
            UserDefaults.standard.set(currentQualityVersion, forKey: qualityVersionKey)
        }
        #if os(iOS)
        if selection.kind == .audioUnit {
            selection.kind = .systemGM
            selection.audioUnit = nil
            save(selection)
        }
        #endif
        return selection
    }

    static func save(_ selection: DrumSoundSourceSelection) {
        guard let data = try? JSONEncoder().encode(selection) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}

enum DrumSoundFontAccess {
    static func bookmark(_ url: URL) throws -> Data {
        #if os(macOS)
        try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        #else
        try url.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        #endif
    }

    static func resolveURL(from bookmarkData: Data) throws -> URL {
        var stale = false
        #if os(macOS)
        let url = try URL(
            resolvingBookmarkData: bookmarkData,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        )
        #else
        let url = try URL(
            resolvingBookmarkData: bookmarkData,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        )
        #endif
        if stale {
            let refreshed = try bookmark(url)
            var selection = DrumSoundSourceStore.load()
            selection.soundFontBookmark = refreshed
            DrumSoundSourceStore.save(selection)
        }
        return url
    }
}
#endif
