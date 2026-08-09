//
//  InternetRelayConfiguration.swift
//  Chordyx
//

import Foundation

enum InternetRelayConfiguration {
    /// When false, CloudKit production-schema errors do not offer Firebase backup.
    static var hasFirebaseFallback: Bool { firebaseDatabaseURL != nil }

    /// Optional Firebase Realtime Database URL from Info.plist / GoogleService-Info.
    static var firebaseDatabaseURL: URL? {
        if let url = urlFromInfoPlist() { return url }
        return urlFromGoogleServiceInfo()
    }

    private static func urlFromInfoPlist() -> URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "FirebaseDatabaseURL") as? String else {
            return nil
        }
        return normalizedDatabaseURL(raw)
    }

    private static func urlFromGoogleServiceInfo() -> URL? {
        guard let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
              let dict = NSDictionary(contentsOfFile: path) as? [String: Any] else {
            return nil
        }
        if let raw = dict["DATABASE_URL"] as? String {
            return normalizedDatabaseURL(raw)
        }
        return nil
    }

    private static func normalizedDatabaseURL(_ raw: String) -> URL? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        if value.hasSuffix("/") { value.removeLast() }
        return URL(string: value)
    }
}

// MARK: - Firebase REST payloads

struct InternetSessionRecord: Codable, Equatable, Sendable {
    var joinCode: String
    var sessionToken: String
    var hostName: String
    var sessionName: String?
    var payloadData: Data
    var updatedAt: Date
    var expiresAt: Date
}

struct InternetControlRecord: Codable, Equatable, Sendable {
    var joinCode: String
    var guestName: String
    var actionData: Data
    var createdAt: Date
}

