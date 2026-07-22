//
//  ProgressionStore.swift
//  Chordyx
//

import Foundation
import Observation
import UniformTypeIdentifiers

extension UTType {
    static let chordyxProgression = UTType(exportedAs: "com.chordyx.progression", conformingTo: .json)
    static let chordyxPack = UTType(exportedAs: "com.chordyx.pack", conformingTo: .json)
}

@Observable
@MainActor
final class ProgressionStore {
    private(set) var progressions: [SavedProgression] = []
    private(set) var setlists: [Setlist] = []

    var iCloudBackupEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Self.iCloudKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.iCloudKey)
            if newValue { syncToCloud() }
        }
    }

    private static let iCloudKey = "iCloudBackupEnabled"
    private static let iCloudContainerID = "iCloud.Espinosa.Chordyx"
    private let fileURL: URL
    private let setlistFileURL: URL
    private let pdfDirectory: URL
    private var cloudURL: URL? {
        FileManager.default.url(forUbiquityContainerIdentifier: Self.iCloudContainerID)?
            .appendingPathComponent("Documents/saved_progressions.json")
    }
    private var cloudSetlistURL: URL? {
        FileManager.default.url(forUbiquityContainerIdentifier: Self.iCloudContainerID)?
            .appendingPathComponent("Documents/setlists.json")
    }

    init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        fileURL = documents.appendingPathComponent("saved_progressions.json")
        setlistFileURL = documents.appendingPathComponent("setlists.json")
        pdfDirectory = documents.appendingPathComponent("PDFCharts", isDirectory: true)
        try? FileManager.default.createDirectory(at: pdfDirectory, withIntermediateDirectories: true)
        // Local first — ubiquity container lookup can stall the Mac main thread at launch.
        load()
        loadSetlists()
        installStarterPackIfNeeded()
        Task(priority: .utility) { [weak self] in
            await self?.importFromCloudInBackground()
        }
    }

    var sortedProgressions: [SavedProgression] {
        progressions.sorted { $0.savedAt > $1.savedAt }
    }

    var sortedSetlists: [Setlist] {
        setlists.sorted { $0.savedAt > $1.savedAt }
    }

    func progression(with id: UUID) -> SavedProgression? {
        progressions.first { $0.id == id }
    }

    func progressions(for setlist: Setlist) -> [SavedProgression] {
        setlist.progressionIDs.compactMap { progression(with: $0) }
    }

    func findDuplicate(named name: String, excluding id: UUID? = nil) -> SavedProgression? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return nil }
        return progressions.first {
            $0.id != id && $0.name.lowercased() == trimmed
        }
    }

    func nameExists(_ name: String, excluding id: UUID? = nil) -> Bool {
        findDuplicate(named: name, excluding: id) != nil
    }

    func uniqueImportName(basedOn name: String) -> String {
        uniqueName(basedOn: name)
    }

    @discardableResult
    func replace(_ progression: SavedProgression, keepingID existing: SavedProgression) -> SavedProgression {
        var updated = progression
        updated = SavedProgression(
            id: existing.id,
            name: progression.name,
            key: progression.key,
            notation: progression.notation,
            chords: progression.chords,
            tempoBPM: progression.tempoBPM,
            beatsPerBar: progression.beatsPerBar,
            beatUnit: progression.beatUnit,
            savedAt: Date(),
            sections: progression.sections,
            lyrics: progression.lyrics,
            loopStartChordID: progression.loopStartChordID,
            loopEndChordID: progression.loopEndChordID,
            isLoopEnabled: progression.isLoopEnabled,
            lyricsLines: progression.lyricsLines,
            pdfFileName: progression.pdfFileName ?? existing.pdfFileName
        )
        return save(updated)
    }

    func setlistNameExists(_ name: String, excluding id: UUID? = nil) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return setlists.contains {
            $0.id != id && $0.name.lowercased() == trimmed
        }
    }

    @discardableResult
    func save(_ progression: SavedProgression) -> SavedProgression {
        let cleaned = SongImportParser.sanitizeProgression(progression)
        if let index = progressions.firstIndex(where: { $0.id == cleaned.id }) {
            progressions[index] = cleaned
        } else {
            progressions.append(cleaned)
        }
        persist()
        syncToCloud()
        return cleaned
    }

    @discardableResult
    func saveSetlist(_ setlist: Setlist) -> Setlist {
        if let index = setlists.firstIndex(where: { $0.id == setlist.id }) {
            setlists[index] = setlist
        } else {
            setlists.append(setlist)
        }
        persistSetlists()
        syncSetlistsToCloud()
        return setlist
    }

    func rename(_ progression: SavedProgression, to newName: String) {
        guard let index = progressions.firstIndex(where: { $0.id == progression.id }) else { return }
        progressions[index].name = newName
        persist()
        syncToCloud()
    }

    @discardableResult
    func duplicate(_ progression: SavedProgression) -> SavedProgression {
        let copy = SavedProgression(
            name: uniqueName(basedOn: progression.name),
            key: progression.key,
            notation: progression.notation,
            chords: progression.chords,
            tempoBPM: progression.tempoBPM,
            beatsPerBar: progression.beatsPerBar,
            beatUnit: progression.beatUnit,
            sections: progression.sections,
            lyrics: progression.lyrics,
            loopStartChordID: progression.loopStartChordID,
            loopEndChordID: progression.loopEndChordID,
            isLoopEnabled: progression.isLoopEnabled,
            lyricsLines: progression.lyricsLines,
            pdfFileName: progression.pdfFileName
        )
        progressions.append(copy)
        persist()
        syncToCloud()
        return copy
    }

    func delete(_ progression: SavedProgression) {
        progressions.removeAll { $0.id == progression.id }
        setlists = setlists.map { list in
            var updated = list
            updated.progressionIDs.removeAll { $0 == progression.id }
            return updated
        }
        persist()
        persistSetlists()
        syncToCloud()
        syncSetlistsToCloud()
    }

    func deleteSetlist(_ setlist: Setlist) {
        setlists.removeAll { $0.id == setlist.id }
        persistSetlists()
        syncSetlistsToCloud()
    }

    func delete(at offsets: IndexSet) {
        let sorted = sortedProgressions
        let idsToRemove = offsets.map { sorted[$0].id }
        progressions.removeAll { idsToRemove.contains($0.id) }
        persist()
        syncToCloud()
    }

    func exportData(for progression: SavedProgression) throws -> Data {
        try JSONEncoder().encode(ChordyxExportFile(progression: progression))
    }

    func importProgression(from data: Data) throws -> SavedProgression {
        let file = try JSONDecoder().decode(ChordyxExportFile.self, from: data)
        let imported = SavedProgression(
            name: uniqueName(basedOn: file.progression.name),
            key: file.progression.key,
            notation: file.progression.notation,
            chords: file.progression.chords,
            tempoBPM: file.progression.tempoBPM,
            beatsPerBar: file.progression.beatsPerBar,
            beatUnit: file.progression.beatUnit,
            sections: file.progression.sections,
            lyrics: file.progression.lyrics,
            loopStartChordID: file.progression.loopStartChordID,
            loopEndChordID: file.progression.loopEndChordID,
            isLoopEnabled: file.progression.isLoopEnabled,
            lyricsLines: file.progression.lyricsLines,
            pdfFileName: file.progression.pdfFileName
        )
        return save(imported)
    }

    func importPack(from data: Data) throws -> Setlist? {
        let file = try JSONDecoder().decode(ChordyxSetlistExportFile.self, from: data)
        var idMap: [UUID: UUID] = [:]
        for progression in file.pack.progressions {
            let newID = UUID()
            idMap[progression.id] = newID
            let imported = SavedProgression(
                id: newID,
                name: uniqueName(basedOn: progression.name),
                key: progression.key,
                notation: progression.notation,
                chords: progression.chords,
                tempoBPM: progression.tempoBPM,
                beatsPerBar: progression.beatsPerBar,
                beatUnit: progression.beatUnit,
                sections: progression.sections,
                lyrics: progression.lyrics,
                loopStartChordID: progression.loopStartChordID,
                loopEndChordID: progression.loopEndChordID,
                isLoopEnabled: progression.isLoopEnabled,
                lyricsLines: progression.lyricsLines,
                pdfFileName: progression.pdfFileName
            )
            save(imported)
        }
        if var setlist = file.pack.setlist {
            setlist = Setlist(
                id: UUID(),
                name: setlistNameExists(setlist.name) ? uniqueSetlistName(basedOn: setlist.name) : setlist.name,
                progressionIDs: setlist.progressionIDs.compactMap { idMap[$0] },
                savedAt: Date()
            )
            saveSetlist(setlist)
            return setlist
        }
        return nil
    }

    func exportPack(setlist: Setlist) throws -> Data {
        let songs = progressions(for: setlist)
        let pack = ChordyxSetlistPack(name: setlist.name, progressions: songs, setlist: setlist)
        return try JSONEncoder().encode(ChordyxSetlistExportFile(pack: pack))
    }

    func pdfURL(for progression: SavedProgression) -> URL? {
        guard let name = progression.pdfFileName else { return nil }
        let url = pdfDirectory.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    @discardableResult
    func attachPDF(from sourceURL: URL, to progression: SavedProgression) throws -> SavedProgression {
        let fileName = "\(progression.id.uuidString).pdf"
        let dest = pdfDirectory.appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.copyItem(at: sourceURL, to: dest)
        var updated = progression
        updated.pdfFileName = fileName
        return save(updated)
    }

    func parseOpenSongText(_ text: String, name: String, key: MusicalKey = .C) -> SavedProgression {
        var chords: [ChordEntry] = []
        var lyricsLines: [LyricsLine] = []
        var order = 0
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            if line.hasPrefix("*") || line.hasPrefix("[") && line.contains("]") {
                continue
            }
            let parts = line.components(separatedBy: " ").filter { !$0.isEmpty }
            var lyricWords: [String] = []
            for part in parts {
                if part.hasPrefix("[") && part.hasSuffix("]") {
                    let symbol = String(part.dropFirst().dropLast())
                    let entry = ChordEntry(
                        symbolName: symbol,
                        latinName: ChordCatalog.latinName(forSymbol: symbol),
                        order: order
                    )
                    chords.append(entry)
                    lyricsLines.append(LyricsLine(text: "", chordSymbol: symbol))
                    order += 1
                } else {
                    lyricWords.append(part)
                }
            }
            if !lyricWords.isEmpty, var last = lyricsLines.popLast() {
                last.text = lyricWords.joined(separator: " ")
                lyricsLines.append(last)
            }
        }
        return SavedProgression(
            name: name,
            key: key,
            notation: .symbol,
            chords: chords,
            lyrics: lyricsLines.map(\.text).joined(separator: "\n"),
            lyricsLines: lyricsLines
        )
    }

    private func uniqueSetlistName(basedOn name: String) -> String {
        var candidate = L10n.duplicateName(basedOn: name)
        var counter = 2
        while setlistNameExists(candidate) {
            candidate = L10n.duplicateName(basedOn: name, counter: counter)
            counter += 1
        }
        return candidate
    }

    private func installStarterPackIfNeeded() {
        let key = "installedStarterWorshipPack"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        let chords = [
            ChordEntry(symbolName: "G", latinName: "Sol", order: 0, durationBeats: 4),
            ChordEntry(symbolName: "C", latinName: "Do", order: 1, durationBeats: 4),
            ChordEntry(symbolName: "G", latinName: "Sol", order: 2, durationBeats: 4),
            ChordEntry(symbolName: "D", latinName: "Re", order: 3, durationBeats: 4),
            ChordEntry(symbolName: "G", latinName: "Sol", order: 4, durationBeats: 4)
        ]
        let saved = save(SavedProgression(
            name: "Amazing Grace",
            key: .G,
            notation: .symbol,
            chords: chords,
            tempoBPM: 72,
            sections: [SectionMarker(name: "Verse", startChordID: chords[0].id, kind: .verse)],
            lyrics: "Amazing grace how sweet the sound",
            lyricsLines: [LyricsLine(text: "Amazing grace how sweet the sound", chordSymbol: "G")]
        ))
        saveSetlist(Setlist(name: "Worship Starter", progressionIDs: [saved.id]))
        UserDefaults.standard.set(true, forKey: key)
    }

    private func uniqueName(basedOn name: String) -> String {
        var candidate = L10n.duplicateName(basedOn: name)
        var counter = 2
        while nameExists(candidate) {
            candidate = L10n.duplicateName(basedOn: name, counter: counter)
            counter += 1
        }
        return candidate
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        if let decoded = try? JSONDecoder().decode([SavedProgression].self, from: data) {
            let cleaned = decoded.map { SongImportParser.sanitizeProgression($0) }
            progressions = cleaned
            if cleaned != decoded {
                persist()
            }
        }
    }

    private func loadSetlists() {
        guard let data = try? Data(contentsOf: setlistFileURL) else { return }
        if let decoded = try? JSONDecoder().decode([Setlist].self, from: data) {
            setlists = decoded
        }
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(progressions)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            #if DEBUG
            print("Failed to persist progressions: \(error)")
            #endif
        }
    }

    private func persistSetlists() {
        do {
            let data = try JSONEncoder().encode(setlists)
            try data.write(to: setlistFileURL, options: [.atomic])
        } catch {
            #if DEBUG
            print("Failed to persist setlists: \(error)")
            #endif
        }
    }

    private func loadFromCloudIfNeeded() {
        guard iCloudBackupEnabled else { return }
        if let cloudURL, FileManager.default.fileExists(atPath: cloudURL.path),
           let data = try? Data(contentsOf: cloudURL) {
            try? data.write(to: fileURL, options: [.atomic])
        }
        if let cloudSetlistURL, FileManager.default.fileExists(atPath: cloudSetlistURL.path),
           let data = try? Data(contentsOf: cloudSetlistURL) {
            try? data.write(to: setlistFileURL, options: [.atomic])
        }
    }

    /// Resolves the iCloud container off the critical launch path, then reloads local UI state.
    private func importFromCloudInBackground() async {
        guard iCloudBackupEnabled else { return }
        let progressionsURL = await Task.detached(priority: .utility) { () -> URL? in
            FileManager.default.url(forUbiquityContainerIdentifier: Self.iCloudContainerID)?
                .appendingPathComponent("Documents/saved_progressions.json")
        }.value
        let setlistsURL = await Task.detached(priority: .utility) { () -> URL? in
            FileManager.default.url(forUbiquityContainerIdentifier: Self.iCloudContainerID)?
                .appendingPathComponent("Documents/setlists.json")
        }.value

        if let progressionsURL, FileManager.default.fileExists(atPath: progressionsURL.path),
           let data = try? Data(contentsOf: progressionsURL) {
            try? data.write(to: fileURL, options: [.atomic])
        }
        if let setlistsURL, FileManager.default.fileExists(atPath: setlistsURL.path),
           let data = try? Data(contentsOf: setlistsURL) {
            try? data.write(to: setlistFileURL, options: [.atomic])
        }
        load()
        loadSetlists()
    }

    private func syncToCloud() {
        guard iCloudBackupEnabled, let cloudURL else { return }
        try? FileManager.default.createDirectory(
            at: cloudURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if let data = try? JSONEncoder().encode(progressions) {
            try? data.write(to: cloudURL, options: [.atomic])
        }
    }

    private func syncSetlistsToCloud() {
        guard iCloudBackupEnabled, let cloudSetlistURL else { return }
        try? FileManager.default.createDirectory(
            at: cloudSetlistURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if let data = try? JSONEncoder().encode(setlists) {
            try? data.write(to: cloudSetlistURL, options: [.atomic])
        }
    }
}
