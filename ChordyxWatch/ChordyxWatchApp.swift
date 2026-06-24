//
//  ChordyxWatchApp.swift
//  Chordyx Watch App
//

import SwiftUI
import WatchConnectivity
import WatchKit

@main
struct ChordyxWatchApp: App {
    var body: some Scene {
        WindowGroup {
            ChordyxWatchSessionView()
        }
    }
}

struct ChordyxWatchSessionView: View {
    @State private var sessionName = "Chordyx"
    @State private var chordName = "—"
    @State private var upcoming = ""
    @State private var tempo: Double = 100
    @State private var isPlaying = false
    @State private var beat = -1
    @State private var hapticsEnabled = true

    var body: some View {
        VStack(spacing: 8) {
            Text(sessionName)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(chordName)
                .font(.system(size: 36, weight: .bold, design: .rounded))
            if !upcoming.isEmpty {
                Text(String(format: String(localized: "then %@"), upcoming))
                    .font(.caption2)
            }
            HStack {
                Text("\(Int(tempo)) BPM")
                if isPlaying, beat >= 0 {
                    Text(String(format: String(localized: "· beat %lld"), beat + 1))
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding()
        .onAppear {
            WatchReceiver.shared.onUpdate = { update in
                let priorChord = chordName
                sessionName = update.sessionName
                chordName = update.chordName
                upcoming = update.upcoming
                tempo = update.tempo
                isPlaying = update.isPlaying
                beat = update.beat
                hapticsEnabled = update.hapticsEnabled
                if update.hapticsEnabled {
                    if update.chordChanged, priorChord != update.chordName {
                        WKInterfaceDevice.current().play(.notification)
                    } else if update.isAccentBeat, update.isPlaying {
                        WKInterfaceDevice.current().play(.click)
                    }
                }
            }
            WatchReceiver.shared.activate()
        }
    }
}

final class WatchReceiver: NSObject, WCSessionDelegate {
    static let shared = WatchReceiver()

    struct Update {
        var sessionName = "Chordyx"
        var chordName = "—"
        var upcoming = ""
        var tempo: Double = 100
        var isPlaying = false
        var beat = -1
        var chordChanged = false
        var isAccentBeat = false
        var hapticsEnabled = true
    }

    var onUpdate: ((Update) -> Void)?

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}

    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
    #endif

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        var update = Update()
        update.sessionName = applicationContext["sessionName"] as? String ?? "Chordyx"
        update.chordName = applicationContext["chordName"] as? String ?? "—"
        update.upcoming = applicationContext["upcoming"] as? String ?? ""
        update.tempo = applicationContext["tempo"] as? Double ?? 100
        update.isPlaying = applicationContext["isPlaying"] as? Bool ?? false
        update.beat = applicationContext["beat"] as? Int ?? -1
        update.chordChanged = applicationContext["chordChanged"] as? Bool ?? false
        update.isAccentBeat = applicationContext["isAccentBeat"] as? Bool ?? false
        update.hapticsEnabled = applicationContext["hapticsEnabled"] as? Bool ?? true
        DispatchQueue.main.async { self.onUpdate?(update) }
    }
}
