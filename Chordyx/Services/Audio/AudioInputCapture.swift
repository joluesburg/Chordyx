//
//  AudioInputCapture.swift
//  Chordyx
//

#if os(macOS) || os(iOS)
import AVFoundation
import Foundation
#if os(macOS)
import CoreAudio
#endif

#if os(macOS)
typealias AudioInputDeviceID = AudioDeviceID
#else
typealias AudioInputDeviceID = UInt32
#endif

struct AudioInputDevice: Identifiable, Equatable, Sendable {
    let id: AudioInputDeviceID
    let name: String
}

final class AudioInputCapture: @unchecked Sendable {
    var onBuffer: ((AVAudioPCMBuffer, TimeInterval) -> Void)?

    private let engine = AVAudioEngine()
    private let processingQueue = DispatchQueue(label: "chordyx.audio.capture", qos: .userInteractive)
    private var isRunning = false
    private var selectedDeviceID: AudioInputDeviceID?

    static func availableInputDevices() -> [AudioInputDevice] {
        #if os(macOS)
        return availableCoreAudioInputDevices()
        #else
        return availableAVAudioSessionInputs()
        #endif
    }

    func selectDevice(_ deviceID: AudioInputDeviceID?) {
        selectedDeviceID = deviceID
        if isRunning {
            stop()
            try? start()
        }
    }

    func start() throws {
        guard !isRunning else { return }

        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        // `.default` (not `.measurement`) keeps playback engines happier on iPhone
        // when Solo Drums is also using AVAudioEngine.
        try session.setCategory(
            .playAndRecord,
            mode: .default,
            options: [.mixWithOthers, .defaultToSpeaker, .allowBluetoothHFP]
        )
        try session.setActive(true, options: [])
        if let selectedDeviceID,
           let inputs = session.availableInputs {
            let match = inputs.first(where: { hashInputUID($0.uid) == selectedDeviceID })
            if let match {
                try session.setPreferredInput(match)
            }
        }
        #elseif os(macOS)
        if let deviceID = selectedDeviceID {
            try setSystemDefaultInputDevice(deviceID)
        }
        #endif

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw AudioCaptureError.noInputAvailable
        }

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 2_048, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            let time = Date().timeIntervalSince1970
            self.processingQueue.async {
                self.onBuffer?(buffer, time)
            }
        }

        // Capture-only: never pass mic signal to speakers (prevents feedback loops).
        engine.mainMixerNode.outputVolume = 0
        input.volume = 0

        engine.prepare()
        try engine.start()
        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
    }

    #if os(macOS)
    private static func availableCoreAudioInputDevices() -> [AudioInputDevice] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize) == noErr else {
            return []
        }

        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize,
            &deviceIDs
        ) == noErr else {
            return []
        }

        return deviceIDs.compactMap { deviceID in
            guard hasInputChannels(deviceID) else { return nil }
            return AudioInputDevice(id: deviceID, name: deviceName(deviceID))
        }
    }

    private static func hasInputChannels(_ deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize) == noErr else { return false }
        let bufferList = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: Int(dataSize))
        defer { bufferList.deallocate() }
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, bufferList) == noErr else { return false }
        let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
        return buffers.contains { $0.mNumberChannels > 0 }
    }

    private static func deviceName(_ deviceID: AudioDeviceID) -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var propertySize = UInt32(MemoryLayout<CFTypeRef?>.size)
        let storage = UnsafeMutablePointer<CFTypeRef?>.allocate(capacity: 1)
        storage.initialize(to: nil)
        defer {
            storage.deinitialize(count: 1)
            storage.deallocate()
        }

        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &propertySize,
            storage
        )

        guard status == noErr, let typeRef = storage.pointee else {
            return String(localized: "Audio Input")
        }

        guard CFGetTypeID(typeRef) == CFStringGetTypeID() else {
            return String(localized: "Audio Input")
        }
        return unsafeDowncast(typeRef, to: CFString.self) as String
    }

    private func setSystemDefaultInputDevice(_ deviceID: AudioDeviceID) throws {
        var device = deviceID
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            UInt32(MemoryLayout<AudioDeviceID>.size),
            &device
        )
        guard status == noErr else { throw AudioCaptureError.deviceSelectionFailed }
    }
    #else
    private static func availableAVAudioSessionInputs() -> [AudioInputDevice] {
        let session = AVAudioSession.sharedInstance()
        return (session.availableInputs ?? []).map { port in
            AudioInputDevice(id: hashInputUID(port.uid), name: port.portName)
        }
    }

    private static func hashInputUID(_ uid: String) -> AudioInputDeviceID {
        AudioInputDeviceID(truncatingIfNeeded: uid.utf8.reduce(UInt64(5381)) { ($0 << 5) &+ $0 &+ UInt64($1) })
    }

    private func hashInputUID(_ uid: String) -> AudioInputDeviceID {
        Self.hashInputUID(uid)
    }
    #endif

    enum AudioCaptureError: LocalizedError {
        case noInputAvailable
        case deviceSelectionFailed

        var errorDescription: String? {
            switch self {
            case .noInputAvailable: String(localized: "No audio input device is available.")
            case .deviceSelectionFailed: String(localized: "Could not select the audio input device.")
            }
        }
    }
}
#endif
