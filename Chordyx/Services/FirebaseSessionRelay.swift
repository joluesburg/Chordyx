//
//  FirebaseSessionRelay.swift
//  Chordyx
//

import Foundation
import Observation

/// Internet session relay using Firebase Realtime Database REST API (no SDK required).
@MainActor
@Observable
final class FirebaseSessionRelay {
    private static let sessionLifetime: TimeInterval = 8 * 60 * 60

    private let databaseURL: URL
    private let session: URLSession
    private var pollTask: Task<Void, Never>?
    private var controlPollTask: Task<Void, Never>?
    private var publishTask: Task<Void, Never>?
    private var lastPublishedRevision = 0
    private var processedControlKeys: Set<String> = []

    private(set) var isAvailable = false
    private(set) var isPolling = false
    private(set) var isPublishing = false
    private(set) var lastError: String?
    private(set) var lastSuccessfulPublishAt: Date?

    var onPayloadReceived: ((SessionSyncPayload) -> Void)?
    var onControlRequest: ((SessionControlAction, String) -> Void)?

    init(databaseURL: URL, session: URLSession = .shared) {
        self.databaseURL = databaseURL
        self.session = session
        isAvailable = true
    }

    func clearError() {
        lastError = nil
    }

    func refreshAccountStatus() async {
        isAvailable = true
    }

    func beginHosting(joinCode: String, sessionToken: UUID) {
        isPublishing = true
        startControlPolling(joinCode: joinCode)
        Task {
            await ensureSessionRecord(joinCode: joinCode, sessionToken: sessionToken)
        }
    }

    func schedulePublish(payload: SessionSyncPayload, joinCode: String, debounceMs: Int = 350) {
        guard isPublishing else { return }
        let revision = lastPublishedRevision + 1
        lastPublishedRevision = revision
        publishTask?.cancel()
        publishTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(debounceMs))
            guard !Task.isCancelled, let self else { return }
            await self.publish(payload: payload, joinCode: joinCode, revision: revision)
        }
    }

    func stopPublishingOnly() {
        isPublishing = false
        publishTask?.cancel()
        publishTask = nil
        controlPollTask?.cancel()
        controlPollTask = nil
    }

    func publish(payload: SessionSyncPayload, joinCode: String, revision: Int? = nil) async {
        guard isPublishing else { return }
        if let revision, revision != lastPublishedRevision { return }

        var guestPayload = payload
        guestPayload.isHost = false
        // Keep piano notes so guests in Piano Keys mode can follow the host's MIDI.

        guard let data = try? JSONEncoder().encode(guestPayload) else { return }

        let record = InternetSessionRecord(
            joinCode: RemoteJoinCode.normalize(joinCode),
            sessionToken: payload.sessionToken.uuidString,
            hostName: SessionManager.currentDisplayName(),
            sessionName: payload.sessionName,
            payloadData: data,
            updatedAt: Date(),
            expiresAt: Date().addingTimeInterval(Self.sessionLifetime)
        )

        do {
            try await putJSON(record, path: sessionPath(for: joinCode))
            lastError = nil
            lastSuccessfulPublishAt = Date()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func stopHosting(joinCode: String) async {
        isPublishing = false
        publishTask?.cancel()
        publishTask = nil
        controlPollTask?.cancel()
        controlPollTask = nil
        processedControlKeys.removeAll()
        _ = try? await delete(path: sessionPath(for: joinCode))
    }

    func fetchSession(joinCode: String) async -> SessionSyncPayload? {
        let code = RemoteJoinCode.normalize(joinCode)
        guard RemoteJoinCode.isValid(code) else {
            lastError = String(localized: "Enter a 6-character join code.")
            return nil
        }

        do {
            guard let record: InternetSessionRecord = try await getJSON(path: sessionPath(for: code)) else {
                lastError = String(localized: "No live session found for that code.")
                return nil
            }
            if record.expiresAt < Date() {
                lastError = String(localized: "That session has expired.")
                return nil
            }
            guard let payload = try? JSONDecoder().decode(SessionSyncPayload.self, from: record.payloadData) else {
                lastError = String(localized: "No live session found for that code.")
                return nil
            }
            lastError = nil
            return payload
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    func startPolling(joinCode: String) {
        let code = RemoteJoinCode.normalize(joinCode)
        guard RemoteJoinCode.isValid(code) else { return }
        pollTask?.cancel()
        isPolling = true
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.pollOnce(joinCode: code)
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
        isPolling = false
    }

    func stopAll() {
        stopPolling()
        publishTask?.cancel()
        publishTask = nil
        controlPollTask?.cancel()
        controlPollTask = nil
        isPublishing = false
        processedControlKeys.removeAll()
    }

    func sendControl(action: SessionControlAction, joinCode: String, guestName: String) async {
        guard let data = try? JSONEncoder().encode(action) else { return }
        let code = RemoteJoinCode.normalize(joinCode)
        let controlID = UUID().uuidString
        let record = InternetControlRecord(
            joinCode: code,
            guestName: guestName,
            actionData: data,
            createdAt: Date()
        )
        _ = try? await putJSON(record, path: "controls/\(code)/\(controlID).json")
    }

    private func pollOnce(joinCode: String) async {
        guard let payload = await fetchSession(joinCode: joinCode) else { return }
        onPayloadReceived?(payload)
    }

    private func ensureSessionRecord(joinCode: String, sessionToken: UUID) async {
        let placeholder = InternetSessionRecord(
            joinCode: RemoteJoinCode.normalize(joinCode),
            sessionToken: sessionToken.uuidString,
            hostName: SessionManager.currentDisplayName(),
            sessionName: nil,
            payloadData: Data(),
            updatedAt: Date(),
            expiresAt: Date().addingTimeInterval(Self.sessionLifetime)
        )
        do {
            try await putJSON(placeholder, path: sessionPath(for: joinCode))
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func startControlPolling(joinCode: String) {
        controlPollTask?.cancel()
        processedControlKeys.removeAll()
        controlPollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.pollControlRequests(joinCode: joinCode)
                try? await Task.sleep(for: .seconds(1.2))
            }
        }
    }

    private func pollControlRequests(joinCode: String) async {
        let code = RemoteJoinCode.normalize(joinCode)
        let path = "controls/\(code).json"
        do {
            guard let controls: [String: InternetControlRecord] = try await getJSON(path: path) else { return }
            for (key, record) in controls {
                guard !processedControlKeys.contains(key),
                      let action = try? JSONDecoder().decode(SessionControlAction.self, from: record.actionData) else {
                    continue
                }
                processedControlKeys.insert(key)
                onControlRequest?(action, record.guestName)
                _ = try? await delete(path: "\(path)/\(key)")
            }
        } catch {
            // Control polling is best-effort.
        }
    }

    private func sessionPath(for joinCode: String) -> String {
        "sessions/\(RemoteJoinCode.normalize(joinCode)).json"
    }

    private func putJSON<T: Encodable>(_ value: T, path: String) async throws {
        let url = url(for: path)
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(value)
        let (_, response) = try await session.data(for: request)
        try validateHTTPResponse(response)
    }

    private func getJSON<T: Decodable>(path: String) async throws -> T? {
        let url = url(for: path)
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        if http.statusCode == 404 { return nil }
        try validateHTTPResponse(response)
        if data.isEmpty || String(data: data, encoding: .utf8) == "null" { return nil }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func delete(path: String) async throws {
        let url = url(for: path)
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        let (_, response) = try await session.data(for: request)
        try validateHTTPResponse(response)
    }

    private func validateHTTPResponse(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    private func url(for path: String) -> URL {
        var base = databaseURL.absoluteString
        if base.hasSuffix("/") {
            base.removeLast()
        }
        return URL(string: "\(base)/\(path)")!
    }
}
