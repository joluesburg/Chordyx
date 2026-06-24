//
//  SessionBackgroundManager.swift
//  Chordyx
//

#if os(iOS)
import UIKit

@MainActor
final class SessionBackgroundManager {
    private var taskID: UIBackgroundTaskIdentifier = .invalid

    func begin() {
        guard taskID == .invalid else { return }
        taskID = UIApplication.shared.beginBackgroundTask(withName: "ChordyxSession") { [weak self] in
            Task { @MainActor in
                self?.end()
            }
        }
    }

    func end() {
        guard taskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(taskID)
        taskID = .invalid
    }
}
#endif
