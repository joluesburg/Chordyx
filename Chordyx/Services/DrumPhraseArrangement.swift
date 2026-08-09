//
//  DrumPhraseArrangement.swift
//  Chordyx
//
//  MIDI phrase banks + arrangement scheduler for Solo Drums loops.
//

import Foundation

// MARK: - Phrase model

enum DrumPhraseKind: String, CaseIterable, Identifiable, Sendable, Codable {
    case intro
    case grooveA
    case grooveB
    case fill
    case breakdown
    case ending

    var id: String { rawValue }

    var shortLabel: String {
        switch self {
        case .intro: String(localized: "Intro")
        case .grooveA: "A"
        case .grooveB: "B"
        case .fill: String(localized: "Fill")
        case .breakdown: String(localized: "Break")
        case .ending: String(localized: "End")
        }
    }
}

/// How aggressively Solo Drums moves through phrase loops.
enum DrumArrangeMode: String, CaseIterable, Identifiable, Sendable, Codable {
    case grooveOnly
    case fillsOn
    case auto
    case full

    var id: String { rawValue }

    var label: String {
        switch self {
        case .grooveOnly: String(localized: "Groove only")
        case .fillsOn: String(localized: "Fills on")
        case .auto: String(localized: "Auto")
        case .full: String(localized: "Full (intro + breaks)")
        }
    }

    var subtitle: String {
        switch self {
        case .grooveOnly: String(localized: "Steady A/B feel — no fills or intros")
        case .fillsOn: String(localized: "Groove with fills every few bars")
        case .auto: String(localized: "Cycles A/B/fill like a live drummer")
        case .full: String(localized: "Intro, grooves, fills, and breakdowns")
        }
    }
}

struct DrumPhraseSlot: Sendable, Equatable {
    let kind: DrumPhraseKind
    let barCount: Int

    init(_ kind: DrumPhraseKind, bars: Int) {
        self.kind = kind
        self.barCount = max(1, bars)
    }
}

struct DrumArrangementTimeline: Sendable {
    let slots: [DrumPhraseSlot]
    let cycleBars: Int

    init(slots: [DrumPhraseSlot]) {
        self.slots = slots
        self.cycleBars = max(1, slots.reduce(0) { $0 + $1.barCount })
    }

    func resolution(atBar barIndex: Int) -> (kind: DrumPhraseKind, barInPhrase: Int, phraseLength: Int) {
        let bar = ((barIndex % cycleBars) + cycleBars) % cycleBars
        var cursor = 0
        for slot in slots {
            let end = cursor + slot.barCount
            if bar < end {
                return (slot.kind, bar - cursor, slot.barCount)
            }
            cursor = end
        }
        return (.grooveA, 0, 1)
    }
}

enum DrumArrangementLibrary {
    static func timeline(
        for pattern: DrumPattern,
        mode: DrumArrangeMode,
        pack: DrumMIDILoopPack? = nil
    ) -> DrumArrangementTimeline {
        let resolvedPack = pack ?? DrumMIDILoopPack.pack(for: pattern)
        switch mode {
        case .grooveOnly:
            return DrumArrangementTimeline(slots: [
                .init(.grooveA, bars: 2),
                .init(.grooveB, bars: 2)
            ])
        case .fillsOn:
            return DrumArrangementTimeline(slots: [
                .init(.grooveA, bars: 3),
                .init(.fill, bars: 1),
                .init(.grooveB, bars: 3),
                .init(.fill, bars: 1)
            ])
        case .auto:
            return autoTimeline(for: pattern, pack: resolvedPack)
        case .full:
            return fullTimeline(for: pattern, pack: resolvedPack)
        }
    }

    private static func autoTimeline(for pattern: DrumPattern, pack: DrumMIDILoopPack) -> DrumArrangementTimeline {
        switch pack {
        case .worship:
            return DrumArrangementTimeline(slots: [
                .init(.grooveA, bars: 4),
                .init(.grooveB, bars: 4),
                .init(.grooveA, bars: 4),
                .init(.fill, bars: 1)
            ])
        case .latin:
            return DrumArrangementTimeline(slots: [
                .init(.grooveA, bars: 4),
                .init(.grooveA, bars: 4),
                .init(.grooveB, bars: 4),
                .init(.fill, bars: 1),
                .init(.grooveA, bars: 2),
                .init(.breakdown, bars: 2)
            ])
        case .funkPop:
            if pattern == .funkGroove || pattern == .gospelGroove {
                return DrumArrangementTimeline(slots: [
                    .init(.grooveA, bars: 4),
                    .init(.grooveB, bars: 4),
                    .init(.fill, bars: 1),
                    .init(.grooveA, bars: 3),
                    .init(.grooveB, bars: 3),
                    .init(.fill, bars: 1)
                ])
            }
            return DrumArrangementTimeline(slots: [
                .init(.grooveA, bars: 4),
                .init(.grooveB, bars: 3),
                .init(.fill, bars: 1)
            ])
        case .urban:
            return DrumArrangementTimeline(slots: [
                .init(.grooveA, bars: 4),
                .init(.grooveB, bars: 4),
                .init(.fill, bars: 1),
                .init(.grooveA, bars: 3),
                .init(.breakdown, bars: 1)
            ])
        case .world:
            return DrumArrangementTimeline(slots: [
                .init(.grooveA, bars: 4),
                .init(.grooveA, bars: 4),
                .init(.grooveB, bars: 3),
                .init(.fill, bars: 1)
            ])
        }
    }

    private static func fullTimeline(for pattern: DrumPattern, pack: DrumMIDILoopPack) -> DrumArrangementTimeline {
        let introBars = pack == .worship ? max(2, pattern.softIntroBars) : pattern.softIntroBars
        var slots: [DrumPhraseSlot] = [
            .init(.intro, bars: introBars),
            .init(.grooveA, bars: 4),
            .init(.grooveA, bars: pack == .latin ? 4 : 2),
            .init(.grooveB, bars: 4),
            .init(.fill, bars: 1),
            .init(.grooveA, bars: 3),
            .init(.breakdown, bars: pack == .funkPop ? 1 : 2),
            .init(.grooveB, bars: 4),
            .init(.fill, bars: 1)
        ]
        if pattern.allowsEndingTag {
            slots.append(.init(.ending, bars: 1))
        }
        return DrumArrangementTimeline(slots: slots)
    }
}

private extension DrumPattern {
    var softIntroBars: Int {
        switch self {
        case .worshipBallad, .softPulse, .bolero, .bossaNova: 4
        case .brushWaltz, .jazzSwing: 2
        default: 2
        }
    }

    var allowsEndingTag: Bool {
        switch self {
        case .worshipBallad, .gospelGroove, .popRock, .funkGroove, .salsa, .songo: true
        default: false
        }
    }
}

// MARK: - Phrase-aware event resolution

enum DrumPhrasePlayer {
    /// Resolve MIDI hits for a step using arrangement phrase context.
    static func events(
        pattern: DrumPattern,
        step: Int,
        barIndex: Int,
        mode: DrumArrangeMode,
        pack: DrumMIDILoopPack? = nil
    ) -> (events: [DrumStepEvent], kind: DrumPhraseKind) {
        let timeline = DrumArrangementLibrary.timeline(
            for: pattern,
            mode: mode,
            pack: pack ?? DrumMIDILoopPack.pack(for: pattern)
        )
        let resolved = timeline.resolution(atBar: barIndex)
        let s = ((step % 16) + 16) % 16
        var events = pattern.phraseBaseEvents(
            step: s,
            kind: resolved.kind,
            barInPhrase: resolved.barInPhrase,
            phraseLength: resolved.phraseLength
        )
        switch resolved.kind {
        case .fill, .ending:
            events.append(contentsOf: pattern.phraseFillOverlay(step: s, kind: resolved.kind))
        case .intro:
            if s == 0, resolved.barInPhrase == 0 {
                events.append(.init(.ride, velocityScale: 0.55))
            }
        case .breakdown:
            // Sparse — keep ghosts only; strip dense doubles later via velocity.
            break
        case .grooveA, .grooveB:
            if mode != .grooveOnly,
               resolved.barInPhrase == resolved.phraseLength - 1,
               s >= 14,
               pattern.allowsPhraseFills {
                events.append(contentsOf: pattern.phraseFillEvents(step: s))
            }
        }
        return (events, resolved.kind)
    }
}

// MARK: - Pattern phrase grids (priority styles get distinct A/B/intro/break)

extension DrumPattern {
    /// Expose fill overlay used by the phrase player (was private).
    func phraseFillEvents(step s: Int) -> [DrumStepEvent] {
        switch s {
        case 12:
            return [
                .init(.snare, velocityScale: 0.78),
                .init(.hihatOpen, velocityScale: 0.42)
            ]
        case 13:
            return [
                .init(.snare, velocityScale: 0.55),
                .init(.rim, velocityScale: 0.65),
                .init(.kick, velocityScale: 0.5)
            ]
        case 14:
            return [
                .init(.snare, velocityScale: 0.7),
                .init(.kick, velocityScale: 0.62)
            ]
        case 15:
            return [
                .init(.snare, velocityScale: 0.95),
                .init(.ride, velocityScale: 0.82)
            ]
        default:
            return []
        }
    }

    func phraseFillOverlay(step s: Int, kind: DrumPhraseKind) -> [DrumStepEvent] {
        var events = phraseFillEvents(step: s)
        if kind == .ending, s == 0 {
            events.append(.init(.ride, velocityScale: 1.05))
            events.append(.init(.kick, velocityScale: 1))
        }
        if kind == .fill, s == 15 {
            events.append(.init(.cowbell, velocityScale: 0.55))
        }
        return events
    }

    func phraseBaseEvents(
        step s: Int,
        kind: DrumPhraseKind,
        barInPhrase: Int,
        phraseLength: Int
    ) -> [DrumStepEvent] {
        switch kind {
        case .intro:
            return introEvents(step: s, barInPhrase: barInPhrase)
        case .breakdown:
            return breakdownEvents(step: s)
        case .ending:
            return endingEvents(step: s)
        case .fill:
            // Fill bars still keep a light groove under the overlay.
            return events(for: s)
        case .grooveA:
            return events(for: s)
        case .grooveB:
            return events(for: s)
        }
    }

    private func introEvents(step s: Int, barInPhrase: Int) -> [DrumStepEvent] {
        var events: [DrumStepEvent] = []
        switch self {
        case .worshipBallad, .softPulse, .bolero:
            if s == 0 { events.append(.init(.kick, velocityScale: 0.55)) }
            if [0, 8].contains(s) { events.append(.init(.ride, velocityScale: 0.4)) }
            if barInPhrase >= 2, s == 4 || s == 12 {
                events.append(.init(.rim, velocityScale: 0.4))
            }
        case .salsa, .songo, .merengue:
            if [0, 6, 10].contains(s) { events.append(.init(.cowbell, velocityScale: 0.7)) }
            if s == 0 { events.append(.init(.conga, velocityScale: 0.65)) }
            if barInPhrase >= 1, s == 8 { events.append(.init(.kick, velocityScale: 0.5)) }
        case .funkGroove, .gospelGroove, .popRock, .rockDrive:
            if s.isMultiple(of: 2) {
                events.append(.init(.hihatClosed, velocityScale: s.isMultiple(of: 4) ? 0.55 : 0.38))
            }
            if s == 0 { events.append(.init(.kick, velocityScale: 0.7)) }
            if barInPhrase >= 1, s == 4 || s == 12 {
                events.append(.init(.snare, velocityScale: 0.55))
            }
        default:
            if s == 0 { events.append(.init(.kick, velocityScale: 0.6)) }
            if [0, 4, 8, 12].contains(s) {
                events.append(.init(.hihatClosed, velocityScale: 0.45))
            }
        }
        return events
    }

    private func breakdownEvents(step s: Int) -> [DrumStepEvent] {
        var events: [DrumStepEvent] = []
        switch self {
        case .salsa, .songo, .merengue:
            if [0, 3, 6, 10].contains(s) {
                events.append(.init(.cowbell, velocityScale: 0.85))
            }
            if s == 0 || s == 8 { events.append(.init(.conga, velocityScale: 0.7)) }
        case .funkGroove, .gospelGroove:
            if s == 0 { events.append(.init(.kick, velocityScale: 0.85)) }
            if [4, 12].contains(s) { events.append(.init(.snare, velocityScale: 0.35)) }
            if s.isMultiple(of: 4) {
                events.append(.init(.hihatClosed, velocityScale: 0.4))
            }
        case .worshipBallad, .softPulse, .bolero:
            if s == 0 { events.append(.init(.kick, velocityScale: 0.5)) }
            if s == 8 { events.append(.init(.ride, velocityScale: 0.35)) }
        default:
            if s == 0 { events.append(.init(.kick, velocityScale: 0.7)) }
            if [4, 12].contains(s) { events.append(.init(.rim, velocityScale: 0.45)) }
            if [0, 8].contains(s) { events.append(.init(.hihatClosed, velocityScale: 0.4)) }
        }
        return events
    }

    private func endingEvents(step s: Int) -> [DrumStepEvent] {
        var events: [DrumStepEvent] = []
        if s == 0 {
            events.append(.init(.kick, velocityScale: 1))
            events.append(.init(.ride, velocityScale: 0.95))
        }
        if s == 4 || s == 8 {
            events.append(.init(.snare, velocityScale: 0.7))
        }
        if s == 12 {
            events.append(.init(.snare, velocityScale: 0.9))
            events.append(.init(.kick, velocityScale: 0.8))
        }
        if s == 15 {
            events.append(.init(.ride, velocityScale: 1.1))
        }
        return events
    }
}
