//
//  ChromaticToneNames.swift
//  Chordyx
//
//  Customizable 12-tone pitch-class names for piano keys and Latin chord roots.
//

import Foundation

/// Named presets for the chromatic scale spelling (pitch class 0 = C / Do … 11 = B / Si).
enum ChromaticTonePreset: String, CaseIterable, Identifiable, Codable, Sendable {
    case latinMixed
    case latinSharps
    case latinFlats
    case englishSharps
    case englishFlats
    case custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .latinMixed: String(localized: "Latin mixed (Do, Do#, Mi♭…)")
        case .latinSharps: String(localized: "Latin sharps (Do, Do#, Re…)")
        case .latinFlats: String(localized: "Latin flats (Do, Re♭, Re…)")
        case .englishSharps: String(localized: "English sharps (C, C#, D…)")
        case .englishFlats: String(localized: "English flats (C, Db, D…)")
        case .custom: String(localized: "Custom")
        }
    }

    /// Fixed spellings for built-in presets. Empty for `.custom`.
    var names: [String] {
        switch self {
        case .latinMixed:
            ["Do", "Do#", "Re", "Mi♭", "Mi", "Fa", "Fa#", "Sol", "Sol#", "La", "Si♭", "Si"]
        case .latinSharps:
            ["Do", "Do#", "Re", "Re#", "Mi", "Fa", "Fa#", "Sol", "Sol#", "La", "La#", "Si"]
        case .latinFlats:
            ["Do", "Re♭", "Re", "Mi♭", "Mi", "Fa", "Sol♭", "Sol", "La♭", "La", "Si♭", "Si"]
        case .englishSharps:
            ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        case .englishFlats:
            ["C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"]
        case .custom:
            []
        }
    }
}

/// Twelve editable tone names keyed by pitch class (0…11).
struct ChromaticToneNames: Equatable, Codable, Sendable {
    /// Exactly 12 names, index = pitch class.
    var names: [String]
    var preset: ChromaticTonePreset

    static let count = 12

    static let `default` = ChromaticToneNames(preset: .latinMixed)

    init(names: [String], preset: ChromaticTonePreset) {
        self.names = Self.normalized(names)
        self.preset = preset
    }

    init(preset: ChromaticTonePreset) {
        let source = preset == .custom
            ? ChromaticTonePreset.latinMixed.names
            : preset.names
        self.names = Self.normalized(source)
        self.preset = preset == .custom ? .custom : preset
    }

    func name(forPitchClass pc: Int) -> String {
        let index = ((pc % Self.count) + Self.count) % Self.count
        let value = names[index].trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? Self.default.names[index] : value
    }

    /// Resolve a letter-name root (`C`, `C#`, `Db`, `Bb`…) to the configured chromatic name.
    func name(forLetterRoot root: String) -> String? {
        guard let pc = Self.pitchClass(forLetterRoot: root) else { return nil }
        return name(forPitchClass: pc)
    }

    mutating func setName(_ name: String, forPitchClass pc: Int) {
        let index = ((pc % Self.count) + Self.count) % Self.count
        var next = names
        next[index] = name.trimmingCharacters(in: .whitespacesAndNewlines)
        names = Self.normalized(next)
        preset = .custom
    }

    mutating func apply(preset: ChromaticTonePreset) {
        guard preset != .custom else {
            self.preset = .custom
            return
        }
        names = Self.normalized(preset.names)
        self.preset = preset
    }

    /// Match current names to a built-in preset when possible.
    mutating func reconcilePreset() {
        for candidate in ChromaticTonePreset.allCases where candidate != .custom {
            if Self.normalized(candidate.names) == names {
                preset = candidate
                return
            }
        }
        preset = .custom
    }

    private static func normalized(_ input: [String]) -> [String] {
        var result = Array(input.prefix(count))
        let fallback = ChromaticTonePreset.latinMixed.names
        while result.count < count {
            result.append(fallback[result.count])
        }
        for i in result.indices {
            let trimmed = result[i].trimmingCharacters(in: .whitespacesAndNewlines)
            result[i] = trimmed.isEmpty ? fallback[i] : trimmed
        }
        return result
    }

    /// Pitch class for a root like `C`, `C#`, `Db`, `Bb`, `E♭`, `F♯`.
    static func pitchClass(forLetterRoot root: String) -> Int? {
        let trimmed = root.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return nil }
        let letter = Character(first.uppercased())
        guard let base = naturalPitchClass[letter] else { return nil }
        let accidental = trimmed.dropFirst()
            .replacingOccurrences(of: "♯", with: "#")
            .replacingOccurrences(of: "♭", with: "b")
            .replacingOccurrences(of: "＃", with: "#")
        var pc = base
        for ch in accidental {
            switch ch {
            case "#", "s", "S": pc += 1
            case "b", "B": pc -= 1
            default: break
            }
        }
        return ((pc % count) + count) % count
    }

    private static let naturalPitchClass: [Character: Int] = [
        "C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11
    ]
}
