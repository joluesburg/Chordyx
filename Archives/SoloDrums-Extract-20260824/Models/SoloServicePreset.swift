//
//  SoloServicePreset.swift
//  Chordyx
//
//  One-tap service / rehearsal presets for Solo Drums (tempo + feel + kit family).
//

import Foundation

struct SoloServicePreset: Identifiable, Hashable, Sendable {
    let id: String
    let label: String
    let subtitle: String
    let systemImage: String
    let bpm: Double
    let pattern: DrumPattern
    let category: SoloDrumInstrumentCategory
    let arrangeMode: DrumArrangeMode

    static let all: [SoloServicePreset] = [
        .init(
            id: "worshipBallad",
            label: String(localized: "Worship ballad"),
            subtitle: String(localized: "72 BPM · soft kit"),
            systemImage: "leaf.fill",
            bpm: 72,
            pattern: .worshipBallad,
            category: .softKit,
            arrangeMode: .auto
        ),
        .init(
            id: "gospelBuild",
            label: String(localized: "Gospel build"),
            subtitle: String(localized: "88 BPM · full kit"),
            systemImage: "hands.clap.fill",
            bpm: 88,
            pattern: .gospelGroove,
            category: .drums,
            arrangeMode: .full
        ),
        .init(
            id: "latinPraise",
            label: String(localized: "Latin praise"),
            subtitle: String(localized: "108 BPM · percusión"),
            systemImage: "figure.dance",
            bpm: 108,
            pattern: .salsa,
            category: .percussion,
            arrangeMode: .auto
        ),
        .init(
            id: "popSet",
            label: String(localized: "Pop set"),
            subtitle: String(localized: "120 BPM · kit"),
            systemImage: "guitars",
            bpm: 120,
            pattern: .popRock,
            category: .drums,
            arrangeMode: .fillsOn
        ),
        .init(
            id: "acousticSoft",
            label: String(localized: "Acoustic soft"),
            subtitle: String(localized: "78 BPM · light perc"),
            systemImage: "sparkles",
            bpm: 78,
            pattern: .softPulse,
            category: .lightPercussion,
            arrangeMode: .grooveOnly
        ),
        .init(
            id: "urbanPulse",
            label: String(localized: "Urban pulse"),
            subtitle: String(localized: "92 BPM · electronic"),
            systemImage: "waveform",
            bpm: 92,
            pattern: .hipHopBoomBap,
            category: .electronic,
            arrangeMode: .auto
        )
    ]
}

/// Last locked Solo groove — for quick resume after stop / relaunch.
struct SoloGrooveResumeSnapshot: Codable, Equatable, Sendable {
    var bpm: Double
    var patternRaw: String
    var categoryRaw: String
    var arrangeModeRaw: String
    var savedAt: Date

    var pattern: DrumPattern {
        DrumPattern(rawValue: patternRaw) ?? .worshipBallad
    }

    var category: SoloDrumInstrumentCategory {
        SoloDrumInstrumentCategory(rawValue: categoryRaw) ?? .drums
    }

    var arrangeMode: DrumArrangeMode {
        DrumArrangeMode(rawValue: arrangeModeRaw) ?? .auto
    }

    var caption: String {
        "\(Int(bpm.rounded())) BPM · \(pattern.label) · \(category.label)"
    }
}

enum SoloGrooveResumeStore {
    private static let key = "soloGrooveResumeSnapshot"

    static func load() -> SoloGrooveResumeSnapshot? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(SoloGrooveResumeSnapshot.self, from: data)
    }

    static func save(_ snapshot: SoloGrooveResumeSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

// MARK: - Custom church presets (user-saved)

struct CustomSoloChurchPreset: Identifiable, Codable, Equatable, Hashable, Sendable {
    var id: UUID
    var label: String
    var bpm: Double
    var patternRaw: String
    var categoryRaw: String
    var arrangeModeRaw: String
    var savedAt: Date

    init(
        id: UUID = UUID(),
        label: String,
        bpm: Double,
        pattern: DrumPattern,
        category: SoloDrumInstrumentCategory,
        arrangeMode: DrumArrangeMode,
        savedAt: Date = Date()
    ) {
        self.id = id
        self.label = label
        self.bpm = bpm
        self.patternRaw = pattern.rawValue
        self.categoryRaw = category.rawValue
        self.arrangeModeRaw = arrangeMode.rawValue
        self.savedAt = savedAt
    }

    var pattern: DrumPattern { DrumPattern(rawValue: patternRaw) ?? .worshipBallad }
    var category: SoloDrumInstrumentCategory {
        SoloDrumInstrumentCategory(rawValue: categoryRaw) ?? .drums
    }
    var arrangeMode: DrumArrangeMode { DrumArrangeMode(rawValue: arrangeModeRaw) ?? .auto }

    var subtitle: String {
        "\(Int(bpm.rounded())) BPM · \(pattern.label) · \(category.label)"
    }

    var asServicePreset: SoloServicePreset {
        SoloServicePreset(
            id: id.uuidString,
            label: label,
            subtitle: subtitle,
            systemImage: "building.columns.fill",
            bpm: bpm,
            pattern: pattern,
            category: category,
            arrangeMode: arrangeMode
        )
    }
}

enum CustomSoloChurchPresetStore {
    private static let key = "customSoloChurchPresets"
    private static let maxCount = 12

    static func loadAll() -> [CustomSoloChurchPreset] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([CustomSoloChurchPreset].self, from: data) else {
            return []
        }
        return decoded.sorted { $0.savedAt > $1.savedAt }
    }

    static func saveAll(_ presets: [CustomSoloChurchPreset]) {
        let trimmed = Array(presets.prefix(maxCount))
        guard let data = try? JSONEncoder().encode(trimmed) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func upsert(_ preset: CustomSoloChurchPreset) {
        var all = loadAll().filter { $0.id != preset.id }
        all.insert(preset, at: 0)
        saveAll(all)
    }

    static func delete(id: UUID) {
        saveAll(loadAll().filter { $0.id != id })
    }
}

