//
//  SoloDrumInstrumentCategory.swift
//  Chordyx
//
//  Solo accompaniment instrument families: full kit, Latin perc, light perc, etc.
//  Choosing a category remaps pattern voices so the same groove can sound like
//  batería, percusión, or a lighter hand-perc bed.
//

import Foundation

/// Instrument family for Solo Drums accompaniment (what plays / how voices map).
enum SoloDrumInstrumentCategory: String, CaseIterable, Identifiable, Codable, Sendable {
    case drums
    case percussion
    case lightPercussion
    case brushes
    case cajon
    case bellsAndMetals
    case electronic
    case softKit

    var id: String { rawValue }

    var label: String {
        switch self {
        case .drums: String(localized: "Batería")
        case .percussion: String(localized: "Percusión")
        case .lightPercussion: String(localized: "Percusión menor")
        case .brushes: String(localized: "Escobillas")
        case .cajon: String(localized: "Cajón")
        case .bellsAndMetals: String(localized: "Campanas y metales")
        case .electronic: String(localized: "Electrónico")
        case .softKit: String(localized: "Kit suave")
        }
    }

    var subtitle: String {
        switch self {
        case .drums:
            String(localized: "Kit completo — kick, caja, hi-hats y platos")
        case .percussion:
            String(localized: "Congas, campana, rim y texturas latinas")
        case .lightPercussion:
            String(localized: "Shaker, pandereta y hats suaves — sin bombo fuerte")
        case .brushes:
            String(localized: "Ride y rim con escobillas — ballads y jazz suave")
        case .cajon:
            String(localized: "Cuerpo de cajón — bombo grave y slaps en rim")
        case .bellsAndMetals:
            String(localized: "Campana, ride y rim — montuno / campana lead")
        case .electronic:
            String(localized: "Kick, snare y hats — sin percusión acústica latina")
        case .softKit:
            String(localized: "Worship soft — rim en vez de caja, ride suave")
        }
    }

    var systemImage: String {
        switch self {
        case .drums: "drum.fill"
        case .percussion: "hands.clap.fill"
        case .lightPercussion: "sparkles"
        case .brushes: "paintbrush.pointed.fill"
        case .cajon: "rectangle.portrait.fill"
        case .bellsAndMetals: "bell.fill"
        case .electronic: "waveform"
        case .softKit: "leaf.fill"
        }
    }

    /// Sections for the Solo Drums picker UI.
    static let pickerSections: [(title: String, categories: [SoloDrumInstrumentCategory])] = [
        (
            String(localized: "Kit"),
            [.drums, .softKit, .brushes, .electronic]
        ),
        (
            String(localized: "Percusión"),
            [.percussion, .lightPercussion, .cajon, .bellsAndMetals]
        )
    ]

    /// Remap a pattern step into the voices this category should play.
    func mapEvents(_ events: [DrumStepEvent]) -> [DrumStepEvent] {
        switch self {
        case .drums:
            return events

        case .percussion:
            return events.compactMap { event in
                switch event.voice {
                case .kick:
                    return .init(.conga, velocityScale: event.velocityScale * 0.92)
                case .snare:
                    return .init(.rim, velocityScale: event.velocityScale * 0.88)
                case .hihatClosed:
                    return .init(.shaker, velocityScale: event.velocityScale * 0.85)
                case .hihatOpen:
                    return .init(.tambourine, velocityScale: event.velocityScale * 0.8)
                case .rim, .cowbell, .conga, .ride, .bongo, .shaker, .tambourine:
                    return event
                }
            }

        case .lightPercussion:
            return events.compactMap { event in
                switch event.voice {
                case .kick, .snare, .conga, .cowbell:
                    // Drop heavy kit / hand drums — keep a soft pulse via shaker/rim only.
                    if event.voice == .kick, event.velocityScale >= 0.85 {
                        return .init(.shaker, velocityScale: 0.55)
                    }
                    if event.voice == .snare {
                        return .init(.tambourine, velocityScale: event.velocityScale * 0.7)
                    }
                    return nil
                case .hihatClosed:
                    return .init(.shaker, velocityScale: event.velocityScale * 0.9)
                case .hihatOpen:
                    return .init(.tambourine, velocityScale: event.velocityScale * 0.85)
                case .rim:
                    return .init(.rim, velocityScale: event.velocityScale * 0.75)
                case .ride:
                    return .init(.shaker, velocityScale: event.velocityScale * 0.65)
                case .shaker, .tambourine, .bongo:
                    return event
                }
            }

        case .brushes:
            return events.compactMap { event in
                switch event.voice {
                case .kick:
                    return .init(.kick, velocityScale: event.velocityScale * 0.55)
                case .snare:
                    return .init(.rim, velocityScale: event.velocityScale * 0.7)
                case .hihatClosed, .hihatOpen:
                    return .init(.ride, velocityScale: event.velocityScale * 0.72)
                case .rim:
                    return .init(.rim, velocityScale: event.velocityScale * 0.85)
                case .ride:
                    return .init(.ride, velocityScale: min(1.1, event.velocityScale * 1.05))
                case .cowbell, .conga, .bongo, .shaker, .tambourine:
                    return nil
                }
            }

        case .cajon:
            return events.compactMap { event in
                switch event.voice {
                case .kick:
                    return .init(.conga, velocityScale: min(1.15, event.velocityScale * 1.05))
                case .snare:
                    return .init(.rim, velocityScale: event.velocityScale * 0.95)
                case .hihatClosed:
                    return .init(.shaker, velocityScale: event.velocityScale * 0.55)
                case .hihatOpen:
                    return .init(.tambourine, velocityScale: event.velocityScale * 0.5)
                case .rim:
                    return .init(.bongo, velocityScale: event.velocityScale * 0.9)
                case .ride, .cowbell:
                    return nil
                case .conga, .bongo, .shaker, .tambourine:
                    return event
                }
            }

        case .bellsAndMetals:
            return events.compactMap { event in
                switch event.voice {
                case .kick:
                    // Sparse low pulse as cowbell accents on strong hits only.
                    return event.velocityScale >= 0.85
                        ? .init(.cowbell, velocityScale: event.velocityScale * 0.75)
                        : nil
                case .snare:
                    return .init(.rim, velocityScale: event.velocityScale * 0.8)
                case .hihatClosed, .hihatOpen:
                    return .init(.ride, velocityScale: event.velocityScale * 0.7)
                case .rim:
                    return .init(.rim, velocityScale: event.velocityScale)
                case .ride:
                    return .init(.ride, velocityScale: event.velocityScale)
                case .cowbell:
                    return .init(.cowbell, velocityScale: min(1.2, event.velocityScale * 1.1))
                case .conga, .bongo, .shaker, .tambourine:
                    return nil
                }
            }

        case .electronic:
            return events.compactMap { event in
                switch event.voice {
                case .kick, .snare, .hihatClosed, .hihatOpen:
                    return event
                case .rim:
                    return .init(.snare, velocityScale: event.velocityScale * 0.55)
                case .ride:
                    return .init(.hihatOpen, velocityScale: event.velocityScale * 0.7)
                case .cowbell, .conga, .bongo, .shaker, .tambourine:
                    return nil
                }
            }

        case .softKit:
            return events.compactMap { event in
                switch event.voice {
                case .kick:
                    return .init(.kick, velocityScale: event.velocityScale * 0.72)
                case .snare:
                    return .init(.rim, velocityScale: event.velocityScale * 0.68)
                case .hihatClosed:
                    return .init(.hihatClosed, velocityScale: event.velocityScale * 0.65)
                case .hihatOpen:
                    return .init(.ride, velocityScale: event.velocityScale * 0.55)
                case .rim:
                    return .init(.rim, velocityScale: event.velocityScale * 0.8)
                case .ride:
                    return .init(.ride, velocityScale: event.velocityScale * 0.85)
                case .cowbell:
                    return .init(.cowbell, velocityScale: event.velocityScale * 0.55)
                case .conga:
                    return .init(.conga, velocityScale: event.velocityScale * 0.5)
                case .bongo, .shaker, .tambourine:
                    return .init(event.voice, velocityScale: event.velocityScale * 0.55)
                }
            }
        }
    }
}

enum SoloDrumInstrumentCategoryStore {
    private static let defaultsKey = "soloDrumInstrumentCategory"

    static func load() -> SoloDrumInstrumentCategory {
        guard let raw = UserDefaults.standard.string(forKey: defaultsKey),
              let category = SoloDrumInstrumentCategory(rawValue: raw) else {
            return .drums
        }
        return category
    }

    static func save(_ category: SoloDrumInstrumentCategory) {
        UserDefaults.standard.set(category.rawValue, forKey: defaultsKey)
    }
}

enum SoloDrumBeatFollowStore {
    private static let defaultsKey = "soloDrumBeatFollowEnabled"

    static func load() -> Bool {
        if UserDefaults.standard.object(forKey: defaultsKey) == nil { return true }
        return UserDefaults.standard.bool(forKey: defaultsKey)
    }

    static func save(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: defaultsKey)
    }
}
