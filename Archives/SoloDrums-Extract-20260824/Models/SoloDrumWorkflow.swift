//
//  SoloDrumWorkflow.swift
//  Chordyx
//
//  User-driven solo drum workflow: listen → confirm → steady loop.
//

import Foundation

/// Synced to iPhone guests so they can show host groove state.
enum SoloDrumWorkflowPhase: String, Sendable, Codable {
    case idle
    case listening
    case awaitingConfirmation
    case playing
    case awaitingTempoShiftConfirmation
}

#if os(macOS) || os(iOS)
struct SoloDrumGrooveProposal: Sendable, Equatable {
    let bpm: Double
    let style: LiveMusicStyle
    let pattern: DrumPattern
    let tempoConfidence: Double
    let styleConfidence: Double
    let globalGenreID: String?
    let globalGenreLabel: String?
    let globalGenreRegion: GlobalMusicRegion?
}
#endif

extension SessionSyncPayload {
    var hostGlobalGenre: GlobalMusicGenre? {
        guard let id = hostGlobalGenreID else { return nil }
        return GlobalMusicGenreCatalog.genre(id: id)
    }

    var hostGlobalGenreRegion: GlobalMusicRegion? {
        guard let raw = hostGlobalGenreRegionRaw else { return nil }
        return GlobalMusicRegion(rawValue: raw)
    }

    var guestGlobalGenreDisplayLabel: String? {
        if let label = hostGlobalGenreLabel, !label.isEmpty { return label }
        return hostGlobalGenre?.label
    }

    var hostSoloInstrumentCategory: SoloDrumInstrumentCategory {
        guard let raw = hostSoloInstrumentCategoryRaw,
              let category = SoloDrumInstrumentCategory(rawValue: raw) else {
            return .drums
        }
        return category
    }
}

extension SessionSyncPayload {
    var hostLiveGrooveStyle: LiveMusicStyle {
        guard let raw = hostLiveGrooveStyleRaw else { return .unknown }
        return LiveMusicStyle(rawValue: raw) ?? .unknown
    }

    var hostLiveGroovePhase: SoloDrumWorkflowPhase {
        guard let raw = hostLiveGroovePhaseRaw,
              let phase = SoloDrumWorkflowPhase(rawValue: raw) else { return .idle }
        return phase
    }

    /// BPM guests should display / follow when the Mac host is analyzing or playing live groove.
    var guestLiveGrooveDisplayBPM: Double? {
        guard hostLiveGrooveActive else { return nil }
        let bpm = hostLiveGrooveBPM ?? tempoBPM
        return bpm > 0 ? bpm : nil
    }

    var guestShouldFollowHostLiveGrooveMetronome: Bool {
        hostLiveGrooveActive && hostLiveGroovePhase == .playing
    }
}
