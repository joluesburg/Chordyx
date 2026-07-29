//
//  ExtendedFeatureEngine.swift
//  Chordyx
//

import Foundation

// MARK: - Setlist intelligence

enum SetlistIntelligenceEngine {
    static func smartChecklist(
        setlist: Setlist?,
        store: ProgressionStore,
        payload: SessionSyncPayload,
        connectedPeerCount: Int
    ) -> [SmartChecklistItem] {
        var items: [SmartChecklistItem] = []

        if let setlist {
            let songs = store.progressions(for: setlist)
            let keys = Set(songs.map(\.key))
            if keys.count > 1 {
                items.append(SmartChecklistItem(
                    id: "keys",
                    title: String(localized: "Multiple keys in setlist"),
                    detail: keys.map(\.displayName).sorted().joined(separator: ", "),
                    icon: "music.quarternote.3",
                    isAutoSatisfied: false,
                    severity: .warning
                ))
            }

            let missingPDF = songs.filter { store.pdfURL(for: $0) == nil }.count
            if missingPDF > 0 {
                items.append(SmartChecklistItem(
                    id: "pdf",
                    title: String(localized: "Missing PDF charts"),
                    detail: String(format: String(localized: "%lld song(s) without PDF"), missingPDF),
                    icon: "doc.richtext",
                    isAutoSatisfied: false,
                    severity: .info
                ))
            }

            let missingSections = songs.filter { $0.sections.isEmpty }.count
            if missingSections > 0 {
                items.append(SmartChecklistItem(
                    id: "sections",
                    title: String(localized: "Songs without sections"),
                    detail: String(format: String(localized: "%lld song(s) need section review"), missingSections),
                    icon: "square.grid.2x2",
                    isAutoSatisfied: false,
                    severity: .info
                ))
            }
        }

        if !payload.isRemoteBackupEnabled {
            items.append(SmartChecklistItem(
                id: "internet",
                title: String(localized: "Internet backup off"),
                detail: String(localized: "Guests on cellular may not connect"),
                icon: "icloud.slash",
                isAutoSatisfied: false,
                severity: .warning
            ))
        }

        if connectedPeerCount == 0 {
            items.append(SmartChecklistItem(
                id: "band",
                title: String(localized: "No musicians connected"),
                detail: String(localized: "Share join code before service"),
                icon: "person.2",
                isAutoSatisfied: false,
                severity: .info
            ))
        }

        return items
    }

    static func capoSuggestion(chartKey: MusicalKey, vocalKey: MusicalKey) -> CapoSuggestion? {
        guard chartKey != vocalKey else { return nil }
        let semitones = Transposer.semitones(from: chartKey, to: vocalKey)
        let normalized = ((semitones % 12) + 12) % 12
        if normalized <= 6 {
            return CapoSuggestion(
                chartKey: chartKey,
                vocalKey: vocalKey,
                capoFret: normalized,
                transposeSemitones: 0
            )
        }
        let down = normalized - 12
        return CapoSuggestion(
            chartKey: chartKey,
            vocalKey: vocalKey,
            capoFret: 0,
            transposeSemitones: down
        )
    }
}

// MARK: - Chart diff

enum ChartDiffEngine {
    static func compare(_ left: SavedProgression, _ right: SavedProgression) -> ChartDiffResult {
        let leftChords = left.chords.sorted { $0.order < $1.order }.map(\.symbolName)
        let rightChords = right.chords.sorted { $0.order < $1.order }.map(\.symbolName)
        let maxCount = max(leftChords.count, rightChords.count)
        var lines: [ChartDiffLine] = []

        if maxCount == 0 {
            return ChartDiffResult(lines: [])
        }

        for index in 0..<maxCount {
            let l = index < leftChords.count ? leftChords[index] : nil
            let r = index < rightChords.count ? rightChords[index] : nil
            switch (l, r) {
            case let (.some(lv), .some(rv)) where lv == rv:
                lines.append(ChartDiffLine(sectionName: nil, left: lv, right: rv, kind: .same))
            case let (.some(lv), .some(rv)):
                lines.append(ChartDiffLine(sectionName: nil, left: lv, right: rv, kind: .changed))
            case let (.some(lv), .none):
                lines.append(ChartDiffLine(sectionName: nil, left: lv, right: "—", kind: .removed))
            case let (.none, .some(rv)):
                lines.append(ChartDiffLine(sectionName: nil, left: "—", right: rv, kind: .added))
            default:
                break
            }
        }

        return ChartDiffResult(lines: lines)
    }
}

// MARK: - Tempo drift

enum TempoDriftMonitor {
    static func driftBPM(expectedBeatEpoch: Double, actualBeatEpoch: Double, tempoBPM: Double) -> Double {
        guard tempoBPM > 0, expectedBeatEpoch > 0, actualBeatEpoch > 0 else { return 0 }
        let delta = actualBeatEpoch - expectedBeatEpoch
        guard abs(delta) > 0.001 else { return 0 }
        let beatDuration = 60.0 / tempoBPM
        let driftRatio = -delta / beatDuration
        return driftRatio * tempoBPM
    }
}

// MARK: - Planning Center stub

enum PlanningCenterImporter {
    /// Parses a minimal JSON export or returns a demo plan for pasted plan titles.
    static func importFromURL(_ url: URL) -> PlanningCenterImportDraft? {
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let title = json["title"] as? String ?? String(localized: "Imported Plan")
        let rawItems = json["items"] as? [[String: Any]] ?? []
        let items = rawItems.enumerated().map { index, item in
            PlanningCenterPlanItem(
                title: item["title"] as? String ?? String(localized: "Song"),
                sequence: item["sequence"] as? Int ?? index + 1,
                keyName: item["key"] as? String
            )
        }
        guard !items.isEmpty else { return nil }
        return PlanningCenterImportDraft(planTitle: title, items: items)
    }

    static func importFromPlainText(_ text: String) -> PlanningCenterImportDraft {
        let lines = text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let items = lines.enumerated().map { index, line in
            PlanningCenterPlanItem(title: line, sequence: index + 1, keyName: nil)
        }
        return PlanningCenterImportDraft(
            planTitle: String(localized: "Pasted Setlist"),
            items: items
        )
    }
}

// MARK: - Service stats store

@MainActor
final class ServiceStatsStore {
    static let shared = ServiceStatsStore()

    private var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("service_session_stats.json")
    }

    private var sessionStartedAt: Date?
    private var cueCount = 0
    private var transposeCount = 0
    private var sectionJumps = 0
    private var tempoSamples: [Double] = []

    private init() {}

    func beginSession() {
        sessionStartedAt = Date()
        cueCount = 0
        transposeCount = 0
        sectionJumps = 0
        tempoSamples = []
    }

    func recordCue() { cueCount += 1 }
    func recordTranspose() { transposeCount += 1 }
    func recordSectionJump() { sectionJumps += 1 }
    func recordTempo(_ bpm: Double) { tempoSamples.append(bpm) }

    func endSession(named name: String, songsPlayed: Int) -> ServiceSessionStats? {
        guard let started = sessionStartedAt else { return nil }
        let stats = ServiceSessionStats(
            sessionName: name,
            durationSeconds: Date().timeIntervalSince(started),
            songsPlayed: songsPlayed,
            cueCount: cueCount,
            transposeCount: transposeCount,
            sectionJumps: sectionJumps,
            averageTempoBPM: tempoSamples.isEmpty ? 0 : tempoSamples.reduce(0, +) / Double(tempoSamples.count)
        )
        sessionStartedAt = nil
        var list = loadAll()
        list.insert(stats, at: 0)
        if let data = try? JSONEncoder().encode(list) {
            try? data.write(to: fileURL, options: .atomic)
        }
        return stats
    }

    func loadAll() -> [ServiceSessionStats] {
        guard let data = try? Data(contentsOf: fileURL),
              let list = try? JSONDecoder().decode([ServiceSessionStats].self, from: data) else { return [] }
        return list
    }
}

// MARK: - Team library metadata

@MainActor
final class TeamLibraryStore {
    static let shared = TeamLibraryStore()

    private var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("team_library_revisions.json")
    }

    private init() {}

    func recordImport(packName: String, songCount: Int, revisionLabel: String) {
        var list = loadAll()
        let revision = TeamLibraryRevision(
            packName: packName,
            songCount: songCount,
            revisionLabel: revisionLabel
        )
        list.insert(revision, at: 0)
        if list.count > 30 { list = Array(list.prefix(30)) }
        if let data = try? JSONEncoder().encode(list) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    func loadAll() -> [TeamLibraryRevision] {
        guard let data = try? Data(contentsOf: fileURL),
              let list = try? JSONDecoder().decode([TeamLibraryRevision].self, from: data) else { return [] }
        return list
    }
}
