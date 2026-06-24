//
//  L10n.swift
//  Chordyx
//

import Foundation

enum L10n {
    static func tr(_ key: String.LocalizationValue) -> String {
        String(localized: key)
    }

    static func tr(_ key: String.LocalizationValue, _ args: CVarArg...) -> String {
        String(format: String(localized: key), locale: Locale.current, arguments: args)
    }

    static let jamSession = String(localized: "Jam Session")
    static let untitledProgression = String(localized: "Untitled Progression")
    static let practiceSuffix = String(localized: "%@ (Practice)")
    static let copyName = String(localized: "%@ Copy")
    static let copyNameNumbered = String(localized: "%@ Copy %lld")
    static let numberedName = String(localized: "%@ %lld")
    static let savedProgressionsCount = String(localized: "%lld saved progressions")
    static let oneSavedProgression = String(localized: "1 saved progression")
    static let createAndSaveSetlists = String(localized: "Create and save setlists")
    static func practiceSessionName(_ name: String) -> String {
        String(format: practiceSuffix, name)
    }

    static func numberedSectionName(_ name: String, number: Int) -> String {
        String(format: numberedName, name, number)
    }

    static func duplicateName(basedOn name: String, counter: Int? = nil) -> String {
        if let counter {
            return String(format: copyNameNumbered, name, counter)
        }
        return String(format: copyName, name)
    }
    static let beatNumber = String(localized: "· beat %lld")
    static let midiDevice = String(localized: "MIDI Device")
}
