//
//  InternetSessionRelayCoordinator.swift
//  Chordyx
//

import Foundation
import Observation

enum InternetRelayTransport: Equatable, Sendable {
    case cloudKit
    case firebase
}

/// Facade over CloudKit (and optional Firebase) internet session relay.
@MainActor
@Observable
final class InternetSessionRelayCoordinator {
    private let cloudKit = CloudKitSessionRelay()
    private var firebase: FirebaseSessionRelay?
    private var activeTransport: InternetRelayTransport = .cloudKit
    private var hostingJoinCode: String?
    private var hostingSessionToken: UUID?
    private var latestPayload: SessionSyncPayload?
    private var retryTask: Task<Void, Never>?

    private(set) var isAvailable = false
    private(set) var isPolling = false
    private(set) var isPublishing = false
    private(set) var lastError: String?
    private(set) var isCloudKitConfigured = true
    private(set) var activeTransportName: String? = "CloudKit"
    private(set) var isRelayLive = false
    private(set) var lastSuccessfulPublishAt: Date?

    var onPayloadReceived: ((SessionSyncPayload) -> Void)? {
        didSet { wireCallbacks() }
    }
    var onControlRequest: ((SessionControlAction, String) -> Void)? {
        didSet { wireCallbacks() }
    }

    init() {
        wireCallbacks()
        if let url = InternetRelayConfiguration.firebaseDatabaseURL {
            firebase = FirebaseSessionRelay(databaseURL: url)
        }
    }

    private var activeRelayIsCloudKit: Bool { activeTransport == .cloudKit }

    private func wireCallbacks() {
        cloudKit.onPayloadReceived = { [weak self] payload in
            self?.onPayloadReceived?(payload)
        }
        cloudKit.onControlRequest = { [weak self] action, name in
            self?.onControlRequest?(action, name)
        }
        firebase?.onPayloadReceived = { [weak self] payload in
            self?.onPayloadReceived?(payload)
        }
        firebase?.onControlRequest = { [weak self] action, name in
            self?.onControlRequest?(action, name)
        }
    }

    private func syncPublishedState() {
        switch activeTransport {
        case .cloudKit:
            isAvailable = cloudKit.isAvailable
            isPolling = cloudKit.isPolling
            isPublishing = cloudKit.isPublishing
            lastError = cloudKit.lastError
            isCloudKitConfigured = cloudKit.isCloudKitConfigured
            lastSuccessfulPublishAt = cloudKit.lastSuccessfulPublishAt
            activeTransportName = "CloudKit"
            if let at = cloudKit.lastSuccessfulPublishAt {
                isRelayLive = Date().timeIntervalSince(at) < 8
            } else {
                isRelayLive = cloudKit.isPublishing && cloudKit.lastError == nil && cloudKit.isAvailable
            }
        case .firebase:
            guard let firebase else { return }
            isAvailable = firebase.isAvailable
            isPolling = firebase.isPolling
            isPublishing = firebase.isPublishing
            lastError = firebase.lastError
            lastSuccessfulPublishAt = firebase.lastSuccessfulPublishAt
            activeTransportName = "Firebase"
            if let at = firebase.lastSuccessfulPublishAt {
                isRelayLive = Date().timeIntervalSince(at) < 8
            } else {
                isRelayLive = firebase.isPublishing && firebase.lastError == nil
            }
        }
    }

    func clearError() {
        cloudKit.clearError()
        firebase?.clearError()
        lastError = nil
    }

    func refreshAccountStatus() async {
        await cloudKit.refreshAccountStatus()
        await firebase?.refreshAccountStatus()
        evaluateTransportAfterCloudKitProbe()
        syncPublishedState()
    }

    private func evaluateTransportAfterCloudKitProbe() {
        isCloudKitConfigured = cloudKit.isCloudKitConfigured
        if !cloudKit.isCloudKitConfigured, InternetRelayConfiguration.hasFirebaseFallback, firebase != nil {
            // Prefer staying on CloudKit until a publish failure triggers fallback.
        }
        isAvailable = cloudKit.isAvailable || (firebase?.isAvailable ?? false)
    }

    private func switchToFirebase() {
        guard let firebase, InternetRelayConfiguration.hasFirebaseFallback else { return }
        activeTransport = .firebase
        activeTransportName = "Firebase"
        wireCallbacks()
        if let code = hostingJoinCode, let token = hostingSessionToken {
            firebase.beginHosting(joinCode: code, sessionToken: token)
            if let payload = latestPayload {
                firebase.schedulePublish(payload: payload, joinCode: code)
            }
        }
        syncPublishedState()
    }

    private func attemptFallbackIfNeeded(joinCode: String) async {
        guard activeTransport == .cloudKit else { return }
        guard InternetRelayConfiguration.hasFirebaseFallback, firebase != nil else { return }
        if cloudKit.lastError != nil || !cloudKit.isCloudKitConfigured {
            switchToFirebase()
            _ = joinCode
        }
    }

    func beginHosting(joinCode: String, sessionToken: UUID) {
        hostingJoinCode = joinCode
        hostingSessionToken = sessionToken
        activeTransport = .cloudKit
        cloudKit.beginHosting(joinCode: joinCode, sessionToken: sessionToken)
        syncPublishedState()
    }

    func schedulePublish(payload: SessionSyncPayload, joinCode: String, debounceMs: Int = 350) {
        latestPayload = payload
        switch activeTransport {
        case .cloudKit:
            cloudKit.schedulePublish(payload: payload, joinCode: joinCode, debounceMs: debounceMs)
        case .firebase:
            firebase?.schedulePublish(payload: payload, joinCode: joinCode, debounceMs: debounceMs)
        }
        syncPublishedState()
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(900))
            guard let self else { return }
            self.syncPublishedState()
            if !self.isRelayLive {
                await self.attemptFallbackIfNeeded(joinCode: joinCode)
            }
        }
    }

    func publish(payload: SessionSyncPayload, joinCode: String, revision: Int? = nil) async {
        latestPayload = payload
        switch activeTransport {
        case .cloudKit:
            await cloudKit.publish(payload: payload, joinCode: joinCode, revision: revision)
            if !cloudKit.isCloudKitConfigured {
                await attemptFallbackIfNeeded(joinCode: joinCode)
            }
        case .firebase:
            await firebase?.publish(payload: payload, joinCode: joinCode, revision: revision)
        }
        syncPublishedState()
    }

    func fetchSession(joinCode: String) async -> SessionSyncPayload? {
        if let payload = await cloudKit.fetchSession(joinCode: joinCode) {
            activeTransport = .cloudKit
            syncPublishedState()
            return payload
        }
        if let firebase, InternetRelayConfiguration.hasFirebaseFallback {
            if let payload = await firebase.fetchSession(joinCode: joinCode) {
                activeTransport = .firebase
                syncPublishedState()
                return payload
            }
        }
        syncPublishedState()
        return nil
    }

    func startPolling(joinCode: String) {
        switch activeTransport {
        case .cloudKit: cloudKit.startPolling(joinCode: joinCode)
        case .firebase: firebase?.startPolling(joinCode: joinCode)
        }
        syncPublishedState()
    }

    func stopPolling() {
        cloudKit.stopPolling()
        firebase?.stopPolling()
        syncPublishedState()
    }

    func stopPublishingOnly() {
        cloudKit.stopPublishingOnly()
        firebase?.stopPublishingOnly()
        syncPublishedState()
    }

    func stopAll() {
        retryTask?.cancel()
        retryTask = nil
        cloudKit.stopAll()
        firebase?.stopAll()
        hostingJoinCode = nil
        hostingSessionToken = nil
        latestPayload = nil
        syncPublishedState()
    }

    func stopHosting(joinCode: String) async {
        await cloudKit.stopHosting(joinCode: joinCode)
        await firebase?.stopHosting(joinCode: joinCode)
        hostingJoinCode = nil
        hostingSessionToken = nil
        syncPublishedState()
    }

    func sendControl(action: SessionControlAction, joinCode: String, guestName: String) async {
        switch activeTransport {
        case .cloudKit:
            await cloudKit.sendControl(action: action, joinCode: joinCode, guestName: guestName)
        case .firebase:
            await firebase?.sendControl(action: action, joinCode: joinCode, guestName: guestName)
        }
        syncPublishedState()
    }

    func retryHostingNow() async {
        guard let code = hostingJoinCode, let token = hostingSessionToken else { return }
        await refreshAccountStatus()
        beginHosting(joinCode: code, sessionToken: token)
        if let payload = latestPayload {
            schedulePublish(payload: payload, joinCode: code, debounceMs: 0)
        }
        syncPublishedState()
    }
}
