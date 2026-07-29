//
//  AdvancedFeatureEngine.swift
//  Chordyx
//

import Foundation

// MARK: - Readiness engine

enum ReadinessEngine {
    static func evaluate(
        payload: SessionSyncPayload,
        connectedPeerCount: Int,
        unrehearsedSongCount: Int,
        checklistSatisfied: Int,
        checklistTotal: Int
    ) -> ReadinessReport {
        var items: [SmartChecklistItem] = []
        var score = 100

        let bandConnected = connectedPeerCount > 0 || payload.performanceMode == .acoustic
        items.append(SmartChecklistItem(
            id: "band",
            title: String(localized: "Band connected"),
            detail: bandConnected
                ? String(format: String(localized: "%lld musicians online"), connectedPeerCount)
                : String(localized: "No guests connected yet"),
            icon: "person.3.fill",
            isAutoSatisfied: bandConnected,
            severity: bandConnected ? .info : .warning
        ))
        if !bandConnected { score -= 20 }

        let laggingPeers = payload.peerPresence.values.filter(\.isLagging).count
        let syncOK = laggingPeers == 0
        items.append(SmartChecklistItem(
            id: "sync",
            title: String(localized: "Sync quality"),
            detail: syncOK
                ? String(localized: "All peers in sync")
                : String(format: String(localized: "%lld peer(s) lagging"), laggingPeers),
            icon: "antenna.radiowaves.left.and.right",
            isAutoSatisfied: syncOK,
            severity: syncOK ? .info : .warning
        ))
        if !syncOK { score -= 15 }

        if unrehearsedSongCount > 0 {
            items.append(SmartChecklistItem(
                id: "rehearsal",
                title: String(localized: "Unrehearsed songs"),
                detail: String(format: String(localized: "%lld songs not practiced this month"), unrehearsedSongCount),
                icon: "music.note.list",
                isAutoSatisfied: false,
                severity: .warning
            ))
            score -= min(25, unrehearsedSongCount * 8)
        } else {
            items.append(SmartChecklistItem(
                id: "rehearsal",
                title: String(localized: "Setlist rehearsed"),
                detail: String(localized: "All songs practiced recently"),
                icon: "checkmark.circle.fill",
                isAutoSatisfied: true,
                severity: .info
            ))
        }

        let checklistDone = checklistTotal == 0 || checklistSatisfied >= checklistTotal
        items.append(SmartChecklistItem(
            id: "checklist",
            title: String(localized: "Pre-service checklist"),
            detail: String(format: String(localized: "%lld of %lld complete"), checklistSatisfied, max(checklistTotal, 1)),
            icon: "checklist",
            isAutoSatisfied: checklistDone,
            severity: checklistDone ? .info : .warning
        ))
        if !checklistDone { score -= 10 }

        let tempoSet = payload.tempoBPM >= 40
        items.append(SmartChecklistItem(
            id: "tempo",
            title: String(localized: "Tempo configured"),
            detail: tempoSet
                ? String(format: String(localized: "%.0f BPM"), payload.tempoBPM)
                : String(localized: "Set metronome tempo"),
            icon: "metronome",
            isAutoSatisfied: tempoSet,
            severity: tempoSet ? .info : .warning
        ))
        if !tempoSet { score -= 10 }

        score = max(0, min(100, score))
        let level: ReadinessLevel = score >= 80 ? .ready : (score >= 55 ? .caution : .notReady)
        return ReadinessReport(score: score, level: level, items: items)
    }
}

// MARK: - Voicing hints

enum VoicingHintsEngine {
    static func hint(for role: GuestViewRole, chordSymbol: String, key: MusicalKey) -> String? {
        let root = chordSymbol.prefix(while: { $0.isLetter || $0 == "#" || $0 == "b" })
        let suffix = String(chordSymbol.dropFirst(root.count))
        switch role {
        case .guitar:
            if suffix.contains("m") && !suffix.contains("maj") {
                return String(format: String(localized: "Guitar: %@ minor shape · watch 3rd"), String(root))
            }
            if suffix.isEmpty || suffix == "maj" {
                return String(format: String(localized: "Guitar: open or barre %@"), String(root))
            }
            return String(format: String(localized: "Guitar: %@ voicing"), chordSymbol)
        case .bass:
            return String(format: String(localized: "Bass: root on %@"), String(root))
        case .keys:
            if suffix.contains("7") {
                return String(format: String(localized: "Keys: dominant color on %@"), String(root))
            }
            return String(format: String(localized: "Keys: pad in 3rd · %@"), chordSymbol)
        case .vocal:
            return String(localized: "Vocal: hold melody · watch chord change")
        case .drums:
            return String(localized: "Drums: keep groove · watch section")
        case .auto:
            return nil
        }
    }

    static func hints(for chordSymbol: String, key: MusicalKey) -> [VoicingHint] {
        GuestViewRole.allCases.compactMap { role in
            guard role != .auto, let hint = hint(for: role, chordSymbol: chordSymbol, key: key) else { return nil }
            return VoicingHint(role: role, chordSymbol: chordSymbol, hint: hint)
        }
    }
}

// MARK: - Vocal range assistant

enum VocalRangeAssistant {
    static func suggest(chartKey: MusicalKey, vocalTarget: MusicalKey?) -> VocalRangeSuggestion? {
        let target = vocalTarget ?? chartKey
        let chartIndex = chartKey.pitchClass
        let targetIndex = target.pitchClass
        let diff = targetIndex - chartIndex

        if diff > 3 {
            let capo = min(5, diff)
            let suggested = MusicalKey.allCases.first { $0.pitchClass == (chartIndex + capo) % 12 } ?? chartKey
            return VocalRangeSuggestion(
                currentKey: chartKey,
                suggestedKey: suggested,
                capoFret: capo,
                reason: String(localized: "Chart may be low for congregational singing in this key"),
                isHighForCongregation: false
            )
        }

        if diff < -2 {
            let transpose = abs(diff)
            let suggested = MusicalKey.allCases.first { $0.pitchClass == (chartIndex + transpose) % 12 } ?? chartKey
            return VocalRangeSuggestion(
                currentKey: chartKey,
                suggestedKey: suggested,
                capoFret: 0,
                reason: String(localized: "Key may be high for most vocalists — consider transposing down"),
                isHighForCongregation: true
            )
        }

        return nil
    }
}

// MARK: - Import quality coach

enum ImportQualityCoach {
    static func tips(for quality: SongImportQuality, draft: SongImportDraft) -> [ImportQualityCoachTip] {
        var tips: [ImportQualityCoachTip] = []

        if quality.checks.first(where: { $0.id == "sections" })?.passed != true {
            tips.append(ImportQualityCoachTip(
                id: "missing-bridge",
                title: String(localized: "Add song sections"),
                detail: String(localized: "Label verse, chorus, and bridge so the band can jump during rehearsal."),
                actionLabel: String(localized: "Review structure")
            ))
        }

        let hasBridge = draft.sections.contains { $0.kind == .bridge }
        let hasChorus = draft.sections.contains { $0.kind == .chorus }
        if hasChorus && !hasBridge && draft.sections.count >= 4 {
            tips.append(ImportQualityCoachTip(
                id: "maybe-bridge",
                title: String(localized: "Missing bridge?"),
                detail: String(localized: "This song has multiple sections but no bridge marker."),
                actionLabel: nil
            ))
        }

        if let keyCheck = quality.checks.first(where: { $0.id == "clean" }), !keyCheck.passed {
            tips.append(ImportQualityCoachTip(
                id: "chart-cleanup",
                title: String(localized: "Clean up chord markers"),
                detail: String(localized: "Some chords are still embedded in lyric lines — separate them for a cleaner chart."),
                actionLabel: String(localized: "Review lyrics")
            ))
        }

        let duplicateChoruses = draft.sections.filter { $0.kind == .chorus }.count
        if duplicateChoruses > 2 {
            tips.append(ImportQualityCoachTip(
                id: "dup-chorus",
                title: String(localized: "Duplicate chorus markers"),
                detail: String(format: String(localized: "%lld chorus sections detected — merge if they're repeats."), duplicateChoruses),
                actionLabel: nil
            ))
        }

        if quality.readiness == .incomplete {
            tips.append(ImportQualityCoachTip(
                id: "incomplete",
                title: String(localized: "Chart needs more work"),
                detail: String(localized: "Add chords and lyrics before sharing with the band."),
                actionLabel: String(localized: "Continue editing")
            ))
        }

        return tips
    }
}

// MARK: - ChurchApps / Planning Center API

enum ChurchAppsSync {
    static let planningCenterBaseURL = "https://api.planningcenteronline.com/services/v2"
    static let churchAppsBaseURL = "https://api.churchapps.org/plans"

    static func parseAPIResponse(_ data: Data) -> PlanningCenterImportDraft? {
        if let draft = decodePlanningCenter(data) { return draft }
        return decodeChurchApps(data)
    }

    private static func decodePlanningCenter(_ data: Data) -> PlanningCenterImportDraft? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let title = json["title"] as? String ?? String(localized: "Planning Center Plan")
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

    private static func decodeChurchApps(_ data: Data) -> PlanningCenterImportDraft? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let title = json["title"] as? String ?? String(localized: "ChurchApps Plan")
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

    static func fetchPlan(from urlString: String) async -> PlanningCenterImportDraft? {
        guard let url = URL(string: urlString) else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return parseAPIResponse(data)
        } catch {
            return nil
        }
    }
}

// MARK: - Team digest builder

enum TeamDigestBuilder {
    static func buildWeekDigest(
        practiceStats: PracticeStatsSummary,
        serviceStats: [ServiceSessionStats]
    ) -> TeamDigestEntry {
        let calendar = Calendar.current
        let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())) ?? Date()

        let recentPractice = practiceStats.sessions.filter {
            calendar.isDate($0.date, equalTo: weekStart, toGranularity: .weekOfYear)
        }
        let recentServices = serviceStats.filter {
            calendar.isDate($0.endedAt, equalTo: weekStart, toGranularity: .weekOfYear)
        }

        let practiceMinutes = recentPractice.reduce(0) { $0 + $1.durationSeconds } / 60
        let serviceMinutes = recentServices.reduce(0) { $0 + $1.durationSeconds } / 60

        return TeamDigestEntry(
            weekStarting: weekStart,
            totalMinutes: practiceMinutes + serviceMinutes,
            sessionsHosted: recentServices.count + recentPractice.count,
            songsPlayed: recentPractice.reduce(0) { $0 + $1.songsPlayed }
                + recentServices.reduce(0) { $0 + $1.songsPlayed },
            topCues: [],
            topHosts: recentServices.map(\.sessionName).prefix(3).map { $0 }
        )
    }
}

// MARK: - Tempo ramp

enum TempoRampEngine {
    static func nextBPM(current: Double, target: Double, barsRemaining: Int, beatsPerBar: Int) -> (bpm: Double, barsLeft: Int) {
        guard barsRemaining > 0, abs(target - current) > 0.5 else {
            return (target, 0)
        }
        let step = (target - current) / Double(barsRemaining)
        let newBPM = current + step
        return (newBPM, barsRemaining - 1)
    }
}

// MARK: - CarPlay rehearsal builder

enum CarPlayRehearsalBuilder {
    static func items(from progressions: [SavedProgression]) -> [CarPlayRehearsalItem] {
        progressions.map { progression in
            CarPlayRehearsalItem(
                id: progression.id,
                title: progression.name,
                chordSummary: progression.summary,
                tempoBPM: progression.tempoBPM
            )
        }
    }
}
