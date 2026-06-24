//
//  WatchSessionBridge.swift
//  Chordyx
//

import Foundation
#if os(iOS)
import WatchConnectivity

@MainActor
final class WatchSessionBridge: NSObject, WCSessionDelegate {
    static let shared = WatchSessionBridge()

    private override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    func sendSessionUpdate(
        sessionName: String,
        chordName: String,
        upcoming: String?,
        tempo: Double,
        isPlaying: Bool,
        beat: Int,
        chordChanged: Bool = false,
        isAccentBeat: Bool = false
    ) {
        guard WCSession.default.activationState == .activated else { return }
        let payload: [String: Any] = [
            "sessionName": sessionName,
            "chordName": chordName,
            "upcoming": upcoming ?? "",
            "tempo": tempo,
            "isPlaying": isPlaying,
            "beat": beat,
            "chordChanged": chordChanged,
            "isAccentBeat": isAccentBeat,
            "hapticsEnabled": GuestDisplaySettings.watchHapticsEnabled
        ]
        try? WCSession.default.updateApplicationContext(payload)
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
}
#else
@MainActor
final class WatchSessionBridge {
    static let shared = WatchSessionBridge()

    private init() {}

    func sendSessionUpdate(
        sessionName: String,
        chordName: String,
        upcoming: String?,
        tempo: Double,
        isPlaying: Bool,
        beat: Int,
        chordChanged: Bool = false,
        isAccentBeat: Bool = false
    ) {}
}
#endif
