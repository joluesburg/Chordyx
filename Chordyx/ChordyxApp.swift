//
//  ChordyxApp.swift
//  Chordyx
//

import SwiftUI

#if os(macOS)
@main
struct ChordyxMacApp: App {
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 900, minHeight: 640)
                .platformDesktopControls()
                .task {
                    AdaptiveKeyLearningEngine.shared.reloadFromDisk()
                }
        }
        .defaultSize(width: 1100, height: 760)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                AdaptiveKeyLearningEngine.shared.reloadFromDisk()
            }
        }
    }
}
#else
@main
struct ChordyxApp: App {
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    AdaptiveKeyLearningEngine.shared.reloadFromDisk()
                }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                AdaptiveKeyLearningEngine.shared.reloadFromDisk()
            }
        }
    }
}
#endif
