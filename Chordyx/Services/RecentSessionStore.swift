//
//  RecentSessionStore.swift
//  Chordyx
//

import Foundation

struct RecentSessionRecord: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var sessionName: String
    var hostDeviceName: String
    var sessionToken: UUID
    var keyRaw: String
    var lastJoinedAt: Date
    var lastActiveChordID: UUID?
    var progressionName: String?

    init(
        id: UUID = UUID(),
        sessionName: String,
        hostDeviceName: String,
        sessionToken: UUID,
        key: MusicalKey,
        lastJoinedAt: Date = Date(),
        lastActiveChordID: UUID? = nil,
        progressionName: String? = nil
    ) {
        self.id = id
        self.sessionName = sessionName
        self.hostDeviceName = hostDeviceName
        self.sessionToken = sessionToken
        self.keyRaw = key.rawValue
        self.lastJoinedAt = lastJoinedAt
        self.lastActiveChordID = lastActiveChordID
        self.progressionName = progressionName
    }

    var key: MusicalKey {
        MusicalKey(rawValue: keyRaw) ?? .C
    }
}

enum RecentSessionStore {
    private static let storageKey = "recentChordyxSessions"
    private static let maxRecords = 8

    static var records: [RecentSessionRecord] {
        get {
            guard let data = UserDefaults.standard.data(forKey: storageKey),
                  let decoded = try? JSONDecoder().decode([RecentSessionRecord].self, from: data) else {
                return []
            }
            return decoded
        }
        set {
            let trimmed = Array(newValue.prefix(maxRecords))
            if let data = try? JSONEncoder().encode(trimmed) {
                UserDefaults.standard.set(data, forKey: storageKey)
            }
        }
    }

    static func rememberJoin(
        sessionName: String,
        hostDeviceName: String,
        sessionToken: UUID,
        key: MusicalKey,
        progressionName: String? = nil
    ) {
        var list = records.filter {
            !($0.sessionName == sessionName && $0.hostDeviceName == hostDeviceName)
        }
        list.insert(
            RecentSessionRecord(
                sessionName: sessionName,
                hostDeviceName: hostDeviceName,
                sessionToken: sessionToken,
                key: key,
                progressionName: progressionName
            ),
            at: 0
        )
        records = list
    }

    static func updateProgress(
        sessionToken: UUID,
        activeChordID: UUID?,
        progressionName: String?
    ) {
        var list = records
        guard let index = list.firstIndex(where: { $0.sessionToken == sessionToken }) else { return }
        list[index].lastActiveChordID = activeChordID
        if let progressionName { list[index].progressionName = progressionName }
        list[index].lastJoinedAt = Date()
        records = list
    }

    static func delete(_ record: RecentSessionRecord) {
        records = records.filter { $0.id != record.id }
    }

    static func deleteAll() {
        records = []
    }
}
