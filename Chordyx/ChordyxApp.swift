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
        }
        .defaultSize(width: 1100, height: 760)
    }
}
#else
@main
struct ChordyxApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
#endif
