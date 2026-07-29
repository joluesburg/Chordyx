//
//  WatchSessionBridge.swift
//  Chordyx
//

import Foundation
#if os(iOS)
@preconcurrency import WatchConnectivity

/// Bridges live session state to the watch app. Not @MainActor — WCSessionDelegate fires on background queues.
final class WatchSessionBridge: NSObject, WCSessionDelegate {
    static let shared = WatchSessionBridge()

    var onRemoteCommand: ((String) -> Void)?

    private var isCounterpartAvailable = false

    private override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    @MainActor
    private func refreshCounterpartAvailability() {
        let session = WCSession.default
        isCounterpartAvailable = session.activationState == .activated
            && session.isPaired
            && session.isWatchAppInstalled
    }

    @MainActor
    func sendSessionUpdate(
        sessionName: String,
        chordName: String,
        upcoming: String?,
        nextSongTitle: String? = nil,
        tempo: Double,
        isPlaying: Bool,
        beat: Int,
        chordChanged: Bool = false,
        isAccentBeat: Bool = false,
        canRemoteControl: Bool = false
    ) {
        guard isCounterpartAvailable else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        let payload: [String: Any] = [
            "sessionName": sessionName,
            "chordName": chordName,
            "upcoming": upcoming ?? "",
            "nextSongTitle": nextSongTitle ?? "",
            "tempo": tempo,
            "isPlaying": isPlaying,
            "beat": beat,
            "chordChanged": chordChanged,
            "isAccentBeat": isAccentBeat,
            "hapticsEnabled": GuestDisplaySettings.watchHapticsEnabled,
            "canRemoteControl": canRemoteControl
        ]
        do {
            try session.updateApplicationContext(payload)
        } catch {
            refreshCounterpartAvailability()
        }
    }

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        DispatchQueue.main.async {
            WatchSessionBridge.shared.refreshCounterpartAvailability()
        }
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            WatchSessionBridge.shared.refreshCounterpartAvailability()
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let command = message["command"] as? String else { return }
        DispatchQueue.main.async {
            WatchSessionBridge.shared.onRemoteCommand?(command)
        }
    }
}
#else
@MainActor
final class WatchSessionBridge {
    static let shared = WatchSessionBridge()

    var onRemoteCommand: ((String) -> Void)?

    private init() {}

    func sendSessionUpdate(
        sessionName: String,
        chordName: String,
        upcoming: String?,
        nextSongTitle: String? = nil,
        tempo: Double,
        isPlaying: Bool,
        beat: Int,
        chordChanged: Bool = false,
        isAccentBeat: Bool = false,
        canRemoteControl: Bool = false
    ) {}
}
#endif
