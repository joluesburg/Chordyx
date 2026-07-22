//
//  SessionManager.swift
//  Chordyx
//

import Foundation
import MultipeerConnectivity
import Observation

@Observable
@MainActor
final class SessionManager: NSObject {
    static let serviceType = "chordyx"
    static let displayNameKey = "displayName"
    static let requireHostApprovalKey = "requireHostApproval"

    static func currentDisplayName() -> String {
        let saved = UserDefaults.standard.string(forKey: displayNameKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let saved, !saved.isEmpty {
            return PlatformDevice.sanitizedPeerName(saved)
        }
        return PlatformDevice.defaultDisplayName
    }

    var requireHostApproval: Bool {
        get { UserDefaults.standard.bool(forKey: Self.requireHostApprovalKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.requireHostApprovalKey) }
    }

    var connectedPeers: [MCPeerID] = []
    var discoveredHosts: [DiscoveredHost] = []
    var pendingJoinRequests: [PendingJoinRequest] = []
    var connectionState: ConnectionState = .idle
    var lastError: String?
    var syncQuality: SyncQuality = .unknown

    var clockOffset: Double = 0
    private(set) var hostPeer: MCPeerID?

    var hostPeerDisplayName: String? {
        hostPeer?.displayName ?? connectedPeers.first?.displayName
    }

    private var myPeerID = MCPeerID(displayName: PlatformDevice.defaultDisplayName)
    private var session: MCSession?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var isHost = false
    private var hostingSessionName: String?
    private var hostingKey: MusicalKey = .C
    private var hostingTempoBPM: Int = 100
    private var hostingSessionToken: UUID = UUID()
    private var bestRoundTrip: Double = .infinity
    private var calibrationTask: Task<Void, Never>?
    private var pendingInvitations: [String: (Bool, MCSession?) -> Void] = [:]

    var onPayloadReceived: ((SessionSyncPayload) -> Void)?
    var onPeersUpdated: (([MCPeerID]) -> Void)?
    var onClockOffsetUpdated: (() -> Void)?
    var onControlRequest: ((SessionControlAction, MCPeerID) -> Void)?
    var onGuestDisconnected: (() -> Void)?

    enum ConnectionState: Equatable {
        case idle
        case hosting
        case browsing
        case connected(peerCount: Int)
    }

    func startHosting(
        sessionName: String,
        key: MusicalKey = .C,
        tempoBPM: Int = 100,
        sessionToken: UUID = UUID()
    ) {
        let safeName = PlatformDevice.sanitizedDiscoveryValue(sessionName)
        hostingSessionName = safeName
        hostingKey = key
        hostingTempoBPM = tempoBPM
        hostingSessionToken = sessionToken
        lastError = nil
        // Detached: Local Network permission must not run under MainActor or iPhone UI freezes
        // (Xcode shows "Task … Queue : com.apple.main-thread").
        let serviceType = Self.serviceType
        Task.detached(priority: .userInitiated) { [weak self, safeName] in
            await LocalNetworkPermission.requestAccess(serviceType: serviceType)
            await MainActor.run {
                self?.beginHosting(sessionName: safeName)
            }
        }
    }

    func updateDiscoveryMetadata(key: MusicalKey, tempoBPM: Int, sessionToken: UUID) {
        guard isHost, let sessionName = hostingSessionName else { return }
        guard key != hostingKey || tempoBPM != hostingTempoBPM || sessionToken != hostingSessionToken else { return }
        hostingKey = key
        hostingTempoBPM = tempoBPM
        hostingSessionToken = sessionToken
        refreshAdvertiserDiscoveryInfo(sessionName: sessionName)
    }

    func startBrowsing() {
        lastError = nil
        let serviceType = Self.serviceType
        Task.detached(priority: .userInitiated) { [weak self] in
            await LocalNetworkPermission.requestAccess(serviceType: serviceType)
            await MainActor.run {
                self?.beginBrowsing()
            }
        }
    }

    /// Re-publish the host on macOS if Bonjour advertising was interrupted.
    func refreshHostingIfNeeded() {
        guard isHost, let sessionName = hostingSessionName else { return }
        if session != nil {
            if advertiser == nil {
                refreshAdvertiserDiscoveryInfo(sessionName: sessionName)
            } else {
                advertiser?.stopAdvertisingPeer()
                advertiser?.startAdvertisingPeer()
            }
            return
        }
        beginHosting(sessionName: sessionName)
    }

    private func refreshAdvertiserDiscoveryInfo(sessionName: String) {
        guard isHost, session != nil else { return }
        advertiser?.stopAdvertisingPeer()
        advertiser = nil

        let discoveryInfo = [
            "sessionName": sessionName,
            "key": hostingKey.rawValue,
            "tempo": "\(hostingTempoBPM)",
            "sessionToken": hostingSessionToken.uuidString
        ]
        advertiser = MCNearbyServiceAdvertiser(
            peer: myPeerID,
            discoveryInfo: discoveryInfo,
            serviceType: Self.serviceType
        )
        advertiser?.delegate = self
        advertiser?.startAdvertisingPeer()

        if let session, !session.connectedPeers.isEmpty {
            connectionState = .connected(peerCount: session.connectedPeers.count)
        } else {
            connectionState = .hosting
        }
    }

    private func beginHosting(sessionName: String) {
        stopAll()
        isHost = true
        pendingJoinRequests = []
        pendingInvitations = [:]
        myPeerID = MCPeerID(displayName: Self.currentDisplayName())

        let mcSession = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .required)
        mcSession.delegate = self
        session = mcSession

        let discoveryInfo = [
            "sessionName": sessionName,
            "key": hostingKey.rawValue,
            "tempo": "\(hostingTempoBPM)",
            "sessionToken": hostingSessionToken.uuidString
        ]
        advertiser = MCNearbyServiceAdvertiser(peer: myPeerID, discoveryInfo: discoveryInfo, serviceType: Self.serviceType)
        advertiser?.delegate = self
        advertiser?.startAdvertisingPeer()
        connectionState = .hosting
    }

    private func beginBrowsing() {
        stopAll()
        isHost = false
        discoveredHosts = []
        myPeerID = MCPeerID(displayName: Self.currentDisplayName())

        let mcSession = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .required)
        mcSession.delegate = self
        session = mcSession

        browser = MCNearbyServiceBrowser(peer: myPeerID, serviceType: Self.serviceType)
        browser?.delegate = self
        browser?.startBrowsingForPeers()
        connectionState = .browsing
    }

    func joinHost(_ host: DiscoveredHost) {
        hostPeer = host.peer
        guard let browser, let session else { return }
        browser.invitePeer(host.peer, to: session, withContext: nil, timeout: 20)
    }

    func acceptJoinRequest(_ request: PendingJoinRequest) {
        pendingInvitations[request.peer.displayName]?(true, session)
        pendingInvitations.removeValue(forKey: request.peer.displayName)
        pendingJoinRequests.removeAll { $0.peer.displayName == request.peer.displayName }
    }

    func rejectJoinRequest(_ request: PendingJoinRequest) {
        pendingInvitations[request.peer.displayName]?(false, nil)
        pendingInvitations.removeValue(forKey: request.peer.displayName)
        pendingJoinRequests.removeAll { $0.peer.displayName == request.peer.displayName }
    }

    func broadcast(_ payload: SessionSyncPayload) {
        guard isHost, let session, !session.connectedPeers.isEmpty else { return }
        send(.state(payload), to: session.connectedPeers, mode: .reliable)
    }

    func sendControlRequest(_ action: SessionControlAction) {
        guard !isHost, let session, let host = resolvedHostPeer(in: session) else { return }
        send(.controlRequest(action), to: [host], mode: .reliable)
    }

    func sendResource(at url: URL, named name: String, to peer: MCPeerID) {
        guard isHost, let session else { return }
        _ = session.sendResource(at: url, withName: name, toPeer: peer) { _ in }
    }

    func disconnect() {
        stopAll(clearHostPeer: true)
        hostingSessionName = nil
        connectionState = .idle
        connectedPeers = []
        discoveredHosts = []
        pendingJoinRequests = []
        rejectAllPendingInvitations()
        clockOffset = 0
        bestRoundTrip = .infinity
        syncQuality = .unknown
    }

    func startClockCalibration() {
        guard !isHost else { return }
        calibrationTask?.cancel()
        calibrationTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.calibrateOnce()
                try? await Task.sleep(for: .seconds(20))
            }
        }
    }

    private func calibrateOnce() async {
        guard !isHost, let session, let host = resolvedHostPeer(in: session) else { return }
        bestRoundTrip = .infinity
        for _ in 0..<7 {
            guard !Task.isCancelled else { return }
            let ping = TimeSyncPing(id: UUID(), clientSendEpoch: Date().timeIntervalSince1970, hostEpoch: nil)
            send(.timeSyncRequest(ping), to: [host], mode: .unreliable)
            try? await Task.sleep(for: .milliseconds(120))
        }
    }

    private func resolvedHostPeer(in session: MCSession) -> MCPeerID? {
        if let hostPeer,
           let match = session.connectedPeers.first(where: { $0.displayName == hostPeer.displayName }) {
            return match
        }
        return session.connectedPeers.first
    }

    private func send(_ message: SessionMessage, to peers: [MCPeerID], mode: MCSessionSendDataMode) {
        guard let session, !peers.isEmpty else { return }
        do {
            let data = try JSONEncoder().encode(message)
            try session.send(data, toPeers: peers, with: mode)
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func handleTimeSyncResponse(_ ping: TimeSyncPing) {
        guard let hostEpoch = ping.hostEpoch else { return }
        let now = Date().timeIntervalSince1970
        let roundTrip = now - ping.clientSendEpoch
        let offset = hostEpoch - (ping.clientSendEpoch + now) / 2
        if roundTrip < bestRoundTrip {
            bestRoundTrip = roundTrip
            clockOffset = offset
            syncQuality = SyncQuality.from(roundTripSeconds: roundTrip)
            onClockOffsetUpdated?()
        }
    }

    private func rejectAllPendingInvitations() {
        for (_, handler) in pendingInvitations {
            handler(false, nil)
        }
        pendingInvitations = [:]
    }

    private func stopAll(clearHostPeer: Bool = false) {
        calibrationTask?.cancel()
        calibrationTask = nil
        rejectAllPendingInvitations()
        advertiser?.stopAdvertisingPeer()
        advertiser = nil
        browser?.stopBrowsingForPeers()
        browser = nil
        session?.disconnect()
        session = nil
        isHost = false
        if clearHostPeer {
            hostPeer = nil
        }
    }
}

extension SessionManager: MCSessionDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor in
            connectedPeers = session.connectedPeers
            if session.connectedPeers.isEmpty {
                switch connectionState {
                case .hosting: connectionState = .hosting
                case .browsing: connectionState = .browsing
                default: connectionState = .idle
                }
                if !isHost {
                    syncQuality = .unknown
                    onGuestDisconnected?()
                }
            } else {
                connectionState = .connected(peerCount: session.connectedPeers.count)
            }
            onPeersUpdated?(session.connectedPeers)
            if !isHost, !session.connectedPeers.isEmpty {
                startClockCalibration()
            }
        }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        Task { @MainActor in
            guard let message = try? JSONDecoder().decode(SessionMessage.self, from: data) else { return }
            switch message {
            case .state(let payload):
                onPayloadReceived?(payload)
            case .timeSyncRequest(let ping):
                var reply = ping
                reply.hostEpoch = Date().timeIntervalSince1970
                send(.timeSyncResponse(reply), to: [peerID], mode: .unreliable)
            case .timeSyncResponse(let ping):
                handleTimeSyncResponse(ping)
            case .controlRequest(let action):
                if isHost {
                    onControlRequest?(action, peerID)
                }
            }
        }
    }

    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

extension SessionManager: MCNearbyServiceAdvertiserDelegate {
    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        Task { @MainActor in
            lastError = error.localizedDescription
        }
    }

    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        Task { @MainActor in
            if requireHostApproval {
                pendingInvitations[peerID.displayName] = invitationHandler
                if !pendingJoinRequests.contains(where: { $0.peer.displayName == peerID.displayName }) {
                    pendingJoinRequests.append(PendingJoinRequest(peer: peerID, receivedAt: Date()))
                }
            } else {
                invitationHandler(true, session)
            }
        }
    }
}

extension SessionManager: MCNearbyServiceBrowserDelegate {
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        Task { @MainActor in
            lastError = error.localizedDescription
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        Task { @MainActor in
            let trimmedName = info?["sessionName"]?.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedName = trimmedName.flatMap { $0.isEmpty ? nil : $0 } ?? L10n.jamSession
            let key = info?["key"].flatMap { MusicalKey(rawValue: $0) }
            let tempo = info?["tempo"].flatMap { Int($0) }
            let token = info?["sessionToken"].flatMap { UUID(uuidString: $0) }
            let host = DiscoveredHost(
                peer: peerID,
                sessionName: resolvedName,
                key: key,
                tempoBPM: tempo,
                sessionToken: token
            )
            if let index = discoveredHosts.firstIndex(where: { $0.peer.displayName == peerID.displayName }) {
                discoveredHosts[index] = host
            } else {
                discoveredHosts.append(host)
            }
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        Task { @MainActor in
            discoveredHosts.removeAll { $0.peer.displayName == peerID.displayName }
        }
    }
}
