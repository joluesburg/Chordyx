//
//  BackingTrackEngine.swift
//  Chordyx
//

import AVFoundation
import Foundation
import Observation

enum BackingTrackError: LocalizedError {
    case copyFailed
    case unsupportedFormat

    var errorDescription: String? {
        switch self {
        case .copyFailed: String(localized: "Couldn’t import that audio file.")
        case .unsupportedFormat: String(localized: "Use MP3, WAV, M4A, or AIFF.")
        }
    }
}

enum BackingTrackStorage {
    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("BackingTracks", isDirectory: true)
    }

    static func fileURL(named fileName: String) -> URL {
        directory.appendingPathComponent(fileName)
    }

    @discardableResult
    static func importFile(from source: URL) throws -> (fileName: String, displayName: String) {
        let accessed = source.startAccessingSecurityScopedResource()
        defer { if accessed { source.stopAccessingSecurityScopedResource() } }

        let ext = source.pathExtension.lowercased()
        let allowed = ["mp3", "wav", "m4a", "aiff", "aif", "caf"]
        guard allowed.contains(ext) else { throw BackingTrackError.unsupportedFormat }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileName = "\(UUID().uuidString).\(ext)"
        let destination = fileURL(named: fileName)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        do {
            try FileManager.default.copyItem(at: source, to: destination)
        } catch {
            throw BackingTrackError.copyFailed
        }
        let displayName = source.deletingPathExtension().lastPathComponent
        return (fileName, displayName)
    }

    static func deleteFile(named fileName: String) {
        let url = fileURL(named: fileName)
        try? FileManager.default.removeItem(at: url)
    }
}

@Observable
@MainActor
final class BackingTrackEngine {
    private(set) var storedFileName: String?
    private(set) var displayName: String = ""
    private(set) var isPlaying = false
    private var player: AVAudioPlayer?

    var volume: Float = 0.85 {
        didSet { player?.volume = volume }
    }

    var hasTrack: Bool { storedFileName != nil }

    func importTrack(from url: URL) throws {
        stop()
        if let old = storedFileName {
            BackingTrackStorage.deleteFile(named: old)
        }
        let imported = try BackingTrackStorage.importFile(from: url)
        storedFileName = imported.fileName
        displayName = imported.displayName
        preparePlayer()
    }

    func loadStored(fileName: String, displayName: String) {
        stop()
        storedFileName = fileName
        self.displayName = displayName
        preparePlayer()
    }

    func play() {
        guard let player else { return }
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        player.play()
        isPlaying = true
    }

    func pause() {
        player?.pause()
        isPlaying = false
    }

    func stop() {
        player?.stop()
        player?.currentTime = 0
        isPlaying = false
    }

    func clear() {
        stop()
        if let fileName = storedFileName {
            BackingTrackStorage.deleteFile(named: fileName)
        }
        storedFileName = nil
        displayName = ""
        player = nil
    }

    private func preparePlayer() {
        guard let fileName = storedFileName else {
            player = nil
            return
        }
        let url = BackingTrackStorage.fileURL(named: fileName)
        do {
            let audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer.prepareToPlay()
            audioPlayer.volume = volume
            audioPlayer.numberOfLoops = 0
            player = audioPlayer
        } catch {
            player = nil
        }
    }
}
