//
//  SessionManager.swift
//  Chordyx
//

import Combine
import Foundation
@preconcurrency import MultipeerConnectivity

/// Not `@Observable`: Observation + `NSObject` overflowed the iPhone main-thread stack
/// (`EXC_BAD_ACCESS code=2`) when this type was first created during launch/bootstrap.
@MainActor
final class SessionManager: NSObject, ObservableObject {
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

    @Published var connectedPeers: [MCPeerID] = []
    @Published var discoveredHosts: [DiscoveredHost] = []
    @Published var pendingJoinRequests: [PendingJoinRequest] = []
    @Published var connectionState: ConnectionState = .idle
    @Published var lastError: String?
    @Published var syncQuality: SyncQuality = .unknown

    @Published var clockOffset: Double = 0
    @Published private(set) var hostPeer: MCPeerID?

    var hostPeerDisplayName: String? {
        hostPeer?.displayName ?? connectedPeers.first?.displayName
    }

    /// Lazily created — MCPeerID at SessionManager init contributed to launch hangs.
    private var myPeerIDStorage: MCPeerID?
    private var myPeerID: MCPeerID {
        get {
            if let myPeerIDStorage { return myPeerIDStorage }
            let created = MCPeerID(displayName: PlatformDevice.defaultDisplayName)
            myPeerIDStorage = created
            return created
        }
        set { myPeerIDStorage = newValue }
    }
    private var session: MCSession?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var advertiseKeepAliveTask: Task<Void, Never>?
    private var isHost = false
    private var hostingSessionName: String?
    private var hostingKey: MusicalKey = .C
    private var hostingTempoBPM: Int = 100
    private var hostingSessionToken: UUID = UUID()
    private var bestRoundTrip: Double = .infinity
    private var calibrationTask: Task<Void, Never>?
    private var pendingInvitations: [String: (Bool, MCSession?) -> Void] = [:]
    /// Maps display names to live MCPeerID instances discovered on the main actor.
    private var peerRegistry: [String: MCPeerID] = [:]
    @Published private(set) var isInviting = false
    private var suppressGuestDisconnectNotification = false
    private var inviteTimeoutTask: Task<Void, Never>?

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
    /// Guest invite timed out / was rejected before any peer connected.
    var onInviteFailed: (() -> Void)?

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
        Task { @MainActor [weak self] in
            await LocalNetworkPermission.requestAccess(serviceType: serviceType)
            self?.refreshHostingIfNeeded()
        }
    }

    func startBrowsing() {
        lastError = nil
        beginBrowsing()
        let serviceType = Self.serviceType
        Task { @MainActor [weak self] in
            await LocalNetworkPermission.requestAccess(serviceType: serviceType)
            // Permission dialog can interrupt Bonjour — restart browsing once granted.
            guard let self, self.browser != nil, !self.isHost else { return }
            self.browser?.stopBrowsingForPeers()
            self.browser?.startBrowsingForPeers()
            self.connectionState = .browsing
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
        // Advertise immediately — deferring this left hosts invisible to guests after Host Setup.
        advertiser?.startAdvertisingPeer()
        startAdvertiseKeepAlive()
    }

    /// Bonjour often goes quiet after Local Network prompts / background — re-announce while hosting.
    private func startAdvertiseKeepAlive() {
        advertiseKeepAliveTask?.cancel()
        advertiseKeepAliveTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(12))
                guard let self, !Task.isCancelled, self.isHost else { return }
                self.refreshHostingIfNeeded()
            }
        }
    }

    private func stopAdvertiseKeepAlive() {
        advertiseKeepAliveTask?.cancel()
        advertiseKeepAliveTask = nil
    }

    private func beginBrowsing() {
        stopAll(clearHostPeer: true)
        isHost = false
        discoveredHosts = []
        peerRegistry = [:]
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
        let peerID = host.invitePeerID
        registerPeer(peerID)
        guard let browser, let session else {
            lastError = String(localized: "Still searching for sessions. Try again in a moment.")
            return
        }
        // Cancel a previous in-flight invite so a second tap / reconnect targets the right host.
        if isInviting {
            inviteTimeoutTask?.cancel()
            inviteTimeoutTask = nil
            isInviting = false
        }
        hostPeer = peerID
        isInviting = true
        lastError = nil
        inviteTimeoutTask?.cancel()
        inviteTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(22))
            guard let self, !Task.isCancelled else { return }
            guard self.isInviting, self.connectedPeers.isEmpty else { return }
            self.isInviting = false
            self.hostPeer = nil
            self.lastError = String(localized: "Couldn’t connect to the host. Try again.")
            self.onInviteFailed?()
        }
        browser.invitePeer(peerID, to: session, withContext: nil, timeout: 20)
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
        stopAdvertiseKeepAlive()
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
        inviteTimeoutTask?.cancel()
        inviteTimeoutTask = nil
        isInviting = false
        connectedPeers = []
        peerRegistry = [:]
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

    private func registerPeer(_ peerID: MCPeerID) {
        peerRegistry[peerID.displayName] = peerID
    }

    func peer(for reference: PeerReference) -> MCPeerID? {
        peerRegistry[reference.displayName]
            ?? connectedPeers.first { $0.displayName == reference.displayName }
    }

    var connectedPeerReferences: [PeerReference] {
        connectedPeers.map(PeerReference.init)
    }
}

extension SessionManager: MCSessionDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor [weak self] in
            guard let self, self.isActiveSession(session) else { return }
            let hadPeers = !connectedPeers.isEmpty
            connectedPeers = session.connectedPeers

            if state == .connected {
                registerPeer(peerID)
                isInviting = false
                inviteTimeoutTask?.cancel()
                inviteTimeoutTask = nil
            } else if state == .notConnected, isInviting, session.connectedPeers.isEmpty {
                // Do not fail immediately — Multipeer often reports notConnected before connecting.
                // joinHost arms a 22s timeout that calls onInviteFailed if still inviting.
            }

            if session.connectedPeers.isEmpty {
                if isHost {
                    connectionState = .hosting
                } else if browser != nil {
                    connectionState = .browsing
                } else {
                    connectionState = .idle
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
            guard let self, self.isActiveSession(session) else { return }
            self.enqueueReceivedPacket(packet, from: peer)
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
        let message = error.localizedDescription
        DispatchQueue.main.async { [weak self] in
            guard let self, advertiser === self.advertiser else { return }
            self.lastError = message
        }
    }

    /// Invitation handlers must run before this method returns — async MainActor hops
    /// let Multipeer time out and guests never connect.
    nonisolated func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didReceiveInvitationFromPeer peerID: MCPeerID,
        withContext context: Data?,
        invitationHandler: @escaping (Bool, MCSession?) -> Void
    ) {
        let accept: () -> Void = { [weak self] in
            MainActor.assumeIsolated {
                guard let self else {
                    invitationHandler(false, nil)
                    return
                }
                guard advertiser === self.advertiser else {
                    invitationHandler(false, nil)
                    return
                }
                if self.requireHostApproval {
                    self.registerPeer(peerID)
                    if let previous = self.pendingInvitations[peerID.displayName] {
                        previous(false, nil)
                    }
                    self.pendingInvitations[peerID.displayName] = invitationHandler
                    if !self.pendingJoinRequests.contains(where: { $0.peer.displayName == peerID.displayName }) {
                        self.pendingJoinRequests.append(
                            PendingJoinRequest(peer: PeerReference(peerID), receivedAt: Date())
                        )
                    }
                } else if let activeSession = self.session {
                    self.registerPeer(peerID)
                    invitationHandler(true, activeSession)
                } else {
                    invitationHandler(false, nil)
                }
            }
        }

        if Thread.isMainThread {
            accept()
        } else {
            DispatchQueue.main.sync(execute: accept)
        }
    }
}

extension SessionManager: MCNearbyServiceBrowserDelegate {
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        Task { @MainActor [weak self] in
            guard let self, browser === self.browser else { return }
            lastError = error.localizedDescription
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        Task { @MainActor [weak self] in
            guard let self, browser === self.browser else { return }
            let trimmedName = info?["sessionName"]?.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedName = trimmedName.flatMap { $0.isEmpty ? nil : $0 } ?? L10n.jamSession
            let key = info?["key"].flatMap { MusicalKey(rawValue: $0) }
            let tempo = info?["tempo"].flatMap { Int($0) }
            let token = info?["sessionToken"].flatMap { UUID(uuidString: $0) }
            registerPeer(peerID)
            let host = DiscoveredHost(
                peerID: peerID,
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
        Task { @MainActor [weak self] in
            guard let self, browser === self.browser else { return }
            // Keep peerRegistry entries — Bonjour often flaps lost/found during host refresh.
            discoveredHosts.removeAll { $0.peer.displayName == peerID.displayName }
        }
    }
}
