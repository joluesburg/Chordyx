//
//  SongImportService.swift
//  Chordyx
//

import Foundation

@MainActor
@Observable
final class SongImportService {
    var isLoading = false
    var draft: SongImportDraft?
    var errorMessage: String?
    var searchResults: [SongSearchResult] = []
    var isSearching = false

    private static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    func reset() {
        draft = nil
        errorMessage = nil
        searchResults = []
        isLoading = false
        isSearching = false
    }

    func search(title: String, artist: String?) async {
        isSearching = true
        errorMessage = nil
        searchResults = []
        draft = nil
        defer { isSearching = false }

        do {
            searchResults = try await SongSearchService.search(title: title, artist: artist)
        } catch let error as SongSearchError {
            errorMessage = error.localizedDescription
        } catch let error as LocalizedError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = SongSearchError.noResults.localizedDescription
        }
    }

    func importSearchResult(_ result: SongSearchResult) async {
        await importFromURL(result.url.absoluteString)
    }

    /// Search only — caller previews a result before importing.
    func findCharts(title: String, artist: String?) async {
        await search(title: title, artist: artist)
    }

    func importFromURL(_ rawURL: String) async {
        guard let url = SongImportParser.normalizeURL(rawURL) else {
            errorMessage = SongImportError.invalidURL.localizedDescription
            return
        }

        isLoading = true
        errorMessage = nil
        draft = nil
        defer { isLoading = false }

        do {
            let html = try await downloadHTML(from: url)
            draft = try SongImportParser.parseDownloadedPage(html: html, sourceURL: url)
        } catch let error as SongImportError {
            errorMessage = error.localizedDescription
        } catch {
            errorMessage = SongImportError.downloadFailed.localizedDescription
        }
    }

    func importFromPlainText(_ text: String, title: String) {
        isLoading = true
        errorMessage = nil
        draft = nil
        defer { isLoading = false }

        do {
            draft = try SongImportParser.parsePlainText(text, title: title)
        } catch let error as SongImportError {
            errorMessage = error.localizedDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func downloadHTML(from url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 25

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...399).contains(http.statusCode) else {
            throw SongImportError.downloadFailed
        }
        if let html = String(data: data, encoding: .utf8) { return html }
        if let html = String(data: data, encoding: .isoLatin1) { return html }
        throw SongImportError.downloadFailed
    }
}
