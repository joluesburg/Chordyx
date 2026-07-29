//
//  AdvancedFeatureStores.swift
//  Chordyx
//

import Foundation

// MARK: - Practice queue

@MainActor
final class PracticeQueueStore {
    static let shared = PracticeQueueStore()

    private var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("practice_queue.json")
    }

    private init() {}

    func loadAll() -> [PracticeQueueItem] {
        guard let data = try? Data(contentsOf: fileURL),
              let items = try? JSONDecoder().decode([PracticeQueueItem].self, from: data) else {
            return []
        }
        return items.sorted { $0.addedAt > $1.addedAt }
    }

    func save(_ items: [PracticeQueueItem]) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    func add(from recording: RehearsalRecording, at timestamp: TimeInterval) {
        var items = loadAll()
        let event = recording.events.last { $0.kind == .errorMarker && abs($0.timestamp - timestamp) < 1 }
        items.insert(PracticeQueueItem(
            recordingID: recording.id,
            recordingName: recording.name,
            songTitle: event?.songTitle,
            timestamp: timestamp,
            chordID: event?.chordID,
            sectionID: event?.sectionID
        ), at: 0)
        save(items)
    }

    func addFromLatestMistake(recording: RehearsalRecording) {
        guard let event = recording.events.last(where: { $0.kind == .errorMarker }) else { return }
        var items = loadAll()
        guard !items.contains(where: { $0.recordingID == recording.id && abs($0.timestamp - event.timestamp) < 1 }) else { return }
        items.insert(PracticeQueueItem(
            recordingID: recording.id,
            recordingName: recording.name,
            songTitle: event.songTitle,
            timestamp: event.timestamp,
            chordID: event.chordID,
            sectionID: event.sectionID
        ), at: 0)
        save(items)
    }

    func markResolved(_ id: UUID) {
        var items = loadAll()
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].isResolved = true
        save(items)
    }

    func unresolved() -> [PracticeQueueItem] {
        loadAll().filter { !$0.isResolved }
    }
}

// MARK: - Sunday folder (offline cache)

@MainActor
final class SundayFolderStore {
    static let shared = SundayFolderStore()

    private var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("sunday_folder.json")
    }

    private init() {}

    func loadAll() -> [SundayFolderEntry] {
        guard let data = try? Data(contentsOf: fileURL),
              let items = try? JSONDecoder().decode([SundayFolderEntry].self, from: data) else {
            return []
        }
        return items.sorted { ($0.serviceDate ?? $0.cachedAt) > ($1.serviceDate ?? $1.cachedAt) }
    }

    func save(_ items: [SundayFolderEntry]) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    func cacheSetlist(name: String, progressionIDs: [UUID], songTitles: [String], serviceDate: Date? = nil) {
        var items = loadAll()
        items.removeAll { $0.setlistName == name }
        items.insert(SundayFolderEntry(
            setlistName: name,
            progressionIDs: progressionIDs,
            songTitles: songTitles,
            serviceDate: serviceDate
        ), at: 0)
        save(items)
    }

    func remove(_ id: UUID) {
        var items = loadAll()
        items.removeAll { $0.id == id }
        save(items)
    }
}

// MARK: - Team pack subscriptions

@MainActor
final class TeamPackSubscriptionStore {
    static let shared = TeamPackSubscriptionStore()

    private var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("team_pack_subscriptions.json")
    }

    private init() {}

    func loadAll() -> [TeamPackSubscription] {
        guard let data = try? Data(contentsOf: fileURL),
              let items = try? JSONDecoder().decode([TeamPackSubscription].self, from: data) else {
            return []
        }
        return items
    }

    func save(_ items: [TeamPackSubscription]) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    func subscribe(packName: String, teamName: String, revisionLabel: String) {
        var items = loadAll()
        if let index = items.firstIndex(where: { $0.packName == packName }) {
            let old = items[index].lastRevisionLabel
            items[index].lastRevisionLabel = revisionLabel
            items[index].subscribedAt = Date()
            if old != revisionLabel && items[index].notifyOnUpdate {
                NotificationCenter.default.post(name: .teamPackUpdated, object: packName)
            }
        } else {
            items.append(TeamPackSubscription(packName: packName, teamName: teamName, lastRevisionLabel: revisionLabel))
        }
        save(items)
    }

    func toggleNotifications(for id: UUID, enabled: Bool) {
        var items = loadAll()
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].notifyOnUpdate = enabled
        save(items)
    }
}

extension Notification.Name {
    static let teamPackUpdated = Notification.Name("ChordyxTeamPackUpdated")
}

// MARK: - Stage layout presets

@MainActor
final class StageLayoutStore {
    static let shared = StageLayoutStore()

    private var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("stage_layout_presets.json")
    }

    private init() {}

    func loadAll() -> [StageLayoutPreset] {
        guard let data = try? Data(contentsOf: fileURL),
              let items = try? JSONDecoder().decode([StageLayoutPreset].self, from: data) else {
            return StageLayoutPreset.defaults
        }
        return items.isEmpty ? StageLayoutPreset.defaults : items
    }

    func save(_ items: [StageLayoutPreset]) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

// MARK: - Team digest history

@MainActor
final class TeamDigestStore {
    static let shared = TeamDigestStore()

    private var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("team_digests.json")
    }

    private init() {}

    func loadAll() -> [TeamDigestEntry] {
        guard let data = try? Data(contentsOf: fileURL),
              let items = try? JSONDecoder().decode([TeamDigestEntry].self, from: data) else {
            return []
        }
        return items.sorted { $0.weekStarting > $1.weekStarting }
    }

    func record(_ entry: TeamDigestEntry) {
        var items = loadAll()
        items.removeAll { Calendar.current.isDate($0.weekStarting, inSameDayAs: entry.weekStarting) }
        items.insert(entry, at: 0)
        save(items)
    }

    private func save(_ items: [TeamDigestEntry]) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    func latest() -> TeamDigestEntry? {
        loadAll().first
    }
}

// MARK: - Arrangement variants (on progression)

enum ArrangementVariantStore {
    static func variants(for progression: SavedProgression) -> [ArrangementVariant] {
        progression.arrangementVariants
    }

    static func apply(_ variant: ArrangementVariant, to progression: inout SavedProgression) {
        progression.key = variant.key
        progression.notation = variant.notation
        progression.chords = variant.chords
        progression.sections = variant.sections
        progression.rehearsalNotes = variant.rehearsalNotes
    }

    static func createVariant(named name: String, from progression: SavedProgression) -> ArrangementVariant {
        ArrangementVariant(
            name: name,
            key: progression.key,
            notation: progression.notation,
            chords: progression.chords,
            sections: progression.sections,
            rehearsalNotes: progression.rehearsalNotes
        )
    }
}
