//
//  DrumAccompanimentEngine.swift
//  Chordyx
//
//  Live drum accompaniment — GM kit, user soundfonts, AU plugins, synthesis.
//

import AVFoundation
import AudioToolbox
import Combine
import Foundation
import os

struct DrumStepEvent: Sendable {
    let voice: DrumVoice
    let velocityScale: Float

    init(_ voice: DrumVoice, velocityScale: Float = 1) {
        self.voice = voice
        self.velocityScale = min(1.25, max(0.35, velocityScale))
    }
}

enum DrumPattern: String, CaseIterable, Identifiable, Sendable {
    case worshipBallad
    case softPulse
    case gospelGroove
    case brushWaltz
    case popRock
    case rockDrive
    case halfTimeRock
    case funkGroove
    case rbSoul
    case hipHopBoomBap
    case trapHalftime
    case discoFour
    case edmPulse
    case jazzSwing
    case bluesShuffle
    case merengue
    case salsa
    case songo
    case bachata
    case cumbia
    case dembow
    case chaCha
    case bossaNova
    case bolero
    case reggaeOneDrop
    case soca
    case afrobeat
    case countryTrain

    var id: String { rawValue }

    static let worshipPatterns: [DrumPattern] = [
        .worshipBallad, .softPulse, .gospelGroove, .brushWaltz
    ]

    static let popRockPatterns: [DrumPattern] = [
        .popRock, .rockDrive, .halfTimeRock, .funkGroove, .rbSoul, .discoFour, .edmPulse
    ]

    static let urbanPatterns: [DrumPattern] = [
        .hipHopBoomBap, .trapHalftime, .dembow
    ]

    static let jazzBluesPatterns: [DrumPattern] = [
        .jazzSwing, .bluesShuffle
    ]

    static let latinPatterns: [DrumPattern] = [
        .merengue, .salsa, .songo, .bachata, .cumbia, .chaCha, .bossaNova, .bolero
    ]

    static let worldPatterns: [DrumPattern] = [
        .reggaeOneDrop, .soca, .afrobeat, .countryTrain
    ]

    static let pickerSections: [(title: String, patterns: [DrumPattern])] = [
        (String(localized: "Worship & gospel"), worshipPatterns),
        (String(localized: "Pop, rock & dance"), popRockPatterns),
        (String(localized: "Urban"), urbanPatterns),
        (String(localized: "Jazz & blues"), jazzBluesPatterns),
        (String(localized: "Latin & Caribbean"), latinPatterns),
        (String(localized: "World & folk"), worldPatterns)
    ]

    static let caribbeanPatterns: [DrumPattern] = latinPatterns + [.soca, .dembow, .reggaeOneDrop]

    /// Every pattern appears in exactly one picker section (pro catalog integrity).
    static var catalogIsComplete: Bool {
        let fromSections = Set(pickerSections.flatMap(\.patterns))
        return fromSections == Set(allCases) && fromSections.count == allCases.count
    }

    var label: String {
        switch self {
        case .worshipBallad: String(localized: "Worship ballad")
        case .softPulse: String(localized: "Soft pulse")
        case .gospelGroove: String(localized: "Gospel groove")
        case .brushWaltz: String(localized: "Brush waltz")
        case .popRock: String(localized: "Pop / rock backbeat")
        case .rockDrive: String(localized: "Rock drive")
        case .halfTimeRock: String(localized: "Half-time rock")
        case .funkGroove: String(localized: "Funk groove")
        case .rbSoul: String(localized: "R&B / soul")
        case .hipHopBoomBap: String(localized: "Hip-hop boom-bap")
        case .trapHalftime: String(localized: "Trap half-time")
        case .discoFour: String(localized: "Disco four-on-floor")
        case .edmPulse: String(localized: "EDM pulse")
        case .jazzSwing: String(localized: "Jazz swing")
        case .bluesShuffle: String(localized: "Blues shuffle")
        case .merengue: String(localized: "Merengue")
        case .salsa: String(localized: "Salsa")
        case .songo: String(localized: "Songó")
        case .bachata: String(localized: "Bachata")
        case .cumbia: String(localized: "Cumbia")
        case .dembow: String(localized: "Dembow / reggaetón")
        case .chaCha: String(localized: "Cha-cha-chá")
        case .bossaNova: String(localized: "Bossa nova")
        case .bolero: String(localized: "Bolero")
        case .reggaeOneDrop: String(localized: "Reggae one-drop")
        case .soca: String(localized: "Soca")
        case .afrobeat: String(localized: "Afrobeat")
        case .countryTrain: String(localized: "Country train")
        }
    }

    var subtitle: String {
        switch self {
        case .worshipBallad: String(localized: "Slow ballad — brush ride, soft kick on 1")
        case .softPulse: String(localized: "Ultra-soft pulse for very slow songs")
        case .gospelGroove: String(localized: "Busier backbeat for uptempo songs")
        case .brushWaltz: String(localized: "3/4 feel with ride pattern")
        case .popRock: String(localized: "Classic 2 & 4 snare — pop, rock, mainstream")
        case .rockDrive: String(localized: "Driving kick and backbeat for uptempo rock")
        case .halfTimeRock: String(localized: "Snare on 3 — modern rock / worship builds")
        case .funkGroove: String(localized: "Funky Drummer pocket — 16th hats, ghost snares")
        case .rbSoul: String(localized: "Laid-back pocket with ghost-note feel")
        case .hipHopBoomBap: String(localized: "Classic boom-bap — kick syncopation, dry snare")
        case .trapHalftime: String(localized: "Sparse kick, hard snare on 3, busy hats")
        case .discoFour: String(localized: "Four-on-floor with open-hat offbeats — 70s/nu-disco")
        case .edmPulse: String(localized: "Four-on-the-floor kick for dance and EDM")
        case .jazzSwing: String(localized: "Ride cymbal swing with light kick")
        case .bluesShuffle: String(localized: "Shuffle backbeat with dominant-7th feel")
        case .merengue: String(localized: "Dominican pulse — tambora drive and güira")
        case .salsa: String(localized: "Montuno bell with tumbao and cascara")
        case .songo: String(localized: "Cuban songó — cascara, tumbao kick & conga")
        case .bachata: String(localized: "Bachata bongó / guira pulse — romantic Caribbean")
        case .cumbia: String(localized: "Cumbia — tumbao kick, guacharaca hats, conga")
        case .dembow: String(localized: "Reggaetón dembow — kick/snare engine for urban Latin")
        case .chaCha: String(localized: "Cha-cha — syncopated cascara and tumbao")
        case .bossaNova: String(localized: "Brazilian soft syncopation and rim patterns")
        case .bolero: String(localized: "Bolero bongó — romantic slow Latin ballad")
        case .reggaeOneDrop: String(localized: "Offbeat skank with kick on beat 3")
        case .soca: String(localized: "Soca drive — carnival kick and busy percussion")
        case .afrobeat: String(localized: "Afrobeat — syncopated kick, shekere hats, snare accents")
        case .countryTrain: String(localized: "Train-beat kick for country and folk")
        }
    }

    /// Swing feel for offbeat 8ths (0 = straight, ~0.6 = jazz shuffle).
    var swingAmount: Double {
        switch self {
        case .jazzSwing: 0.66
        case .bluesShuffle: 0.64
        case .bossaNova: 0.48
        case .rbSoul, .brushWaltz: 0.5
        case .hipHopBoomBap: 0.42
        case .worshipBallad, .softPulse: 0.1
        case .bolero, .bachata: 0.16
        case .salsa, .chaCha: 0.12
        case .songo, .cumbia: 0.18
        case .merengue, .soca: 0.06
        case .gospelGroove: 0.22
        case .funkGroove, .afrobeat: 0.16
        case .reggaeOneDrop: 0.2
        case .trapHalftime, .dembow: 0.08
        case .popRock, .rockDrive, .halfTimeRock, .discoFour: 0.04
        default: 0
        }
    }

    /// Styles that breathe with light 4-bar fills (not ballads / soft Latin).
    var allowsPhraseFills: Bool {
        switch self {
        case .worshipBallad, .softPulse, .bolero, .bossaNova, .brushWaltz,
             .reggaeOneDrop, .bachata, .trapHalftime:
            false
        default:
            true
        }
    }

    /// Snare / hats sit slightly late for pocket (R&B, reggae, bossa).
    var laidBackPocket: Bool {
        switch self {
        case .rbSoul, .reggaeOneDrop, .bossaNova, .funkGroove, .bolero,
             .gospelGroove, .songo, .hipHopBoomBap, .bachata, .afrobeat:
            true
        default:
            false
        }
    }

    /// One bar of 16th-note steps with velocity accents (`barIndex` enables A/B + fills).
    /// Prefer `DrumPhrasePlayer.events` when an arrangement mode is active.
    func events(for step: Int, barIndex: Int = 0) -> [DrumStepEvent] {
        let s = ((step % 16) + 16) % 16
        let bar = max(0, barIndex)
        let phraseBar = bar % 4
        let isB = bar % 2 == 1
        var events = baseEvents(step: s, isB: isB, phraseBar: phraseBar)
        if allowsPhraseFills, phraseBar == 3, s >= 12 {
            events.append(contentsOf: phraseFillEvents(step: s))
        } else if allowsPhraseFills, phraseBar == 0, s == 0, bar > 0 {
            // Crash / ride wash into the top of a new 4-bar phrase.
            events.append(.init(.ride, velocityScale: 0.88))
            if [.rockDrive, .gospelGroove, .popRock].contains(self) {
                events.append(.init(.kick, velocityScale: 1.05))
            }
        }
        return events
    }

    /// One bar of 16th-note steps.
    func hits(for step: Int) -> Set<DrumVoice> {
        Set(events(for: step).map(\.voice))
    }

    // MARK: - Pattern grids (studio / live drummer vocabulary)

    private func baseEvents(step s: Int, isB: Bool, phraseBar: Int) -> [DrumStepEvent] {
        switch self {
        case .worshipBallad:
            // Soft church ballad: heartbeat kick, cross-stick 2/4, brush ride + air.
            var e: [DrumStepEvent] = []
            if s == 0 { e.append(.init(.kick, velocityScale: 0.82)) }
            if s == 8 { e.append(.init(.kick, velocityScale: isB ? 0.42 : 0.32)) }
            if phraseBar == 2, s == 12 { e.append(.init(.kick, velocityScale: 0.28)) }
            if s == 4 || s == 12 { e.append(.init(.rim, velocityScale: s == 4 ? 0.58 : 0.52)) }
            if [0, 4, 8, 12].contains(s) {
                e.append(.init(.ride, velocityScale: s == 0 ? 0.62 : 0.44))
            }
            if [2, 6, 10, 14].contains(s) {
                e.append(.init(.hihatClosed, velocityScale: 0.24))
            }
            if isB, s == 14 { e.append(.init(.rim, velocityScale: 0.32)) }
            if phraseBar == 3, s == 15 { e.append(.init(.ride, velocityScale: 0.5)) }
            return e

        case .softPulse:
            // Minimal pulse — kick on 1, feathered 3, soft stick, almost no cymbal.
            var e: [DrumStepEvent] = []
            if s == 0 { e.append(.init(.kick, velocityScale: 0.55)) }
            if s == 8 { e.append(.init(.kick, velocityScale: isB ? 0.36 : 0.28)) }
            if s == 4 || s == 12 { e.append(.init(.rim, velocityScale: 0.38)) }
            if [0, 8].contains(s) { e.append(.init(.ride, velocityScale: 0.3)) }
            if [6, 14].contains(s) { e.append(.init(.shaker, velocityScale: 0.28)) }
            if isB, s == 10 { e.append(.init(.hihatClosed, velocityScale: 0.2)) }
            return e

        case .gospelGroove:
            // Church pocket: syncopated kick, fat 2/4, ghost 16ths, open-hat breath.
            var e: [DrumStepEvent] = []
            let kicks = isB ? [0, 3, 6, 8, 10, 14] : [0, 3, 8, 10]
            if kicks.contains(s) {
                let hot = [0, 8].contains(s)
                e.append(.init(.kick, velocityScale: hot ? 1.05 : (s == 3 || s == 10 ? 0.78 : 0.6)))
            }
            if s == 4 || s == 12 { e.append(.init(.snare, velocityScale: 1.05)) }
            // Ghost grid around the backbeat
            if [1, 2, 6, 7, 9, 11, 14, 15].contains(s) {
                let vel: Float = [2, 6, 14].contains(s) ? 0.34 : 0.22
                e.append(.init(.snare, velocityScale: vel))
            }
            if s.isMultiple(of: 2) {
                e.append(.init(.hihatClosed, velocityScale: s.isMultiple(of: 4) ? 0.78 : 0.5))
            } else if [1, 5, 9, 13].contains(s) {
                e.append(.init(.hihatClosed, velocityScale: 0.32))
            }
            if [3, 11].contains(s) { e.append(.init(.hihatOpen, velocityScale: 0.48)) }
            if phraseBar == 2, s == 15 { e.append(.init(.ride, velocityScale: 0.55)) }
            return e

        case .brushWaltz:
            // Jazz waltz brushes on 16-step grid (feels like 3/4): 1 · 2 · 3
            var e: [DrumStepEvent] = []
            if s == 0 { e.append(.init(.kick, velocityScale: 0.66)) }
            if s == 5 { e.append(.init(.rim, velocityScale: 0.55)) }
            if s == 11 { e.append(.init(.rim, velocityScale: 0.62)) }
            if [0, 2, 3, 5, 7, 8, 10, 11, 13, 14].contains(s) {
                let accent = [0, 5, 11].contains(s)
                e.append(.init(.ride, velocityScale: accent ? 0.72 : 0.46))
            }
            if isB, s == 8 { e.append(.init(.kick, velocityScale: 0.38)) }
            if phraseBar % 2 == 1, s == 14 { e.append(.init(.snare, velocityScale: 0.22)) }
            return e

        case .popRock:
            // Radio pop/rock: solid 1+3 kick, crisp 2/4, 8th hats, open on “4+”.
            var e: [DrumStepEvent] = []
            if s == 0 || s == 8 { e.append(.init(.kick, velocityScale: 1.02)) }
            if isB, s == 6 { e.append(.init(.kick, velocityScale: 0.74)) }
            if !isB, s == 10 { e.append(.init(.kick, velocityScale: 0.58)) }
            if phraseBar == 2, s == 14 { e.append(.init(.kick, velocityScale: 0.5)) }
            if s == 4 || s == 12 { e.append(.init(.snare, velocityScale: 1)) }
            if [3, 7, 11, 15].contains(s) { e.append(.init(.snare, velocityScale: 0.18)) }
            if s.isMultiple(of: 2) {
                e.append(.init(.hihatClosed, velocityScale: s.isMultiple(of: 4) ? 0.8 : 0.54))
            }
            if s == 15 { e.append(.init(.hihatOpen, velocityScale: isB ? 0.55 : 0.4)) }
            return e

        case .rockDrive:
            // Arena rock: driving kick on 1/& of 2/3, snare 2/4, busy hats.
            var e: [DrumStepEvent] = []
            let kicks = isB ? [0, 3, 6, 8, 11, 14] : [0, 6, 8, 14]
            if kicks.contains(s) {
                e.append(.init(.kick, velocityScale: [0, 8].contains(s) ? 1.05 : 0.8))
            }
            if s == 4 || s == 12 { e.append(.init(.snare, velocityScale: 1.05)) }
            if [7, 15].contains(s) { e.append(.init(.snare, velocityScale: 0.32)) }
            if [2, 10].contains(s) { e.append(.init(.snare, velocityScale: 0.2)) }
            if s.isMultiple(of: 2) {
                e.append(.init(.hihatClosed, velocityScale: s.isMultiple(of: 4) ? 0.76 : 0.6))
            }
            if [2, 10].contains(s) { e.append(.init(.hihatOpen, velocityScale: 0.45)) }
            if phraseBar == 1, s == 0 { e.append(.init(.ride, velocityScale: 0.7)) }
            return e

        case .funkGroove:
            // Funky Drummer DNA: dense kick, 16th ghosts, open-hat chokes.
            var e: [DrumStepEvent] = []
            let kicks = isB
                ? [0, 2, 3, 5, 8, 10, 11, 13]
                : [0, 3, 5, 8, 10, 13]
            if kicks.contains(s) {
                let hot = [0, 8].contains(s)
                let med = [3, 5, 10].contains(s)
                e.append(.init(.kick, velocityScale: hot ? 1.05 : (med ? 0.86 : 0.68)))
            }
            if s == 4 || s == 12 { e.append(.init(.snare, velocityScale: 1.05)) }
            // Layered ghost grid (Clyde-ish)
            if [1, 2, 6, 7, 9, 11, 14, 15].contains(s) {
                e.append(.init(.snare, velocityScale: [2, 6, 11, 14].contains(s) ? 0.36 : 0.24))
            }
            e.append(.init(
                .hihatClosed,
                velocityScale: s.isMultiple(of: 4) ? 0.82 : (s.isMultiple(of: 2) ? 0.5 : 0.34)
            ))
            if [6, 14].contains(s) { e.append(.init(.hihatOpen, velocityScale: 0.55)) }
            if isB, s == 2 { e.append(.init(.hihatOpen, velocityScale: 0.4)) }
            if [7, 15].contains(s) { e.append(.init(.rim, velocityScale: 0.48)) }
            return e

        case .rbSoul:
            // Laid-back R&B: kick anticipations, soft ghosts, silky hats.
            var e: [DrumStepEvent] = []
            let kicks = isB ? [0, 3, 7, 10, 14] : [0, 7, 10]
            if kicks.contains(s) {
                e.append(.init(.kick, velocityScale: s == 0 ? 1 : 0.7))
            }
            if s == 4 || s == 12 { e.append(.init(.snare, velocityScale: 0.92)) }
            if [2, 5, 6, 9, 13, 14].contains(s) {
                e.append(.init(.snare, velocityScale: [6, 14].contains(s) ? 0.32 : 0.2))
            }
            if s.isMultiple(of: 2) {
                e.append(.init(.hihatClosed, velocityScale: s.isMultiple(of: 4) ? 0.64 : 0.42))
            } else {
                e.append(.init(.hihatClosed, velocityScale: 0.28))
            }
            if [3, 11].contains(s) { e.append(.init(.hihatOpen, velocityScale: 0.42)) }
            if phraseBar == 2, s == 15 { e.append(.init(.ride, velocityScale: 0.4)) }
            return e

        case .edmPulse:
            // Four-on-the-floor + clap/snare 2/4 + offbeat hats.
            var e: [DrumStepEvent] = []
            if [0, 4, 8, 12].contains(s) { e.append(.init(.kick, velocityScale: 1.08)) }
            if s == 4 || s == 12 { e.append(.init(.snare, velocityScale: 0.9)) }
            if s.isMultiple(of: 2) {
                e.append(.init(.hihatClosed, velocityScale: s.isMultiple(of: 4) ? 0.5 : 0.74))
            } else {
                e.append(.init(.hihatClosed, velocityScale: 0.32))
            }
            if isB, [6, 14].contains(s) { e.append(.init(.hihatOpen, velocityScale: 0.52)) }
            if phraseBar == 2, s == 15 { e.append(.init(.ride, velocityScale: 0.6)) }
            if phraseBar == 3, s == 0 { e.append(.init(.rim, velocityScale: 0.45)) }
            return e

        case .jazzSwing:
            // Spang-a-lang ride, feathered kick, cross-stick comps, hi-hat chick on 2/4.
            var e: [DrumStepEvent] = []
            if s == 0 { e.append(.init(.kick, velocityScale: 0.55)) }
            if s == 8 { e.append(.init(.kick, velocityScale: isB ? 0.5 : 0.38)) }
            if isB, s == 5 { e.append(.init(.kick, velocityScale: 0.32)) }
            if phraseBar == 2, s == 12 { e.append(.init(.kick, velocityScale: 0.3)) }
            if [4, 12].contains(s) { e.append(.init(.rim, velocityScale: 0.55)) }
            if [6, 14].contains(s) { e.append(.init(.snare, velocityScale: 0.22)) }
            if isB, [2, 10].contains(s) { e.append(.init(.snare, velocityScale: 0.18)) }
            // Classic ride: ding–ding-a-ding mapped to 16ths
            if [0, 3, 4, 7, 8, 11, 12, 15].contains(s) {
                let ding = [0, 4, 8, 12].contains(s)
                e.append(.init(.ride, velocityScale: ding ? 0.9 : 0.58))
            }
            if [4, 12].contains(s) { e.append(.init(.hihatClosed, velocityScale: 0.48)) } // chick
            return e

        case .bluesShuffle:
            // Shuffle 12/8 feel on 16ths: strong quarters + swung &s.
            var e: [DrumStepEvent] = []
            if s == 0 || s == 8 { e.append(.init(.kick, velocityScale: 1.02)) }
            if isB, [3, 6].contains(s) { e.append(.init(.kick, velocityScale: 0.58)) }
            if s == 4 || s == 12 { e.append(.init(.snare, velocityScale: 0.96)) }
            if [7, 15].contains(s) { e.append(.init(.snare, velocityScale: 0.28)) }
            if [0, 4, 8, 12].contains(s) {
                e.append(.init(.hihatClosed, velocityScale: 0.76))
            }
            if [2, 6, 10, 14].contains(s) {
                e.append(.init(.hihatClosed, velocityScale: 0.48))
            }
            if [3, 11].contains(s) { e.append(.init(.hihatOpen, velocityScale: 0.4)) }
            return e

        case .merengue:
            // Tambora pulse + güira 16ths + conga answers (DR feel).
            var e: [DrumStepEvent] = []
            if [0, 4, 8, 12].contains(s) {
                e.append(.init(.kick, velocityScale: s == 0 || s == 8 ? 1.02 : 0.84))
            }
            // Tambora slap / rim every 8th
            if s.isMultiple(of: 2) {
                e.append(.init(.rim, velocityScale: s.isMultiple(of: 4) ? 0.8 : 0.62))
            }
            // Güira (hats) nearly continuous
            e.append(.init(
                .hihatClosed,
                velocityScale: s.isMultiple(of: 4) ? 0.58 : (s.isMultiple(of: 2) ? 0.48 : 0.36)
            ))
            if [3, 7, 11, 15].contains(s) {
                e.append(.init(.conga, velocityScale: isB && s == 15 ? 0.95 : 0.78))
            }
            if [1, 9].contains(s) { e.append(.init(.bongo, velocityScale: 0.45)) }
            if isB, s == 10 { e.append(.init(.conga, velocityScale: 0.58)) }
            if phraseBar == 2, s == 0 { e.append(.init(.cowbell, velocityScale: 0.7)) }
            return e

        case .salsa:
            // Campana 2-3 / cascara, tumbao kick (not rock 2/4), conga marcha.
            var e: [DrumStepEvent] = []
            // 2-3 campana on A, denser B (mambo)
            let campana = isB
                ? [0, 2, 4, 7, 8, 10, 12, 14]
                : [0, 3, 6, 8, 10, 12]
            if campana.contains(s) {
                let accent = [0, 6, 8, 12].contains(s)
                e.append(.init(.cowbell, velocityScale: accent ? 1.05 : 0.68))
            }
            // Conga tumbao / marcha
            if [0, 8].contains(s) { e.append(.init(.conga, velocityScale: 0.95)) }
            if [2, 6, 10, 14].contains(s) { e.append(.init(.conga, velocityScale: 0.62)) }
            if [3, 11, 15].contains(s) { e.append(.init(.conga, velocityScale: 0.48)) }
            if isB, [5, 13].contains(s) { e.append(.init(.bongo, velocityScale: 0.5)) }
            // Bass drum tumbao (anticipations) — avoid rock snare backbeat
            let kicks = isB ? [0, 3, 7, 9, 14] : [0, 7, 9]
            if kicks.contains(s) {
                e.append(.init(.kick, velocityScale: s == 0 ? 0.8 : 0.62))
            }
            // Cascara on rim / stick
            if [0, 2, 3, 5, 7, 8, 10, 11, 13, 14].contains(s) {
                e.append(.init(.rim, velocityScale: [0, 8].contains(s) ? 0.55 : 0.4))
            }
            if [4, 12].contains(s) { e.append(.init(.hihatClosed, velocityScale: 0.35)) }
            return e

        case .songo:
            // Cuban songó: funky kick, cascara, conga, light snare ghost — church-band staple.
            var e: [DrumStepEvent] = []
            let kicks = isB
                ? [0, 3, 5, 8, 10, 12, 13, 15]
                : [0, 3, 5, 8, 10, 13]
            if kicks.contains(s) {
                let hot = [0, 8].contains(s)
                let med = [3, 5, 10].contains(s)
                e.append(.init(.kick, velocityScale: hot ? 1.05 : (med ? 0.86 : 0.7)))
            }
            // Cross-stick / rim on 2 & 4 + ghosts
            if [4, 12].contains(s) { e.append(.init(.rim, velocityScale: 0.85)) }
            if [2, 7, 11, 15].contains(s) { e.append(.init(.rim, velocityScale: 0.38)) }
            if [6, 14].contains(s) { e.append(.init(.snare, velocityScale: 0.28)) }
            // Cascara (shell / hats)
            if [0, 2, 3, 5, 7, 8, 10, 11, 13, 14].contains(s) {
                e.append(.init(.hihatClosed, velocityScale: [0, 8].contains(s) ? 0.72 : 0.5))
            }
            if isB, [1, 9].contains(s) { e.append(.init(.hihatClosed, velocityScale: 0.36)) }
            // Conga answers
            if [2, 6, 10, 14].contains(s) { e.append(.init(.conga, velocityScale: 0.9)) }
            if [5, 11, 15].contains(s) { e.append(.init(.conga, velocityScale: 0.55)) }
            if isB, s == 9 { e.append(.init(.cowbell, velocityScale: 0.6)) }
            if phraseBar == 2, s == 0 { e.append(.init(.ride, velocityScale: 0.55)) }
            return e

        case .bossaNova:
            // Soft Brazilian: surdo-ish kick, partido alto rim, whisper hats.
            var e: [DrumStepEvent] = []
            if s == 0 { e.append(.init(.kick, velocityScale: 0.68)) }
            if [7, 11].contains(s) { e.append(.init(.kick, velocityScale: 0.45)) }
            if isB, s == 14 { e.append(.init(.kick, velocityScale: 0.36)) }
            // Partido alto / clave-ish sticks
            let sticks = isB ? [2, 5, 8, 10, 13] : [3, 6, 7, 10, 14]
            if sticks.contains(s) {
                e.append(.init(.rim, velocityScale: [3, 7, 10].contains(s) ? 0.62 : 0.48))
            }
            if [0, 4, 8, 12].contains(s) { e.append(.init(.hihatClosed, velocityScale: 0.4)) }
            if [2, 6, 10, 14].contains(s) { e.append(.init(.hihatClosed, velocityScale: 0.32)) }
            if [5, 13].contains(s) { e.append(.init(.hihatOpen, velocityScale: 0.36)) }
            if [1, 9].contains(s) { e.append(.init(.shaker, velocityScale: 0.3)) }
            return e

        case .bolero:
            // Romantic bolero: soft kick, bongó martillo, light conga.
            var e: [DrumStepEvent] = []
            if s == 0 { e.append(.init(.kick, velocityScale: 0.7)) }
            if s == 10 { e.append(.init(.kick, velocityScale: 0.48)) }
            if isB, s == 6 { e.append(.init(.kick, velocityScale: 0.36)) }
            // Martillo
            if [0, 3, 6, 8, 11, 14].contains(s) {
                e.append(.init(.bongo, velocityScale: [0, 8].contains(s) ? 0.78 : 0.55))
            }
            if [2, 5, 9, 13].contains(s) {
                e.append(.init(.rim, velocityScale: 0.38))
            }
            if [4, 12].contains(s) { e.append(.init(.conga, velocityScale: 0.58)) }
            if [7, 15].contains(s) { e.append(.init(.conga, velocityScale: 0.42)) }
            if [2, 7, 13].contains(s) { e.append(.init(.hihatClosed, velocityScale: 0.28)) }
            return e

        case .reggaeOneDrop:
            // One-drop: silence on 1, kick+snare on 3, offbeat skank.
            var e: [DrumStepEvent] = []
            if s == 8 {
                e.append(.init(.kick, velocityScale: 1.05))
                e.append(.init(.snare, velocityScale: 0.88))
            }
            if isB, s == 0 { e.append(.init(.kick, velocityScale: 0.36)) } // rare pickup
            if [4, 12].contains(s) { e.append(.init(.rim, velocityScale: 0.72)) }
            if [2, 6, 10, 14].contains(s) {
                e.append(.init(.hihatClosed, velocityScale: 0.68))
            }
            if [3, 7, 11, 15].contains(s) {
                e.append(.init(.hihatOpen, velocityScale: 0.34))
            }
            if [1, 5, 9, 13].contains(s) { e.append(.init(.shaker, velocityScale: 0.26)) }
            return e

        case .countryTrain:
            // Train beat: even kick quarters, snare 2/4, busy 16th brushes.
            var e: [DrumStepEvent] = []
            if [0, 4, 8, 12].contains(s) {
                e.append(.init(.kick, velocityScale: s == 0 || s == 8 ? 1 : 0.8))
            }
            if s == 4 || s == 12 { e.append(.init(.snare, velocityScale: 0.98)) }
            if [2, 6, 10, 14].contains(s) { e.append(.init(.snare, velocityScale: 0.22)) }
            e.append(.init(
                .hihatClosed,
                velocityScale: s.isMultiple(of: 4) ? 0.72 : (s.isMultiple(of: 2) ? 0.52 : 0.4)
            ))
            if isB, [6, 14].contains(s) { e.append(.init(.rim, velocityScale: 0.48)) }
            if phraseBar == 2, s == 15 { e.append(.init(.ride, velocityScale: 0.5)) }
            return e

        case .halfTimeRock:
            // Modern half-time: kick on 1, snare on 3, roomy hats.
            var e: [DrumStepEvent] = []
            if s == 0 { e.append(.init(.kick, velocityScale: 1.08)) }
            if isB, s == 6 { e.append(.init(.kick, velocityScale: 0.7)) }
            if s == 10 { e.append(.init(.kick, velocityScale: 0.55)) }
            if s == 8 { e.append(.init(.snare, velocityScale: 1.1)) }
            if [4, 12].contains(s) { e.append(.init(.rim, velocityScale: 0.35)) }
            if s.isMultiple(of: 2) {
                e.append(.init(.hihatClosed, velocityScale: s.isMultiple(of: 4) ? 0.55 : 0.4))
            }
            if s == 15 { e.append(.init(.hihatOpen, velocityScale: 0.45)) }
            if phraseBar == 2, s == 0 { e.append(.init(.ride, velocityScale: 0.75)) }
            return e

        case .hipHopBoomBap:
            // Boom-bap: syncopated kick, dry snare 2/4, swung hats.
            var e: [DrumStepEvent] = []
            let kicks = isB ? [0, 3, 7, 10, 14] : [0, 7, 10]
            if kicks.contains(s) {
                e.append(.init(.kick, velocityScale: s == 0 ? 1.05 : 0.78))
            }
            if s == 4 || s == 12 { e.append(.init(.snare, velocityScale: 1.0)) }
            if [2, 6, 11, 14].contains(s) { e.append(.init(.snare, velocityScale: 0.22)) }
            if s.isMultiple(of: 2) {
                e.append(.init(.hihatClosed, velocityScale: s.isMultiple(of: 4) ? 0.7 : 0.48))
            } else {
                e.append(.init(.hihatClosed, velocityScale: 0.3))
            }
            if [7, 15].contains(s) { e.append(.init(.rim, velocityScale: 0.4)) }
            return e

        case .trapHalftime:
            // Trap: snare/clap on 3, sparse kick, rolling 16th hats + open.
            var e: [DrumStepEvent] = []
            let kicks = isB ? [0, 5, 11] : [0, 6]
            if kicks.contains(s) {
                e.append(.init(.kick, velocityScale: s == 0 ? 1.05 : 0.72))
            }
            if s == 8 { e.append(.init(.snare, velocityScale: 1.08)) }
            e.append(.init(
                .hihatClosed,
                velocityScale: s.isMultiple(of: 4) ? 0.55 : (s.isMultiple(of: 2) ? 0.42 : 0.34)
            ))
            if [3, 7, 11, 15].contains(s) { e.append(.init(.hihatOpen, velocityScale: 0.4)) }
            if phraseBar == 2, s == 14 { e.append(.init(.rim, velocityScale: 0.45)) }
            return e

        case .discoFour:
            // Classic disco: four-on-floor, open hats on offbeats, clap 2/4.
            var e: [DrumStepEvent] = []
            if [0, 4, 8, 12].contains(s) { e.append(.init(.kick, velocityScale: 1.05)) }
            if s == 4 || s == 12 { e.append(.init(.snare, velocityScale: 0.92)) }
            if [2, 6, 10, 14].contains(s) {
                e.append(.init(.hihatOpen, velocityScale: 0.7))
            }
            if [0, 4, 8, 12].contains(s) {
                e.append(.init(.hihatClosed, velocityScale: 0.45))
            }
            if isB, s == 15 { e.append(.init(.tambourine, velocityScale: 0.55)) }
            return e

        case .bachata:
            // Bachata: soft kick, bongó-ish rim, guira/shaker 8ths.
            var e: [DrumStepEvent] = []
            if s == 0 { e.append(.init(.kick, velocityScale: 0.7)) }
            if s == 8 { e.append(.init(.kick, velocityScale: isB ? 0.48 : 0.4)) }
            if [0, 3, 6, 8, 11, 14].contains(s) {
                e.append(.init(.bongo, velocityScale: [0, 8].contains(s) ? 0.75 : 0.52))
            }
            if [4, 12].contains(s) { e.append(.init(.rim, velocityScale: 0.55)) }
            if s.isMultiple(of: 2) {
                e.append(.init(.shaker, velocityScale: s.isMultiple(of: 4) ? 0.5 : 0.38))
            }
            if isB, s == 10 { e.append(.init(.conga, velocityScale: 0.45)) }
            return e

        case .cumbia:
            // Cumbia: tumbao kick, guacharaca hats, conga accents.
            var e: [DrumStepEvent] = []
            if [0, 6, 8, 14].contains(s) {
                e.append(.init(.kick, velocityScale: [0, 8].contains(s) ? 0.95 : 0.7))
            }
            if [4, 12].contains(s) { e.append(.init(.rim, velocityScale: 0.7)) }
            e.append(.init(
                .hihatClosed,
                velocityScale: s.isMultiple(of: 2) ? 0.55 : 0.4
            ))
            if [2, 7, 10, 15].contains(s) { e.append(.init(.conga, velocityScale: 0.72)) }
            if [3, 11].contains(s) { e.append(.init(.bongo, velocityScale: 0.48)) }
            if isB, s == 9 { e.append(.init(.cowbell, velocityScale: 0.5)) }
            return e

        case .dembow:
            // Reggaetón dembow engine (boom-ch-boom-chick family).
            var e: [DrumStepEvent] = []
            // Kick on 1, & of 2, 3 — classic dembow skeleton
            if [0, 6, 8].contains(s) {
                e.append(.init(.kick, velocityScale: s == 0 ? 1.08 : 0.9))
            }
            if isB, s == 14 { e.append(.init(.kick, velocityScale: 0.65)) }
            // Snare/clap on 2 and 4 (+ dembow answer)
            if [4, 12].contains(s) { e.append(.init(.snare, velocityScale: 1.05)) }
            if [7, 15].contains(s) { e.append(.init(.snare, velocityScale: 0.55)) }
            e.append(.init(
                .hihatClosed,
                velocityScale: s.isMultiple(of: 4) ? 0.6 : (s.isMultiple(of: 2) ? 0.45 : 0.32)
            ))
            if [3, 11].contains(s) { e.append(.init(.hihatOpen, velocityScale: 0.42)) }
            if phraseBar == 2, s == 10 { e.append(.init(.rim, velocityScale: 0.4)) }
            return e

        case .chaCha:
            // Cha-cha-chá: syncopated cascara + tumbao, light cowbell.
            var e: [DrumStepEvent] = []
            if [0, 7, 9].contains(s) {
                e.append(.init(.kick, velocityScale: s == 0 ? 0.78 : 0.58))
            }
            if isB, s == 3 { e.append(.init(.kick, velocityScale: 0.5)) }
            let cascara = [0, 2, 3, 5, 7, 8, 10, 11, 13, 14]
            if cascara.contains(s) {
                e.append(.init(.rim, velocityScale: [0, 8].contains(s) ? 0.62 : 0.45))
            }
            if [0, 4, 8, 12].contains(s) {
                e.append(.init(.cowbell, velocityScale: s == 0 || s == 8 ? 0.85 : 0.55))
            }
            if [2, 6, 10, 14].contains(s) { e.append(.init(.conga, velocityScale: 0.7)) }
            if [5, 13].contains(s) { e.append(.init(.conga, velocityScale: 0.48)) }
            if [4, 12].contains(s) { e.append(.init(.hihatClosed, velocityScale: 0.35)) }
            return e

        case .soca:
            // Soca: driving kick 8ths, snare 2/4, busy hats + tambourine.
            var e: [DrumStepEvent] = []
            if s.isMultiple(of: 2) {
                e.append(.init(.kick, velocityScale: s.isMultiple(of: 4) ? 1.02 : 0.78))
            }
            if s == 4 || s == 12 { e.append(.init(.snare, velocityScale: 0.95)) }
            e.append(.init(
                .hihatClosed,
                velocityScale: s.isMultiple(of: 4) ? 0.65 : 0.48
            ))
            if [3, 7, 11, 15].contains(s) {
                e.append(.init(.tambourine, velocityScale: 0.55))
            }
            if isB, [6, 14].contains(s) { e.append(.init(.conga, velocityScale: 0.6)) }
            if phraseBar == 2, s == 0 { e.append(.init(.cowbell, velocityScale: 0.7)) }
            return e

        case .afrobeat:
            // Afrobeat: syncopated kick, shekere/hats, snare accents, conga.
            var e: [DrumStepEvent] = []
            let kicks = isB ? [0, 3, 5, 8, 10, 13] : [0, 3, 8, 11]
            if kicks.contains(s) {
                e.append(.init(.kick, velocityScale: [0, 8].contains(s) ? 1.02 : 0.75))
            }
            if [4, 12].contains(s) { e.append(.init(.snare, velocityScale: 0.85)) }
            if [7, 15].contains(s) { e.append(.init(.snare, velocityScale: 0.4)) }
            e.append(.init(
                .shaker,
                velocityScale: s.isMultiple(of: 2) ? 0.55 : 0.4
            ))
            if [2, 6, 10, 14].contains(s) {
                e.append(.init(.hihatClosed, velocityScale: 0.5))
            }
            if [1, 5, 9, 13].contains(s) { e.append(.init(.conga, velocityScale: 0.65)) }
            if isB, s == 14 { e.append(.init(.cowbell, velocityScale: 0.55)) }
            return e
        }
    }

}

enum DrumVoice: Sendable, CaseIterable {
    case kick, snare, hihatClosed, hihatOpen, rim, ride, cowbell, conga
    case shaker, tambourine, bongo

    /// General MIDI drum map (channel 10).
    var generalMIDINote: UInt8 {
        switch self {
        case .kick: 36
        case .snare: 38
        case .hihatClosed: 42
        case .hihatOpen: 46
        case .rim: 37
        case .ride: 51
        case .cowbell: 56
        case .conga: 64
        case .shaker: 82
        case .tambourine: 54
        case .bongo: 60
        }
    }

    var defaultVelocity: UInt8 {
        switch self {
        case .kick: 105
        case .snare: 98
        case .hihatClosed: 68
        case .hihatOpen: 74
        case .rim: 86
        case .ride: 76
        case .cowbell: 88
        case .conga: 94
        case .shaker: 72
        case .tambourine: 80
        case .bongo: 90
        }
    }

    var noteOffMilliseconds: UInt64 {
        switch self {
        case .kick: 130
        case .snare: 160
        case .hihatClosed: 45
        case .hihatOpen: 220
        case .rim: 55
        case .ride: 340
        case .cowbell: 140
        case .conga: 210
        case .shaker: 90
        case .tambourine: 160
        case .bongo: 180
        }
    }
}

/// Wall-clock sequencer on a high-priority queue so piano/MIDI work on the main thread cannot drop beats.
private final class DrumGrooveClock: @unchecked Sendable {
    static let maxCatchUpSteps = 4
    /// Fast poll — must be << one 16th so steps fire on the boundary, not a full 16th late.
    private static let pollIntervalMs = 5

    private let queue = DispatchQueue(label: "com.chordyx.drum-groove", qos: .userInteractive)
    private var timer: DispatchSourceTimer?
    private var isActive = false
    private var bpm: Double = 120
    private var useWallClock = false
    private var anchorTime: CFAbsoluteTime?
    private var lastAbsoluteStep = -1
    private var freeRunningStep = 0
    private var lastFreeRunningHostTime: CFAbsoluteTime = 0
    var onTick: (@Sendable (Int) -> Void)?

    deinit {
        // Drop the callback first so a late tick cannot hop into a freed engine.
        onTick = nil
        // Cancel on the groove queue without `sync` — syncing from MainActor deinit while
        // the queue is inside `onTick` → MainActor hop can deadlock / corrupt the stack.
        queue.async { [timer] in
            timer?.cancel()
        }
    }

    func start(bpm: Double, wallClockAnchor: CFAbsoluteTime?) {
        queue.async {
            self.stopLocked()
            self.bpm = bpm
            self.useWallClock = wallClockAnchor != nil
            self.anchorTime = wallClockAnchor
            self.lastAbsoluteStep = -1
            self.freeRunningStep = 0
            self.lastFreeRunningHostTime = CFAbsoluteTimeGetCurrent()
            self.isActive = true
            self.installTimer()
        }
    }

    func stop() {
        queue.async {
            self.stopLocked()
        }
    }

    func retime(to bpm: Double, wallClockAnchor: CFAbsoluteTime?) {
        queue.async {
            guard self.isActive else { return }
            let oldBPM = self.bpm
            self.bpm = bpm
            if self.useWallClock, let anchor = wallClockAnchor ?? self.anchorTime, oldBPM > 0 {
                let oldSixteenth = (60.0 / oldBPM) / 4.0
                let newSixteenth = (60.0 / bpm) / 4.0
                guard oldSixteenth > 0, newSixteenth > 0 else { return }
                let now = CFAbsoluteTimeGetCurrent()
                let elapsed = now - anchor
                let absoluteStep = elapsed / oldSixteenth
                self.anchorTime = now - absoluteStep * newSixteenth
                // Keep lastAbsoluteStep so we don't re-trigger the current step.
            }
            self.installTimer()
        }
    }

    private func stopLocked() {
        timer?.cancel()
        timer = nil
        isActive = false
    }

    private func installTimer() {
        timer?.cancel()
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(
            deadline: .now(),
            repeating: .milliseconds(Self.pollIntervalMs),
            leeway: .milliseconds(1)
        )
        source.setEventHandler { [weak self] in
            self?.tick()
        }
        source.resume()
        timer = source
    }

    private func tick() {
        guard isActive else { return }
        let sixteenth = (60.0 / bpm) / 4.0
        guard sixteenth > 0 else { return }

        if useWallClock, let anchor = anchorTime {
            let elapsed = CFAbsoluteTimeGetCurrent() - anchor
            let absoluteStep = Int(floor(elapsed / sixteenth))
            guard absoluteStep > lastAbsoluteStep else { return }
            let fromStep = max(lastAbsoluteStep + 1, absoluteStep - Self.maxCatchUpSteps + 1)
            for step in fromStep...absoluteStep {
                onTick?(step)
            }
            lastAbsoluteStep = absoluteStep
        } else {
            let now = CFAbsoluteTimeGetCurrent()
            if lastFreeRunningHostTime == 0 {
                lastFreeRunningHostTime = now
            }
            let elapsed = now - lastFreeRunningHostTime
            let stepsDue = Int(floor(elapsed / sixteenth))
            guard stepsDue > freeRunningStep else { return }
            let from = freeRunningStep
            let to = min(stepsDue, from + Self.maxCatchUpSteps)
            for step in from..<to {
                onTick?(step)
            }
            freeRunningStep = to
        }
    }
}

@MainActor
final class DrumAccompanimentEngine: ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var currentBPM: Double = 72
    @Published private(set) var currentStep = 0
    @Published private(set) var isGrooveFrozen = false
    @Published private(set) var usesSampleDrumKit = false
    @Published private(set) var soundSourceLabel = String(localized: "Apple GM drums")
    @Published private(set) var isLoadingSoundSource = false
    @Published private(set) var soundSourceError: String?
    @Published private(set) var availableAudioUnits: [DrumAUComponentRef] = []
    /// Current arrangement phrase (A / B / Fill / …) for Solo Drums UI.
    @Published private(set) var currentPhraseKind: DrumPhraseKind = .grooveA

    var volume: Float = 0.72 {
        didSet { applyOutputVolume() }
    }

    /// Chart-section dynamics (verse softer / chorus louder). Multiplies `volume`.
    var dynamicsGain: Float = 1 {
        didSet { applyOutputVolume() }
    }

    /// Entrance fade (0…1) after count-in. Multiplies `volume`.
    var entranceGain: Float = 1 {
        didSet { applyOutputVolume() }
    }

    /// MIDI phrase arrangement mode (Auto / Groove only / Fills / Full).
    var arrangeMode: DrumArrangeMode = .auto

    /// Soften body hits under fills so accents/ghosts read (still 100% MIDI / tempo-native).
    var hybridMIDILayers = true

    /// Extra hybrid ducking from the selected instrument category.
    var hybridCategorySoftening: Float = 1

    /// Optional user-captured MIDI loop grid (overrides pattern arrangement while set).
    private(set) var activeUserMIDILoop: UserMIDIDrumLoop?

    /// Style pack coloring for arrangement timelines.
    var loopPack: DrumMIDILoopPack = .worship

    /// Instrument family (batería / percusión / …) that remaps pattern voices.
    var instrumentCategory: SoloDrumInstrumentCategory = .drums

    /// When true, quarter-note clicks are rendered on this same audio engine as the kit
    /// (eliminates dual-AVAudioEngine latency vs MetronomeEngine).
    var metronomeClickThroughGroove = false

    /// UI beat callback: (beatInBar 0…3, isDownbeat). Fired from the groove clock.
    var onGrooveBeat: ((Int, Bool) -> Void)?

    var soundSourceSelection: DrumSoundSourceSelection {
        get { soundSourceSelectionStorage }
        set {
            soundSourceSelectionStorage = newValue
            DrumSoundSourceStore.save(newValue)
        }
    }

    /// Created on first playback — never during SessionViewModel / splash launch.
    private lazy var engine = AVAudioEngine()
    private lazy var masterMixer = AVAudioMixerNode()
    private lazy var grooveClickPlayer = AVAudioPlayerNode()
    private var samplerUnit: AVAudioUnitSampler?
    private var pluginUnit: AVAudioUnit?
    private var voicePlayerPools: [DrumVoice: [AVAudioPlayerNode]] = [:]
    private var voicePoolIndices: [DrumVoice: Int] = [:]
    private let grooveClock = DrumGrooveClock()
    private var pattern: DrumPattern = .worshipBallad
    private var learnedPattern: LearnedDrumPattern?
    private var beatsPerBar = 4
    private var buffers: [DrumVoice: AVAudioPCMBuffer] = [:]
    private var grooveAccentClick: AVAudioPCMBuffer?
    private var grooveNormalClick: AVAudioPCMBuffer?
    private var activeBackend: DrumPlaybackBackend = .none
    /// Cross-thread playback flags live in a Sendable gate — safe inside `withLock`.
    private let playbackGate = OSAllocatedUnfairLock(initialState: PlaybackGate())
    private var reverbUnit: AVAudioUnitReverb?
    /// `mainMixerNode` forces AURemoteIO — never touch it from `init` (app-launch crash / hang).
    private var isOutputGraphWired = false
    private var didScheduleInitialSoundLoad = false
    private var didLoadSoundSourcePreference = false

    private var soundSourceSelectionStorage = DrumSoundSourceSelection.default

    private var tempoLocked = false
    private var grooveAnchorUnixEpochStorage: Double?

    private struct PlaybackGate: Sendable {
        var isPlaying = false
        var generation: UInt64 = 0
        var bpm: Double = 72
        var isGrooveFrozen = false
        var grooveAnchorTime: CFAbsoluteTime?
    }

    private func publishPlaybackMirrors(_ gate: PlaybackGate) {
        isPlaying = gate.isPlaying
        isGrooveFrozen = gate.isGrooveFrozen
        currentBPM = gate.bpm
    }

    private enum DrumPlaybackBackend {
        case none
        case midiSampler
        case midiPlugin
        case synthesis
    }

    private static let gmSoundBankPath =
        "/System/Library/Components/CoreAudio.component/Contents/Resources/gs_instruments.dls"

    init() {
        // Do not touch AVAudioEngine here — constructing/attaching during
        // SessionViewModel init freezes launch (splash hangs / EXC_BAD_ACCESS).
        // Sound-source preference is loaded on first configure/playback.
        grooveClock.onTick = { [weak self] step in
            Task { @MainActor [weak self] in
                self?.playGrooveStep(step)
            }
        }
    }

    private func ensureOutputGraphWired() {
        guard !isOutputGraphWired else { return }
        isOutputGraphWired = true
        engine.attach(masterMixer)
        engine.attach(grooveClickPlayer)
        applyOutputVolume()
        let reverb = AVAudioUnitReverb()
        reverb.loadFactoryPreset(.mediumRoom)
        reverb.wetDryMix = 18
        engine.attach(reverb)
        engine.connect(masterMixer, to: reverb, format: nil)
        engine.connect(reverb, to: engine.mainMixerNode, format: nil)
        // Dry click path — same output device/latency as the kit, no reverb smear.
        engine.connect(grooveClickPlayer, to: engine.mainMixerNode, format: nil)
        reverbUnit = reverb
    }

    private func scheduleInitialSoundLoadIfNeeded() {
        guard !didScheduleInitialSoundLoad else { return }
        didScheduleInitialSoundLoad = true
        Task { await reloadSoundBackend() }
    }

    private func applyOutputVolume() {
        let combined = max(0, min(1.25, volume * dynamicsGain * entranceGain))
        masterMixer.outputVolume = combined
    }

    func setReverbWetDry(_ mix: Float) {
        reverbUnit?.wetDryMix = max(0, min(40, mix))
    }

    /// True when the groove clock is on (or near) the bar downbeat.
    func isNearDownbeat(toleranceSteps: Int = 1) -> Bool {
        let stepsPerBar = max(1, beatsPerBar) * 4
        let step = ((currentStep % stepsPerBar) + stepsPerBar) % stepsPerBar
        return step <= toleranceSteps || step >= stepsPerBar - toleranceSteps
    }

    func refreshAvailableAudioUnits() {
        #if os(macOS)
        availableAudioUnits = DrumAudioUnitCatalog.discoverMusicDevices()
        #else
        availableAudioUnits = []
        #endif
    }

    func applySoundSourceSelection(_ selection: DrumSoundSourceSelection) async {
        soundSourceSelection = selection
        await reloadSoundBackend()
    }

    func importSoundFont(from url: URL) async {
        var selection = soundSourceSelection
        selection.kind = .userSoundFont
        selection.soundFontDisplayName = url.lastPathComponent
        do {
            selection.soundFontBookmark = try DrumSoundFontAccess.bookmark(url)
            soundSourceError = nil
        } catch {
            soundSourceError = error.localizedDescription
            return
        }
        soundSourceSelection = selection
        await reloadSoundBackend()
    }

    func start(bpm: Double, pattern: DrumPattern, beatsPerBar: Int = 4, freezeToWallClock: Bool = false) {
        let frozenAndPlaying = playbackGate.withLock { $0.isGrooveFrozen && $0.isPlaying }
        if frozenAndPlaying { return }
        stop(force: true)
        let clamped = clampBPM(bpm)
        let cfNow = CFAbsoluteTimeGetCurrent()
        let unixNow = cfNow + kCFAbsoluteTimeIntervalSince1970
        let gate = playbackGate.withLock { state -> PlaybackGate in
            state.bpm = clamped
            state.isPlaying = true
            if freezeToWallClock {
                state.isGrooveFrozen = true
                state.grooveAnchorTime = cfNow
            } else {
                state.isGrooveFrozen = false
                state.grooveAnchorTime = nil
            }
            return state
        }
        grooveAnchorUnixEpochStorage = freezeToWallClock ? unixNow : nil
        tempoLocked = freezeToWallClock
        publishPlaybackMirrors(gate)
        self.pattern = pattern
        self.beatsPerBar = max(1, beatsPerBar)
        currentStep = 0
        configureAudioIfNeeded()
        ensureGrooveClickBuffers()
        startGrooveClock()
    }

    func stop(force: Bool = false) {
        let shouldStop = playbackGate.withLock { state -> Bool in
            let shouldStop = !state.isGrooveFrozen || force
            if shouldStop {
                state.generation &+= 1
                state.isPlaying = false
            }
            return shouldStop
        }
        guard shouldStop else { return }
        isPlaying = false
        currentStep = 0
        grooveClock.stop()
        silenceActiveMIDINotes()
        if metronomeClickThroughGroove {
            grooveClickPlayer.stop()
        }
    }

    private func cancelScheduledPlayback() {
        playbackGate.withLock { $0.generation &+= 1 }
    }

    func setPattern(_ pattern: DrumPattern, force: Bool = false) {
        let frozen = playbackGate.withLock { $0.isGrooveFrozen }
        guard !frozen || force else { return }
        self.pattern = pattern
        learnedPattern = nil
        if activeUserMIDILoop == nil {
            loopPack = DrumMIDILoopPack.pack(for: pattern)
        }
    }

    func setArrangeMode(_ mode: DrumArrangeMode) {
        arrangeMode = mode
    }

    func setLoopPack(_ pack: DrumMIDILoopPack) {
        loopPack = pack
    }

    func setHybridMIDILayers(_ enabled: Bool) {
        hybridMIDILayers = enabled
    }

    func setInstrumentCategory(_ category: SoloDrumInstrumentCategory) {
        instrumentCategory = category
        hybridCategorySoftening = SoloDrumPolish.hybridFillSoftening(for: category)
        setReverbWetDry(SoloDrumPolish.reverbWetDry(for: category))
        SoloDrumInstrumentCategoryStore.save(category)
    }

    func setUserMIDILoop(_ loop: UserMIDIDrumLoop?) {
        activeUserMIDILoop = loop
    }

    /// Snapshot the current arranged feel into a reusable tempo-native MIDI loop.
    func captureUserMIDILoop(displayName: String, bars: Int = 4) -> UserMIDIDrumLoop {
        UserMIDIDrumLoop.capture(
            displayName: displayName,
            pattern: pattern,
            arrangeMode: arrangeMode,
            bars: bars
        )
    }

    func setLearnedPattern(_ pattern: LearnedDrumPattern?, force: Bool = false) {
        let frozen = playbackGate.withLock { $0.isGrooveFrozen }
        guard !frozen || force else { return }
        learnedPattern = pattern?.isEmpty == false ? pattern : nil
        if learnedPattern != nil {
            activeUserMIDILoop = nil
        }
    }

    var grooveAnchor: CFAbsoluteTime? {
        playbackGate.withLock { $0.grooveAnchorTime }
    }

    /// Groove bar-0 as Unix epoch — same clock domain as `MetronomeEngine`.
    var grooveStartUnixEpoch: Double? {
        if let stored = grooveAnchorUnixEpochStorage { return stored }
        guard let cf = grooveAnchor else { return nil }
        return cf + kCFAbsoluteTimeIntervalSince1970
    }

    /// Seconds per quarter note at the locked groove BPM (matches the 16th-note grid).
    var grooveSecondsPerQuarter: Double {
        let bpm = max(48, playbackGate.withLock { $0.bpm })
        return 60.0 / bpm
    }

    func setMetronomeClickThroughGroove(_ enabled: Bool) {
        metronomeClickThroughGroove = enabled
        if enabled {
            ensureGrooveClickBuffers()
            configureAudioIfNeeded()
            if ChordyxPreferences.separateClickVolume {
                grooveClickPlayer.volume = ChordyxPreferences.clickVolume
            } else {
                grooveClickPlayer.volume = 1
            }
            if !grooveClickPlayer.isPlaying { grooveClickPlayer.play() }
        }
    }

    private func ensureGrooveClickBuffers() {
        guard grooveAccentClick == nil || grooveNormalClick == nil else { return }
        ensureOutputGraphWired()
        let format = engine.mainMixerNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { return }
        grooveAccentClick = makeGrooveClickBuffer(frequency: 1568, format: format)
        grooveNormalClick = makeGrooveClickBuffer(frequency: 988, format: format)
    }

    private func scheduleGrooveClick(accent: Bool) {
        ensureGrooveClickBuffers()
        guard let buffer = accent ? grooveAccentClick : grooveNormalClick else { return }
        if !engine.isRunning { try? engine.start() }
        if !grooveClickPlayer.isPlaying { grooveClickPlayer.play() }
        grooveClickPlayer.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
    }

    private func makeGrooveClickBuffer(frequency: Double, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let sampleRate = format.sampleRate
        guard sampleRate > 0 else { return nil }
        let duration = 0.045
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }
        buffer.frameLength = frameCount
        let channels = Int(format.channelCount)
        for frame in 0..<Int(frameCount) {
            let t = Double(frame) / sampleRate
            let envelope = exp(-t * 32)
            let sample = Float(sin(2 * .pi * frequency * t) * envelope * 0.55)
            for ch in 0..<channels {
                buffer.floatChannelData?[ch][frame] = sample
            }
        }
        return buffer
    }

    /// Locks the groove grid to wall-clock time so chord/MIDI work on the main thread cannot reset phase.
    func freezeGroove() {
        let cfNow = CFAbsoluteTimeGetCurrent()
        let unixNow = cfNow + kCFAbsoluteTimeIntervalSince1970
        let gate = playbackGate.withLock { state -> PlaybackGate in
            state.grooveAnchorTime = cfNow
            state.isGrooveFrozen = true
            return state
        }
        grooveAnchorUnixEpochStorage = unixNow
        tempoLocked = true
        publishPlaybackMirrors(gate)
        if gate.isPlaying {
            startGrooveClock()
        }
    }

    func unfreezeGroove() {
        let gate = playbackGate.withLock { state -> PlaybackGate in
            state.isGrooveFrozen = false
            state.grooveAnchorTime = nil
            return state
        }
        grooveAnchorUnixEpochStorage = nil
        metronomeClickThroughGroove = false
        tempoLocked = false
        publishPlaybackMirrors(gate)
    }

    /// Adjusts locked groove tempo while preserving musical position on the grid.
    func retimeLockedGroove(to bpm: Double) {
        let snapshot = playbackGate.withLock { state -> (frozen: Bool, playing: Bool, bpm: Double, anchor: CFAbsoluteTime?) in
            (state.isGrooveFrozen, state.isPlaying, state.bpm, state.grooveAnchorTime)
        }
        guard snapshot.frozen, snapshot.playing else { return }
        let clamped = clampBPM(bpm)
        guard abs(clamped - snapshot.bpm) > 0.25 else { return }

        let (gate, updatedUnixEpoch) = playbackGate.withLock { state -> (PlaybackGate, Double?) in
            var updatedUnixEpoch: Double?
            if let anchor = state.grooveAnchorTime {
                let oldSixteenth = (60.0 / state.bpm) / 4.0
                let newSixteenth = (60.0 / clamped) / 4.0
                if oldSixteenth > 0, newSixteenth > 0 {
                    let now = CFAbsoluteTimeGetCurrent()
                    let elapsed = now - anchor
                    let absoluteStep = elapsed / oldSixteenth
                    let newAnchor = now - absoluteStep * newSixteenth
                    state.grooveAnchorTime = newAnchor
                    updatedUnixEpoch = newAnchor + kCFAbsoluteTimeIntervalSince1970
                }
            }
            state.bpm = clamped
            return (state, updatedUnixEpoch)
        }
        if let updatedUnixEpoch {
            grooveAnchorUnixEpochStorage = updatedUnixEpoch
        }
        publishPlaybackMirrors(gate)
        grooveClock.retime(to: clamped, wallClockAnchor: gate.grooveAnchorTime)
    }

    func lockTempo(at bpm: Double) {
        let frozen = playbackGate.withLock { $0.isGrooveFrozen }
        guard !frozen else { return }
        let clamped = clampBPM(bpm)
        let previous = playbackGate.withLock { $0.bpm }
        let bpmChanged = abs(clamped - previous) > 0.25
        let gate = playbackGate.withLock { state -> PlaybackGate in
            state.bpm = clamped
            return state
        }
        tempoLocked = true
        publishPlaybackMirrors(gate)
        if gate.isPlaying, bpmChanged {
            startGrooveClock()
        }
    }

    func unlockTempo() {
        let frozen = playbackGate.withLock { $0.isGrooveFrozen }
        guard !frozen else { return }
        tempoLocked = false
    }

    func followTempo(_ bpm: Double) {
        guard !tempoLocked else { return }
        let clamped = clampBPM(bpm)
        let snapshot = playbackGate.withLock { state -> (playing: Bool, bpm: Double) in
            (state.isPlaying, state.bpm)
        }
        guard snapshot.playing else {
            let gate = playbackGate.withLock { state -> PlaybackGate in
                state.bpm = clamped
                return state
            }
            publishPlaybackMirrors(gate)
            return
        }
        let nextBPM: Double
        if abs(clamped - snapshot.bpm) > 10 {
            nextBPM = clamped
        } else {
            nextBPM = snapshot.bpm * 0.82 + clamped * 0.18
        }
        let gate = playbackGate.withLock { state -> PlaybackGate in
            state.bpm = nextBPM
            return state
        }
        publishPlaybackMirrors(gate)
        startGrooveClock()
    }

    private func clampBPM(_ bpm: Double) -> Double {
        min(max(bpm, 48), 200)
    }

    private func configureAudioIfNeeded() {
        ensureOutputGraphWired()
        if !didLoadSoundSourcePreference {
            didLoadSoundSourcePreference = true
            soundSourceSelectionStorage = DrumSoundSourceStore.load()
        }
        scheduleInitialSoundLoadIfNeeded()
        #if os(macOS)
        refreshAvailableAudioUnits()
        #endif
        #if os(iOS)
        activatePlaybackAudioSession()
        #endif
        if !engine.isRunning {
            engine.prepare()
            try? engine.start()
        }
    }

    #if os(iOS)
    /// Shared category with metronome / backing track — mixWithOthers avoids fighting other engines.
    private func activatePlaybackAudioSession() {
        let session = AVAudioSession.sharedInstance()
        // Prefer playAndRecord when mic capture may also run; otherwise playback is enough.
        let category: AVAudioSession.Category =
            session.category == .playAndRecord ? .playAndRecord : .playback
        try? session.setCategory(
            category,
            mode: .default,
            options: [.mixWithOthers, .defaultToSpeaker, .allowBluetoothHFP, .allowBluetoothA2DP]
        )
        try? session.setActive(true, options: [])
    }
    #endif

    private func reloadSoundBackend() async {
        let wasPlaying = isPlaying
        let savedPattern = pattern
        let savedBPM = currentBPM
        let savedBeats = beatsPerBar
        let savedStep = currentStep
        let restoredVolume = volume

        ensureOutputGraphWired()
        didScheduleInitialSoundLoad = true
        isLoadingSoundSource = true
        soundSourceError = nil
        // Mute during graph rebuild so iOS doesn't spit a loud click/noise burst.
        masterMixer.outputVolume = 0
        defer {
            masterMixer.outputVolume = restoredVolume
            isLoadingSoundSource = false
        }

        cancelScheduledPlayback()
        // Pause the groove while we rebuild so hits don't fire into a half-wired graph.
        let gate = playbackGate.withLock { state -> PlaybackGate in
            state.isPlaying = false
            return state
        }
        publishPlaybackMirrors(gate)
        grooveClock.stop()
        teardownActiveBackend()

        switch soundSourceSelection.kind {
        case .systemGM:
            await loadSystemGMBackend()
        case .userSoundFont:
            await loadUserSoundFontBackend()
        case .audioUnit:
            await loadAudioUnitBackend()
        case .synthesis:
            loadSynthesisBackend()
        }

        #if os(iOS)
        activatePlaybackAudioSession()
        #endif
        if !engine.isRunning {
            engine.prepare()
            try? engine.start()
        }
        startSynthesisPlayersIfNeeded()

        // Brief settle so the new backend doesn't pop into an already-hot output.
        try? await Task.sleep(nanoseconds: 40_000_000)

        if wasPlaying {
            let gate = playbackGate.withLock { state -> PlaybackGate in
                state.isPlaying = true
                state.bpm = savedBPM
                return state
            }
            publishPlaybackMirrors(gate)
            pattern = savedPattern
            beatsPerBar = savedBeats
            currentStep = savedStep
            startGrooveClock()
        }
    }

    private func loadSystemGMBackend() async {
        guard FileManager.default.fileExists(atPath: Self.gmSoundBankPath) else {
            loadSynthesisBackend()
            soundSourceError = String(
                localized: "System drum bank unavailable — using basic synth. Load a soundfont (.sf2) for fuller drums."
            )
            return
        }

        let sampler = AVAudioUnitSampler()
        do {
            try sampler.loadSoundBankInstrument(
                at: URL(fileURLWithPath: Self.gmSoundBankPath),
                program: 0,
                bankMSB: UInt8(kAUSampler_DefaultPercussionBankMSB),
                bankLSB: UInt8(kAUSampler_DefaultBankLSB)
            )
            attachMIDISampler(sampler)
            soundSourceLabel = DrumSoundSourceKind.systemGM.label
            usesSampleDrumKit = true
            activeBackend = .midiSampler
        } catch {
            soundSourceError = error.localizedDescription
            loadSynthesisBackend()
        }
    }

    private func loadUserSoundFontBackend() async {
        guard let bookmark = soundSourceSelection.soundFontBookmark else {
            soundSourceError = String(localized: "Choose a soundfont file first.")
            await loadSystemGMBackend()
            return
        }

        let url: URL
        do {
            url = try DrumSoundFontAccess.resolveURL(from: bookmark)
        } catch {
            soundSourceError = error.localizedDescription
            await loadSystemGMBackend()
            return
        }

        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }

        let sampler = AVAudioUnitSampler()
        do {
            let ext = url.pathExtension.lowercased()
            if ext == "dls" {
                try sampler.loadSoundBankInstrument(
                    at: url,
                    program: 0,
                    bankMSB: UInt8(kAUSampler_DefaultPercussionBankMSB),
                    bankLSB: UInt8(kAUSampler_DefaultBankLSB)
                )
            } else {
                try sampler.loadInstrument(at: url)
            }
            attachMIDISampler(sampler)
            let name = soundSourceSelection.soundFontDisplayName ?? url.lastPathComponent
            soundSourceLabel = name
            usesSampleDrumKit = true
            activeBackend = .midiSampler
        } catch {
            soundSourceError = error.localizedDescription
            await loadSystemGMBackend()
        }
    }

    private func loadAudioUnitBackend() async {
        guard let ref = soundSourceSelection.audioUnit else {
            soundSourceError = String(localized: "Select an AU plugin first.")
            await loadSystemGMBackend()
            return
        }

        do {
            let unit = try await instantiateAudioUnit(ref)
            attachMIDIPlugin(unit)
            soundSourceLabel = ref.displayName
            usesSampleDrumKit = true
            activeBackend = .midiPlugin
        } catch {
            soundSourceError = String(
                localized: "Could not load “\(ref.name)”. Try a soundfont or Apple GM drums. \(error.localizedDescription)"
            )
            await loadSystemGMBackend()
        }
    }

    private func instantiateAudioUnit(_ ref: DrumAUComponentRef) async throws -> AVAudioUnit {
        try await withCheckedThrowingContinuation { continuation in
            AVAudioUnit.instantiate(with: ref.audioComponentDescription, options: []) { unit, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let unit {
                    continuation.resume(returning: unit)
                } else {
                    continuation.resume(throwing: DrumSoundLoadError.instantiationFailed)
                }
            }
        }
    }

    private func attachMIDISampler(_ sampler: AVAudioUnitSampler) {
        samplerUnit = sampler
        pluginUnit = nil
        engine.attach(sampler)
        engine.connect(sampler, to: masterMixer, format: nil)
    }

    private func attachMIDIPlugin(_ unit: AVAudioUnit) {
        samplerUnit = nil
        pluginUnit = unit
        engine.attach(unit)
        engine.connect(unit, to: masterMixer, format: nil)
    }

    private func teardownActiveBackend() {
        cancelScheduledPlayback()
        silenceActiveMIDINotes()

        if engine.isRunning {
            engine.stop()
        }

        if let samplerUnit {
            engine.disconnectNodeOutput(samplerUnit)
            engine.detach(samplerUnit)
            self.samplerUnit = nil
        }

        if let pluginUnit {
            engine.disconnectNodeOutput(pluginUnit)
            engine.detach(pluginUnit)
            self.pluginUnit = nil
        }

        for pool in voicePlayerPools.values {
            for player in pool {
                engine.disconnectNodeOutput(player)
                engine.detach(player)
            }
        }
        voicePlayerPools.removeAll()
        voicePoolIndices.removeAll()
        buffers.removeAll()
        activeBackend = .none
        usesSampleDrumKit = false
    }

    private func synthesisPoolSize(for voice: DrumVoice) -> Int {
        switch voice {
        case .hihatClosed: 5
        case .snare: 4
        case .kick: 3
        case .hihatOpen, .rim: 3
        default: 2
        }
    }

    private func nextSynthesisPlayer(for voice: DrumVoice) -> AVAudioPlayerNode? {
        guard let pool = voicePlayerPools[voice], !pool.isEmpty else { return nil }
        let index = voicePoolIndices[voice, default: 0]
        voicePoolIndices[voice] = (index + 1) % pool.count
        return pool[index]
    }

    private func synthesisRenderFormat() -> AVAudioFormat {
        let output = engine.outputNode.outputFormat(forBus: 0)
        if output.sampleRate >= 8_000, output.channelCount > 0 {
            return output
        }
        return AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)
            ?? AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
    }

    private func loadSynthesisBackend() {
        let format = synthesisRenderFormat()
        for voice in DrumVoice.allCases {
            let count = synthesisPoolSize(for: voice)
            var pool: [AVAudioPlayerNode] = []
            pool.reserveCapacity(count)
            for _ in 0..<count {
                let player = AVAudioPlayerNode()
                engine.attach(player)
                engine.connect(player, to: masterMixer, format: format)
                // Start players only after the engine is running (see startSynthesisPlayersIfNeeded).
                pool.append(player)
            }
            voicePlayerPools[voice] = pool
            voicePoolIndices[voice] = 0
        }

        buffers[.kick] = DrumVoiceSynthesis.kick(format: format)
        buffers[.snare] = DrumVoiceSynthesis.snare(format: format)
        buffers[.hihatClosed] = DrumVoiceSynthesis.hihatClosed(format: format)
        buffers[.hihatOpen] = DrumVoiceSynthesis.hihatOpen(format: format)
        buffers[.rim] = DrumVoiceSynthesis.rim(format: format)
        buffers[.ride] = DrumVoiceSynthesis.ride(format: format)
        buffers[.cowbell] = DrumVoiceSynthesis.cowbell(format: format)
        buffers[.conga] = DrumVoiceSynthesis.conga(format: format)
        buffers[.shaker] = DrumVoiceSynthesis.shaker(format: format)
        buffers[.tambourine] = DrumVoiceSynthesis.tambourine(format: format)
        buffers[.bongo] = DrumVoiceSynthesis.bongo(format: format)

        soundSourceLabel = String(localized: "Studio kit")
        usesSampleDrumKit = false
        activeBackend = .synthesis
    }

    private func startSynthesisPlayersIfNeeded() {
        guard activeBackend == .synthesis else { return }
        for pool in voicePlayerPools.values {
            for player in pool where !player.isPlaying {
                player.play()
            }
        }
    }

    private func teardownSynthesisPlayers() {
        for pool in voicePlayerPools.values {
            for player in pool {
                engine.disconnectNodeOutput(player)
                engine.detach(player)
            }
        }
        voicePlayerPools.removeAll()
        voicePoolIndices.removeAll()
        buffers.removeAll()
    }

    private func startGrooveClock() {
        let snapshot = playbackGate.withLock { state in
            (
                playing: state.isPlaying,
                bpm: state.bpm,
                anchor: state.isGrooveFrozen ? state.grooveAnchorTime : nil
            )
        }
        guard snapshot.playing else { return }
        grooveClock.start(bpm: snapshot.bpm, wallClockAnchor: snapshot.anchor)
    }

    private func playGrooveStep(_ absoluteStep: Int) {
        let snapshot = playbackGate.withLock { state in
            (playing: state.isPlaying, generation: state.generation, bpm: state.bpm)
        }
        guard snapshot.playing else { return }

        let stepInBar = ((absoluteStep % 16) + 16) % 16
        let barIndex = max(0, absoluteStep / 16)
        currentStep = stepInBar

        let resolved = eventsForCurrentStep(stepInBar, barIndex: barIndex)
        currentPhraseKind = resolved.kind
        let hits = resolved.events
        let swing = activeUserMIDILoop?.swingHint ?? pattern.swingAmount
        let sixteenth = (60.0 / snapshot.bpm) / 4.0

        // Quarter-note click on the same engine as the kit (avoids dual-AVAudioEngine latency).
        if metronomeClickThroughGroove, stepInBar % 4 == 0 {
            let beatInBar = stepInBar / 4
            scheduleGrooveClick(accent: beatInBar == 0)
            onGrooveBeat?(beatInBar, beatInBar == 0)
        }

        for event in hits {
            let delay = grooveDelay(
                for: stepInBar,
                voice: event.voice,
                sixteenth: sixteenth,
                swing: swing
            )
            if delay > 0.0004 {
                let captured = event
                let generation = snapshot.generation
                Task { @MainActor [weak self] in
                    let ns = UInt64(max(0, delay) * 1_000_000_000)
                    try? await Task.sleep(nanoseconds: ns)
                    guard let self else { return }
                    let stillPlaying = self.playbackGate.withLock { state in
                        state.isPlaying && state.generation == generation
                    }
                    guard stillPlaying else { return }
                    self.play(captured)
                }
            } else {
                play(event)
            }
        }
    }

    /// Swing + per-voice microtiming so grooves feel played, not quantized flat.
    private func grooveDelay(
        for step: Int,
        voice: DrumVoice,
        sixteenth: Double,
        swing: Double
    ) -> TimeInterval {
        var delay: TimeInterval = 0
        if swing > 0 {
            // Delayed offbeat 8ths (the “and”)
            if [2, 6, 10, 14].contains(step) {
                delay += sixteenth * swing * 0.34
            }
            // Shuffle 16ths for jazz / blues — soft push on the e/a
            if (pattern == .jazzSwing || pattern == .bluesShuffle),
               [1, 5, 9, 13].contains(step) {
                delay += sixteenth * swing * 0.12
            }
        }
        // Kick stays tight; hats wander; snare can sit back in pocket styles.
        let micro: TimeInterval
        switch voice {
        case .kick:
            micro = Double.random(in: 0...0.003)
        case .snare, .rim:
            micro = pattern.laidBackPocket
                ? Double.random(in: 0.002...0.011)
                : Double.random(in: 0...0.006)
        case .hihatClosed, .hihatOpen:
            micro = Double.random(in: 0...0.008)
        case .ride, .cowbell, .conga, .bongo:
            micro = Double.random(in: 0...0.005)
        case .shaker, .tambourine:
            micro = Double.random(in: 0...0.007)
        }
        return delay + micro
    }

    private func eventsForCurrentStep(
        _ step: Int,
        barIndex: Int
    ) -> (events: [DrumStepEvent], kind: DrumPhraseKind) {
        if let learnedPattern, !learnedPattern.isEmpty {
            let mapped = instrumentCategory.mapEvents(learnedPattern.events(for: step))
            return (mapped, .grooveA)
        }
        if let userLoop = activeUserMIDILoop {
            let events = userLoop.events(for: step, barIndex: barIndex)
            let kind: DrumPhraseKind = (barIndex % max(1, userLoop.barCount) == userLoop.barCount - 1)
                ? .fill
                : (barIndex % 2 == 0 ? .grooveA : .grooveB)
            let mixed = DrumHybridMixer.apply(
                events: events,
                kind: kind,
                hybridEnabled: hybridMIDILayers,
                categorySoftening: hybridCategorySoftening
            )
            return (instrumentCategory.mapEvents(mixed), kind)
        }

        // Pack-aware arrange mode: worship pack stays gentler on Full; funk pack prefers fills.
        let mode = arrangedModeForPack()
        let resolved = DrumPhrasePlayer.events(
            pattern: pattern,
            step: step,
            barIndex: barIndex,
            mode: mode,
            pack: loopPack
        )
        let mixed = DrumHybridMixer.apply(
            events: resolved.events,
            kind: resolved.kind,
            hybridEnabled: hybridMIDILayers,
            categorySoftening: hybridCategorySoftening
        )
        return (instrumentCategory.mapEvents(mixed), resolved.kind)
    }

    private func arrangedModeForPack() -> DrumArrangeMode {
        switch (arrangeMode, loopPack) {
        case (.full, .worship):
            // Soft pack: Full still gets intro/breaks but not aggressive fills every cycle.
            return .full
        case (.auto, .funkPop), (.auto, .latin), (.auto, .urban), (.auto, .world):
            return .auto
        case (.auto, .worship):
            return .fillsOn
        default:
            return arrangeMode
        }
    }

    private func play(_ event: DrumStepEvent) {
        play(event.voice, velocityScale: event.velocityScale)
    }

    private func play(_ voice: DrumVoice, velocityScale: Float = 1) {
        let playing = playbackGate.withLock { $0.isPlaying }
        guard playing, activeBackend != .none else { return }
        if !engine.isRunning {
            try? engine.start()
        }

        // Kick steadier; hats/ghosts more dynamic.
        let humanize: Float
        switch voice {
        case .kick:
            humanize = Float.random(in: 0.92...1.0)
        case .snare:
            humanize = Float.random(in: 0.88...1.02)
        case .hihatClosed, .hihatOpen:
            humanize = Float.random(in: 0.78...1.05)
        default:
            humanize = Float.random(in: 0.86...1.02)
        }
        let velocity = UInt8(
            min(127, max(1, Int(Float(voice.defaultVelocity) * humanize * velocityScale)))
        )
        let note = voice.generalMIDINote
        let channel: UInt8 = 9

        // Closed hat chokes an open hat for a more kit-like feel.
        if voice == .hihatClosed {
            chokeOpenHiHat(channel: channel)
        }

        switch activeBackend {
        case .midiSampler:
            samplerUnit?.startNote(note, withVelocity: velocity, onChannel: channel)
            scheduleMIDINoteOff(note: note, channel: channel, voice: voice, sampler: samplerUnit)
        case .midiPlugin:
            if let instrument = pluginUnit as? AVAudioUnitMIDIInstrument {
                instrument.startNote(note, withVelocity: velocity, onChannel: channel)
                scheduleMIDINoteOff(note: note, channel: channel, voice: voice, plugin: instrument)
            }
        case .synthesis:
            guard let template = buffers[voice],
                  let player = nextSynthesisPlayer(for: voice) else { return }
            let gain = humanize * velocityScale
            let buffer = abs(gain - 1) < 0.03 ? template : DrumVoiceSynthesis.scaledCopy(template, gain: gain)
            player.scheduleBuffer(buffer, completionHandler: nil)
        case .none:
            break
        }
    }

    private func chokeOpenHiHat(channel: UInt8) {
        let open = DrumVoice.hihatOpen.generalMIDINote
        switch activeBackend {
        case .midiSampler:
            samplerUnit?.stopNote(open, onChannel: channel)
        case .midiPlugin:
            (pluginUnit as? AVAudioUnitMIDIInstrument)?.stopNote(open, onChannel: channel)
        case .synthesis, .none:
            break
        }
    }

    private func scheduleMIDINoteOff(
        note: UInt8,
        channel: UInt8,
        voice: DrumVoice,
        sampler: AVAudioUnitSampler? = nil,
        plugin: AVAudioUnitMIDIInstrument? = nil
    ) {
        let generation = playbackGate.withLock { $0.generation }
        let noteDuration = voice.noteOffMilliseconds
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(noteDuration) * 1_000_000)
            guard let self else { return }
            let stillPlaying = self.playbackGate.withLock { state in
                state.isPlaying && state.generation == generation
            }
            guard stillPlaying else { return }
            if let sampler, self.samplerUnit === sampler {
                sampler.stopNote(note, onChannel: channel)
            } else if let plugin, self.pluginUnit === plugin {
                plugin.stopNote(note, onChannel: channel)
            }
        }
    }

    private func silenceActiveMIDINotes() {
        let channel: UInt8 = 9
        if let sampler = samplerUnit {
            for voice in DrumVoice.allCases {
                sampler.stopNote(voice.generalMIDINote, onChannel: channel)
            }
        }
        if let plugin = pluginUnit as? AVAudioUnitMIDIInstrument {
            for voice in DrumVoice.allCases {
                plugin.stopNote(voice.generalMIDINote, onChannel: channel)
            }
        }
    }
}

private enum DrumSoundLoadError: LocalizedError {
    case instantiationFailed

    var errorDescription: String? {
        switch self {
        case .instantiationFailed:
            String(localized: "The audio plugin could not be opened.")
        }
    }
}

// MARK: - Acoustic-style drum synthesis

enum DrumVoiceSynthesis {
    static func scaledCopy(_ source: AVAudioPCMBuffer, gain: Float) -> AVAudioPCMBuffer {
        guard let copy = AVAudioPCMBuffer(pcmFormat: source.format, frameCapacity: source.frameLength) else {
            return source
        }
        copy.frameLength = source.frameLength
        let channels = Int(source.format.channelCount)
        for channel in 0..<channels {
            guard let src = source.floatChannelData?[channel],
                  let dst = copy.floatChannelData?[channel] else { continue }
            for frame in 0..<Int(source.frameLength) {
                dst[frame] = src[frame] * gain
            }
        }
        return copy
    }

    static func kick(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        render(format: format, duration: 0.52, seed: 3) { ctx, t, sr in
            let punchEnv = exp(-t * 11.5)
            let bodyEnv = exp(-t * 5.2)
            let pitch = 165.0 * exp(-t * 18.0) + 52.0
            let click = sin(2 * .pi * pitch * t) * punchEnv * 0.88
            let sub = sin(2 * .pi * 42 * t) * bodyEnv * 0.58
            let thump = sin(2 * .pi * 88 * t) * exp(-t * 22) * 0.22
            let beater = ctx.bandpassNoise(t: t, low: 1800, high: 6500, seed: 3, sampleRate: sr) * exp(-t * 95) * 0.14
            return softClip(Float(click + sub + thump + beater))
        }
    }

    static func snare(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        render(format: format, duration: 0.28, seed: 17) { ctx, t, sr in
            let env = exp(-t * 22.0)
            let body = sin(2 * .pi * 185 * t) * exp(-t * 38) * 0.28
            let shell = sin(2 * .pi * 320 * t) * exp(-t * 55) * 0.12
            let wires = ctx.bandpassNoise(t: t, low: 2200, high: 9000, seed: 17, sampleRate: sr) * env * 0.55
            let crack = ctx.bandpassNoise(t: t, low: 900, high: 4200, seed: 29, sampleRate: sr) * exp(-t * 68) * 0.28
            let ghost = ctx.bandpassNoise(t: t, low: 1400, high: 7000, seed: 37, sampleRate: sr) * exp(-t * 42) * 0.06
            return softClip(Float(body + shell + wires + crack + ghost))
        }
    }

    static func hihatClosed(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        render(format: format, duration: 0.065, seed: 41) { ctx, t, sr in
            let env = exp(-t * 145.0)
            let metal = ctx.bandpassNoise(t: t, low: 5200, high: 14000, seed: 41, sampleRate: sr) * env * 0.42
            let shimmer = sin(2 * .pi * 9800 * t) * exp(-t * 210) * 0.09
            let sizzle = sin(2 * .pi * 12400 * t) * exp(-t * 260) * 0.05
            return softClip(Float(metal + shimmer + sizzle))
        }
    }

    static func hihatOpen(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        render(format: format, duration: 0.32, seed: 53) { ctx, t, sr in
            let env = exp(-t * 14.0)
            let wash = ctx.bandpassNoise(t: t, low: 3800, high: 12000, seed: 53, sampleRate: sr) * env * 0.38
            let ring = sin(2 * .pi * 7600 * t) * exp(-t * 9) * 0.08
            let air = ctx.pinkNoise(t: t, seed: 61) * exp(-t * 7) * 0.1
            return softClip(Float(wash + ring + air))
        }
    }

    static func rim(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        render(format: format, duration: 0.07, seed: 7) { ctx, t, sr in
            let ping = sin(2 * .pi * 2450 * t) * exp(-t * 95) * 0.52
            let wood = sin(2 * .pi * 920 * t) * exp(-t * 72) * 0.28
            let click = ctx.bandpassNoise(t: t, low: 1200, high: 4800, seed: 7, sampleRate: sr) * exp(-t * 110) * 0.14
            return softClip(Float(ping + wood + click))
        }
    }

    static func ride(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        render(format: format, duration: 0.62, seed: 23) { ctx, t, sr in
            let env = exp(-t * 5.8)
            let wash = ctx.bandpassNoise(t: t, low: 2800, high: 9000, seed: 23, sampleRate: sr) * env * 0.28
            let ping = sin(2 * .pi * 4300 * t) * exp(-t * 18) * 0.16
            let body = sin(2 * .pi * 680 * t) * exp(-t * 11) * 0.1
            let stick = ctx.bandpassNoise(t: t, low: 1800, high: 5500, seed: 31, sampleRate: sr) * exp(-t * 45) * 0.07
            return softClip(Float(wash + ping + body + stick))
        }
    }

    static func cowbell(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        render(format: format, duration: 0.22, seed: 71) { ctx, t, sr in
            let env = exp(-t * 24.0)
            let fundamental = sin(2 * .pi * 587 * t) * 0.46
            let partial = sin(2 * .pi * 845 * t) * 0.34
            let inharmonic = sin(2 * .pi * 1120 * t) * exp(-t * 38) * 0.12
            let click = ctx.bandpassNoise(t: t, low: 2200, high: 7000, seed: 71, sampleRate: sr) * exp(-t * 88) * 0.08
            return softClip(Float((fundamental + partial + inharmonic + click) * env))
        }
    }

    static func conga(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        render(format: format, duration: 0.36, seed: 83) { ctx, t, sr in
            let pitch = 248.0 * exp(-t * 13.0) + 96.0
            let slap = sin(2 * .pi * pitch * t) * exp(-t * 16) * 0.78
            let body = sin(2 * .pi * 132 * t) * exp(-t * 8.5) * 0.24
            let hand = ctx.bandpassNoise(t: t, low: 400, high: 2200, seed: 83, sampleRate: sr) * exp(-t * 52) * 0.12
            return softClip(Float(slap + body + hand))
        }
    }

    static func shaker(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        render(format: format, duration: 0.12, seed: 97) { ctx, t, sr in
            let env = exp(-t * 38.0)
            let beads = ctx.bandpassNoise(t: t, low: 4500, high: 13000, seed: 97, sampleRate: sr) * env * 0.48
            let shell = ctx.pinkNoise(t: t, seed: 101) * exp(-t * 28) * 0.08
            return softClip(Float(beads + shell))
        }
    }

    static func tambourine(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        render(format: format, duration: 0.28, seed: 109) { ctx, t, sr in
            let env = exp(-t * 16.0)
            let jingles = ctx.bandpassNoise(t: t, low: 5200, high: 12000, seed: 109, sampleRate: sr) * env * 0.4
            let slap = sin(2 * .pi * 980 * t) * exp(-t * 55) * 0.12
            let rattle = ctx.bandpassNoise(t: t, low: 2800, high: 8000, seed: 113, sampleRate: sr) * exp(-t * 22) * 0.16
            return softClip(Float(jingles + slap + rattle))
        }
    }

    static func bongo(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        render(format: format, duration: 0.24, seed: 127) { ctx, t, sr in
            let pitch = 320.0 * exp(-t * 16.0) + 140.0
            let open = sin(2 * .pi * pitch * t) * exp(-t * 18) * 0.72
            let skin = ctx.bandpassNoise(t: t, low: 600, high: 2800, seed: 127, sampleRate: sr) * exp(-t * 48) * 0.14
            return softClip(Float(open + skin))
        }
    }

    private struct RenderContext {
        var pinkState: Double = 0
        var bpLowState: Double = 0
        var bpHighState: Double = 0

        mutating func pinkNoise(t: Double, seed: Int) -> Double {
            let white = noiseSample(t: t, seed: seed)
            pinkState = pinkState * 0.92 + white * 0.08
            return pinkState
        }

        mutating func bandpassNoise(t: Double, low: Double, high: Double, seed: Int, sampleRate: Double) -> Double {
            let white = noiseSample(t: t, seed: seed)
            let sr = max(sampleRate, 8_000)
            let lowAlpha = min(0.99, max(0.01, 2 * .pi * low / sr))
            let highAlpha = min(0.99, max(0.01, 2 * .pi * high / sr))
            bpLowState += lowAlpha * (white - bpLowState)
            bpHighState += highAlpha * (white - bpHighState)
            return bpLowState - bpHighState
        }
    }

    private static func render(
        format: AVAudioFormat,
        duration: Double,
        seed: Int,
        sample: (inout RenderContext, Double, Double) -> Float
    ) -> AVAudioPCMBuffer? {
        let sampleRate = format.sampleRate
        guard sampleRate > 0 else { return nil }
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }
        buffer.frameLength = frameCount
        let channels = Int(format.channelCount)
        var ctx = RenderContext()
        for frame in 0..<Int(frameCount) {
            let t = Double(frame) / sampleRate
            // Fade the first/last few ms so kit switches and note edges don't click.
            let fadeIn = min(1, t / 0.004)
            let fadeOut = min(1, (duration - t) / 0.008)
            let gate = Float(max(0, min(fadeIn, fadeOut)))
            let value = sample(&ctx, t, sampleRate) * gate
            for channel in 0..<channels {
                buffer.floatChannelData?[channel][frame] = value
            }
        }
        applyBusGlue(buffer)
        return buffer
    }

    private static func applyBusGlue(_ buffer: AVAudioPCMBuffer) {
        guard let channel = buffer.floatChannelData?[0] else { return }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return }
        var peak: Float = 0
        for frame in 0..<count {
            peak = max(peak, abs(channel[frame]))
        }
        // Keep Studio Kit quieter than GM so a switch doesn't feel like a noise blast.
        let targetPeak: Float = 0.62
        let makeup = peak > 0.001 ? min(1.05, targetPeak / peak) : 1
        for frame in 0..<count {
            let x = channel[frame] * makeup
            channel[frame] = x / (1 + abs(x * 0.7))
        }
        if buffer.format.channelCount > 1, let right = buffer.floatChannelData?[1] {
            for frame in 0..<count {
                right[frame] = channel[frame]
            }
        }
    }

    private static func noiseSample(t: Double, seed: Int) -> Double {
        var hash = seed &+ Int(t * 44_100)
        hash = ((hash >> 16) ^ hash) &* 0x45d9f3b
        hash = ((hash >> 16) ^ hash) &* 0x45d9f3b
        hash = (hash >> 16) ^ hash
        let normalized = Double(hash) / Double(UInt32.max)
        return (normalized * 2) - 1
    }

    private static func softClip(_ sample: Float) -> Float {
        let x = sample * 1.05
        return x / (1 + abs(x))
    }
}
