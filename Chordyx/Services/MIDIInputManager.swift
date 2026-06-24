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

    private var client = MIDIClientRef()
    private var inputPort = MIDIPortRef()
    private var connectedSources: [MIDIEndpointRef] = []
    private var allSources: [MIDISourceInfo] = []

    private let lock = NSLock()
    private var heldNotes: Set<Int> = []
    private var pedalNotes: Set<Int> = []
    private var started = false

    var advanceTriggerNote: Int {
        get {
            let value = UserDefaults.standard.object(forKey: Self.advanceNoteKey) as? Int
            return value ?? 36
        }
        set { UserDefaults.standard.set(newValue, forKey: Self.advanceNoteKey) }
    }

    var previousTriggerNote: Int {
        get {
            let value = UserDefaults.standard.object(forKey: Self.previousNoteKey) as? Int
            return value ?? 37
        }
        set { UserDefaults.standard.set(newValue, forKey: Self.previousNoteKey) }
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
    }

    private func handleNotification(_ notification: UnsafePointer<MIDINotification>) {
        switch notification.pointee.messageID {
        case .msgObjectAdded, .msgObjectRemoved, .msgSetupChanged:
            DispatchQueue.main.async { [weak self] in
                self?.refreshSources()
            }
        default:
            break
        }
    }

    private func handlePackets(_ packetList: UnsafePointer<MIDIPacketList>) {
        lock.lock()
        var notes = heldNotes
        var pedals = pedalNotes
        lock.unlock()

        var pedalActions: [MIDIPedalAction] = []

        for packet in packetList.unsafeSequence() {
            let length = Int(packet.pointee.length)
            withUnsafeBytes(of: packet.pointee.data) { rawBuffer in
                let bytes = Array(rawBuffer.prefix(length))
                parse(bytes, into: &notes, pedalNotes: &pedals, pedalActions: &pedalActions)
            }
        }

        lock.lock()
        let notesChanged = notes != heldNotes
        heldNotes = notes
        pedalNotes = pedals
        lock.unlock()

        if notesChanged {
            let sorted = notes.sorted()
            DispatchQueue.main.async { [weak self] in
                self?.onNotesChanged?(sorted)
            }
        }

        if !pedalActions.isEmpty {
            DispatchQueue.main.async { [weak self] in
                pedalActions.forEach { self?.onPedalAction?($0) }
            }
        }
    }

    private func parse(
        _ bytes: [UInt8],
        into notes: inout Set<Int>,
        pedalNotes: inout Set<Int>,
        pedalActions: inout [MIDIPedalAction]
    ) {
        var index = 0
        while index < bytes.count {
            let status = bytes[index]
            guard status & 0x80 != 0 else { index += 1; continue }
            let command = status & 0xF0

            switch command {
            case 0x90, 0x80:
                guard index + 2 < bytes.count else { return }
                let note = Int(bytes[index + 1] & 0x7F)
                let velocity = bytes[index + 2] & 0x7F
                let isOn = command == 0x90 && velocity > 0

                if note == advanceTriggerNote || note == previousTriggerNote {
                    if isOn, !pedalNotes.contains(note) {
                        pedalNotes.insert(note)
                        pedalActions.append(note == advanceTriggerNote ? .nextChord : .previousChord)
                    } else if !isOn {
                        pedalNotes.remove(note)
                    }
                } else if isOn {
                    notes.insert(note)
                } else {
                    notes.remove(note)
                }
                index += 3

            case 0xB0:
                guard index + 2 < bytes.count else { return }
                let controller = bytes[index + 1]
                let value = bytes[index + 2]
                if controller == 116, value >= 64 {
                    pedalActions.append(.nextChord)
                } else if controller == 117, value >= 64 {
                    pedalActions.append(.previousChord)
                }
                index += 3

            case 0xA0, 0xE0:
                index += 3
            case 0xC0, 0xD0:
                index += 2
            default:
                index += 1
            }
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
