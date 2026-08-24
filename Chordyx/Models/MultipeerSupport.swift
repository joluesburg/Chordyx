//
//  MultipeerSupport.swift
//  Chordyx
//
//  Legacy MultipeerConnectivity types are not Sendable. Keep MCPeerID/MCSession on
//  @MainActor (SessionManager) and pass PeerReference across models and UI instead.
//

@preconcurrency import MultipeerConnectivity

/// Stable, Sendable peer identity for discovery UI and session models.
/// Resolve to `MCPeerID` only on `@MainActor` via `SessionManager.peer(for:)`.
struct PeerReference: Sendable, Hashable, Equatable, Identifiable {
    let displayName: String
    var id: String { displayName }

    init(displayName: String) {
        self.displayName = displayName
    }

    init(_ peerID: MCPeerID) {
        self.displayName = peerID.displayName
    }
}

/// Guest-facing Multipeer / Internet link phase for Join + Session chrome.
enum GuestLinkStatus: Equatable, Sendable {
    case idle
    case searching
    case connecting
    case connectedLocal
    case connectedInternet
    case reconnecting
    case failed

    var label: String {
        switch self {
        case .idle: String(localized: "Idle")
        case .searching: String(localized: "Searching nearby…")
        case .connecting: String(localized: "Connecting…")
        case .connectedLocal: String(localized: "Connected · Nearby")
        case .connectedInternet: String(localized: "Connected · Internet")
        case .reconnecting: String(localized: "Reconnecting…")
        case .failed: String(localized: "Connection failed")
        }
    }

    var systemImage: String {
        switch self {
        case .idle: "wifi"
        case .searching: "wifi"
        case .connecting: "antenna.radiowaves.left.and.right"
        case .connectedLocal: "checkmark.circle.fill"
        case .connectedInternet: "icloud.fill"
        case .reconnecting: "arrow.triangle.2.circlepath"
        case .failed: "wifi.exclamationmark"
        }
    }

    var isConnected: Bool {
        switch self {
        case .connectedLocal, .connectedInternet: true
        default: false
        }
    }

    var showsProminentBanner: Bool {
        switch self {
        case .reconnecting, .failed, .connecting: true
        default: false
        }
    }
}

/// Nearby host shown in Join Session. Keeps the live `MCPeerID` from Bonjour discovery
/// so invites still work after transient `lostPeer` events clear the peer registry.
struct DiscoveredHost: Identifiable, Equatable {
    let peer: PeerReference
    /// Bonjour peer handle from `foundPeer` — required for `MCNearbyServiceBrowser.invitePeer`.
    let invitePeerID: MCPeerID
    let sessionName: String
    let key: MusicalKey?
    let tempoBPM: Int?
    let sessionToken: UUID?
    var id: String { peer.displayName }

    init(
        peerID: MCPeerID,
        sessionName: String,
        key: MusicalKey?,
        tempoBPM: Int?,
        sessionToken: UUID?
    ) {
        peer = PeerReference(peerID)
        invitePeerID = peerID
        self.sessionName = sessionName
        self.key = key
        self.tempoBPM = tempoBPM
        self.sessionToken = sessionToken
    }

    var subtitle: String {
        var parts: [String] = ["Host: \(peer.displayName)"]
        if let key { parts.append("Key \(key.displayName)") }
        if let tempoBPM { parts.append("\(tempoBPM) BPM") }
        return parts.joined(separator: " · ")
    }

    static func == (lhs: DiscoveredHost, rhs: DiscoveredHost) -> Bool {
        lhs.peer == rhs.peer
            && lhs.invitePeerID === rhs.invitePeerID
            && lhs.sessionName == rhs.sessionName
            && lhs.key == rhs.key
            && lhs.tempoBPM == rhs.tempoBPM
            && lhs.sessionToken == rhs.sessionToken
    }
}
