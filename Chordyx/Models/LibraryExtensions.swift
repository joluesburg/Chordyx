//
//  LibraryExtensions.swift
//  Chordyx
//

import Foundation
import MultipeerConnectivity
import SwiftUI

// MARK: - Sections & setlists

struct SectionMarker: Identifiable, Codable, Equatable, Hashable, Sendable {
    let id: UUID
    var name: String
    var startChordID: UUID
    var lyrics: String
    var kind: WorshipSectionKind
    var repeatCount: Int
    var autoCueText: String?
    var autoCueSymbol: String?
    var autoCueTrigger: SectionCueTrigger?

    init(
        id: UUID = UUID(),
        name: String,
        startChordID: UUID,
        lyrics: String = "",
        kind: WorshipSectionKind = .custom,
        repeatCount: Int = 1,
        autoCueText: String? = nil,
        autoCueSymbol: String? = nil,
        autoCueTrigger: SectionCueTrigger? = nil
    ) {
        self.id = id
        self.name = name
        self.startChordID = startChordID
        self.lyrics = lyrics
        self.kind = kind
        self.repeatCount = max(1, repeatCount)
        self.autoCueText = autoCueText
        self.autoCueSymbol = autoCueSymbol
        self.autoCueTrigger = autoCueTrigger
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, startChordID, lyrics, kind, repeatCount
        case autoCueText, autoCueSymbol, autoCueTrigger
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        startChordID = try container.decode(UUID.self, forKey: .startChordID)
        lyrics = try container.decodeIfPresent(String.self, forKey: .lyrics) ?? ""
        kind = try container.decodeIfPresent(WorshipSectionKind.self, forKey: .kind) ?? .custom
        repeatCount = max(1, try container.decodeIfPresent(Int.self, forKey: .repeatCount) ?? 1)
        autoCueText = try container.decodeIfPresent(String.self, forKey: .autoCueText)
        autoCueSymbol = try container.decodeIfPresent(String.self, forKey: .autoCueSymbol)
        autoCueTrigger = try container.decodeIfPresent(SectionCueTrigger.self, forKey: .autoCueTrigger)
    }
}

struct Setlist: Identifiable, Codable, Equatable, Hashable, Sendable {
    let id: UUID
    var name: String
    var progressionIDs: [UUID]
    var savedAt: Date

    init(id: UUID = UUID(), name: String, progressionIDs: [UUID], savedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.progressionIDs = progressionIDs
        self.savedAt = savedAt
    }
}

// MARK: - Export

struct ChordyxExportFile: Codable, Sendable {
    static let currentVersion = 1
    var version: Int
    var progression: SavedProgression

    init(progression: SavedProgression, version: Int = Self.currentVersion) {
        self.version = version
        self.progression = progression
    }
}

struct ChordyxSetlistExportFile: Codable, Sendable {
    static let currentVersion = 1
    var version: Int
    var pack: ChordyxSetlistPack

    init(pack: ChordyxSetlistPack, version: Int = Self.currentVersion) {
        self.version = version
        self.pack = pack
    }
}

// MARK: - Discovery & connection

struct DiscoveredHost: Identifiable, Equatable, Sendable {
    let peer: MCPeerID
    let sessionName: String
    let key: MusicalKey?
    let tempoBPM: Int?
    let sessionToken: UUID?
    var id: String { peer.displayName }

    var subtitle: String {
        var parts: [String] = ["Host: \(peer.displayName)"]
        if let key { parts.append("Key \(key.displayName)") }
        if let tempoBPM { parts.append("\(tempoBPM) BPM") }
        return parts.joined(separator: " · ")
    }
}

struct PendingJoinRequest: Identifiable, Equatable, Sendable {
    let peer: MCPeerID
    let receivedAt: Date
    var id: String { peer.displayName }
}

enum SyncQuality: String, Codable, Sendable {
    case unknown
    case good
    case fair
    case poor
    case remote

    var label: String {
        switch self {
        case .unknown: String(localized: "Syncing…")
        case .good: String(localized: "Sync OK")
        case .fair: String(localized: "Sync fair")
        case .poor: String(localized: "Sync weak")
        case .remote: String(localized: "Internet backup")
        }
    }

    static func from(roundTripSeconds: Double?) -> SyncQuality {
        guard let rtt = roundTripSeconds, rtt.isFinite else { return .unknown }
        if rtt < 0.08 { return .good }
        if rtt < 0.2 { return .fair }
        return .poor
    }
}

// MARK: - Nashville numbers

enum NashvilleDisplay {
    static let inlineTokens = ["sus4", "sus2", "dim", "aug", "maj", "sus", "m"]

    private static let superscriptDigits: [Character: Character] = [
        "0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴",
        "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹"
    ]

    /// Formats a Nashville string so extension digits use unicode superscripts (57 → 5⁷).
    static func format(_ nashville: String) -> String {
        nashville
            .split(separator: "/", omittingEmptySubsequences: false)
            .map { formatPart(String($0)) }
            .joined(separator: "/")
    }

    static func makeAttributed(
        _ nashville: String,
        font: Font,
        size: CGFloat
    ) -> AttributedString {
        nashville
            .split(separator: "/", omittingEmptySubsequences: false)
            .enumerated()
            .reduce(into: AttributedString()) { result, item in
                if item.offset > 0 {
                    result.append(attributed("/", font: font))
                }
                result.append(formatPartAttributed(String(item.element), font: font, size: size))
            }
    }

    private static func formatPart(_ part: String) -> String {
        let (degree, suffix) = splitDegree(from: part)
        guard !degree.isEmpty else { return part }
        return degree + formatSuffix(suffix)
    }

    private static func formatPartAttributed(_ part: String, font: Font, size: CGFloat) -> AttributedString {
        let (degree, suffix) = splitDegree(from: part)
        guard !degree.isEmpty else {
            return attributed(part, font: font)
        }
        var result = attributed(degree, font: font)
        result.append(formatSuffixAttributed(suffix, font: font, size: size))
        return result
    }

    private static func splitDegree(from part: String) -> (degree: String, suffix: String) {
        var index = part.startIndex
        var degree = ""

        if index < part.endIndex, part[index] == "b" || part[index] == "#" {
            degree.append(part[index])
            index = part.index(after: index)
        }
        while index < part.endIndex, part[index].isASCII, part[index].isNumber {
            degree.append(part[index])
            index = part.index(after: index)
        }
        return (degree, String(part[index...]))
    }

    private static func formatSuffix(_ suffix: String) -> String {
        guard !suffix.isEmpty else { return "" }

        var result = ""
        var remaining = suffix[...]

        while !remaining.isEmpty {
            let lower = remaining.lowercased()
            if let token = inlineTokens.first(where: { lower.hasPrefix($0) }) {
                result += String(remaining.prefix(token.count))
                remaining = remaining.dropFirst(token.count)
                continue
            }

            if let first = remaining.first, first.isASCII, first.isNumber {
                var end = remaining.startIndex
                while end < remaining.endIndex, remaining[end].isASCII, remaining[end].isNumber {
                    end = remaining.index(after: end)
                }
                result += superscriptDigits(in: String(remaining[..<end]))
                remaining = remaining[end...]
                continue
            }

            var end = remaining.startIndex
            while end < remaining.endIndex {
                let next = remaining.index(after: end)
                let tail = remaining[next...]
                if tail.first?.isASCII == true, tail.first?.isNumber == true { break }
                if inlineTokens.contains(where: { tail.lowercased().hasPrefix($0) }) { break }
                end = next
            }
            result += String(remaining[..<end])
            remaining = remaining[end...]
        }

        return result
    }

    private static func formatSuffixAttributed(_ suffix: String, font: Font, size: CGFloat) -> AttributedString {
        guard !suffix.isEmpty else { return AttributedString() }

        var result = AttributedString()
        var remaining = suffix[...]

        while !remaining.isEmpty {
            let lower = remaining.lowercased()
            if let token = inlineTokens.first(where: { lower.hasPrefix($0) }) {
                let end = remaining.index(remaining.startIndex, offsetBy: token.count)
                result.append(attributed(String(remaining[..<end]), font: font))
                remaining = remaining[end...]
                continue
            }

            if let first = remaining.first, first.isASCII, first.isNumber {
                var end = remaining.startIndex
                while end < remaining.endIndex, remaining[end].isASCII, remaining[end].isNumber {
                    end = remaining.index(after: end)
                }
                result.append(superscriptAttributed(String(remaining[..<end]), size: size))
                remaining = remaining[end...]
                continue
            }

            var end = remaining.startIndex
            while end < remaining.endIndex {
                let next = remaining.index(after: end)
                let tail = remaining[next...]
                if tail.first?.isASCII == true, tail.first?.isNumber == true { break }
                if inlineTokens.contains(where: { tail.lowercased().hasPrefix($0) }) { break }
                end = next
            }
            result.append(attributed(String(remaining[..<end]), font: font))
            remaining = remaining[end...]
        }

        return result
    }

    private static func superscriptDigits(in text: String) -> String {
        String(text.map { superscriptDigits[$0] ?? $0 })
    }

    private static func attributed(_ string: String, font: Font) -> AttributedString {
        var text = AttributedString(string)
        var attributes = AttributeContainer()
        attributes.font = font
        text.mergeAttributes(attributes)
        return text
    }

    private static func superscriptAttributed(_ text: String, size: CGFloat) -> AttributedString {
        var attributed = AttributedString(superscriptDigits(in: text))
        var attributes = AttributeContainer()
        attributes.font = .system(size: size * 0.52, weight: .semibold, design: .rounded)
        attributes.baselineOffset = size * 0.38
        attributed.mergeAttributes(attributes)
        return attributed
    }
}

private extension Character {
    var isASCII: Bool {
        unicodeScalars.allSatisfy { $0.isASCII }
    }
}

enum NashvilleConverter {
    private static let majorDegrees: [Int: String] = [
        0: "1", 2: "2", 4: "3", 5: "4", 7: "5", 9: "6", 11: "7"
    ]

    static func number(for symbol: String, in key: MusicalKey) -> String {
        let raw: String
        if let (root, suffix) = Transposer.parse(symbol),
           let rootPC = Transposer.pitchClass(ofRoot: root) {
            let interval = ((rootPC - key.pitchClass) % 12 + 12) % 12
            let degree = majorDegrees[interval] ?? accidentalDegree(interval)
            let quality = qualitySuffix(suffix)
            raw = degree + quality
        } else if isNashvilleLiteral(symbol) {
            raw = symbol
        } else {
            return symbol
        }
        return NashvilleDisplay.format(raw)
    }

    private static func isNashvilleLiteral(_ symbol: String) -> Bool {
        guard let first = symbol.first else { return false }
        return first.isNumber || first == "b" || first == "#"
    }

    private static func accidentalDegree(_ interval: Int) -> String {
        if let lower = majorDegrees[interval - 1] { return "b\(lower)" }
        if let higher = majorDegrees[interval + 1] { return "#\(higher)" }
        return "\(interval)"
    }

    private static func qualitySuffix(_ suffix: String) -> String {
        let s = suffix.lowercased()
        if s.isEmpty { return "" }
        if s.contains("dim") || s.contains("°") { return "dim" }
        if s.hasPrefix("aug") || s.hasPrefix("+") { return "aug" }
        if s.hasPrefix("sus2") { return "sus2" }
        if s.hasPrefix("sus4") || s == "sus" { return "sus4" }
        if (s.hasPrefix("m") && !s.hasPrefix("maj")) || s.hasPrefix("min") {
            return "m" + suffix.drop(while: { $0 == "m" || $0 == "i" || $0 == "n" })
        }
        return suffix
    }
}
