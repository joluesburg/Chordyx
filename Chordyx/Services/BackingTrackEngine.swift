//
//  BackingTrackEngine.swift
//  Chordyx
//

import AVFoundation
import Combine
import Foundation

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

@MainActor
final class BackingTrackEngine: ObservableObject {
    @Published private(set) var storedFileName: String?
    @Published private(set) var displayName: String = ""
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    private var player: AVAudioPlayer?
    private var progressTask: Task<Void, Never>?

    static let defaultSkipInterval: TimeInterval = 15

    var volume: Float = 0.85 {
        didSet { player?.volume = volume }
    }

    var hasTrack: Bool { storedFileName != nil }

    static func formatTime(_ time: TimeInterval) -> String {
        let total = max(0, Int(time.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

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
        syncTimingFromPlayer()
        startProgressUpdates()
    }

    func pause() {
        player?.pause()
        isPlaying = false
        syncTimingFromPlayer()
        stopProgressUpdates()
    }

    func stop() {
        player?.stop()
        player?.currentTime = 0
        isPlaying = false
        syncTimingFromPlayer()
        stopProgressUpdates()
    }

    func seek(to time: TimeInterval) {
        guard let player else { return }
        let clamped = min(max(0, time), max(player.duration, 0))
        player.currentTime = clamped
        currentTime = clamped
    }

    func skip(by interval: TimeInterval) {
        guard let player else { return }
        seek(to: player.currentTime + interval)
    }

    func clear() {
        stop()
        if let fileName = storedFileName {
            BackingTrackStorage.deleteFile(named: fileName)
        }
        storedFileName = nil
        displayName = ""
        player = nil
        currentTime = 0
        duration = 0
    }

    private func preparePlayer() {
        guard let fileName = storedFileName else {
            player = nil
            currentTime = 0
            duration = 0
            return
        }
        let url = BackingTrackStorage.fileURL(named: fileName)
        do {
            let audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer.prepareToPlay()
            audioPlayer.volume = volume
            audioPlayer.numberOfLoops = 0
            player = audioPlayer
            syncTimingFromPlayer()
        } catch {
            player = nil
            currentTime = 0
            duration = 0
        }
    }

    private func syncTimingFromPlayer() {
        guard let player else {
            currentTime = 0
            duration = 0
            return
        }
        duration = player.duration
        currentTime = player.currentTime
        if isPlaying, !player.isPlaying {
            isPlaying = false
            currentTime = player.duration
            stopProgressUpdates()
        }
    }

    private func startProgressUpdates() {
        progressTask?.cancel()
        progressTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                guard let self else { return }
                self.syncTimingFromPlayer()
            }
        }
    }

    private func stopProgressUpdates() {
        progressTask?.cancel()
        progressTask = nil
    }
}
