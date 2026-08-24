//
//  PlatformDevice.swift
//  Chordyx
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif

enum PlatformDevice {
    /// True on iPhone; false on iPad, Mac, and other platforms.
    static var isPhone: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .phone
        #else
        false
        #endif
    }

    /// iOS/iPadOS app running on Apple Silicon Mac (App Store “iPad app on Mac”).
    static var isiOSAppOnMac: Bool {
        #if os(iOS)
        ProcessInfo.processInfo.isiOSAppOnMac
        #else
        false
        #endif
    }

    /// True on iPad (including iPad app on Mac when idiom is pad).
    static var isPad: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .pad
        #else
        false
        #endif
    }

    /// iPad, Mac, and iOS-on-Mac need explicit button styles for reliable taps.
    static var usesDesktopControls: Bool {
        #if os(macOS)
        true
        #elseif os(iOS)
        !isPhone
        #else
        false
        #endif
    }

    /// Backward-compatible alias.
    static var usesDesktopJoinUI: Bool { usesDesktopControls }

    static var defaultDisplayName: String {
        #if os(macOS)
        let raw = Host.current().localizedName ?? ProcessInfo.processInfo.hostName
        #else
        let raw = UIDevice.current.name
        #endif
        return sanitizedPeerName(raw)
    }

    /// MCPeerID display names are limited to 63 UTF-8 bytes.
    static func sanitizedPeerName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = trimmed.isEmpty ? "Musician" : trimmed
        var result = ""
        for character in fallback {
            let candidate = result + String(character)
            if candidate.utf8.count > 63 { break }
            result = candidate
        }
        return result.isEmpty ? "Musician" : result
    }

    static func sanitizedDiscoveryValue(_ value: String, maxUTF8Bytes: Int = 48) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = trimmed.isEmpty ? L10n.jamSession : trimmed
        var result = ""
        for character in fallback {
            let candidate = result + String(character)
            if candidate.utf8.count > maxUTF8Bytes { break }
            result = candidate
        }
        return result.isEmpty ? L10n.jamSession : result
    }
}
