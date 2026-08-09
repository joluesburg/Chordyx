//
//  PracticeStatsStore.swift
//  Chordyx
//

import Foundation

@MainActor
final class PracticeStatsStore {
    static let shared = PracticeStatsStore()

    private var activeSessionStart: Date?
    private var activeSessionName = ""
    private var songsThisSession = 0
    private var holdCount = 0
    private var vampCount = 0

    private var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("practice_stats.json")
    }

    private init() {}

    var sessions: [PracticeSessionRecord] { load().sessions }

    func load() -> PracticeStatsSummary {
        guard let data = try? Data(contentsOf: fileURL),
              let summary = try? JSONDecoder().decode(PracticeStatsSummary.self, from: data) else {
            return PracticeStatsSummary(sessions: [])
        }
        return summary
    }

    private func persist(_ summary: PracticeStatsSummary) {
        guard let data = try? JSONEncoder().encode(summary) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    func beginSession(named name: String) {
        activeSessionStart = Date()
        activeSessionName = name
        songsThisSession = 0
        holdCount = 0
        vampCount = 0
    }

    func endSession() {
        guard let started = activeSessionStart else { return }
        var summary = load()
        summary.sessions.insert(
            PracticeSessionRecord(
                date: started,
                durationSeconds: Date().timeIntervalSince(started),
                songsPlayed: songsThisSession,
                sessionName: activeSessionName.isEmpty ? String(localized: "Practice") : activeSessionName,
                holdCueCount: holdCount,
                vampCueCount: vampCount
            ),
            at: 0
        )
        if summary.sessions.count > 200 {
            summary.sessions = Array(summary.sessions.prefix(200))
        }
        persist(summary)
        activeSessionStart = nil
        activeSessionName = ""
        songsThisSession = 0
        holdCount = 0
        vampCount = 0
    }

    func recordSongPlayed() {
        guard activeSessionStart != nil else { return }
        songsThisSession += 1
    }

    func recordCue(_ cueText: String) {
        guard activeSessionStart != nil else { return }
        let lowered = cueText.lowercased()
        if lowered.contains("hold") { holdCount += 1 }
        if lowered.contains("vamp") { vampCount += 1 }
    }
}
