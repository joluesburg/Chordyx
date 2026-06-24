//
//  SongImportParser.swift
//  Chordyx
//

import Foundation

struct SongImportDraft: Sendable, Equatable {
    var title: String
    var artist: String?
    var key: MusicalKey
    var chords: [ChordEntry]
    var lyricsLines: [LyricsLine]
    var sections: [SectionMarker]
    var plainLyrics: String
    var sourceURL: URL?
    var warnings: [String]
    var tempoBPM: Double?
    var beatsPerBar: Int
    var beatUnit: Int
}

enum SongImportError: LocalizedError {
    case invalidURL
    case downloadFailed
    case unsupportedSite
    case noContentFound
    case noChordsFound

    var errorDescription: String? {
        switch self {
        case .invalidURL: String(localized: "That doesn’t look like a valid web address.")
        case .downloadFailed: String(localized: "Couldn’t download the song page. Check your connection and try again.")
        case .unsupportedSite: String(localized: "This website isn’t supported yet. Try La Cuerda, Ultimate Guitar, or paste plain chord/lyric text.")
        case .noContentFound: String(localized: "No chord chart was found on that page.")
        case .noChordsFound: String(localized: "No chords could be recognized in the text.")
        }
    }
}

@MainActor
enum SongImportParser {

    // MARK: - Public entry points

    static func normalizeURL(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var candidate = trimmed
        if !candidate.contains("://") {
            candidate = "https://\(candidate)"
        }
        guard var components = URLComponents(string: candidate) else { return nil }
        let host = components.host?.lowercased() ?? ""
        if host.contains("lacuerda.net") && !host.hasPrefix("acordes.") && !host.hasPrefix("chords.") && !host.hasPrefix("cifras.") {
            components.host = "acordes.lacuerda.net"
        }
        return components.url
    }

    static func parseDownloadedPage(html: String, sourceURL: URL) throws -> SongImportDraft {
        let host = sourceURL.host?.lowercased() ?? ""
        if host.contains("lacuerda.net") {
            return try parseLaCuerdaHTML(html, sourceURL: sourceURL)
        }
        if host.contains("ultimate-guitar.com") || host.contains("tabs.ultimate-guitar.com") {
            return try parseUltimateGuitarHTML(html, sourceURL: sourceURL)
        }
        if let text = extractPlainChordText(fromGenericHTML: html), !text.isEmpty {
            let title = extractGenericTitle(from: html) ?? sourceURL.lastPathComponent.replacingOccurrences(of: "_", with: " ")
            return try parsePlainText(text, title: title, artist: nil, sourceURL: sourceURL)
        }
        throw SongImportError.unsupportedSite
    }

    static func parsePlainText(
        _ text: String,
        title: String,
        artist: String? = nil,
        key: MusicalKey? = nil,
        sourceURL: URL? = nil
    ) throws -> SongImportDraft {
        let normalized = normalizePlainText(text)
        guard !normalized.isEmpty else { throw SongImportError.noContentFound }

        var warnings: [String] = []
        let metadata = extractMetadata(from: normalized)
        let lines = normalized.components(separatedBy: .newlines)

        var events: [ParseEvent] = []
        var pendingChords: [String] = []

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }

            if isMetadataLine(line) { continue }

            if let section = detectSection(in: line) {
                events.append(.section(section))
                continue
            }

            if line.hasPrefix("{") && line.contains("}") {
                events.append(contentsOf: parseChordProLine(line))
                continue
            }

            let bracketTokens = extractBracketChords(from: line)
            if !bracketTokens.isEmpty && lyricPortion(of: line, chordTokens: bracketTokens).trimmingCharacters(in: .whitespaces).isEmpty {
                pendingChords = bracketTokens
                events.append(.chords(bracketTokens))
                continue
            }

            if !bracketTokens.isEmpty {
                let lyric = lyricPortion(of: line, chordTokens: bracketTokens)
                events.append(.chords(bracketTokens))
                if !lyric.isEmpty {
                    events.append(.lyric(lyric, bracketTokens.first))
                }
                pendingChords = bracketTokens
                continue
            }

            let tokens = line.split(whereSeparator: \.isWhitespace).map(String.init)
            let chordTokens = tokens.filter { isLikelyChordSymbol($0) }
            let lyricTokens = tokens.filter { !isLikelyChordSymbol($0) }

            if !chordTokens.isEmpty && lyricTokens.isEmpty {
                pendingChords = chordTokens
                events.append(.chords(chordTokens))
                continue
            }

            if !lyricTokens.isEmpty {
                let lyric = lyricTokens.joined(separator: " ")
                let symbol = chordTokens.first ?? pendingChords.first
                if !chordTokens.isEmpty {
                    pendingChords = chordTokens
                    events.append(.chords(chordTokens))
                }
                events.append(.lyric(lyric, symbol))
            }
        }

        let built = buildDraft(
            from: events,
            title: title,
            artist: artist,
            key: key,
            sourceURL: sourceURL,
            tempoBPM: metadata.tempoBPM,
            beatsPerBar: metadata.beatsPerBar ?? 4,
            beatUnit: metadata.beatUnit ?? 4,
            warnings: &warnings
        )
        guard !built.chords.isEmpty else { throw SongImportError.noChordsFound }
        return built
    }

    // MARK: - Site-specific HTML

    private static func parseLaCuerdaHTML(_ html: String, sourceURL: URL) throws -> SongImportDraft {
        let title = extractLaCuerdaTitle(from: html) ?? "Imported Song"
        let artist = extractLaCuerdaArtist(from: html)
        let preBlocks = extractHTMLPreBlocks(from: html)
        guard let best = preBlocks.max(by: { $0.count < $1.count }) else {
            throw SongImportError.noContentFound
        }
        let plain = laCuerdaPreToPlainText(best)
        var draft = try parsePlainText(plain, title: title, artist: artist, sourceURL: sourceURL)
        draft.warnings.insert("Imported from La Cuerda — sections are detected automatically; review before playing live.", at: 0)
        return draft
    }

    private static func parseUltimateGuitarHTML(_ html: String, sourceURL: URL) throws -> SongImportDraft {
        if let jsonRange = html.range(of: "\"content\":\"") {
            let tail = html[jsonRange.upperBound...]
            if let end = tail.range(of: "\",\"") {
                let escaped = String(tail[..<end.lowerBound])
                let decoded = decodeJSONString(escaped)
                let title = extractUGTitle(from: html) ?? "Imported Song"
                var draft = try parsePlainText(decoded, title: title, sourceURL: sourceURL)
                if draft.tempoBPM == nil, let bpm = extractUltimateGuitarTempo(from: html) {
                    draft.tempoBPM = bpm
                    draft.warnings.append("Metronome tempo set to \(Int(bpm)) BPM (\(draft.beatsPerBar)/\(draft.beatUnit)).")
                }
                return draft
            }
        }
        if let pre = extractHTMLPreBlocks(from: html).max(by: { $0.count < $1.count }) {
            let title = extractUGTitle(from: html) ?? "Imported Song"
            var draft = try parsePlainText(laCuerdaPreToPlainText(pre), title: title, sourceURL: sourceURL)
            if draft.tempoBPM == nil, let bpm = extractUltimateGuitarTempo(from: html) {
                draft.tempoBPM = bpm
                draft.warnings.append("Metronome tempo set to \(Int(bpm)) BPM (\(draft.beatsPerBar)/\(draft.beatUnit)).")
            }
            return draft
        }
        throw SongImportError.noContentFound
    }

    // MARK: - Build SavedProgression pieces

    private enum ParseEvent {
        case chords([String])
        case lyric(String, String?)
        case section(SectionDraft)
    }

    private struct SectionDraft {
        var name: String
        var kind: WorshipSectionKind
    }

    private static func buildDraft(
        from events: [ParseEvent],
        title: String,
        artist: String?,
        key: MusicalKey?,
        sourceURL: URL?,
        tempoBPM: Double?,
        beatsPerBar: Int,
        beatUnit: Int,
        warnings: inout [String]
    ) -> SongImportDraft {
        var chords: [ChordEntry] = []
        var lyricsLines: [LyricsLine] = []
        var lyricChordIndices: [Int] = []
        var sectionStarts: [(name: String, kind: WorshipSectionKind, index: Int)] = []

        func appendChord(_ raw: String) {
            let symbol = normalizeChordSymbol(raw)
            guard !symbol.isEmpty, isLikelyChordSymbol(symbol) else { return }
            if chords.last?.symbolName == symbol { return }
            chords.append(
                ChordEntry(
                    symbolName: symbol,
                    latinName: ChordCatalog.latinName(forSymbol: symbol),
                    order: chords.count
                )
            )
        }

        func chordIndexForLyric() -> Int {
            max(0, chords.count - 1)
        }

        for event in events {
            switch event {
            case .section(let section):
                sectionStarts.append((section.name, section.kind, chords.count))
            case .chords(let symbols):
                for symbol in symbols { appendChord(symbol) }
            case .lyric(let text, let symbol):
                if let symbol { appendChord(symbol) }
                let lineSymbol = lyricChordSymbol(symbol ?? chords.last?.symbolName, lyric: text)
                lyricsLines.append(LyricsLine(text: text, chordSymbol: lineSymbol))
                lyricChordIndices.append(chordIndexForLyric())
            }
        }

        let explicitCount = sectionStarts.filter { $0.index < chords.count }.count
        let hadExplicitVerse = sectionStarts.contains { $0.kind == .verse }

        var sections = SongSectionAnalyzer.buildSections(
            chords: chords,
            lyricsLines: lyricsLines,
            lyricChordIndices: lyricChordIndices,
            explicitStarts: sectionStarts
        )
        sections = SongSectionAnalyzer.attachLyrics(
            to: sections,
            chords: chords,
            lyricsLines: lyricsLines,
            lyricChordIndices: lyricChordIndices
        )

        if explicitCount > 0, sections.count < explicitCount {
            warnings.append("\(explicitCount - sections.count) section marker(s) could not be linked to chords.")
        }

        if sections.isEmpty, chords.count > 2 {
            warnings.append("No sections were detected — review the chart before playing live.")
        } else if !sections.isEmpty {
            let summary = SongSectionAnalyzer.sectionSummary(sections)
            if explicitCount == 0 {
                warnings.append("Sections detected automatically: \(summary). Tap a section to jump while playing.")
            } else {
                warnings.append("Imported with sections: \(summary). Each section has its own chord ring.")
                if !hadExplicitVerse, sections.contains(where: { $0.kind == .verse }) {
                    warnings.append("No Verse marker was in the chart — a Verse ring was added automatically before the Chorus.")
                }
            }
        }

        if chords.count > 8, !sections.isEmpty {
            warnings.append("Full song has \(chords.count) chord changes — use Chart view or section jumps for the best experience.")
        }

        if let tempoBPM {
            warnings.append("Metronome tempo set to \(Int(tempoBPM)) BPM (\(beatsPerBar)/\(beatUnit)).")
        }

        let detectedKey = key ?? detectKey(from: chords)
        let plainLyrics = lyricsLines.map(\.text).filter { !$0.isEmpty }.joined(separator: "\n")

        return SongImportDraft(
            title: title,
            artist: artist,
            key: detectedKey,
            chords: chords,
            lyricsLines: lyricsLines,
            sections: sections,
            plainLyrics: plainLyrics,
            sourceURL: sourceURL,
            warnings: warnings,
            tempoBPM: tempoBPM,
            beatsPerBar: beatsPerBar,
            beatUnit: beatUnit
        )
    }

    // MARK: - Tempo & time signature

    private static let minTempoBPM = 40.0
    private static let maxTempoBPM = 240.0

    private struct ExtractedSongMetadata: Sendable {
        var tempoBPM: Double?
        var beatsPerBar: Int?
        var beatUnit: Int?
    }

    private static func extractMetadata(from text: String) -> ExtractedSongMetadata {
        var metadata = ExtractedSongMetadata()
        let header = text.components(separatedBy: .newlines).prefix(40).joined(separator: "\n")

        let bpmPatterns = [
            #"(?i)\bbpm\s*[:=]?\s*(\d{2,3})\b"#,
            #"(?i)\btiempo\s*(?:de\s+la\s+cancion|de\s+la\s+canción)?\s*[:=]?\s*(\d{2,3})\s*bpm"#,
            #"(?i)\btiempo\s*[:=]\s*(\d{2,3})\b"#,
            #"(?i)\bpulso\s*[:=]?\s*(\d{2,3})\b"#,
            #"(?i)\btempo\s*[:=]?\s*(\d{2,3})\b"#,
            #"(?i)\b(\d{2,3})\s*bpm\b"#,
        ]

        for pattern in bpmPatterns {
            if let raw = firstRegexGroup(in: header, pattern: pattern), let value = Double(raw) {
                metadata.tempoBPM = clampTempo(value)
                break
            }
        }

        let timeSignaturePatterns = [
            #"(?i)(?:comp[aá]s|firma\s+de\s+tiempo|time\s+signature)\s*[:=]?\s*(\d+)\s*/\s*(\d+)"#,
        ]

        for pattern in timeSignaturePatterns {
            if let groups = firstRegexGroups(in: header, pattern: pattern, groupCount: 2),
               let beats = Int(groups[0]), let unit = Int(groups[1]), beats > 0, unit > 0 {
                metadata.beatsPerBar = beats
                metadata.beatUnit = unit
                break
            }
        }

        return metadata
    }

    private static func extractUltimateGuitarTempo(from html: String) -> Double? {
        let patterns = [
            #"(?i)\"bpm\"\s*:\s*(\d{2,3})"#,
            #"(?i)\"tempo\"\s*:\s*(\d{2,3})"#,
        ]
        for pattern in patterns {
            if let raw = firstRegexGroup(in: html, pattern: pattern), let value = Double(raw) {
                return clampTempo(value)
            }
        }
        return nil
    }

    private static func clampTempo(_ value: Double) -> Double {
        min(max(value.rounded(), minTempoBPM), maxTempoBPM)
    }

    private static func isMetadataLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }

        let metadataPrefixes = [
            #"(?i)^bpm\s*[:=]"#,
            #"(?i)^tiempo\b"#,
            #"(?i)^pulso\b"#,
            #"(?i)^comp[aá]s\b"#,
            #"(?i)^firma\s+de\s+tiempo\b"#,
            #"(?i)^escala\s*[:=]"#,
            #"(?i)^tono\s*[:=]"#,
            #"(?i)^tempo\s*[:=]"#,
            #"(?i)^-{3,}$"#,
            #"(?i)^\*{3,}$"#,
            #"(?i)^simbolog[ií]a\b"#,
            #"(?i)^nota\s+\d"#,
            #"(?i)^\d{2,3}\s*bpm\s*$"#,
        ]

        for pattern in metadataPrefixes {
            if trimmed.range(of: pattern, options: .regularExpression) != nil { return true }
        }

        if trimmed.range(of: #"(?i)\b(bpm|tiempo|comp[aá]s|tono|escala|pulso|tempo)\b"#, options: .regularExpression) != nil,
           !trimmed.contains("[") {
            let tokens = trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
            let chordCount = tokens.filter { isLikelyChordSymbol($0) }.count
            if chordCount == 0 { return true }
        }

        return false
    }

    private static func firstRegexGroups(in text: String, pattern: String, groupCount: Int) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        var groups: [String] = []
        for index in 1...groupCount {
            guard match.range(at: index).location != NSNotFound,
                  let range = Range(match.range(at: index), in: text) else { return nil }
            groups.append(String(text[range]))
        }
        return groups
    }

    // MARK: - Text helpers

    private static func normalizePlainText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "–", with: "-")
    }

    private static func normalizeChordSymbol(_ raw: String) -> String {
        var symbol = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        symbol = symbol.replacingOccurrences(of: "[", with: "")
        symbol = symbol.replacingOccurrences(of: "]", with: "")
        if let solfege = SolfegeConverter.toLetterSymbol(symbol) {
            symbol = solfege
        }
        symbol = symbol.replacingOccurrences(of: "A#", with: "Bb")
        if symbol == "H" { symbol = "B" }
        return symbol
    }

    private static let validChordRegex: NSRegularExpression? = {
        // Roots + optional qualities (Am, F#m7, G/B, Csus4, Dmaj7, …) — not lyric words like "desde" or "aca".
        let pattern = #"^[A-G](?:[#b♭♯])?(?:(?:m(?:aj(?:7|9|11|13)?|in(?:7|9)?|[246789])?|maj(?:7|9|11|13)?|dim(?:7)?|aug|sus(?:2|4)?|add(?:9|11|13)?|[246789]|1[13])(?:[#b♭♯]?(?:5|9|11|13|2|4|6))*)?(?:/[A-G][#b♭♯]?)?$"#
        return try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
    }()

    private static func isLikelyChordSymbol(_ token: String) -> Bool {
        let cleaned = normalizeChordSymbol(token)
        guard !cleaned.isEmpty, cleaned.count <= 14 else { return false }
        guard let regex = validChordRegex else { return false }
        let range = NSRange(cleaned.startIndex..., in: cleaned)
        guard regex.firstMatch(in: cleaned, options: [], range: range)?.range == range else { return false }
        if cleaned.count == 1, cleaned.first?.isLowercase == true { return false }
        return true
    }

    private static func lyricChordSymbol(_ raw: String?, lyric: String) -> String? {
        guard let raw else { return nil }
        let cleaned = normalizeChordSymbol(raw)
        guard validAngloChord(cleaned) else { return nil }
        let lowerLyric = lyric.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if cleaned.uppercased() == "A", lowerLyric.hasPrefix("al ") { return nil }
        return cleaned
    }

    private static func validAngloChord(_ cleaned: String) -> Bool {
        guard let regex = validChordRegex else { return false }
        let range = NSRange(cleaned.startIndex..., in: cleaned)
        return regex.firstMatch(in: cleaned, options: [], range: range)?.range == range
    }

    private static func detectSection(in line: String) -> SectionDraft? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        if let bracketed = sectionLabel(in: trimmed, open: "[", close: "]") {
            return classifySectionLabel(bracketed)
        }
        if let parenthesized = sectionLabel(in: trimmed, open: "(", close: ")") {
            return classifySectionLabel(parenthesized)
        }

        let upper = trimmed.uppercased()
        let stripped = upper
            .replacingOccurrences(of: "//", with: "")
            .replacingOccurrences(of: ":", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let classified = classifySectionLabel(stripped) {
            return classified
        }

        if trimmed.hasPrefix("//") {
            var inner = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            if inner.hasSuffix("//") {
                inner = String(inner.dropLast(2)).trimmingCharacters(in: .whitespaces)
            }
            if !inner.isEmpty {
                if let known = classifySectionLabel(inner) { return known }
                return SectionDraft(name: String(inner.capitalized), kind: .custom)
            }
        }
        return nil
    }

    private static func sectionLabel(in line: String, open: Character, close: Character) -> String? {
        guard line.first == open, line.last == close, line.count >= 3 else { return nil }
        let inner = String(line.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !inner.isEmpty, !isLikelyChordSymbol(inner) else { return nil }
        return inner
    }

    private static func classifySectionLabel(_ raw: String) -> SectionDraft? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let upper = trimmed.uppercased()
        let stripped = upper
            .replacingOccurrences(of: ":", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let mappings: [(keywords: [String], kind: WorshipSectionKind, name: String)] = [
            (["INTRO", "INTRODUCCION", "INTRODUCCIÓN", "INICIO"], .intro, "Intro"),
            (["VERSO", "ESTROFA", "VERSE", "STROFA"], .verse, "Verse"),
            (["PRE-CORO", "PRE CORO", "PRECORO", "PRE CHORUS", "PRECHORUS"], .preChorus, "Pre-Chorus"),
            (["CORO", "CHORUS", "ESTRIBILLO", "REFRAIN"], .chorus, "Chorus"),
            (["PUENTE", "BRIDGE"], .bridge, "Bridge"),
            (["TAG"], .tag, "Tag"),
            (["FINAL", "OUTRO", "ENDING", "CODA"], .ending, "Ending"),
            (["INTERLUDIO", "INTERLUDE"], .custom, "Interlude"),
            (["SOLO"], .custom, "Solo"),
        ]

        for mapping in mappings {
            guard mapping.keywords.contains(where: { stripped.contains($0) }) else { continue }
            let displayName = numberedSectionName(base: mapping.name, from: trimmed) ?? mapping.name
            if stripped.count <= 48 { return SectionDraft(name: displayName, kind: mapping.kind) }
        }

        if let numbered = numberedSectionName(base: nil, from: trimmed) {
            return SectionDraft(name: numbered, kind: .verse)
        }

        return nil
    }

    private static func numberedSectionName(base: String?, from raw: String) -> String? {
        let pattern = #"(?i)^(verse|verso|estrofa|chorus|coro|estribillo|bridge|puente|intro|outro)\s*[#.]?\s*(\d+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)),
              let labelRange = Range(match.range(at: 1), in: raw),
              let numberRange = Range(match.range(at: 2), in: raw) else { return nil }

        let label = String(raw[labelRange]).lowercased()
        let number = String(raw[numberRange])
        let resolvedBase: String
        if let base {
            resolvedBase = base
        } else {
            switch label {
            case "verse", "verso", "estrofa": resolvedBase = "Verse"
            case "chorus", "coro", "estribillo": resolvedBase = "Chorus"
            case "bridge", "puente": resolvedBase = "Bridge"
            case "intro": resolvedBase = "Intro"
            case "outro": resolvedBase = "Ending"
            default: resolvedBase = label.capitalized
            }
        }
        return "\(resolvedBase) \(number)"
    }

    private static func parseChordProLine(_ line: String) -> [ParseEvent] {
        var events: [ParseEvent] = []
        var lyric = ""
        var current = line[...]
        while let open = current.firstIndex(of: "{"), let close = current[open...].firstIndex(of: "}") {
            lyric += current[..<open]
            let symbol = String(current[current.index(after: open)..<close])
            events.append(.chords([symbol]))
            current = current[current.index(after: close)...]
        }
        lyric += current
        let trimmed = lyric.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            events.append(.lyric(trimmed, nil))
        }
        return events
    }

    private static func extractBracketChords(from line: String) -> [String] {
        guard line.contains("[") else { return [] }
        var chords: [String] = []
        var remainder = line[...]
        while let open = remainder.firstIndex(of: "["), let close = remainder[open...].firstIndex(of: "]") {
            let symbol = String(remainder[remainder.index(after: open)..<close])
            if isLikelyChordSymbol(symbol) { chords.append(symbol) }
            remainder = remainder[remainder.index(after: close)...]
        }
        return chords
    }

    private static func lyricPortion(of line: String, chordTokens: [String]) -> String {
        var result = line
        for token in chordTokens {
            result = result.replacingOccurrences(of: "[\(token)]", with: "")
        }
        return result.trimmingCharacters(in: .whitespaces)
    }

    private static func detectKey(from chords: [ChordEntry]) -> MusicalKey {
        guard let first = chords.first?.symbolName,
              let parsed = Transposer.parse(first),
              let pc = Transposer.pitchClass(ofRoot: parsed.root) else { return .C }
        return MusicalKey.allCases.first { $0.pitchClass == pc } ?? .C
    }

    // MARK: - HTML helpers

    private static func laCuerdaPreToPlainText(_ preHTML: String) -> String {
        var text = preHTML
        text = text.replacingOccurrences(of: "<br>", with: "\n", options: .caseInsensitive)
        text = text.replacingOccurrences(of: "<br/>", with: "\n", options: .caseInsensitive)
        text = text.replacingOccurrences(of: "<br />", with: "\n", options: .caseInsensitive)

        let anchorPattern = #"<A[^>]*>([^<]+)</A>"#
        if let regex = try? NSRegularExpression(pattern: anchorPattern, options: .caseInsensitive) {
            let range = NSRange(text.startIndex..., in: text)
            text = regex.stringByReplacingMatches(in: text, range: range, withTemplate: "[$1]")
        }

        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        text = decodeHTMLEntities(text)
        return text
    }

    private static func extractHTMLPreBlocks(from html: String) -> [String] {
        let pattern = #"(?is)<pre[^>]*>(.*?)</pre>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(html.startIndex..., in: html)
        return regex.matches(in: html, range: range).compactMap { match in
            guard let r = Range(match.range(at: 1), in: html) else { return nil }
            return String(html[r])
        }
    }

    private static func extractPlainChordText(fromGenericHTML html: String) -> String? {
        let blocks = extractHTMLPreBlocks(from: html).map(laCuerdaPreToPlainText)
        return blocks.max(by: { $0.count < $1.count })
    }

    private static func extractLaCuerdaTitle(from html: String) -> String? {
        if let match = firstRegexGroup(in: html, pattern: #"(?is)<H1>\s*([^<]+)"#) {
            return match.components(separatedBy: "<").first?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let match = firstRegexGroup(in: html, pattern: #""name"\s*:\s*"([^"]+)""#) {
            return match
        }
        return extractGenericTitle(from: html)
    }

    private static func extractLaCuerdaArtist(from html: String) -> String? {
        if let match = firstRegexGroup(in: html, pattern: #""byArtist"[^}]*"name"\s*:\s*"([^"]+)""#) {
            return match
        }
        if let match = firstRegexGroup(in: html, pattern: #"(?is)<H1>[^<]*<br>\s*<A[^>]*>([^<]+)</A>"#) {
            return match
        }
        return nil
    }

    private static func extractUGTitle(from html: String) -> String? {
        firstRegexGroup(in: html, pattern: #"(?is)<meta property="og:title" content="([^"]+)""#)
            ?? extractGenericTitle(from: html)
    }

    private static func extractGenericTitle(from html: String) -> String? {
        firstRegexGroup(in: html, pattern: #"(?is)<title>([^<|]+)"#)?
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func firstRegexGroup(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func decodeHTMLEntities(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
    }

    private static func decodeJSONString(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\r", with: "")
            .replacingOccurrences(of: "\\t", with: "\t")
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\/", with: "/")
    }

    /// Removes lyric words that were mistakenly stored as chords (e.g. "desde", "aca").
    static func sanitizeProgression(_ progression: SavedProgression) -> SavedProgression {
        let sorted = progression.chords.sorted { $0.order < $1.order }
        let validChords = sorted.filter { isLikelyChordSymbol($0.symbolName) }
        guard validChords.count != sorted.count else { return progression }

        let validIDs = Set(validChords.map(\.id))
        let remappedChords = validChords.enumerated().map { index, chord in
            ChordEntry(
                id: chord.id,
                symbolName: chord.symbolName,
                latinName: chord.latinName,
                order: index,
                durationBeats: chord.durationBeats,
                lyrics: chord.lyrics
            )
        }

        var cleaned = progression
        cleaned.chords = remappedChords
        cleaned.sections = progression.sections.filter { validIDs.contains($0.startChordID) }
        cleaned.lyricsLines = progression.lyricsLines.map { line in
            guard let symbol = line.chordSymbol, !isLikelyChordSymbol(symbol) else { return line }
            return LyricsLine(id: line.id, text: line.text, chordSymbol: nil)
        }
        if let loopStart = progression.loopStartChordID, !validIDs.contains(loopStart) {
            cleaned.loopStartChordID = nil
        }
        if let loopEnd = progression.loopEndChordID, !validIDs.contains(loopEnd) {
            cleaned.loopEndChordID = nil
        }
        if cleaned.loopStartChordID == nil || cleaned.loopEndChordID == nil {
            cleaned.isLoopEnabled = false
        }
        return cleaned
    }
}

// MARK: - Section analysis

/// Builds worship-style section markers (Intro, Verse, Chorus, Bridge, …) from imported charts.
@MainActor
enum SongSectionAnalyzer {

    struct Candidate: Sendable {
        let kind: WorshipSectionKind
        let name: String
        let startIndex: Int
        let priority: Int
    }

    static func buildSections(
        chords: [ChordEntry],
        lyricsLines: [LyricsLine],
        lyricChordIndices: [Int],
        explicitStarts: [(name: String, kind: WorshipSectionKind, index: Int)]
    ) -> [SectionMarker] {
        guard !chords.isEmpty else { return [] }

        let explicitMarkers = explicitStarts
            .filter { $0.index < chords.count }
            .map { start in
                SectionMarker(
                    name: start.name,
                    startChordID: chords[start.index].id,
                    kind: start.kind
                )
            }

        if !explicitMarkers.isEmpty {
            return enrichImportedSections(
                explicit: explicitMarkers,
                chords: chords,
                lyricsLines: lyricsLines,
                lyricChordIndices: lyricChordIndices
            )
        }

        var candidates: [Candidate] = explicitStarts.map { start in
            Candidate(
                kind: start.kind,
                name: start.name,
                startIndex: min(max(start.index, 0), chords.count - 1),
                priority: 100
            )
        }

        if candidates.count < 2 {
            candidates.append(contentsOf: inferCandidates(
                chords: chords,
                lyricsLines: lyricsLines,
                lyricChordIndices: lyricChordIndices
            ))
        }

        candidates = dedupeCandidates(candidates)
        candidates.sort { lhs, rhs in
            if lhs.startIndex == rhs.startIndex { return lhs.priority > rhs.priority }
            return lhs.startIndex < rhs.startIndex
        }

        var markers: [SectionMarker] = []
        var usedStarts: Set<Int> = []

        for candidate in candidates {
            guard candidate.startIndex < chords.count else { continue }
            if usedStarts.contains(candidate.startIndex) { continue }
            usedStarts.insert(candidate.startIndex)
            markers.append(SectionMarker(
                name: candidate.name,
                startChordID: chords[candidate.startIndex].id,
                kind: candidate.kind
            ))
        }

        if markers.isEmpty, chords.count > 2 {
            markers.append(SectionMarker(name: "Verse", startChordID: chords[0].id, kind: .verse))
        }

        return sortMarkers(markers, chords: chords)
    }

    static func sectionBreakdown(
        chords: [ChordEntry],
        sections: [SectionMarker]
    ) -> [(section: SectionMarker, chords: [ChordEntry])] {
        let sorted = chords.sorted { $0.order < $1.order }
        let orderedSections = sortMarkers(sections, chords: sorted)
        guard !orderedSections.isEmpty else {
            return sorted.isEmpty ? [] : [(SectionMarker(name: "Song", startChordID: sorted[0].id, kind: .custom), sorted)]
        }

        return orderedSections.enumerated().map { index, section in
            let start = sorted.firstIndex(where: { $0.id == section.startChordID }) ?? 0
            let end: Int
            if index + 1 < orderedSections.count,
               let nextStart = sorted.firstIndex(where: { $0.id == orderedSections[index + 1].startChordID }) {
                end = nextStart
            } else {
                end = sorted.count
            }
            return (section, Array(sorted[start..<end]))
        }
    }

    static func attachLyrics(
        to sections: [SectionMarker],
        chords: [ChordEntry],
        lyricsLines: [LyricsLine],
        lyricChordIndices: [Int]
    ) -> [SectionMarker] {
        guard !sections.isEmpty,
              lyricChordIndices.count == lyricsLines.count,
              !lyricsLines.isEmpty else { return sections }

        let sorted = chords.sorted { $0.order < $1.order }
        let breakdown = sectionBreakdown(chords: sorted, sections: sections)

        return breakdown.map { item in
            let start = sorted.firstIndex(where: { $0.id == item.section.startChordID }) ?? 0
            let end = (sorted.firstIndex(where: { $0.id == item.chords.last?.id }) ?? start) + 1
            let lines = lyricsLines.enumerated().compactMap { index, line -> String? in
                guard index < lyricChordIndices.count else { return nil }
                let chordIndex = lyricChordIndices[index]
                guard chordIndex >= start, chordIndex < end else { return nil }
                let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
                return text.isEmpty ? nil : text
            }
            var section = item.section
            section.lyrics = lines.joined(separator: "\n")
            return section
        }
    }

    private static func sortMarkers(_ markers: [SectionMarker], chords: [ChordEntry]) -> [SectionMarker] {
        markers.sorted { lhs, rhs in
            let li = chords.firstIndex(where: { $0.id == lhs.startChordID }) ?? Int.max
            let ri = chords.firstIndex(where: { $0.id == rhs.startChordID }) ?? Int.max
            return li < ri
        }
    }

    static func sectionSummary(_ sections: [SectionMarker]) -> String {
        sections.map(\.name).joined(separator: ", ")
    }

    /// When a chart labels only Intro + Chorus (common on La Cuerda), infer Verse and trim oversized intros.
    private static func enrichImportedSections(
        explicit: [SectionMarker],
        chords: [ChordEntry],
        lyricsLines: [LyricsLine],
        lyricChordIndices: [Int]
    ) -> [SectionMarker] {
        var markers = sortMarkers(explicit, chords: chords)
        let symbols = chords.map(\.symbolName)

        markers = insertMissingVerse(into: markers, chords: chords, symbols: symbols)
        markers = insertVerseForOversizedIntro(into: markers, chords: chords, symbols: symbols)
        markers = insertSecondVerseIfNeeded(into: markers, chords: chords, symbols: symbols)

        let inferred = inferCandidates(chords: chords, lyricsLines: lyricsLines, lyricChordIndices: lyricChordIndices)
        markers = mergeInferredSections(into: markers, inferred: inferred, chords: chords)

        return dedupeMarkersByStart(markers, chords: chords)
    }

    private static func insertMissingVerse(
        into markers: [SectionMarker],
        chords: [ChordEntry],
        symbols: [String]
    ) -> [SectionMarker] {
        guard !markers.contains(where: { $0.kind == .verse }) else { return markers }
        guard let chorus = markers.first(where: { $0.kind == .chorus }) else { return markers }

        let chorusStart = chordIndex(for: chorus, in: chords)
        guard chorusStart >= 2 else { return markers }

        let verseStart = verseStartBeforeChorus(
            markers: markers,
            chords: chords,
            symbols: symbols,
            chorusStart: chorusStart
        )

        guard verseStart > 0, verseStart < chorusStart else { return markers }
        guard !markers.contains(where: { chordIndex(for: $0, in: chords) == verseStart }) else { return markers }

        var updated = markers
        updated.append(SectionMarker(name: "Verse", startChordID: chords[verseStart].id, kind: .verse))
        return updated
    }

    private static func insertVerseForOversizedIntro(
        into markers: [SectionMarker],
        chords: [ChordEntry],
        symbols: [String]
    ) -> [SectionMarker] {
        guard let intro = markers.first(where: { $0.kind == .intro }) else { return markers }

        let introStart = chordIndex(for: intro, in: chords)
        let introEnd = nextSectionStart(after: intro, in: markers, chords: chords)
        let introLength = introEnd - introStart
        guard introLength > maxTypicalIntroChords else { return markers }

        let splitAt = introStart + idealIntroLength(symbols: symbols, regionStart: introStart, regionEnd: introEnd)
        guard splitAt > introStart, splitAt < introEnd else { return markers }

        var updated = markers
        if !updated.contains(where: { $0.kind == .verse && chordIndex(for: $0, in: chords) == splitAt }) {
            updated.append(SectionMarker(name: "Verse", startChordID: chords[splitAt].id, kind: .verse))
        }
        return updated
    }

    private static func insertSecondVerseIfNeeded(
        into markers: [SectionMarker],
        chords: [ChordEntry],
        symbols: [String]
    ) -> [SectionMarker] {
        let ordered = sortMarkers(markers, chords: chords)
        let choruses = ordered.filter { $0.kind == .chorus }
        guard choruses.count >= 2 else { return markers }

        var updated = markers
        for index in 0..<(choruses.count - 1) {
            let firstEnd = nextSectionStart(after: choruses[index], in: ordered, chords: chords)
            let secondStart = chordIndex(for: choruses[index + 1], in: chords)
            guard secondStart - firstEnd >= 4 else { continue }
            guard !updated.contains(where: {
                $0.kind == .verse && chordIndex(for: $0, in: chords) == firstEnd
            }) else { continue }

            let name = updated.filter { $0.kind == .verse }.count >= 1 ? "Verse 2" : "Verse"
            updated.append(SectionMarker(name: name, startChordID: chords[firstEnd].id, kind: .verse))
        }
        return updated
    }

    private static func mergeInferredSections(
        into markers: [SectionMarker],
        inferred: [Candidate],
        chords: [ChordEntry]
    ) -> [SectionMarker] {
        var updated = markers
        let usedStarts = Set(markers.map { chordIndex(for: $0, in: chords) })
        let usedKinds = Set(markers.map(\.kind))

        for candidate in inferred.sorted(by: { $0.startIndex < $1.startIndex }) {
            guard candidate.startIndex < chords.count else { continue }
            guard !usedStarts.contains(candidate.startIndex) else { continue }
            guard !usedKinds.contains(candidate.kind) else { continue }
            updated.append(SectionMarker(
                name: candidate.name,
                startChordID: chords[candidate.startIndex].id,
                kind: candidate.kind
            ))
        }
        return updated
    }

    private static let maxTypicalIntroChords = 4

    private static func verseStartBeforeChorus(
        markers: [SectionMarker],
        chords: [ChordEntry],
        symbols: [String],
        chorusStart: Int
    ) -> Int {
        if let intro = markers.first(where: { $0.kind == .intro }) {
            let introStart = chordIndex(for: intro, in: chords)
            let introEnd = nextSectionStart(after: intro, in: markers, chords: chords)
            if introEnd >= chorusStart {
                return introStart + idealIntroLength(
                    symbols: symbols,
                    regionStart: introStart,
                    regionEnd: chorusStart
                )
            }
            return introEnd
        }

        if let lastBeforeChorus = sortMarkers(markers, chords: chords)
            .filter({ chordIndex(for: $0, in: chords) < chorusStart })
            .last {
            let start = chordIndex(for: lastBeforeChorus, in: chords)
            let end = nextSectionStart(after: lastBeforeChorus, in: markers, chords: chords)
            if end - start >= 4 { return end }
            return min(start + 2, chorusStart - 1)
        }

        return min(4, max(2, chorusStart / 2))
    }

    private static func idealIntroLength(symbols: [String], regionStart: Int, regionEnd: Int) -> Int {
        let length = max(0, regionEnd - regionStart)
        guard length > maxTypicalIntroChords else { return length }

        let slice = Array(symbols[regionStart..<regionEnd])
        let detected = detectIntroLength(symbols: slice, chorusFirstIndex: length)
        if detected > 0, detected < length {
            return min(detected, maxTypicalIntroChords)
        }
        return min(maxTypicalIntroChords, max(2, length / 4))
    }

    private static func chordIndex(for section: SectionMarker, in chords: [ChordEntry]) -> Int {
        chords.firstIndex(where: { $0.id == section.startChordID }) ?? 0
    }

    private static func nextSectionStart(
        after section: SectionMarker,
        in markers: [SectionMarker],
        chords: [ChordEntry]
    ) -> Int {
        let ordered = sortMarkers(markers, chords: chords)
        guard let index = ordered.firstIndex(where: { $0.id == section.id }) else { return chords.count }
        if index + 1 < ordered.count {
            return chordIndex(for: ordered[index + 1], in: chords)
        }
        return chords.count
    }

    private static func dedupeMarkersByStart(_ markers: [SectionMarker], chords: [ChordEntry]) -> [SectionMarker] {
        var byStart: [Int: SectionMarker] = [:]
        for marker in markers {
            let start = chordIndex(for: marker, in: chords)
            byStart[start] = marker
        }
        return sortMarkers(Array(byStart.values), chords: chords)
    }

    private static func inferCandidates(
        chords: [ChordEntry],
        lyricsLines: [LyricsLine],
        lyricChordIndices: [Int]
    ) -> [Candidate] {
        let symbols = chords.map(\.symbolName)
        guard symbols.count >= 3 else { return [] }

        var results: [Candidate] = []
        let chorus = findDominantRepeatingPattern(in: symbols)

        let introLength = detectIntroLength(symbols: symbols, chorusFirstIndex: chorus?.indices.first)
        if introLength > 0 {
            results.append(Candidate(kind: .intro, name: "Intro", startIndex: 0, priority: 60))
        }

        let verseStart = introLength > 0 ? introLength : 0
        results.append(Candidate(kind: .verse, name: "Verse", startIndex: verseStart, priority: 55))

        if let chorus {
            results.append(Candidate(
                kind: .chorus,
                name: "Chorus",
                startIndex: chorus.indices[0],
                priority: 70
            ))

            if let preChorusStart = findPreChorusStart(
                symbols: symbols,
                chorusStart: chorus.indices[0],
                verseStart: verseStart
            ) {
                results.append(Candidate(
                    kind: .preChorus,
                    name: "Pre-Chorus",
                    startIndex: preChorusStart,
                    priority: 50
                ))
            }

            if chorus.indices.count >= 2,
               let bridgeStart = findBridgeStart(
                   symbols: symbols,
                   chorusPattern: chorus.pattern,
                   firstChorusEnd: chorus.indices[0] + chorus.pattern.count,
                   secondChorusStart: chorus.indices[1]
               ) {
                results.append(Candidate(kind: .bridge, name: "Bridge", startIndex: bridgeStart, priority: 55))
            }
        }

        if let tagStart = findTagStart(symbols: symbols, chorus: chorus) {
            results.append(Candidate(kind: .tag, name: "Tag", startIndex: tagStart, priority: 45))
        }

        if let endingStart = findEndingStart(symbols: symbols, existing: results) {
            results.append(Candidate(kind: .ending, name: "Ending", startIndex: endingStart, priority: 40))
        }

        results.append(contentsOf: inferFromLyricStanzas(
            lyricsLines: lyricsLines,
            lyricChordIndices: lyricChordIndices,
            existing: results
        ))

        return results
    }

    private static func findDominantRepeatingPattern(in symbols: [String]) -> (pattern: [String], indices: [Int])? {
        guard symbols.count >= 6 else { return nil }

        var best: (pattern: [String], indices: [Int], score: Int)?

        let maxLength = min(12, symbols.count / 2)
        for length in (3...maxLength).reversed() {
            var buckets: [String: [Int]] = [:]
            for start in 0...(symbols.count - length) {
                let slice = Array(symbols[start..<(start + length)])
                buckets[slice.joined(separator: "\u{1F}"), default: []].append(start)
            }

            for (_, indices) in buckets where indices.count >= 2 {
                let sorted = indices.sorted()
                guard let first = sorted.first, let last = sorted.last, last - first >= length else { continue }
                let pattern = Array(symbols[first..<(first + length)])
                let score = pattern.count * sorted.count
                if let currentBest = best {
                    if score > currentBest.score {
                        best = (pattern, sorted, score)
                    }
                } else {
                    best = (pattern, sorted, score)
                }
            }
        }

        guard let best else { return nil }
        return (best.pattern, best.indices)
    }

    private static func detectIntroLength(symbols: [String], chorusFirstIndex: Int?) -> Int {
        let maxIntro = min(4, symbols.count / 4)
        guard maxIntro > 0 else { return 0 }

        if let chorusFirstIndex, chorusFirstIndex > 0, chorusFirstIndex <= maxIntro + 2 {
            return chorusFirstIndex
        }

        if symbols.count >= 10 {
            let head = Array(symbols.prefix(min(3, symbols.count)))
            let tail = Array(symbols.dropFirst(3).prefix(head.count))
            if head != tail { return min(3, symbols.count / 5) }
        }

        return symbols.count >= 16 ? 2 : 0
    }

    private static func findPreChorusStart(symbols: [String], chorusStart: Int, verseStart: Int) -> Int? {
        guard chorusStart - verseStart >= 4 else { return nil }
        let gapStart = max(verseStart + 2, chorusStart - 6)
        let gapEnd = chorusStart
        guard gapEnd - gapStart >= 2, gapEnd - gapStart <= 8 else { return nil }

        for length in (2...min(6, gapEnd - gapStart)).reversed() {
            let start = gapEnd - length
            if start < gapStart { continue }
            let slice = Array(symbols[start..<gapEnd])
            if countOccurrences(of: slice, in: symbols) == 1 {
                return start
            }
        }
        return nil
    }

    private static func findBridgeStart(
        symbols: [String],
        chorusPattern: [String],
        firstChorusEnd: Int,
        secondChorusStart: Int
    ) -> Int? {
        let rangeStart = firstChorusEnd
        let rangeEnd = secondChorusStart
        guard rangeEnd - rangeStart >= 4 else { return nil }

        for length in (4...min(10, rangeEnd - rangeStart)).reversed() {
            for start in rangeStart..<(rangeEnd - length + 1) {
                let slice = Array(symbols[start..<(start + length)])
                if slice == chorusPattern { continue }
                if countOccurrences(of: slice, in: symbols) == 1 {
                    return start
                }
            }
        }
        return nil
    }

    private static func findTagStart(
        symbols: [String],
        chorus: (pattern: [String], indices: [Int])?
    ) -> Int? {
        guard symbols.count >= 8 else { return nil }
        let searchStart = max(symbols.count - 12, (chorus?.indices.last ?? 0) + (chorus?.pattern.count ?? 0))

        for length in (2...4).reversed() {
            guard symbols.count - length >= searchStart else { continue }
            let start = symbols.count - length
            let slice = Array(symbols[start..<symbols.count])
            if countOccurrences(of: slice, in: symbols) >= 2 {
                return start
            }
        }
        return nil
    }

    private static func findEndingStart(symbols: [String], existing: [Candidate]) -> Int? {
        guard symbols.count >= 6 else { return nil }
        let lastIndex = symbols.count - 1
        if existing.contains(where: { $0.startIndex == lastIndex }) { return nil }
        if existing.contains(where: { $0.kind == .tag && $0.startIndex >= symbols.count - 4 }) { return nil }
        return max(lastIndex - 1, 0)
    }

    private static func inferFromLyricStanzas(
        lyricsLines: [LyricsLine],
        lyricChordIndices: [Int],
        existing: [Candidate]
    ) -> [Candidate] {
        guard lyricsLines.count >= 4, lyricChordIndices.count == lyricsLines.count else { return [] }

        var stanzaStarts: [Int] = [0]
        for index in 1..<lyricsLines.count {
            let prev = lyricsLines[index - 1].text.trimmingCharacters(in: .whitespacesAndNewlines)
            let current = lyricsLines[index].text.trimmingCharacters(in: .whitespacesAndNewlines)
            if prev.isEmpty || current.isEmpty {
                stanzaStarts.append(index)
            }
        }

        guard stanzaStarts.count >= 2 else { return [] }

        var inferred: [Candidate] = []
        let hasChorus = existing.contains(where: { $0.kind == .chorus })

        if !hasChorus, stanzaStarts.count >= 2 {
            let mid = stanzaStarts[stanzaStarts.count / 2]
            let chordIndex = lyricChordIndices[mid]
            inferred.append(Candidate(kind: .chorus, name: "Chorus", startIndex: chordIndex, priority: 35))
        }

        return inferred
    }

    private static func countOccurrences(of pattern: [String], in symbols: [String]) -> Int {
        guard !pattern.isEmpty, pattern.count <= symbols.count else { return 0 }
        var count = 0
        for start in 0...(symbols.count - pattern.count) {
            if Array(symbols[start..<(start + pattern.count)]) == pattern {
                count += 1
            }
        }
        return count
    }

    private static func dedupeCandidates(_ candidates: [Candidate]) -> [Candidate] {
        var bestByKind: [WorshipSectionKind: Candidate] = [:]
        var bestByIndex: [Int: Candidate] = [:]

        for candidate in candidates {
            if let existing = bestByKind[candidate.kind] {
                if candidate.priority > existing.priority
                    || (candidate.priority == existing.priority && candidate.startIndex < existing.startIndex) {
                    bestByKind[candidate.kind] = candidate
                }
            } else {
                bestByKind[candidate.kind] = candidate
            }
        }

        for candidate in bestByKind.values {
            if let existing = bestByIndex[candidate.startIndex] {
                if candidate.priority > existing.priority {
                    bestByIndex[candidate.startIndex] = candidate
                }
            } else {
                bestByIndex[candidate.startIndex] = candidate
            }
        }

        return Array(bestByIndex.values)
    }
}

// MARK: - Solfège conversion

/// Converts solfège-style chord symbols (common on Spanish chord charts) to letter names.
enum SolfegeConverter {
    private static let syllables: [(name: String, letter: String)] = [
        ("SOL", "G"),
        ("LA", "A"),
        ("SI", "B"),
        ("DO", "C"),
        ("RE", "D"),
        ("MI", "E"),
        ("FA", "F"),
    ]

    static func toLetterSymbol(_ raw: String) -> String? {
        var token = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "[", with: "")
            .replacingOccurrences(of: "]", with: "")
        guard !token.isEmpty else { return nil }

        token = token
            .replacingOccurrences(of: "♯", with: "#")
            .replacingOccurrences(of: "♭", with: "b")
            .replacingOccurrences(of: "MAJ", with: "maj")
            .replacingOccurrences(of: "MIN", with: "m")

        let upper = token.uppercased()
        for entry in syllables {
            guard upper.hasPrefix(entry.name) else { continue }
            let suffixStart = token.index(token.startIndex, offsetBy: entry.name.count)
            let suffix = String(token[suffixStart...])
            let normalizedSuffix = normalizeSuffix(suffix)
            return entry.letter + normalizedSuffix
        }
        return nil
    }

    private static func normalizeSuffix(_ suffix: String) -> String {
        var s = suffix.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.uppercased() == "M" { return "" }
        if s.hasPrefix("M") && s.count > 1, s.dropFirst().first?.isNumber == true {
            s = "m" + s.dropFirst()
        }
        return s
    }
}
