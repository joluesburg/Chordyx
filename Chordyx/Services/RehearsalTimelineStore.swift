//
//  RehearsalTimelineStore.swift
//  Chordyx
//

import Foundation

@MainActor
final class RehearsalTimelineStore {
    static let shared = RehearsalTimelineStore()

    private(set) var isRecording = false
    private(set) var isReplaying = false

    private var startedAt: Date?
    private var initialPayload: SessionSyncPayload?
    private var events: [RehearsalEvent] = []
    private var replayTask: Task<Void, Never>?

    private var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("rehearsal_timeline.json")
    }

    private init() {}

    func loadAll() -> [RehearsalRecording] {
        guard let data = try? Data(contentsOf: fileURL),
              let items = try? JSONDecoder().decode([RehearsalRecording].self, from: data) else {
            return []
        }
        return items.sorted { $0.recordedAt > $1.recordedAt }
    }

    func save(_ recording: RehearsalRecording) {
        var items = loadAll()
        if let index = items.firstIndex(where: { $0.id == recording.id }) {
            items[index] = recording
        } else {
            items.insert(recording, at: 0)
        }
        persist(items)
    }

    func delete(_ id: UUID) {
        persist(loadAll().filter { $0.id != id })
    }

    private func persist(_ items: [RehearsalRecording]) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    func startRecording(sessionName: String, payload: SessionSyncPayload) {
        isRecording = true
        startedAt = Date()
        initialPayload = payload
        events = []
        _ = sessionName
    }

    func stopRecording(name: String) -> RehearsalRecording? {
        guard isRecording, let startedAt else {
            isRecording = false
            return nil
        }
        let recording = RehearsalRecording(
            name: name,
            sessionName: name,
            recordedAt: startedAt,
            duration: Date().timeIntervalSince(startedAt),
            events: events,
            initialPayload: initialPayload
        )
        isRecording = false
        self.startedAt = nil
        initialPayload = nil
        events = []
        save(recording)
        return recording
    }

    func log(
        _ kind: RehearsalEventKind,
        chordID: UUID? = nil,
        tempoBPM: Double? = nil,
        cueText: String? = nil,
        sectionID: UUID? = nil,
        songTitle: String? = nil
    ) {
        guard isRecording, let startedAt else { return }
        events.append(
            RehearsalEvent(
                kind: kind,
                timestamp: Date().timeIntervalSince(startedAt),
                chordID: chordID,
                tempoBPM: tempoBPM,
                cueText: cueText,
                sectionID: sectionID,
                songTitle: songTitle
            )
        )
    }

    func inProgressRecording(sessionName: String) -> RehearsalRecording? {
        guard isRecording, let startedAt else { return nil }
        return RehearsalRecording(
            name: sessionName,
            sessionName: sessionName,
            recordedAt: startedAt,
            duration: Date().timeIntervalSince(startedAt),
            events: events,
            initialPayload: initialPayload
        )
    }

    func replay(_ recording: RehearsalRecording, handler: @escaping (RehearsalEvent) -> Void) {
        stopReplay()
        isReplaying = true
        let sorted = recording.events.sorted { $0.timestamp < $1.timestamp }
        replayTask = Task { @MainActor in
            let start = Date()
            for event in sorted {
                if Task.isCancelled { break }
                let delay = event.timestamp - Date().timeIntervalSince(start)
                if delay > 0 {
                    try? await Task.sleep(for: .seconds(delay))
                }
                if Task.isCancelled { break }
                handler(event)
            }
            self.isReplaying = false
            self.replayTask = nil
        }
    }

    func stopReplay() {
        replayTask?.cancel()
        replayTask = nil
        isReplaying = false
    }
}
