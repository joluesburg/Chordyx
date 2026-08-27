//
//  KeyChordAnalysis.swift
//  Chordyx
//
//  Pure key/chord analysis helpers — safe to call from any isolation domain.
//

import Foundation

enum KeyChordAnalysis: Sendable {
    private static let majorProfile: [Double] = [
        6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88
    ]
    private static let minorProfile: [Double] = [
        6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17
    ]

    /// True when the held voicing looks like a real chord (not a melody single note).
    /// Major triads often label as bare letters ("C", "G") — those count when ≥3 pitch classes.
    static func isChordVoicing(pitchClassCount: Int, symbol: String) -> Bool {
        guard pitchClassCount >= 2, let parsed = Transposer.parse(symbol) else { return false }
        let suffix = parsed.suffix
            .split(separator: "/", maxSplits: 1)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        // Bare letter with a full triad/seventh voicing under the fingers = major (or incomplete label).
        if suffix.isEmpty {
            return pitchClassCount >= 3
        }
        // Any explicit quality with ≥2 distinct pitch classes counts (incl. power / sus / m7).
        return true
    }

    /// True triad / seventh / major-letter quality — strengthens Auto-key evidence.
    /// Bare letters are treated as major triads (MIDI controllers emit "C" for C–E–G).
    static func hasTriadOrSeventhQuality(_ symbol: String) -> Bool {
        guard let parsed = Transposer.parse(symbol) else { return false }
        let suffix = parsed.suffix
            .split(separator: "/", maxSplits: 1)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        // Power chords alone are too weak / scale-like to unlock Auto-key by themselves.
        if suffix == "5" { return false }
        return true
    }

    /// Power chords and sus are valid live evidence when the host plays guitar.
    /// Piano majors (bare letter + ≥3 PCs) and inversions (C/E) always count.
    static func contributesToLiveKeyEvidence(symbol: String, pitchClassCount: Int, guitarMode: Bool) -> Bool {
        if isChordVoicing(pitchClassCount: pitchClassCount, symbol: symbol) { return true }
        guard guitarMode, pitchClassCount >= 2 else { return false }
        let normalized = LiveRing.normalize(symbol)
        if normalized.hasSuffix("5") || normalized.contains("sus") { return true }
        return false
    }

    /// Build an Auto-key evidence symbol that keeps slash-bass inversions when MIDI provides them.
    static func keyEvidenceSymbol(
        displaySymbol: String,
        noteIndices: [Int],
        preferFlats: Bool
    ) -> String {
        let trimmed = displaySymbol.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        guard let bassPC = noteIndices.min().map({ PianoNote.pitchClass(forStored: $0) }),
              let parsed = Transposer.parse(LiveRing.normalize(trimmed)),
              let rootPC = Transposer.pitchClass(ofRoot: parsed.root),
              bassPC != rootPC else {
            return trimmed
        }
        // Already has inversion spelling.
        if trimmed.contains("/") { return trimmed }
        let names = preferFlats ? Transposer.flatNames : Transposer.sharpNames
        let quality = LiveRing.normalize(trimmed)
        return "\(quality)/\(names[bassPC])"
    }

    /// Enough ordered chord evidence to announce a key.
    /// Worship rule: never lock on a single short phrase — wait for ~2 full loops.
    static func hasProgressionEvidence(_ symbols: [String]) -> Bool {
        let normalized = symbols.map { LiveRing.normalize($0) }.filter { !$0.isEmpty }
        // Three consecutive chords are never enough (host rule).
        guard normalized.count >= 6 else { return false }

        let roots = normalized.compactMap { symbol -> Int? in
            guard let parsed = Transposer.parse(symbol) else { return nil }
            return Transposer.pitchClass(ofRoot: parsed.root)
        }
        let distinctRoots = Set(roots)
        guard distinctRoots.count >= 2 else { return false }

        let hasQualityChord = normalized.contains { hasTriadOrSeventhQuality($0) }
        guard hasQualityChord else { return false }

        let hasPowerChord = normalized.contains { symbol in
            guard let parsed = Transposer.parse(symbol) else { return false }
            return parsed.suffix.trimmingCharacters(in: .whitespacesAndNewlines) == "5"
        }
        if hasPowerChord && normalized.allSatisfy({ symbol in
            guard let parsed = Transposer.parse(symbol) else { return false }
            let suffix = parsed.suffix.trimmingCharacters(in: .whitespacesAndNewlines)
            return suffix == "5" || suffix.isEmpty
        }) {
            return false
        }

        // Primary gate: the same loop heard twice in a row.
        if WorshipAutoKeyRules.hasTwoLoopEvidence(normalized) {
            return true
        }

        // Clear V→I / IV→I / ii–V–I arrival (e.g. …Am D G) — don't wait for 8 chords
        // while the UI still shows the default Do/C letter.
        if authenticDominantCadenceDestination(in: normalized) != nil, distinctRoots.count >= 3 {
            return true
        }
        if majorCadenceDestination(in: normalized) != nil, distinctRoots.count >= 3, normalized.count >= 7 {
            return true
        }
        // Fmaj7 + Gm7 + … + C7 — I/V7 jazz-worship set on the pad is enough evidence.
        if establishedMajorTonicFromIAndV7(in: normalized) != nil, distinctRoots.count >= 3 {
            return true
        }
        // D G A / D Bm G A — major family is enough; don't wait while Mi is stuck on screen.
        if establishedMajorFamilyTonic(in: normalized) != nil, distinctRoots.count >= 3 {
            return true
        }

        // Fallback for irregular phrases: enough length + cadence / established tonic.
        guard normalized.count >= 8 else { return false }
        if establishedMinorTonic(in: normalized) != nil { return true }
        if distinctRoots.count >= 3 { return true }
        return false
    }

    // MARK: - Live tonal center arbitration

    private struct ChordTone: Sendable {
        let root: Int
        let isMinor: Bool
    }

    private static func chordTones(from symbols: [String]) -> [ChordTone] {
        symbols.compactMap { symbol -> ChordTone? in
            guard let parsed = Transposer.parse(symbol),
                  let root = Transposer.pitchClass(ofRoot: parsed.root) else { return nil }
            let suffix = parsed.suffix.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let isMinor = suffix.hasPrefix("m") && !suffix.hasPrefix("maj")
            return ChordTone(root: root, isMinor: isMinor)
        }
    }

    /// Major tonic that received a clear V→I / IV→I / ii→V→I arrival (live cadence wins).
    static func majorCadenceDestination(in symbols: [String]) -> Int? {
        let tones = chordTones(from: symbols)
        guard tones.count >= 2, let last = tones.last, !last.isMinor else { return nil }
        let tonic = last.root

        // Final arrival is V→I or IV→I.
        if tones.count >= 2 {
            let prev = tones[tones.count - 2]
            let interval = (tonic - prev.root + 12) % 12
            if interval == 5 || interval == 7 { return tonic }
        }
        // ii→V→I
        if tones.count >= 3 {
            let a = tones[tones.count - 3]
            let b = tones[tones.count - 2]
            let c = tones[tones.count - 1]
            let aIsII = a.isMinor && (a.root - c.root + 12) % 12 == 2
            let bIsV = (b.root - c.root + 12) % 12 == 7
            if aIsII, bIsV, !c.isMinor { return tonic }
        }
        // Phrase ends on I and contains both V and (IV or ii) for that tonic.
        let hasV = tones.contains { ($0.root - tonic + 12) % 12 == 7 }
        let hasIV = tones.contains { !$0.isMinor && ($0.root - tonic + 12) % 12 == 5 }
        let hasII = tones.contains { $0.isMinor && ($0.root - tonic + 12) % 12 == 2 }
        let tonicHits = tones.filter { $0.root == tonic && !$0.isMinor }.count
        if tonicHits >= 1, hasV, hasIV || hasII { return tonic }
        return nil
    }

    /// Dm–Em–F–G / Dm–Em7–F–G — diatonic climb from ii in a major key (C), not D minor.
    private static func looksLikeMajorSupertonicRun(tones: [ChordTone], minorRoot: Int) -> Bool {
        guard let first = tones.first, first.isMinor, first.root == minorRoot else { return false }
        let roots = Set(tones.map(\.root))
        let third = (minorRoot + 2) % 12   // Em from Dm
        let fourth = (minorRoot + 3) % 12  // F
        let fifth = (minorRoot + 5) % 12   // G
        let hasClimb = roots.contains(third) && roots.contains(fourth) && roots.contains(fifth)
        guard hasClimb else { return false }
        let hasMinorMarkers = tones.contains {
            let deg = ($0.root - minorRoot + 12) % 12
            if deg == 5, $0.isMinor { return true } // iv
            if deg == 8, !$0.isMinor { return true } // bVI
            if deg == 10, !$0.isMinor { return true } // bVII
            if deg == 7 { return true } // V of minor
            return false
        }
        return !hasMinorMarkers
    }

    private static func hasMinorModeSupport(tones: [ChordTone], minorTonic: Int) -> Bool {
        tones.contains { tone in
            let deg = (tone.root - minorTonic + 12) % 12
            if deg == 5, tone.isMinor { return true } // iv
            if deg == 8, !tone.isMinor { return true } // bVI
            if deg == 10, !tone.isMinor { return true } // bVII
            if deg == 7 { return true } // V / v
            // bIII alone is too weak (G in Em–F–G is also V of C) — don't count it.
            return false
        }
    }

    /// True minor-mode tonic (song in that minor) — not merely ii / vi of a major key.
    static func establishedMinorTonic(in symbols: [String]) -> Int? {
        let normalized = symbols.map { LiveRing.normalize($0) }.filter { !$0.isEmpty }
        let tones = chordTones(from: normalized)
        guard tones.count >= 3 else { return nil }

        var minorMass = [Int: Double]()
        var minorHits = [Int: Int]()
        for (index, tone) in tones.enumerated() where tone.isMinor {
            let weight = 1.0 + Double(index) / Double(max(tones.count, 1)) * 0.45
            let frame = (index == 0 || index == tones.count - 1) ? 1.35 : 1.0
            minorMass[tone.root, default: 0] += weight * frame
            minorHits[tone.root, default: 0] += 1
        }
        guard let (minorTonic, mass) = minorMass.max(by: { $0.value < $1.value }),
              mass >= 1.15 else { return nil }

        let hits = minorHits[minorTonic] ?? 0
        let opens = tones.first?.isMinor == true && tones.first?.root == minorTonic
        let closes = tones.last?.isMinor == true && tones.last?.root == minorTonic

        // Major cadence elsewhere → this minor is ii / vi, not the song tonic.
        if let majorI = majorCadenceDestination(in: normalized), majorI != minorTonic {
            let isSupertonicOfMajor = (minorTonic - majorI + 12) % 12 == 2
            let isRelativeMinorOfMajor = (minorTonic - majorI + 12) % 12 == 9
            if isSupertonicOfMajor || isRelativeMinorOfMajor {
                return nil
            }
        }

        // Dorian/Aeolian ascending run from ii (Dm Em F G) is C major, not D minor.
        if looksLikeMajorSupertonicRun(tones: tones, minorRoot: minorTonic) {
            return nil
        }

        if closes { return minorTonic }
        if hits >= 2, opens || closes { return minorTonic }
        if hits >= 2, mass >= 2.0 { return minorTonic }
        // Open minor phrase with real minor-mode companions (iv / bVI / V of minor).
        if opens, hits >= 1, mass >= 1.3, hasMinorModeSupport(tones: tones, minorTonic: minorTonic) {
            return minorTonic
        }
        return nil
    }

    /// Final arbitration after MIR / neural scores — keeps major I stable and blocks E-from-Dm.
    static func resolveLiveTonalCenter(
        symbols: [String],
        scores: [MusicalKey: Double],
        currentBest: MusicalKey
    ) -> MusicalKey {
        let normalized = symbols.map { LiveRing.normalize($0) }.filter { !$0.isEmpty }
        guard normalized.count >= 3 else { return currentBest }

        // 0) Worship / church loop priors (2× vi–IV–I–V, V–IV–I, Andalusian, …).
        if let worshipKey = WorshipAutoKeyRules.resolveKey(from: normalized) {
            return worshipKey
        }

        // 0b) Major family I+IV+V(+vi) — D G A Bm → D before any MIR/audio can invent E/Mi.
        if let tonicPC = establishedMajorFamilyTonic(in: normalized),
           let key = MusicalKey.allCases.first(where: { $0.pitchClass == tonicPC }) {
            return key
        }

        // 0c) I + V7 evidence (Fmaj7…C7 → F) beats relative/false letters like E/Mi.
        if let tonicPC = establishedMajorTonicFromIAndV7(in: normalized),
           let key = MusicalKey.allCases.first(where: { $0.pitchClass == tonicPC }) {
            return key
        }

        let tones = chordTones(from: normalized)

        // 1) Authentic V→I always wins (Am–D–…–D–G → G, never relative C).
        if let majorI = authenticDominantCadenceDestination(in: normalized),
           let key = MusicalKey.allCases.first(where: { $0.pitchClass == majorI }) {
            return key
        }
        // Soft: broader cadence (incl. IV→I) only when scores already lean that way.
        if let majorI = majorCadenceDestination(in: normalized),
           let key = MusicalKey.allCases.first(where: { $0.pitchClass == majorI }) {
            let majorScore = scores[key] ?? 0
            let bestScore = scores[currentBest] ?? 0
            if key == currentBest || majorScore >= bestScore * 0.55 {
                return key
            }
        }

        // 2) Ascending ii–iii–IV–V run → major tonic a whole step below the opening minor.
        if let first = tones.first, first.isMinor,
           looksLikeMajorSupertonicRun(tones: tones, minorRoot: first.root),
           let majorKey = MusicalKey.allCases.first(where: { $0.pitchClass == (first.root + 10) % 12 }) {
            return majorKey
        }

        // 3) Established minor tonic: prefer it over false iii / unrelated majors.
        if let minorTonic = establishedMinorTonic(in: normalized),
           let minorKey = MusicalKey.allCases.first(where: { $0.pitchClass == minorTonic }) {
            let relativeMajorPC = (minorTonic + 3) % 12
            if currentBest.pitchClass == minorTonic { return currentBest }
            if currentBest.pitchClass == relativeMajorPC {
                let closesMinor = tones.last?.isMinor == true && tones.last?.root == minorTonic
                if closesMinor { return minorKey }
                return currentBest
            }
            let dist = min(
                (currentBest.pitchClass - minorTonic + 12) % 12,
                (minorTonic - currentBest.pitchClass + 12) % 12
            )
            if dist >= 2 { return minorKey }
        }

        return preferMinorTonicIfSupported(symbols: normalized, scores: scores, currentBest: currentBest)
    }

    /// Live Auto-key veto for candidates that fight the heard progression.
    static func isImplausibleLiveKeyCandidate(symbols: [String], candidate: MusicalKey) -> Bool {
        if isImplausibleAgainstMajorFamily(symbols: symbols, candidate: candidate) {
            return true
        }
        if isImplausibleAgainstEstablishedMajorTonic(symbols: symbols, candidate: candidate) {
            return true
        }
        if isImplausibleAgainstMajorCadence(symbols: symbols, candidate: candidate) {
            return true
        }
        return isImplausibleAgainstMinorTonic(symbols: symbols, candidate: candidate)
    }

    /// D–G–A / D–Bm–G–A → Re. Reject Mi/E and every letter that isn't D or its relative minor.
    static func isImplausibleAgainstMajorFamily(
        symbols: [String],
        candidate: MusicalKey
    ) -> Bool {
        let normalized = symbols.map { LiveRing.normalize($0) }.filter { !$0.isEmpty }
        guard let tonic = establishedMajorFamilyTonic(in: normalized) else { return false }
        if candidate.pitchClass == tonic { return false }
        let relativeMinor = (tonic + 9) % 12
        if candidate.pitchClass == relativeMinor { return false }
        return true
    }

    /// I + IV + V (and optional vi) with plain major V — the worship / pop family that
    /// never needed a dominant-seventh to be obvious (D G A Bm → D, never E).
    static func establishedMajorFamilyTonic(in symbols: [String]) -> Int? {
        let tones = chordTonesDetailed(from: symbols)
        guard tones.count >= 3 else { return nil }

        var majorHits = [Int: Int]()
        var minorHits = [Int: Int]()
        var dominantRoots = Set<Int>()
        for tone in tones {
            if tone.isDominantSeventh {
                // V7 never counts as a tonic I candidate (C7 is V of F, not tonic C).
                dominantRoots.insert(tone.root)
                continue
            }
            if tone.isSolidMajorTonic {
                majorHits[tone.root, default: 0] += 2
            } else if tone.isMajorFamily {
                majorHits[tone.root, default: 0] += 1
            } else if tone.isMinorFamily {
                minorHits[tone.root, default: 0] += 1
            }
        }

        var best: (tonic: Int, score: Int)?
        for tonic in 0..<12 {
            let iHits = majorHits[tonic] ?? 0
            guard iHits >= 1 else { continue }
            let iv = (tonic + 5) % 12
            let v = (tonic + 7) % 12
            let ii = (tonic + 2) % 12
            let iii = (tonic + 4) % 12
            let vi = (tonic + 9) % 12
            let hasIV = (majorHits[iv] ?? 0) >= 1
            let hasV = (majorHits[v] ?? 0) >= 1 || dominantRoots.contains(v)
            let hasII = (minorHits[ii] ?? 0) >= 1
            let hasIII = (minorHits[iii] ?? 0) >= 1
            let hasVI = (minorHits[vi] ?? 0) >= 1

            // Must hear V (or V7). I+IV+vi without V is too ambiguous (Am D Bm Em G looks like D).
            guard hasV else { continue }
            // Plus at least one more diatonic pillar.
            guard hasIV || hasII || hasVI else { continue }

            var score = iHits * 3
            if hasV { score += 4 }
            if hasIV { score += 3 }
            if hasII { score += 2 }
            if hasVI { score += 1 }
            if hasIII { score += 1 }
            if dominantRoots.contains(v) { score += 2 }
            if score >= 9, best == nil || score > best!.score {
                best = (tonic, score)
            }
        }
        return best?.tonic
    }

    /// Fmaj7 + C7 (I + V7) → Fa. Reject Mi/E and other distant letters.
    static func isImplausibleAgainstEstablishedMajorTonic(
        symbols: [String],
        candidate: MusicalKey
    ) -> Bool {
        let normalized = symbols.map { LiveRing.normalize($0) }.filter { !$0.isEmpty }
        guard let tonic = establishedMajorTonicFromIAndV7(in: normalized) else { return false }
        if candidate.pitchClass == tonic { return false }
        let relativeMinor = (tonic + 9) % 12
        if candidate.pitchClass == relativeMinor { return false }
        return true
    }

    /// Clear I / Imaj7 plus V7 (or V) of that tonic in the phrase — worship / jazz jam lock.
    static func establishedMajorTonicFromIAndV7(in symbols: [String]) -> Int? {
        let tones = chordTonesDetailed(from: symbols)
        guard tones.count >= 3 else { return nil }

        var tonicStrength = [Int: Int]()
        var hasV7 = Set<Int>()
        var hasV = Set<Int>()

        for tone in tones {
            // Dom7 on a root is V7 of something — never treat it as that root's tonic I.
            if tone.isDominantSeventh {
                let tonic = (tone.root + 5) % 12
                hasV7.insert(tonic)
                continue
            }
            if tone.isSolidMajorTonic {
                tonicStrength[tone.root, default: 0] += 3
            } else if tone.isMajorFamily {
                // sus / ambiguous major-ish — weak tonic evidence only.
                tonicStrength[tone.root, default: 0] += 1
                let asVOf = (tone.root + 5) % 12
                hasV.insert(asVOf)
            }
            if tone.isMinorFamily {
                // counted below as ii / iii / vi support
            }
        }

        var best: (tonic: Int, score: Int)?
        for (tonic, strength) in tonicStrength where strength >= 2 {
            var score = strength
            if hasV7.contains(tonic) { score += 6 }
            else if hasV.contains(tonic) { score += 2 }
            else { continue }
            let hasII = tones.contains { $0.isMinorFamily && ($0.root - tonic + 12) % 12 == 2 }
            let hasIII = tones.contains { $0.isMinorFamily && ($0.root - tonic + 12) % 12 == 4 }
            let hasIV = tones.contains { $0.isSolidMajorTonic && ($0.root - tonic + 12) % 12 == 5 }
            let hasVI = tones.contains { $0.isMinorFamily && ($0.root - tonic + 12) % 12 == 9 }
            if hasII { score += 2 }
            if hasIII { score += 1 }
            if hasIV { score += 1 }
            if hasVI { score += 1 }
            // Prefer the tonic that actually received V7 (Fmaj7+C7 → F, not G from D7 alone).
            if hasV7.contains(tonic) { score += 2 }
            if score >= 8, best == nil || score > best!.score {
                best = (tonic, score)
            }
        }
        return best?.tonic
    }

    private struct DetailedTone: Sendable {
        let root: Int
        let isMinorFamily: Bool
        let isMajorFamily: Bool
        let isSolidMajorTonic: Bool
        let isDominantSeventh: Bool
    }

    private static func chordTonesDetailed(from symbols: [String]) -> [DetailedTone] {
        symbols.compactMap { symbol -> DetailedTone? in
            // Analyze quality on the chord body; keep bass PC available for inversion weight.
            let body = LiveRing.normalize(symbol)
            guard let parsed = Transposer.parse(body),
                  let root = Transposer.pitchClass(ofRoot: parsed.root) else { return nil }
            let s = parsed.suffix.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let isMinor = s.hasPrefix("m") && !s.hasPrefix("maj")
            let isDom7 = !isMinor && !s.hasPrefix("maj") && (
                s == "7"
                    || (s.hasPrefix("7") && !s.contains("sus"))
                    || s.hasPrefix("9")
                    || s.hasPrefix("11")
                    || s.hasPrefix("13")
                    || s == "dom7"
            )
            let isSus = s.contains("sus")
            let isSolidMajor = !isMinor && !isDom7 && !isSus && (
                s.isEmpty || s.hasPrefix("maj") || s.hasPrefix("add") || s == "6" || s == "6/9"
            )
            let isMajorFamily = !isMinor && (isSolidMajor || isSus || isDom7 || s == "5")
            return DetailedTone(
                root: root,
                isMinorFamily: isMinor,
                isMajorFamily: isMajorFamily,
                isSolidMajorTonic: isSolidMajor,
                isDominantSeventh: isDom7
            )
        }
    }

    /// Reject Do/C when the phrase clearly cadences elsewhere (…D→G → Sol, not Do).
    /// Only authentic V→I (not IV→I / plagal) — Am F C G must still be allowed as C.
    static func isImplausibleAgainstMajorCadence(symbols: [String], candidate: MusicalKey) -> Bool {
        let normalized = symbols.map { LiveRing.normalize($0) }.filter { !$0.isEmpty }
        guard let majorI = authenticDominantCadenceDestination(in: normalized) else { return false }
        if candidate.pitchClass == majorI { return false }
        // Relative minor of the cadence tonic is still plausible (Em for G).
        let relativeMinor = (majorI + 9) % 12
        if candidate.pitchClass == relativeMinor { return false }
        return true
    }

    /// V→I only (penultimate is dominant of the final major chord).
    static func authenticDominantCadenceDestination(in symbols: [String]) -> Int? {
        let tones = chordTones(from: symbols)
        guard tones.count >= 2, let last = tones.last, !last.isMinor else { return nil }
        let prev = tones[tones.count - 2]
        guard !prev.isMinor else { return nil }
        let interval = (last.root - prev.root + 12) % 12
        // Perfect 4th up from V → I (D→G, G→C, A→D, …).
        guard interval == 5 else { return nil }
        return last.root
    }

    /// Reject keys that fight a clear minor tonic (Dm playing must never announce E/Mi).
    /// Only when the minor tonic is *established* — not when Dm is merely ii of C / F.
    static func isImplausibleAgainstMinorTonic(symbols: [String], candidate: MusicalKey) -> Bool {
        let normalized = symbols.map { LiveRing.normalize($0) }.filter { !$0.isEmpty }
        guard normalized.count >= 3 else { return false }
        guard let minorTonic = establishedMinorTonic(in: normalized) else { return false }

        if candidate.pitchClass == minorTonic { return false }
        let relativeMajorPC = (minorTonic + 3) % 12
        if candidate.pitchClass == relativeMajorPC { return false }

        if let majorI = majorCadenceDestination(in: normalized), candidate.pitchClass == majorI {
            return false
        }

        let dist = min(
            (candidate.pitchClass - minorTonic + 12) % 12,
            (minorTonic - candidate.pitchClass + 12) % 12
        )
        return dist >= 2
    }

    /// Prefer the minor tonal center when the progression is clearly minor-rooted
    /// (e.g. Dm–Gm–A / Dm–Bb–F–C) instead of jumping to a relative / unrelated major.
    static func preferMinorTonicIfSupported(
        symbols: [String],
        scores: [MusicalKey: Double],
        currentBest: MusicalKey
    ) -> MusicalKey {
        let normalized = symbols.map { LiveRing.normalize($0) }.filter { !$0.isEmpty }
        guard normalized.count >= 3 else { return currentBest }
        let tones = chordTones(from: normalized)

        // Never override a resolved major cadence (C major must stay C when Dm is only ii).
        if let majorI = majorCadenceDestination(in: normalized),
           currentBest.pitchClass == majorI {
            return currentBest
        }
        if let first = tones.first, first.isMinor,
           looksLikeMajorSupertonicRun(tones: tones, minorRoot: first.root),
           let majorKey = MusicalKey.allCases.first(where: { $0.pitchClass == (first.root + 10) % 12 }) {
            return majorKey
        }

        guard let minorTonic = establishedMinorTonic(in: normalized) else {
            return currentBest
        }
        let majorAtSame = tones.filter { $0.root == minorTonic && !$0.isMinor }.count
        guard majorAtSame == 0 else { return currentBest }

        let candidate = MusicalKey.allCases.first { $0.pitchClass == minorTonic } ?? currentBest
        if candidate == currentBest { return currentBest }

        let candidateScore = scores[candidate] ?? 0
        let bestScore = scores[currentBest] ?? 0
        let relativeMajorPC = (minorTonic + 3) % 12
        let bestIsRelativeMajor = currentBest.pitchClass == relativeMajorPC

        // Pop I–V–vi–IV: vi is not the song tonic — keep the major center unless phrase closes on i.
        if bestIsRelativeMajor {
            let closesMinor = tones.last?.isMinor == true && tones.last?.root == minorTonic
            if !closesMinor { return currentBest }
        }

        if bestIsRelativeMajor, candidateScore >= bestScore * 0.68 {
            return candidate
        }
        if candidateScore >= bestScore * 0.80 {
            return candidate
        }

        let dist = min((currentBest.pitchClass - minorTonic + 12) % 12,
                       (minorTonic - currentBest.pitchClass + 12) % 12)
        // Hard veto only for clear false tonics (E/Mi from Dm), not nearby majors like C↔D.
        if dist >= 2, !bestIsRelativeMajor {
            return candidate
        }
        return currentBest
    }

    private static func hasAuthenticOrPlagalCadence(symbols: [String]) -> Bool {
        guard symbols.count >= 2 else { return false }
        for i in 1..<symbols.count {
            guard let a = Transposer.parse(symbols[i - 1]),
                  let b = Transposer.parse(symbols[i]),
                  let ra = Transposer.pitchClass(ofRoot: a.root),
                  let rb = Transposer.pitchClass(ofRoot: b.root) else { continue }
            let interval = (rb - ra + 12) % 12
            // V→I (up perfect 4th / down 5th) or IV→I (down perfect 4th).
            if interval == 5 || interval == 7 { return true }
        }
        return false
    }

    private static func dominantTonicRoot(in roots: [Int]) -> Int? {
        var counts = [Int: Int]()
        for root in roots { counts[root, default: 0] += 1 }
        guard let top = counts.max(by: { $0.value < $1.value }) else { return nil }
        return top.value >= 2 ? top.key : nil
    }

    static func krumhanselSchmuckler(from symbols: [String]) -> [MusicalKey: Double] {
        var histogram = [Double](repeating: 0, count: 12)
        for (index, symbol) in symbols.enumerated() {
            guard let parsed = Transposer.parse(symbol),
                  let pc = Transposer.pitchClass(ofRoot: parsed.root) else { continue }
            let recency = 1.0 + Double(index) / Double(max(symbols.count, 1)) * 0.5
            let qualityWeight = qualityWeight(for: parsed.suffix)
            histogram[pc] += recency * qualityWeight
        }
        let sum = histogram.reduce(0, +)
        guard sum > 0 else { return [:] }
        for index in 0..<12 { histogram[index] /= sum }

        var keyScores = [MusicalKey: Double]()
        for key in MusicalKey.allCases {
            let tonic = key.pitchClass
            var majorCorr = 0.0
            var minorCorr = 0.0
            for pc in 0..<12 {
                let rotatedMajor = majorProfile[(pc - tonic + 12) % 12]
                let rotatedMinor = minorProfile[(pc - tonic + 12) % 12]
                majorCorr += histogram[pc] * rotatedMajor
                minorCorr += histogram[pc] * rotatedMinor
            }
            keyScores[key] = max(majorCorr, minorCorr) / 6.35
        }
        return keyScores
    }

    static func fingerprint(from symbols: [String]) -> String {
        var tokens: [String] = []
        for symbol in symbols {
            guard let parsed = Transposer.parse(symbol),
                  let pc = Transposer.pitchClass(ofRoot: parsed.root) else { continue }
            let q = qualityToken(parsed.suffix)
            tokens.append("\(pc):\(q)")
        }
        return tokens.sorted().joined(separator: "|")
    }

    /// Ordered root+quality tokens (keeps sequence for progression matching).
    static func orderedTokens(from symbols: [String]) -> [String] {
        symbols.compactMap { symbol -> String? in
            guard let parsed = Transposer.parse(symbol),
                  let pc = Transposer.pitchClass(ofRoot: parsed.root) else { return nil }
            return "\(pc):\(qualityToken(parsed.suffix))"
        }
    }

    /// How well `live` matches a known library progression (0…1).
    /// Prefers ordered contiguous runs, then unique-chord overlap.
    static func progressionSimilarity(live: [String], library: [String]) -> Double {
        let liveTokens = orderedTokens(from: live)
        let libraryTokens = orderedTokens(from: library)
        guard liveTokens.count >= 3, libraryTokens.count >= 3 else { return 0 }

        let liveWindow = Array(liveTokens.suffix(min(16, liveTokens.count)))
        let absolute = absoluteSimilarity(liveWindow: liveWindow, libraryTokens: libraryTokens)
        let relative = bestRelativeMatch(liveWindow: liveWindow, libraryTokens: libraryTokens).score
        return max(absolute, relative)
    }

    /// Best library progression key for the live sequence, if similarity is strong enough.
    /// When the match is transpose-related, returns the live key (library key + interval).
    static func bestLibraryKeyMatch(
        liveSymbols: [String],
        library: [(name: String, key: MusicalKey, symbols: [String])]
    ) -> (key: MusicalKey, confidence: Double, name: String, similarity: Double)? {
        var best: (key: MusicalKey, confidence: Double, name: String, similarity: Double)?
        for entry in library {
            let liveTokens = orderedTokens(from: liveSymbols)
            let libraryTokens = orderedTokens(from: entry.symbols)
            guard liveTokens.count >= 3, libraryTokens.count >= 3 else { continue }

            let liveWindow = Array(liveTokens.suffix(min(16, liveTokens.count)))
            let absolute = absoluteSimilarity(liveWindow: liveWindow, libraryTokens: libraryTokens)
            let relative = bestRelativeMatch(liveWindow: liveWindow, libraryTokens: libraryTokens)
            let similarity = max(absolute, relative.score)
            guard similarity >= 0.58 else { continue }

            let liveFP = fingerprint(from: Array(liveSymbols.suffix(12)))
            let libFP = fingerprint(from: entry.symbols)
            let exactBoost = liveFP == libFP ? 0.12 : 0
            let confidence = min(0.96, 0.55 + similarity * 0.40 + exactBoost)

            let resolvedKey: MusicalKey
            if absolute >= relative.score - 0.02 {
                resolvedKey = entry.key
            } else {
                let livePC = (entry.key.pitchClass + relative.shift) % 12
                resolvedKey = MusicalKey.allCases.first { $0.pitchClass == livePC } ?? entry.key
            }

            if best == nil || similarity > best!.similarity {
                best = (resolvedKey, confidence, entry.name, similarity)
            }
        }
        return best
    }

    private static func absoluteSimilarity(liveWindow: [String], libraryTokens: [String]) -> Double {
        let liveSet = Set(liveWindow)
        let librarySet = Set(libraryTokens)
        let intersection = liveSet.intersection(librarySet).count
        let union = liveSet.union(librarySet).count
        let jaccard = union == 0 ? 0.0 : Double(intersection) / Double(union)
        let contiguous = maxContiguousOverlap(liveWindow, libraryTokens)
        let contiguousScore = Double(contiguous) / Double(min(liveWindow.count, libraryTokens.count, 8))
        return min(1, jaccard * 0.45 + contiguousScore * 0.55)
    }

    private static func bestRelativeMatch(
        liveWindow: [String],
        libraryTokens: [String]
    ) -> (score: Double, shift: Int) {
        var bestScore = 0.0
        var bestShift = 0
        for shift in 0..<12 {
            let shiftedLive = liveWindow.map { token -> String in
                let parts = token.split(separator: ":")
                guard parts.count == 2, let pc = Int(parts[0]) else { return token }
                return "\((pc - shift + 12) % 12):\(parts[1])"
            }
            let score = absoluteSimilarity(liveWindow: shiftedLive, libraryTokens: libraryTokens)
            if score > bestScore {
                bestScore = score
                bestShift = shift
            }
        }
        return (bestScore, bestShift)
    }

    private static func maxContiguousOverlap(_ a: [String], _ b: [String]) -> Int {
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        var best = 0
        let doubled = b + b
        for startA in 0..<a.count {
            for startB in 0..<b.count {
                var length = 0
                while startA + length < a.count,
                      startB + length < doubled.count,
                      a[startA + length] == doubled[startB + length] {
                    length += 1
                }
                best = max(best, length)
            }
        }
        return best
    }

    private static func qualityWeight(for suffix: String) -> Double {
        let s = suffix.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if s.isEmpty || s.hasPrefix("maj") || s == "6" || s.hasPrefix("add") || s.contains("sus") { return 1.0 }
        if s.hasPrefix("m") && !s.hasPrefix("maj") { return 1.15 }
        if s.hasPrefix("7") || s.contains("9") || s.contains("13") { return 1.05 }
        if s.contains("dim") || s == "m7b5" { return 0.85 }
        return 0.95
    }

    private static func qualityToken(_ suffix: String) -> String {
        let s = suffix.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if s.hasPrefix("m") && !s.hasPrefix("maj") { return "m" }
        if s.hasPrefix("7") || s.contains("9") { return "7" }
        if s.contains("dim") { return "d" }
        return "M"
    }
}
