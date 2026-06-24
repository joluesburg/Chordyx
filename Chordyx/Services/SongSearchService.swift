//
//  SongSearchService.swift
//  Chordyx
//

import Foundation

struct SongSearchResult: Identifiable, Sendable, Equatable {
    let id: String
    let title: String
    let artist: String
    let url: URL
    let sourceName: String
    let relevanceScore: Double

    var subtitle: String { "\(artist) · \(sourceName)" }
}

enum SongSearchError: LocalizedError {
    case emptyQuery
    case noResults

    var errorDescription: String? {
        switch self {
        case .emptyQuery: String(localized: "Enter a song title to search.")
        case .noResults: String(localized: "No chord charts found. Try adding the artist name or paste a link instead.")
        }
    }
}

enum SongSearchService {

    private static let desktopUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    private static let laCuerdaHosts = [
        "acordes.lacuerda.net",
        "chords.lacuerda.net",
        "cifras.lacuerda.net",
    ]

    static func search(title: String, artist: String?) async throws -> [SongSearchResult] {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { throw SongSearchError.emptyQuery }

        let query = buildQuery(title: trimmedTitle, artist: artist)
        var collected: [SongSearchResult] = []

        await withTaskGroup(of: [SongSearchResult].self) { group in
            for host in laCuerdaHosts {
                group.addTask {
                    await searchLaCuerda(host: host, query: query, title: trimmedTitle, artist: artist)
                }
            }
            for await batch in group {
                collected.append(contentsOf: batch)
            }
        }

        collected = dedupe(collected)
        collected.sort { $0.relevanceScore > $1.relevanceScore }

        guard !collected.isEmpty else { throw SongSearchError.noResults }
        return Array(collected.prefix(20))
    }

    private static func buildQuery(title: String, artist: String?) -> String {
        let trimmedArtist = artist?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmedArtist.isEmpty { return title }
        return "\(title) \(trimmedArtist)"
    }

    private static func searchLaCuerda(
        host: String,
        query: String,
        title: String,
        artist: String?
    ) async -> [SongSearchResult] {
        guard var components = URLComponents(string: "https://\(host)/busca.php") else { return [] }
        components.queryItems = [
            URLQueryItem(name: "exp", value: query),
            URLQueryItem(name: "canc", value: "0"),
        ]
        guard let url = components.url else { return [] }

        do {
            let html = try await downloadHTML(from: url)
            let labels = parseResultLabels(from: html)
            let slugs = parseSlugPairs(from: html)
            let source = laCuerdaSourceName(for: host)

            return slugs.enumerated().compactMap { index, pair in
                let label: (artist: String, title: String)
                if index < labels.count {
                    label = labels[index]
                } else {
                    label = (humanizeSlug(pair.artistSlug), humanizeSlug(pair.songSlug))
                }
                guard let songURL = URL(string: "https://\(host)/\(pair.artistSlug)/\(pair.songSlug)") else {
                    return nil
                }
                let score = relevanceScore(
                    queryTitle: title,
                    queryArtist: artist,
                    resultTitle: label.title,
                    resultArtist: label.artist
                )
                return SongSearchResult(
                    id: "\(host)-\(pair.artistSlug)-\(pair.songSlug)",
                    title: label.title,
                    artist: label.artist,
                    url: songURL,
                    sourceName: source,
                    relevanceScore: score
                )
            }
        } catch {
            return []
        }
    }

    private static func laCuerdaSourceName(for host: String) -> String {
        if host.hasPrefix("chords.") { return "La Cuerda (EN)" }
        if host.hasPrefix("cifras.") { return "La Cuerda (PT)" }
        return "La Cuerda"
    }

    private static func parseSlugPairs(from html: String) -> [(artistSlug: String, songSlug: String)] {
        guard let artistSlugs = extractJSStringArray(from: html, name: "hds"),
              let songSlugs = extractJSStringArray(from: html, name: "fns") else { return [] }
        return zip(artistSlugs, songSlugs).map { ($0.0, $0.1) }
    }

    private static func parseResultLabels(from html: String) -> [(artist: String, title: String)] {
        let pattern = #"(?is)<a href="/([^/]+)/">([^<]+)</a></td><td><ul[^>]*>\s*<li[^>]*>\s*<a href="javascript:">([^<]+)</a>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        let range = NSRange(html.startIndex..., in: html)
        return regex.matches(in: html, range: range).compactMap { match in
            guard let artistRange = Range(match.range(at: 2), in: html),
                  let titleRange = Range(match.range(at: 3), in: html) else { return nil }
            let artist = decodeHTMLEntities(String(html[artistRange]).trimmingCharacters(in: .whitespacesAndNewlines))
            let title = decodeHTMLEntities(String(html[titleRange]).trimmingCharacters(in: .whitespacesAndNewlines))
            return (artist, title)
        }
    }

    private static func extractJSStringArray(from html: String, name: String) -> [String]? {
        let pattern = "var \(name)=\\[(.*?)\\];"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let arrayRange = Range(match.range(at: 1), in: html) else { return nil }

        let body = String(html[arrayRange])
        let tokenPattern = #"'([^']*)'|"([^"]*)""#
        guard let tokenRegex = try? NSRegularExpression(pattern: tokenPattern) else { return nil }

        return tokenRegex.matches(in: body, range: NSRange(body.startIndex..., in: body)).compactMap { tokenMatch in
            for group in 1...2 {
                if let r = Range(tokenMatch.range(at: group), in: body), !body[r].isEmpty {
                    return String(body[r])
                }
            }
            return nil
        }
    }

    private static func relevanceScore(
        queryTitle: String,
        queryArtist: String?,
        resultTitle: String,
        resultArtist: String
    ) -> Double {
        var score = tokenOverlap(normalize(queryTitle), normalize(resultTitle)) * 100
        if let queryArtist, !queryArtist.isEmpty {
            score += tokenOverlap(normalize(queryArtist), normalize(resultArtist)) * 90
        }
        if normalize(queryTitle) == normalize(resultTitle) { score += 25 }
        if let queryArtist, normalize(queryArtist) == normalize(resultArtist) { score += 25 }
        return score
    }

    private static func tokenOverlap(_ lhs: String, _ rhs: String) -> Double {
        let left = Set(lhs.split(separator: " ").filter { $0.count > 1 })
        let right = Set(rhs.split(separator: " ").filter { $0.count > 1 })
        guard !left.isEmpty, !right.isEmpty else { return lhs == rhs ? 1 : 0 }
        let intersection = left.intersection(right).count
        let union = left.union(right).count
        return union == 0 ? 0 : Double(intersection) / Double(union)
    }

    private static func normalize(_ text: String) -> String {
        text.folding(options: .diacriticInsensitive, locale: .current)
            .lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func dedupe(_ results: [SongSearchResult]) -> [SongSearchResult] {
        var seen: Set<String> = []
        return results.filter { result in
            let key = result.url.absoluteString.lowercased()
            guard !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
    }

    private static func downloadHTML(from url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.setValue(desktopUserAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...399).contains(http.statusCode) else {
            throw SongImportError.downloadFailed
        }
        if let html = String(data: data, encoding: .utf8) { return html }
        if let html = String(data: data, encoding: .isoLatin1) { return html }
        throw SongImportError.downloadFailed
    }

    private static func humanizeSlug(_ slug: String) -> String {
        slug.replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .capitalized
    }

    private static func decodeHTMLEntities(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&#39;", with: "'")
    }
}
