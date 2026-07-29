//
//  RemoteJoinCode.swift
//  Chordyx
//

import Foundation
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Six-character codes for joining a live session over iCloud (no local Wi‑Fi required).
enum RemoteJoinCode {
    private static let alphabet = Array("BCDFGHJKLMNPQRSTVWXYZ23456789")

    static func generate() -> String {
        String((0..<6).map { _ in alphabet.randomElement()! })
    }

    static func normalize(_ input: String) -> String {
        String(
            input
                .uppercased()
                .filter { alphabet.contains($0) }
                .prefix(6)
        )
    }

    static func isValid(_ code: String) -> Bool {
        normalize(code).count == 6
    }

    static func formatted(_ code: String) -> String {
        let normalized = normalize(code)
        guard normalized.count == 6 else { return normalized }
        let index = normalized.index(normalized.startIndex, offsetBy: 3)
        return "\(normalized[..<index])-\(normalized[index...])"
    }

    static func copyToClipboard(_ code: String) {
        let formatted = formatted(code)
        #if os(iOS)
        UIPasteboard.general.string = formatted
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(formatted, forType: .string)
        #endif
    }
}
