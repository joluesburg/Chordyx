//
//  ChordyxApp.swift
//  Chordyx
//

import SwiftUI

#if os(macOS)
@main
struct ChordyxMacApp: App {
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
    }
}
#else
@main
struct ChordyxApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(ChordyxAppDelegate.self) private var appDelegate
    #endif

    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    #if os(iOS)
                    PhoneOrientationMonitor.shared.start()
                    #endif
                    AdaptiveKeyLearningEngine.shared.reloadFromDisk()
                }
        }
    }
}
#endif
