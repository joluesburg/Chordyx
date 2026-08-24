//
//  CloudKitSessionRelay.swift
//  Chordyx
//

import CloudKit
import Foundation

/// Publishes and subscribes to live session state through CloudKit when local Wi‑Fi is unavailable.
@MainActor
final class CloudKitSessionRelay {
    static let containerIdentifier = "iCloud.Espinosa.Chordyx"
    private static let sessionRecordType = "ChordyxLiveSession"
    private static let controlRecordType = "ChordyxControlRequest"
    private static let sessionLifetime: TimeInterval = 8 * 60 * 60

    /// Lazily created — CKContainer during SessionViewModel init froze iPhone Loading….
    private var containerStorage: CKContainer?
    private var container: CKContainer {
        if let containerStorage { return containerStorage }
        let created = CKContainer(identifier: Self.containerIdentifier)
        containerStorage = created
        return created
    }
    private var pollTask: Task<Void, Never>?
    private var controlPollTask: Task<Void, Never>?
    private var publishTask: Task<Void, Never>?
    private var lastPublishedRevision = 0
    /// Skip identical cloud payloads so guests don't re-apply the same state every poll.
    private var lastPolledPayloadData: Data?
    private var idlePollStreak = 0

    private(set) var isAvailable = false
    private(set) var isPolling = false
    /// Host is actively trying to publish session updates to iCloud.
    private(set) var isPublishing = false
    private(set) var lastError: String?
    private(set) var isCloudKitConfigured = true
    private(set) var lastSuccessfulPublishAt: Date?

    var onPayloadReceived: ((SessionSyncPayload) -> Void)?
    var onControlRequest: ((SessionControlAction, String) -> Void)?

    init() {}

    func clearError() {
        lastError = nil
    }

    func refreshAccountStatus() async {
        do {
            let status = try await container.accountStatus()
            isAvailable = status == .available
            if !isAvailable {
                lastError = String(localized: "Sign in to iCloud on this device to use Internet backup.")
            }
        } catch {
            isAvailable = false
            lastError = error.localizedDescription
        }
    }

    func beginHosting(joinCode: String, sessionToken: UUID) {
        isPublishing = true
        startControlPolling(joinCode: joinCode)
        Task {
            if !isAvailable { await refreshAccountStatus() }
            guard isAvailable else { return }
            await ensureSessionRecord(joinCode: joinCode, sessionToken: sessionToken)
        }
    }

    func schedulePublish(payload: SessionSyncPayload, joinCode: String, debounceMs: Int = 100) {
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

    /// Stops publishing without deleting the cloud record so the band can rejoin after a brief host restart.
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
        if !isAvailable { await refreshAccountStatus() }
        guard isAvailable else { return }

        var guestPayload = payload
        guestPayload.isHost = false
        // Keep piano notes so guests in Piano Keys mode can follow the host's MIDI.

        guard let data = try? JSONEncoder().encode(guestPayload) else {
            lastError = String(localized: "Could not prepare session data for Internet backup.")
            return
        }

        let recordID = sessionRecordID(for: joinCode)
        do {
            let record: CKRecord
            if let existing = try? await fetchRecord(id: recordID) {
                record = existing
            } else {
                record = CKRecord(recordType: Self.sessionRecordType, recordID: recordID)
                record["joinCode"] = RemoteJoinCode.normalize(joinCode) as CKRecordValue
                record["sessionToken"] = payload.sessionToken.uuidString as CKRecordValue
                record["hostName"] = SessionManager.currentDisplayName() as CKRecordValue
            }
            record["payloadData"] = data as CKRecordValue
            record["sessionName"] = payload.sessionName as CKRecordValue
            record["updatedAt"] = Date() as CKRecordValue
            record["expiresAt"] = Date().addingTimeInterval(Self.sessionLifetime) as CKRecordValue
            _ = try await saveRecord(record)
            lastError = nil
            isCloudKitConfigured = true
            lastSuccessfulPublishAt = Date()
        } catch {
            lastError = friendlyErrorMessage(for: error)
            if isProductionSchemaError(error) {
                isCloudKitConfigured = false
            }
        }
    }

    func stopHosting(joinCode: String) async {
        isPublishing = false
        publishTask?.cancel()
        publishTask = nil
        controlPollTask?.cancel()
        controlPollTask = nil
        let recordID = sessionRecordID(for: joinCode)
        do {
            try await container.publicCloudDatabase.deleteRecord(withID: recordID)
        } catch {
            // Best effort — sessions also expire automatically.
        }
    }

    func fetchSession(joinCode: String, deliverOnlyIfChanged: Bool = false) async -> SessionSyncPayload? {
        await refreshAccountStatus()
        guard isAvailable else { return nil }
        let code = RemoteJoinCode.normalize(joinCode)
        guard RemoteJoinCode.isValid(code) else {
            lastError = String(localized: "Enter a 6-character join code.")
            return nil
        }
        do {
            guard let record = try await fetchRecord(id: sessionRecordID(for: code)) else {
                lastError = String(localized: "No live session found for that code. Ask the host to wait for the green checkmark on their join code.")
                return nil
            }

            if let expiresAt = record["expiresAt"] as? Date, expiresAt < Date() {
                lastError = String(localized: "That session has expired.")
                return nil
            }

            guard let data = record["payloadData"] as? Data, !data.isEmpty else {
                lastError = String(localized: "Host is still connecting to iCloud. Wait for the green checkmark, then try again.")
                return nil
            }

            if deliverOnlyIfChanged, data == lastPolledPayloadData {
                lastError = nil
                return nil
            }

            guard let payload = try? JSONDecoder().decode(SessionSyncPayload.self, from: data) else {
                lastError = String(localized: "Could not read session data. Ask the host to restart the session.")
                return nil
            }

            lastPolledPayloadData = data
            lastError = nil
            return payload
        } catch let error as CKError where error.code == .unknownItem {
            lastError = String(localized: "No live session found for that code. Ask the host to wait for the green checkmark on their join code.")
            return nil
        } catch {
            lastError = friendlyErrorMessage(for: error)
            return nil
        }
    }

    func startPolling(joinCode: String) {
        let code = RemoteJoinCode.normalize(joinCode)
        guard RemoteJoinCode.isValid(code) else { return }
        pollTask?.cancel()
        isPolling = true
        lastPolledPayloadData = nil
        idlePollStreak = 0
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                let changed = await self?.pollOnce(joinCode: code) ?? false
                guard let self, !Task.isCancelled else { return }
                let delayMs: UInt64
                if changed {
                    self.idlePollStreak = 0
                    // Hot path after a chord change — check again quickly.
                    delayMs = 80
                } else {
                    self.idlePollStreak = min(self.idlePollStreak + 1, 6)
                    // Back off while idle so a full band doesn't hammer CloudKit.
                    switch self.idlePollStreak {
                    case 0...1: delayMs = 110
                    case 2...3: delayMs = 180
                    default: delayMs = 280
                    }
                }
                try? await Task.sleep(for: .milliseconds(delayMs))
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
        isPolling = false
        lastPolledPayloadData = nil
        idlePollStreak = 0
    }

    func stopAll() {
        stopPolling()
        publishTask?.cancel()
        publishTask = nil
        controlPollTask?.cancel()
        controlPollTask = nil
        isPublishing = false
    }

    func sendControl(action: SessionControlAction, joinCode: String, guestName: String) async {
        guard isAvailable else { return }
        guard let data = try? JSONEncoder().encode(action) else { return }
        let code = RemoteJoinCode.normalize(joinCode)
        let recordID = CKRecord.ID(recordName: "ctrl-\(code)-\(UUID().uuidString)")
        let record = CKRecord(recordType: Self.controlRecordType, recordID: recordID)
        record["joinCode"] = code as CKRecordValue
        record["guestName"] = guestName as CKRecordValue
        record["actionData"] = data as CKRecordValue
        record["createdAt"] = Date() as CKRecordValue
        _ = try? await saveRecord(record)
    }

    /// Returns `true` when a newer payload was delivered to the guest.
    @discardableResult
    private func pollOnce(joinCode: String) async -> Bool {
        guard let payload = await fetchSession(joinCode: joinCode, deliverOnlyIfChanged: true) else {
            return false
        }
        onPayloadReceived?(payload)
        return true
    }

    private func ensureSessionRecord(joinCode: String, sessionToken: UUID) async {
        let record = makeSessionRecord(joinCode: joinCode, sessionToken: sessionToken, payloadData: nil)
        do {
            _ = try await saveRecord(record)
            lastError = nil
            isCloudKitConfigured = true
            lastSuccessfulPublishAt = Date()
        } catch {
            lastError = friendlyErrorMessage(for: error)
            if isProductionSchemaError(error) {
                isCloudKitConfigured = false
            }
        }
    }

    private func startControlPolling(joinCode: String) {
        controlPollTask?.cancel()
        controlPollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.pollControlRequests(joinCode: joinCode)
                try? await Task.sleep(for: .seconds(1.2))
            }
        }
    }

    private func pollControlRequests(joinCode: String) async {
        let code = RemoteJoinCode.normalize(joinCode)
        let predicate = NSPredicate(format: "joinCode == %@", code)
        let query = CKQuery(recordType: Self.controlRecordType, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]

        do {
            let (matchResults, _) = try await container.publicCloudDatabase.records(matching: query)
            for (recordID, result) in matchResults {
                guard case .success(let record) = result,
                      let guestName = record["guestName"] as? String,
                      let data = record["actionData"] as? Data,
                      let action = try? JSONDecoder().decode(SessionControlAction.self, from: data) else {
                    continue
                }
                onControlRequest?(action, guestName)
                _ = try? await container.publicCloudDatabase.deleteRecord(withID: recordID)
            }
        } catch {
            // Control polling is best-effort.
        }
    }

    private func sessionRecordID(for joinCode: String) -> CKRecord.ID {
        CKRecord.ID(recordName: "session-\(RemoteJoinCode.normalize(joinCode))")
    }

    private func makeSessionRecord(
        joinCode: String,
        sessionToken: UUID,
        payloadData: Data?
    ) -> CKRecord {
        let normalized = RemoteJoinCode.normalize(joinCode)
        let record = CKRecord(recordType: Self.sessionRecordType, recordID: sessionRecordID(for: joinCode))
        record["joinCode"] = normalized as CKRecordValue
        record["sessionToken"] = sessionToken.uuidString as CKRecordValue
        record["hostName"] = SessionManager.currentDisplayName() as CKRecordValue
        record["updatedAt"] = Date() as CKRecordValue
        record["expiresAt"] = Date().addingTimeInterval(Self.sessionLifetime) as CKRecordValue
        if let payloadData {
            record["payloadData"] = payloadData as CKRecordValue
        }
        return record
    }

    private func fetchRecord(id: CKRecord.ID) async throws -> CKRecord? {
        do {
            return try await container.publicCloudDatabase.record(for: id)
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
    }

    private func saveRecord(_ record: CKRecord) async throws -> CKRecord {
        try await container.publicCloudDatabase.save(record)
    }

    func isProductionSchemaError(_ error: Error) -> Bool {
        let message = error.localizedDescription.lowercased()
        return message.contains("production schema") || message.contains("cannot create new type")
    }

    private func friendlyErrorMessage(for error: Error) -> String {
        if isProductionSchemaError(error) {
            if InternetRelayConfiguration.hasFirebaseFallback {
                return String(localized: "Switching to Internet backup…")
            }
            return String(localized: "Internet backup is not active on iCloud yet. The host must finish one-time iCloud setup, or use the same Wi‑Fi with Nearby.")
        }

        if let ckError = error as? CKError {
            switch ckError.code {
            case .notAuthenticated:
                return String(localized: "Sign in to iCloud in Settings to use Internet join codes.")
            case .networkUnavailable, .networkFailure, .serviceUnavailable, .zoneBusy:
                return String(localized: "No Internet connection to iCloud. Check cellular data and try again.")
            case .permissionFailure:
                return String(localized: "iCloud permission denied. Sign in to iCloud and try again.")
            default:
                break
            }
        }

        return error.localizedDescription
    }
}
