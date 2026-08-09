//
//  ServiceTemplateStore.swift
//  Chordyx
//

import Foundation

@MainActor
final class ServiceTemplateStore {
    static let shared = ServiceTemplateStore()

    private var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("service_templates.json")
    }

    private init() {}

    func load() -> [ServiceTemplate] {
        guard let data = try? Data(contentsOf: fileURL),
              let items = try? JSONDecoder().decode([ServiceTemplate].self, from: data) else {
            return []
        }
        return items
    }

    func ensureLoaded() -> [ServiceTemplate] {
        let existing = load()
        if existing.isEmpty {
            seedDefaults()
            return load()
        }
        return existing
    }

    func save(_ template: ServiceTemplate) {
        var items = load()
        if let index = items.firstIndex(where: { $0.id == template.id }) {
            items[index] = template
        } else {
            items.insert(template, at: 0)
        }
        persist(items)
    }

    func delete(_ id: UUID) {
        persist(load().filter { $0.id != id })
    }

    private func persist(_ items: [ServiceTemplate]) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private func seedDefaults() {
        let sunday = ServiceTemplate(
            name: String(localized: "Sunday Service"),
            performanceMode: .live,
            countInBars: 1,
            defaultTempoBPM: 72,
            timelineBlocks: [
                ServiceTimelineBlock(title: String(localized: "Worship"), offsetMinutes: 0, estimatedMinutes: 25),
                ServiceTimelineBlock(title: String(localized: "Message"), offsetMinutes: 25, estimatedMinutes: 35),
                ServiceTimelineBlock(title: String(localized: "Closing"), offsetMinutes: 60, estimatedMinutes: 10),
            ]
        )
        let rehearsal = ServiceTemplate(
            name: String(localized: "Midweek Rehearsal"),
            performanceMode: .rehearsal,
            countInBars: 2,
            defaultTempoBPM: 90
        )
        persist([sunday, rehearsal])
    }
}
