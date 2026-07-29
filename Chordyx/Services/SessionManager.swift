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
    private(set) var isInviting = false
    private var suppressGuestDisconnectNotification = false

    private var pendingStatePacket: Data?
    private var pendingStatePeer: MCPeerID?
    private var receiveCoalesceTask: Task<Void, Never>?

    private var pendingLiveBroadcast: (data: Data, peers: [MCPeerID])?
    private var liveBroadcastCoalesceTask: Task<Void, Never>?
    private var lastSentLiveSymbol: String?

    var onPayloadReceived: ((SessionSyncPayload) -> Void)?
    var onLiveChordReceived: ((LiveChordWire) -> Void)?
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
        // Start Multipeer immediately. Awaiting Local Network permission first left hosting
        // delayed/stuck and could freeze UI; Bonjour prompts when advertising begins.
        beginHosting(sessionName: safeName)
        let serviceType = Self.serviceType
        Task.detached(priority: .utility) {
            await LocalNetworkPermission.requestAccess(serviceType: serviceType)
        }
    }

    func startBrowsing() {
        lastError = nil
        beginBrowsing()
        let serviceType = Self.serviceType
        Task.detached(priority: .utility) {
            await LocalNetworkPermission.requestAccess(serviceType: serviceType)
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

    /// Re-publish the host on macOS if Bonjour advertising was interrupted.
    func refreshHostingIfNeeded() {
        guard isHost, let sessionName = hostingSessionName, session != nil else { return }

        if advertiser == nil {
            refreshAdvertiserDiscoveryInfo(sessionName: sessionName)
        } else if session?.connectedPeers.isEmpty == true {
            advertiser?.stopAdvertisingPeer()
            advertiser?.startAdvertisingPeer()
        }
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
        connectionState = .hosting
        // Defer Bonjour advertise one turn so Session UI stays interactive on first frame.
        Task { @MainActor [weak self] in
            await Task.yield()
            self?.advertiser?.startAdvertisingPeer()
        }
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
        guard let browser, let session else {
            lastError = String(localized: "Still searching for sessions. Try again in a moment.")
            return
        }
        guard !isInviting else { return }
        isInviting = true
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

    func broadcastLive(_ wire: LiveChordWire) {
        guard isHost, let session, !session.connectedPeers.isEmpty else { return }
        guard let data = SessionMessageCodec.encode(.liveChord(wire)) else { return }
        let peers = session.connectedPeers
        let symbolChanged = wire.liveChordSymbol != lastSentLiveSymbol
        // Piano-key teaching needs reliable delivery — unreliable drops mid-chord notes.
        let mode: MCSessionSendDataMode = wire.pianoNotes.isEmpty ? .unreliable : .reliable
        if symbolChanged || !wire.pianoNotes.isEmpty {
            lastSentLiveSymbol = wire.liveChordSymbol
            liveBroadcastCoalesceTask?.cancel()
            liveBroadcastCoalesceTask = nil
            pendingLiveBroadcast = nil
            sendEncoded(data, to: peers, mode: mode)
        } else {
            pendingLiveBroadcast = (data, peers)
            scheduleLiveBroadcastCoalesce(delayMs: 12)
        }
    }

    func broadcast(_ payload: SessionSyncPayload, mode: MCSessionSendDataMode = .reliable) {
        guard isHost, let session, !session.connectedPeers.isEmpty else { return }
        guard let data = SessionMessageCodec.encode(.state(payload)) else { return }
        let peers = session.connectedPeers
        if mode == .unreliable {
            pendingLiveBroadcast = (data, peers)
            scheduleLiveBroadcastCoalesce(delayMs: 12)
            return
        }
        sendEncoded(data, to: peers, mode: mode)
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
        guard let data = SessionMessageCodec.encode(message) else { return }
        sendEncoded(data, to: peers, mode: mode)
    }

    private func sendEncoded(_ data: Data, to peers: [MCPeerID], mode: MCSessionSendDataMode) {
        guard let session, !peers.isEmpty else { return }
        do {
            try session.send(data, toPeers: peers, with: mode)
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func scheduleLiveBroadcastCoalesce(delayMs: UInt64 = 12) {
        guard liveBroadcastCoalesceTask == nil else { return }
        liveBroadcastCoalesceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(delayMs))
            guard let self else { return }
            self.liveBroadcastCoalesceTask = nil
            guard self.session != nil, let pending = self.pendingLiveBroadcast else { return }
            self.pendingLiveBroadcast = nil
            self.sendEncoded(pending.data, to: pending.peers, mode: .unreliable)
        }
    }

    private func enqueueReceivedPacket(_ data: Data, from peer: MCPeerID) {
        guard session != nil else { return }
        if Self.packetContainsLiveChordPayload(data) {
            guard let message = SessionMessageCodec.decode(data) else { return }
            handleReceived(message, from: peer)
            return
        }
        if Self.packetContainsStatePayload(data) {
            pendingStatePacket = data
            pendingStatePeer = peer
            scheduleReceiveCoalesce()
            return
        }
        guard let message = SessionMessageCodec.decode(data) else { return }
        handleReceived(message, from: peer)
    }

    private func scheduleReceiveCoalesce() {
        guard receiveCoalesceTask == nil else { return }
        receiveCoalesceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(12))
            guard let self else { return }
            self.receiveCoalesceTask = nil
            guard self.session != nil,
                  let data = self.pendingStatePacket,
                  let peer = self.pendingStatePeer else { return }
            self.pendingStatePacket = nil
            self.pendingStatePeer = nil
            guard let message = SessionMessageCodec.decode(data) else { return }
            self.handleReceived(message, from: peer)
        }
    }

    private static func packetContainsLiveChordPayload(_ data: Data) -> Bool {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        return json["liveChord"] != nil
    }

    private static func packetContainsStatePayload(_ data: Data) -> Bool {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        return json["state"] != nil
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
        suppressGuestDisconnectNotification = true
        calibrationTask?.cancel()
        calibrationTask = nil
        receiveCoalesceTask?.cancel()
        receiveCoalesceTask = nil
        pendingStatePacket = nil
        pendingStatePeer = nil
        liveBroadcastCoalesceTask?.cancel()
        liveBroadcastCoalesceTask = nil
        pendingLiveBroadcast = nil
        lastSentLiveSymbol = nil
        rejectAllPendingInvitations()
        isInviting = false
        connectedPeers = []
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
        suppressGuestDisconnectNotification = false
    }

    private func isActiveSession(_ session: MCSession) -> Bool {
        guard let active = self.session else { return false }
        return session === active
    }
}

extension SessionManager: MCSessionDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor [weak self] in
            guard let self, self.isActiveSession(session) else { return }
            let hadPeers = !connectedPeers.isEmpty
            connectedPeers = session.connectedPeers

            if state == .connected || state == .notConnected {
                isInviting = false
            }

            if session.connectedPeers.isEmpty {
                switch connectionState {
                case .hosting: connectionState = .hosting
                case .browsing: connectionState = .browsing
                default: connectionState = .idle
                }
                if !isHost, hadPeers, !suppressGuestDisconnectNotification {
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
        let packet = data
        let peer = peerID
        Task { @MainActor [weak self] in
            self?.enqueueReceivedPacket(packet, from: peer)
        }
    }

    private func handleReceived(_ message: SessionMessage, from peerID: MCPeerID) {
        switch message {
        case .state(let payload):
            onPayloadReceived?(payload)
        case .liveChord(let wire):
            onLiveChordReceived?(wire)
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
        Task { @MainActor [weak self] in
            guard let self else {
                invitationHandler(false, nil)
                return
            }
            if requireHostApproval {
                pendingInvitations[peerID.displayName] = invitationHandler
                if !pendingJoinRequests.contains(where: { $0.peer.displayName == peerID.displayName }) {
                    pendingJoinRequests.append(PendingJoinRequest(peer: peerID, receivedAt: Date()))
                }
            } else if let activeSession = session {
                invitationHandler(true, activeSession)
            } else {
                invitationHandler(false, nil)
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
