//
//  MIDIInputManager.swift
//  Chordyx
//

import Foundation
import CoreMIDI

enum MIDIPedalAction: Sendable {
    case nextChord
    case previousChord
}

struct MIDISourceInfo: Identifiable, Equatable, Sendable {
    let id: Int32
    let name: String
    var isConnected: Bool
}

final class MIDIInputManager: @unchecked Sendable {
    var onNotesChanged: (([Int]) -> Void)?
    var onSourcesChanged: (([String]) -> Void)?
    var onAvailableSourcesChanged: (([MIDISourceInfo]) -> Void)?
    var onPedalAction: ((MIDIPedalAction) -> Void)?

    private static let selectedSourcesKey = "midiSelectedSourceIDs"
    private static let advanceNoteKey = "midiAdvanceNote"
    private static let previousNoteKey = "midiPreviousNote"
    /// Disabled until the host assigns foot-pedal notes in MIDI Setup.
    static let pedalTriggerDisabled = -1

    private var client = MIDIClientRef()
    private var inputPort = MIDIPortRef()
    private var connectedSources: [MIDIEndpointRef] = []
    private var allSources: [MIDISourceInfo] = []

    private let lock = NSLock()
    private var heldNotes: Set<Int> = []
    private var notesReleasedWhileSustained: Set<Int> = []
    private var sustainPedalDown = false
    private var pedalNotes: Set<Int> = []
    private var started = false
    private var refreshWorkItem: DispatchWorkItem?

    var advanceTriggerNote: Int {
        get {
            guard UserDefaults.standard.object(forKey: Self.advanceNoteKey) != nil else {
                return Self.pedalTriggerDisabled
            }
            return UserDefaults.standard.integer(forKey: Self.advanceNoteKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: Self.advanceNoteKey) }
    }

    var previousTriggerNote: Int {
        get {
            guard UserDefaults.standard.object(forKey: Self.previousNoteKey) != nil else {
                return Self.pedalTriggerDisabled
            }
            return UserDefaults.standard.integer(forKey: Self.previousNoteKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: Self.previousNoteKey) }
    }

    private func isPedalTriggerNote(_ note: Int) -> Bool {
        if advanceTriggerNote >= 0, note == advanceTriggerNote { return true }
        if previousTriggerNote >= 0, note == previousTriggerNote { return true }
        return false
    }

    func start() {
        guard !started else { return }
        started = true

        let clientName = "Chordyx" as CFString
        MIDIClientCreateWithBlock(clientName, &client) { [weak self] notification in
            self?.handleNotification(notification)
        }

        let portName = "Chordyx Input" as CFString
        MIDIInputPortCreateWithBlock(client, portName, &inputPort) { [weak self] packetList, _ in
            self?.handlePackets(packetList)
        }

        DispatchQueue.main.async { [weak self] in
            self?.refreshSources()
        }
    }

    func refreshSources() {
        var discovered: [MIDISourceInfo] = []
        let count = MIDIGetNumberOfSources()
        for index in 0..<count {
            let source = MIDIGetSource(index)
            guard source != 0 else { continue }
            let endpointID = uniqueID(of: source)
            discovered.append(MIDISourceInfo(
                id: endpointID,
                name: displayName(of: source),
                isConnected: connectedSources.contains(source)
            ))
        }
        allSources = discovered
        onAvailableSourcesChanged?(discovered)

        let selected = selectedSourceIDs()
        if selected.isEmpty {
            connectAllSources()
        } else {
            connect(sourcesWithIDs: selected)
        }
    }

    func setSourceConnected(id: Int32, connected: Bool) {
        var selected = Set(selectedSourceIDs())
        if connected {
            selected.insert(id)
        } else {
            selected.remove(id)
        }
        UserDefaults.standard.set(Array(selected), forKey: Self.selectedSourcesKey)
        refreshSources()
    }

    func connectAllSources() {
        UserDefaults.standard.removeObject(forKey: Self.selectedSourcesKey)
        connect(sourcesWithIDs: allSources.map(\.id))
    }

    private func selectedSourceIDs() -> [Int32] {
        UserDefaults.standard.array(forKey: Self.selectedSourcesKey) as? [Int32] ?? []
    }

    private func connect(sourcesWithIDs ids: [Int32]) {
        for source in connectedSources {
            MIDIPortDisconnectSource(inputPort, source)
        }
        connectedSources.removeAll()

        var names: [String] = []
        let count = MIDIGetNumberOfSources()
        for index in 0..<count {
            let source = MIDIGetSource(index)
            guard source != 0 else { continue }
            let endpointID = uniqueID(of: source)
            guard ids.contains(endpointID) else { continue }
            if MIDIPortConnectSource(inputPort, source, nil) == noErr {
                connectedSources.append(source)
                names.append(displayName(of: source))
            }
        }
        onSourcesChanged?(names)
        onAvailableSourcesChanged?(allSources.map { info in
            MIDISourceInfo(
                id: info.id,
                name: info.name,
                isConnected: connectedSources.contains(where: {
                    uniqueID(of: $0) == info.id
                })
            )
        })
        publishHeldNotes()
    }

    private func handleNotification(_ notification: UnsafePointer<MIDINotification>) {
        switch notification.pointee.messageID {
        case .msgObjectAdded, .msgObjectRemoved, .msgSetupChanged:
            scheduleRefreshSources()
        default:
            break
        }
    }

    private func scheduleRefreshSources() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.refreshWorkItem?.cancel()
            let work = DispatchWorkItem { [weak self] in
                self?.refreshSources()
            }
            self.refreshWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
        }
    }

    private func handlePackets(_ packetList: UnsafePointer<MIDIPacketList>) {
        lock.lock()
        var notes = heldNotes
        var releasedWhileSustained = notesReleasedWhileSustained
        var sustainDown = sustainPedalDown
        var pedals = pedalNotes
        lock.unlock()

        var pedalActions: [MIDIPedalAction] = []

        // Must walk the list via pointers / unsafeSequence — copying MIDIPacket and
        // calling MIDIPacketNext(&localCopy) reads the wrong memory and drops notes.
        for packet in packetList.unsafeSequence() {
            let length = Int(packet.pointee.length)
            withUnsafeBytes(of: packet.pointee.data) { rawBuffer in
                let bytes = Array(rawBuffer.prefix(length))
                parse(
                    bytes,
                    into: &notes,
                    releasedWhileSustained: &releasedWhileSustained,
                    sustainPedalDown: &sustainDown,
                    pedalNotes: &pedals,
                    pedalActions: &pedalActions
                )
            }
        }

        lock.lock()
        let notesChanged = notes != heldNotes
            || sustainDown != sustainPedalDown
            || releasedWhileSustained != notesReleasedWhileSustained
        heldNotes = notes
        notesReleasedWhileSustained = releasedWhileSustained
        sustainPedalDown = sustainDown
        pedalNotes = pedals
        lock.unlock()

        if notesChanged {
            publishHeldNotes(notes)
        }

        if !pedalActions.isEmpty {
            let deliver: () -> Void = { [weak self] in
                pedalActions.forEach { self?.onPedalAction?($0) }
            }
            if Thread.isMainThread {
                deliver()
            } else {
                DispatchQueue.main.async(qos: .userInteractive, execute: deliver)
            }
        }
    }

    private func publishHeldNotes(_ notes: Set<Int>? = nil) {
        let sorted: [Int]
        if let notes {
            sorted = notes.sorted()
        } else {
            lock.lock()
            sorted = heldNotes.sorted()
            lock.unlock()
        }
        let deliver: () -> Void = { [weak self] in
            self?.onNotesChanged?(sorted)
        }
        if Thread.isMainThread {
            deliver()
        } else {
            DispatchQueue.main.async(qos: .userInteractive, execute: deliver)
        }
    }

    private func parse(
        _ bytes: [UInt8],
        into notes: inout Set<Int>,
        releasedWhileSustained: inout Set<Int>,
        sustainPedalDown: inout Bool,
        pedalNotes: inout Set<Int>,
        pedalActions: inout [MIDIPedalAction]
    ) {
        var index = 0
        var runningStatus: UInt8?

        while index < bytes.count {
            let byte = bytes[index]

            // System real-time — single-byte messages (clock, active sensing, etc.).
            if byte >= 0xF8 {
                index += 1
                continue
            }

            if byte == 0xF0 {
                index += 1
                while index < bytes.count, bytes[index] != 0xF7 {
                    index += 1
                }
                if index < bytes.count { index += 1 }
                runningStatus = nil
                continue
            }

            var status = byte
            if status & 0x80 != 0 {
                if status >= 0xF1, status <= 0xF7 {
                    index += systemCommonLength(for: status, bytes: bytes, start: index)
                    runningStatus = nil
                    continue
                }
                runningStatus = status
                index += 1
            } else if let running = runningStatus {
                status = running
            } else {
                index += 1
                continue
            }

            let command = status & 0xF0

            switch command {
            case 0x90, 0x80:
                guard index + 1 < bytes.count else { return }
                let note = Int(bytes[index] & 0x7F)
                let velocity = bytes[index + 1] & 0x7F
                index += 2
                let isOn = command == 0x90 && velocity > 0
                applyNoteEvent(
                    note: note,
                    isOn: isOn,
                    into: &notes,
                    releasedWhileSustained: &releasedWhileSustained,
                    sustainPedalDown: sustainPedalDown,
                    pedalNotes: &pedalNotes,
                    pedalActions: &pedalActions
                )

            case 0xB0:
                guard index + 1 < bytes.count else { return }
                let controller = bytes[index]
                let value = bytes[index + 1]
                index += 2
                handleControlChange(
                    controller: controller,
                    value: value,
                    notes: &notes,
                    releasedWhileSustained: &releasedWhileSustained,
                    sustainPedalDown: &sustainPedalDown,
                    pedalActions: &pedalActions
                )

            case 0xA0, 0xE0:
                guard index + 1 < bytes.count else { return }
                index += 2

            case 0xC0, 0xD0:
                guard index < bytes.count else { return }
                index += 1

            default:
                // Unknown status — stop rather than spin on the same byte.
                return
            }
        }
    }

    private func systemCommonLength(for status: UInt8, bytes: [UInt8], start: Int) -> Int {
        switch status {
        case 0xF1, 0xF3: return 2
        case 0xF2: return 3
        default: return 1
        }
    }

    private func applyNoteEvent(
        note: Int,
        isOn: Bool,
        into notes: inout Set<Int>,
        releasedWhileSustained: inout Set<Int>,
        sustainPedalDown: Bool,
        pedalNotes: inout Set<Int>,
        pedalActions: inout [MIDIPedalAction]
    ) {
        if isOn {
            notes.insert(note)
            releasedWhileSustained.remove(note)
        } else if sustainPedalDown {
            releasedWhileSustained.insert(note)
        } else {
            notes.remove(note)
            releasedWhileSustained.remove(note)
        }

        if isPedalTriggerNote(note) {
            if isOn, !pedalNotes.contains(note) {
                pedalNotes.insert(note)
                pedalActions.append(note == advanceTriggerNote ? .nextChord : .previousChord)
            } else if !isOn {
                pedalNotes.remove(note)
            }
        }
    }

    private func handleControlChange(
        controller: UInt8,
        value: UInt8,
        notes: inout Set<Int>,
        releasedWhileSustained: inout Set<Int>,
        sustainPedalDown: inout Bool,
        pedalActions: inout [MIDIPedalAction]
    ) {
        switch controller {
        case 64:
            let engaged = value >= 64
            if sustainPedalDown, !engaged {
                for note in releasedWhileSustained {
                    notes.remove(note)
                }
                releasedWhileSustained.removeAll()
            }
            sustainPedalDown = engaged
        case 120, 123:
            notes.removeAll()
            releasedWhileSustained.removeAll()
        case 116 where value >= 64:
            pedalActions.append(.nextChord)
        case 117 where value >= 64:
            pedalActions.append(.previousChord)
        default:
            break
        }
    }

    private func uniqueID(of endpoint: MIDIEndpointRef) -> Int32 {
        var id: Int32 = 0
        _ = MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyUniqueID, &id)
        return id
    }

    private func displayName(of endpoint: MIDIEndpointRef) -> String {
        var property: Unmanaged<CFString>?
        let status = MIDIObjectGetStringProperty(endpoint, kMIDIPropertyDisplayName, &property)
        if status == noErr, let name = property?.takeRetainedValue() {
            return name as String
        }
        return L10n.midiDevice
    }
}
