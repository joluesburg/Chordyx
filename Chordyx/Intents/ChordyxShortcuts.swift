//
//  ChordyxShortcuts.swift
//  Chordyx
//

import AppIntents
import Foundation

#if os(iOS)
struct ChordyxAdvanceChordIntent: AppIntent {
    static var title: LocalizedStringResource = "Next Chord"
    static var description = IntentDescription("Advance to the next chord in Chordyx.")

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            NotificationCenter.default.post(name: .chordyxShortcutAdvance, object: nil)
        }
        return .result()
    }
}

struct ChordyxSendCueIntent: AppIntent {
    static var title: LocalizedStringResource = "Send Band Cue"
    static var description = IntentDescription("Send a band cue in the active Chordyx session.")

    @Parameter(title: "Cue")
    var cue: CueOption

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            NotificationCenter.default.post(
                name: .chordyxShortcutCue,
                object: nil,
                userInfo: ["cue": cue.rawValue]
            )
        }
        return .result()
    }
}

enum CueOption: String, AppEnum {
    case hold, build, breakCue, vamp, ending

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Band Cue")
    static var caseDisplayRepresentations: [CueOption: DisplayRepresentation] = [
        .hold: "Hold",
        .build: "Build",
        .breakCue: "Break",
        .vamp: "Vamp",
        .ending: "Ending",
    ]
}

struct ChordyxShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ChordyxAdvanceChordIntent(),
            phrases: [
                "Next chord in \(.applicationName)",
                "Advance chord in \(.applicationName)",
            ],
            shortTitle: "Next Chord",
            systemImageName: "forward.fill"
        )
        AppShortcut(
            intent: ChordyxSendCueIntent(),
            phrases: [
                "Send \(\.$cue) in \(.applicationName)",
                "Band cue \(\.$cue) in \(.applicationName)",
            ],
            shortTitle: "Band Cue",
            systemImageName: "megaphone.fill"
        )
    }
}

extension Notification.Name {
    static let chordyxShortcutAdvance = Notification.Name("chordyxShortcutAdvance")
    static let chordyxShortcutCue = Notification.Name("chordyxShortcutCue")
}

enum ChordyxShortcutBridge {
    static func install(on viewModel: SessionViewModel) {
        NotificationCenter.default.addObserver(
            forName: .chordyxShortcutAdvance,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in viewModel.advanceChord() }
        }
        NotificationCenter.default.addObserver(
            forName: .chordyxShortcutCue,
            object: nil,
            queue: .main
        ) { note in
            guard let raw = note.userInfo?["cue"] as? String else { return }
            Task { @MainActor in
                switch raw {
                case CueOption.hold.rawValue: viewModel.sendLiveCue("Hold", symbol: "hand.raised.fill")
                case CueOption.build.rawValue: viewModel.sendLiveCue("Build", symbol: "arrow.up.circle.fill")
                case CueOption.breakCue.rawValue: viewModel.sendLiveCue("Break", symbol: "pause.circle.fill")
                case CueOption.vamp.rawValue: viewModel.sendLiveCue("Vamp", symbol: "infinity.circle.fill")
                case CueOption.ending.rawValue: viewModel.sendLiveCue("Ending", symbol: "flag.checkered")
                default: break
                }
            }
        }
    }
}
#endif
