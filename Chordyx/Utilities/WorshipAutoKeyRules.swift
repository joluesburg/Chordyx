//
//  WorshipAutoKeyRules.swift
//  Chordyx
//
//  Church / worship Auto-key priors from host musician rules:
//  - Never lock on 3 chords alone — wait for ~2 full loops
//  - vi–IV–I–V → relative major; Andalusian / i–V → minor letter
//  - Ambiguous 3-chord stems are decided by the 4th chord (and a second loop)
//

import Foundation

enum WorshipAutoKeyRules: Sendable {

    struct Tone: Equatable, Sendable {
        let root: Int
        let isMinor: Bool
    }

    /// True when a chord loop of length 3…8 has been heard at least twice in a row.
    static func hasTwoLoopEvidence(_ symbols: [String]) -> Bool {
        let tones = tones(from: symbols)
        guard tones.count >= 6 else { return false }
        let maxL = min(12, tones.count / 2)
        for length in 3...maxL {
            if consecutiveLoopRepetitions(tones: tones, length: length) >= 2 {
                return true
            }
        }
        return false
    }

    /// Strong worship key if two loops match a known pattern; otherwise nil.
    static func resolveKey(from symbols: [String]) -> MusicalKey? {
        let tones = tones(from: symbols)
        guard tones.count >= 6 else { return nil }

        let maxL = min(12, tones.count / 2)
        for length in stride(from: maxL, through: 3, by: -1) {
            guard consecutiveLoopRepetitions(tones: tones, length: length) >= 2 else { continue }
            let loop = Array(tones.suffix(length))
            if let key = matchLoop(loop) {
                return key
            }
            // Also try rotating the loop (song may start mid-cycle).
            for shift in 1..<length {
                let rotated = Array(loop[shift...]) + Array(loop[..<shift])
                if let key = matchLoop(rotated) {
                    return key
                }
            }
        }
        return nil
    }

    /// Boost / override scores for the MIR blend when a worship loop is clear.
    static func applyScoreBoost(
        symbols: [String],
        into scores: inout [MusicalKey: Double]
    ) {
        guard let key = resolveKey(from: symbols) else { return }
        scores[key, default: 0] += 0.55
    }

    // MARK: - Loop matching

    private static func matchLoop(_ loop: [Tone]) -> MusicalKey? {
        // Prefer longer / more specific templates first.
        if let key = matchDegreeTemplate(
            loop,
            degrees: [0, 7, 0, 5, 10, 3, 8, 5, 7, 0],
            minorMask: [true, false, true, true, false, false, false, true, false, true],
            tonicIsMinor: true
        ) {
            // Am E Am Dm G C F Dm E Am (worship minor journey) — key letter = Am tonic.
            return key
        }
        if let key = matchDegreeTemplate(
            loop,
            degrees: [9, 5, 0, 7],
            minorMask: [true, false, false, false],
            tonicIsMinor: false
        ) {
            return key // vi IV I V → major
        }
        if let key = matchDegreeTemplate(
            loop,
            degrees: [0, 7, 9, 5],
            minorMask: [false, false, true, false],
            tonicIsMinor: false
        ) {
            return key // I V vi IV
        }
        if let key = matchDegreeTemplate(
            loop,
            degrees: [0, 9, 5, 7],
            minorMask: [false, true, false, false],
            tonicIsMinor: false
        ) {
            return key // I vi IV V
        }
        if let key = matchDegreeTemplate(
            loop,
            degrees: [0, 10, 8, 7],
            minorMask: [true, false, false, false],
            tonicIsMinor: true
        ) {
            return key // Andalusian i bVII bVI V
        }
        if let key = matchDegreeTemplate(
            loop,
            degrees: [0, 5, 7, 0],
            minorMask: [true, true, false, true],
            tonicIsMinor: true
        ) {
            return key // i iv V i
        }
        // Am D Bm Em → G (ii V iii vi) — common worship / pop in G; not C.
        if let key = matchDegreeTemplate(
            loop,
            degrees: [2, 7, 4, 9],
            minorMask: [true, false, true, true],
            tonicIsMinor: false
        ) {
            return key
        }
        // Am D Bm Em Am D G → G (ii V iii vi ii V I)
        if let key = matchDegreeTemplate(
            loop,
            degrees: [2, 7, 4, 9, 2, 7, 0],
            minorMask: [true, false, true, true, true, false, false],
            tonicIsMinor: false
        ) {
            return key
        }
        // Am D G → G (ii V I) shorter stem
        if let key = matchDegreeTemplate(
            loop,
            degrees: [2, 7, 0],
            minorMask: [true, false, false],
            tonicIsMinor: false
        ) {
            return key // ii V I
        }
        if let key = matchDegreeTemplate(
            loop,
            degrees: [7, 5, 0],
            minorMask: [false, false, false],
            tonicIsMinor: false
        ) {
            return key // V IV I (C Bb F → F)
        }
        if let key = matchDegreeTemplate(
            loop,
            degrees: [5, 7, 0],
            minorMask: [false, false, false],
            tonicIsMinor: false
        ) {
            return key // IV V I
        }
        if let key = matchDegreeTemplate(
            loop,
            degrees: [0, 5, 7],
            minorMask: [false, false, false],
            tonicIsMinor: false
        ) {
            return key // I IV V
        }
        if let key = matchDegreeTemplate(
            loop,
            degrees: [0, 5, 7, 9],
            minorMask: [false, false, false, true],
            tonicIsMinor: false
        ) {
            return key // I IV V vi
        }
        if let key = matchDegreeTemplate(
            loop,
            degrees: [0, 7, 5, 9],
            minorMask: [false, false, false, true],
            tonicIsMinor: false
        ) {
            return key // I V IV vi  (G D C Em → G)
        }
        if let key = matchAmbiguousFour(loop) {
            return key
        }
        if let key = matchDegreeTemplate(
            loop,
            degrees: [9, 7, 5, 7],
            minorMask: [true, false, false, false],
            tonicIsMinor: false
        ) {
            return key // Am G F G → C
        }
        if let key = matchDegreeTemplate(
            loop,
            degrees: [0, 9, 2, 7],
            minorMask: [false, false, true, false],
            tonicIsMinor: false
        ) {
            return key // C A7 Dm G / G E7 Am D turnaround family
        }
        return nil
    }

    /// 3-chord stems + deciding 4th chord (host rules). Roots are absolute pitch classes.
    private static func matchAmbiguousFour(_ loop: [Tone]) -> MusicalKey? {
        guard loop.count == 4 else { return nil }
        let roots = loop.map(\.root)

        // D Em G + A → D; + C → G
        if roots[0] == 2, roots[1] == 4, roots[2] == 7 {
            if roots[3] == 9 { return .D }
            if roots[3] == 0 { return .G }
        }
        // C Dm F + Bb → F; + G → C
        if roots[0] == 0, roots[1] == 2, roots[2] == 5 {
            if roots[3] == 10 { return .F }
            if roots[3] == 7 { return .C }
        }
        // E F#m A + B → E; + D → A
        if roots[0] == 4, roots[1] == 6, roots[2] == 9 {
            if roots[3] == 11 { return .E }
            if roots[3] == 2 { return .A }
        }
        // G Am C + D → G; + F → C
        if roots[0] == 7, roots[1] == 9, roots[2] == 0 {
            if roots[3] == 2 { return .G }
            if roots[3] == 5 { return .C }
        }
        // Am F G + C → C; + Dm → A (Am)
        if roots[0] == 9, roots[1] == 5, roots[2] == 7 {
            if roots[3] == 0 { return .C }
            if roots[3] == 2 { return .A }
        }
        // Em C D + G → G; + Am → E (Em)
        if roots[0] == 4, roots[1] == 0, roots[2] == 2 {
            if roots[3] == 7 { return .G }
            if roots[3] == 9 { return .E }
        }
        // Em G C + D → G; + Am/B → E; + F → C
        if roots[0] == 4, roots[1] == 7, roots[2] == 0 {
            if roots[3] == 2 { return .G }
            if roots[3] == 9 || roots[3] == 11 { return .E }
            if roots[3] == 5 { return .C }
        }
        // Dm F G + C → C; + Am → D (Dm)
        if roots[0] == 2, roots[1] == 5, roots[2] == 7 {
            if roots[3] == 0 { return .C }
            if roots[3] == 9 { return .D }
        }
        // Em G A + D → D; + C → G
        if roots[0] == 4, roots[1] == 7, roots[2] == 9 {
            if roots[3] == 2 { return .D }
            if roots[3] == 0 { return .G }
        }
        // Dm Bb C + F → F; + Gm → D (Dm)
        if roots[0] == 2, roots[1] == 10, roots[2] == 0 {
            if roots[3] == 5 { return .F }
            if roots[3] == 7, loop[3].isMinor { return .D }
        }
        return nil
    }

    /// Degrees are relative to `MusicalKey` tonic letter (Am song → `.A`).
    private static func matchDegreeTemplate(
        _ loop: [Tone],
        degrees: [Int],
        minorMask: [Bool],
        tonicIsMinor: Bool
    ) -> MusicalKey? {
        guard loop.count == degrees.count, degrees.count == minorMask.count else { return nil }
        _ = tonicIsMinor
        for tonic in MusicalKey.allCases {
            let t = tonic.pitchClass
            var ok = true
            for i in 0..<loop.count {
                let expectedRoot = (t + degrees[i]) % 12
                guard loop[i].root == expectedRoot else {
                    ok = false
                    break
                }
                let wantMinor = minorMask[i]
                if loop[i].isMinor == wantMinor { continue }
                // Dom7 / maj on a "major" slot is fine; never accept major where minor is required.
                if !wantMinor, !loop[i].isMinor { continue }
                ok = false
                break
            }
            if ok { return tonic }
        }
        return nil
    }

    // MARK: - Helpers

    static func tones(from symbols: [String]) -> [Tone] {
        symbols.compactMap { symbol -> Tone? in
            let base = LiveRing.normalize(symbol)
            guard let parsed = Transposer.parse(base),
                  let root = Transposer.pitchClass(ofRoot: parsed.root) else { return nil }
            let suffix = parsed.suffix.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let isMinor = suffix.hasPrefix("m") && !suffix.hasPrefix("maj")
            return Tone(root: root, isMinor: isMinor)
        }
    }

    private static func consecutiveLoopRepetitions(tones: [Tone], length: Int) -> Int {
        guard tones.count >= length * 2 else { return 0 }
        let end = tones.count
        let last = Array(tones[(end - length)..<end])
        let prev = Array(tones[(end - 2 * length)..<(end - length)])
        guard loopsEqual(last, prev) else { return 0 }
        var reps = 2
        var cursor = end - 2 * length
        while cursor >= length {
            let earlier = Array(tones[(cursor - length)..<cursor])
            if loopsEqual(earlier, last) {
                reps += 1
                cursor -= length
            } else {
                break
            }
        }
        return reps
    }

    private static func loopsEqual(_ a: [Tone], _ b: [Tone]) -> Bool {
        guard a.count == b.count else { return false }
        for i in 0..<a.count {
            if a[i].root != b[i].root { return false }
            // Quality: treat both minor or both major; allow maj7/dom as major.
            if a[i].isMinor != b[i].isMinor { return false }
        }
        return true
    }
}
