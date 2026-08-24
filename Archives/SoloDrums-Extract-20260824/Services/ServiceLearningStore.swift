//
//  ServiceLearningStore.swift
//  Chordyx
//

#if os(macOS) || os(iOS)
import Foundation

@MainActor
final class ServiceLearningStore {
    static let shared = ServiceLearningStore()

    private static let maxRecords = 150
    private static let fileName = "service_learning_library.json"

    private var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Self.fileName)
    }

    private init() {}

    func loadAll() -> [ServiceLearningRecord] {
        guard let data = try? Data(contentsOf: fileURL),
              let list = try? JSONDecoder().decode([ServiceLearningRecord].self, from: data) else {
            return []
        }
        return list.sorted { $0.recordedAt > $1.recordedAt }
    }

    func save(_ record: ServiceLearningRecord) {
        var list = loadAll()
        list.insert(record, at: 0)
        if list.count > Self.maxRecords {
            list = Array(list.prefix(Self.maxRecords))
        }
        persist(list)
    }

    func update(_ record: ServiceLearningRecord) {
        var list = loadAll()
        if let index = list.firstIndex(where: { $0.id == record.id }) {
            list[index] = record
            persist(list)
        }
    }

    func delete(id: UUID) {
        var list = loadAll()
        list.removeAll { $0.id == id }
        persist(list)
    }

    func records(for profileName: String) -> [ServiceLearningRecord] {
        loadAll().filter { $0.profileName == profileName }
    }

    private func persist(_ list: [ServiceLearningRecord]) {
        if let data = try? JSONEncoder().encode(list) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
#endif
