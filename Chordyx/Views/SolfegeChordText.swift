//
//  SolfegeChordText.swift
//  Chordyx
//

import SwiftUI

/// Renders solfège and Nashville chord names with extensions as superscript
/// (e.g. Solᵐ⁷, 5⁷, 6m⁷).
enum SolfegeChordText {
    private static let syllables = ["Sol", "Do", "Re", "Mi", "Fa", "La", "Si"]

    static func make(
        _ name: String,
        notation: ChordNotation,
        size: CGFloat,
        weight: Font.Weight = .bold,
        design: Font.Design = .rounded
    ) -> Text {
        let font = Font.system(size: size, weight: weight, design: design)
        switch notation {
        case .latin:
            return Text(latinAttributed(name, font: font, size: size))
        case .nashville:
            return Text(NashvilleDisplay.makeAttributed(name, font: font, size: size))
        case .symbol:
            return Text(name).font(font)
        }
    }

    private static func latinAttributed(_ latin: String, font: Font, size: CGFloat) -> AttributedString {
        let parts = latin.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2 else {
            return formatPartAttributed(latin, font: font, size: size)
        }
        var result = formatPartAttributed(String(parts[0]), font: font, size: size)
        result.append(attributed("/", font: font))
        result.append(formatPartAttributed(String(parts[1]), font: font, size: size))
        return result
    }

    private static func formatPartAttributed(_ latin: String, font: Font, size: CGFloat) -> AttributedString {
        for syllable in syllables where latin.hasPrefix(syllable) {
            let root = String(syllable)
            let suffix = String(latin.dropFirst(syllable.count))
            var result = attributed(root, font: font)
            if !suffix.isEmpty {
                result.append(superscriptAttributed(suffix, size: size))
            }
            return result
        }
        return attributed(latin, font: font)
    }

    private static func attributed(_ string: String, font: Font) -> AttributedString {
        var text = AttributedString(string)
        var attributes = AttributeContainer()
        attributes.font = font
        text.mergeAttributes(attributes)
        return text
    }

    private static func superscriptAttributed(_ text: String, size: CGFloat) -> AttributedString {
        var attributed = AttributedString(text)
        var attributes = AttributeContainer()
        attributes.font = .system(size: size * 0.58, weight: .semibold, design: .rounded)
        attributes.baselineOffset = size * 0.24
        attributed.mergeAttributes(attributes)
        return attributed
    }
}

extension ChordEntry {
    func chordText(
        for notation: ChordNotation,
        key: MusicalKey = .C,
        transposeSemitones: Int = 0,
        capoFret: Int = 0,
        size: CGFloat,
        weight: Font.Weight = .bold,
        design: Font.Design = .rounded
    ) -> Text {
        SolfegeChordText.make(
            ChordDisplayHelper.displayName(
                for: self,
                notation: notation,
                songKey: key,
                transposeSemitones: transposeSemitones,
                capoFret: capoFret
            ),
            notation: notation,
            size: size,
            weight: weight,
            design: design
        )
    }
}
