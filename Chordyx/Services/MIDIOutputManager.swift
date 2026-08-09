//
//  MIDIOutputManager.swift
//  Chordyx
//

import Foundation
import CoreMIDI

@MainActor
final class MIDIOutputManager {
    static let shared = MIDIOutputManager()

    private var client = MIDIClientRef()
    private var source = MIDIEndpointRef()
    private var isEnabled = false

    private init() {
        if MIDIClientCreate("ChordyxOut" as CFString, nil, nil, &client) == noErr {
            MIDISourceCreate(client, "Chordyx Cues" as CFString, &source)
        }
    }

    var isAvailable: Bool { source != 0 }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
    }

    func sendChordChange(rootPitchClass: Int) {
        guard isEnabled, source != 0 else { return }
        let note = UInt8(60 + (rootPitchClass % 12))
        send(bytes: [0x90, note, 90])
        send(bytes: [0x80, note, 0])
    }

    func sendCue(_ cueText: String) {
        guard isEnabled, source != 0 else { return }
        let program: UInt8 = switch cueText {
        case "Break": 110
        case "Hold": 111
        case "Vamp": 112
        case "Ending": 113
        default: 100
        }
        send(bytes: [0xC0, program])
    }

    private func send(bytes: [UInt8]) {
        guard source != 0 else { return }
        var packetList = MIDIPacketList()
        let packetPtr = MIDIPacketListInit(&packetList)
        _ = MIDIPacketListAdd(
            &packetList,
            MemoryLayout.size(ofValue: packetList),
            packetPtr,
            0,
            bytes.count,
            bytes
        )
        guard packetList.numPackets > 0 else { return }
        MIDISend(source, 0, &packetList)
    }
}
