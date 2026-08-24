//
//  DrumMIDILoopPacks.swift
//  Chordyx
//
//  Tempo-native MIDI loop packs + user-saved custom grids (no audio/WAV).
//  Changing BPM only retimes the step clock — feel stays musical.
//

import Foundation

// MARK: - Event layer (hybrid body / ghost)

enum DrumEventLayer: String, Sendable, Codable {
    /// Kick / backbeat / main hats — the “body” of the groove.
    case body
    /// Ghosts, bells, congas, fill ornaments.
    case accent
}

extension DrumStepEvent {
    /// Classify a hit for hybrid ducking (body softens under fills).
    var layer: DrumEventLayer {
        switch voice {
        case .kick, .snare:
            return velocityScale >= 0.55 ? .body : .accent
        case .hihatClosed, .hihatOpen, .ride:
            return velocityScale >= 0.55 ? .body : .accent
        case .rim, .cowbell, .conga, .bongo, .shaker, .tambourine:
            return .accent
        }
    }
}

// MARK: - Named MIDI loop packs (multi-bar phrase banks)

enum DrumMIDILoopPack: String, CaseIterable, Identifiable, Sendable {
    case worship
    case latin
    case funkPop
    case urban
    case world

    var id: String { rawValue }

    var label: String {
        switch self {
        case .worship: String(localized: "Worship pack")
        case .latin: String(localized: "Latin pack")
        case .funkPop: String(localized: "Funk / Pop pack")
        case .urban: String(localized: "Urban pack")
        case .world: String(localized: "World pack")
        }
    }

    var subtitle: String {
        switch self {
        case .worship: String(localized: "Ballad → gospel builds, soft intros")
        case .latin: String(localized: "Merengue, salsa, songó, bachata, cumbia")
        case .funkPop: String(localized: "Pocket funk, pop/rock, jazz & blues")
        case .urban: String(localized: "Hip-hop, trap, dembow, disco")
        case .world: String(localized: "Reggae, afrobeat, country train")
        }
    }

    /// Preferred patterns this pack colors when Auto arrangement runs.
    var patterns: [DrumPattern] {
        switch self {
        case .worship: [.worshipBallad, .softPulse, .gospelGroove, .brushWaltz]
        case .latin: [.merengue, .salsa, .songo, .bossaNova, .bolero, .bachata, .cumbia, .chaCha, .soca]
        case .funkPop: [.funkGroove, .popRock, .rockDrive, .rbSoul, .edmPulse, .halfTimeRock, .jazzSwing, .bluesShuffle]
        case .urban: [.hipHopBoomBap, .trapHalftime, .dembow, .discoFour]
        case .world: [.reggaeOneDrop, .afrobeat, .countryTrain]
        }
    }

    static func pack(for pattern: DrumPattern) -> DrumMIDILoopPack {
        if worship.patterns.contains(pattern) { return .worship }
        if latin.patterns.contains(pattern) { return .latin }
        if urban.patterns.contains(pattern) { return .urban }
        if world.patterns.contains(pattern) { return .world }
        return .funkPop
    }
}

// MARK: - User custom MIDI loops (step grids)

struct UserMIDIDrumLoop: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var displayName: String
    /// Bars of 16 sixteenths; each step is a list of voices with velocity.
    var bars: [[[UserMIDIDrumHit]]]
    var createdAt: TimeInterval
    /// Optional feel hint for swing amount when recalled.
    var swingHint: Double

    init(
        id: UUID = UUID(),
        displayName: String,
        bars: [[[UserMIDIDrumHit]]],
        createdAt: TimeInterval = Date().timeIntervalSince1970,
        swingHint: Double = 0
    ) {
        self.id = id
        self.displayName = displayName
        self.bars = bars
        self.createdAt = createdAt
        self.swingHint = max(0, min(0.7, swingHint))
    }

    var barCount: Int { bars.count }

    func events(for step: Int, barIndex: Int) -> [DrumStepEvent] {
        guard !bars.isEmpty else { return [] }
        let bar = ((barIndex % bars.count) + bars.count) % bars.count
        let s = ((step % 16) + 16) % 16
        let row = bars[bar]
        guard s < row.count else { return [] }
        return row[s].compactMap { hit in
            guard let voice = DrumVoice(storageKey: hit.voice) else { return nil }
            return DrumStepEvent(voice, velocityScale: hit.velocityScale)
        }
    }

    static func capture(
        displayName: String,
        pattern: DrumPattern,
        arrangeMode: DrumArrangeMode,
        bars: Int = 4
    ) -> UserMIDIDrumLoop {
        let count = max(1, min(8, bars))
        var grid: [[[UserMIDIDrumHit]]] = []
        for bar in 0..<count {
            var steps: [[UserMIDIDrumHit]] = []
            for step in 0..<16 {
                let resolved = DrumPhrasePlayer.events(
                    pattern: pattern,
                    step: step,
                    barIndex: bar,
                    mode: arrangeMode
                )
                steps.append(resolved.events.map {
                    UserMIDIDrumHit(voice: $0.voice.storageKey, velocityScale: $0.velocityScale)
                })
            }
            grid.append(steps)
        }
        return UserMIDIDrumLoop(
            displayName: displayName,
            bars: grid,
            swingHint: pattern.swingAmount
        )
    }
}

struct UserMIDIDrumHit: Codable, Equatable, Sendable {
    var voice: String
    var velocityScale: Float
}

enum UserMIDIDrumLoopStore {
    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("MIDIDrumLoops", isDirectory: true)
    }

    static var catalogURL: URL {
        directory.appendingPathComponent("catalog.json")
    }

    static func load() -> [UserMIDIDrumLoop] {
        guard let data = try? Data(contentsOf: catalogURL),
              let loops = try? JSONDecoder().decode([UserMIDIDrumLoop].self, from: data) else {
            return []
        }
        return loops
    }

    static func save(_ loops: [UserMIDIDrumLoop]) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(loops) else { return }
        try? data.write(to: catalogURL, options: .atomic)
    }

    static func upsert(_ loop: UserMIDIDrumLoop) {
        var all = load()
        if let idx = all.firstIndex(where: { $0.id == loop.id }) {
            all[idx] = loop
        } else {
            all.insert(loop, at: 0)
        }
        save(all)
    }

    static func delete(_ id: UUID) {
        var all = load()
        all.removeAll { $0.id == id }
        save(all)
    }
}

// MARK: - Hybrid ducking helpers

enum DrumHybridMixer {
    /// Soften body hits during fill/breakdown so accents read clearly — still MIDI, still tempo-native.
    static func apply(
        events: [DrumStepEvent],
        kind: DrumPhraseKind,
        hybridEnabled: Bool,
        categorySoftening: Float = 1
    ) -> [DrumStepEvent] {
        guard hybridEnabled else { return events }
        let bodyScale: Float
        switch kind {
        case .fill, .ending:
            bodyScale = 0.42 * max(0.35, min(1.2, categorySoftening))
        case .breakdown:
            bodyScale = 0.55 * max(0.35, min(1.2, categorySoftening))
        case .intro:
            bodyScale = 0.75
        case .grooveA, .grooveB:
            bodyScale = 1
        }
        guard bodyScale < 0.99 else { return events }
        return events.map { event in
            guard event.layer == .body else { return event }
            return DrumStepEvent(event.voice, velocityScale: event.velocityScale * bodyScale)
        }
    }
}
