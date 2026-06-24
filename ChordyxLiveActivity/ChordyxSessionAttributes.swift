//
//  ChordyxSessionAttributes.swift
//  ChordyxLiveActivity
//

import ActivityKit
import Foundation

struct ChordyxSessionAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var sessionName: String
        var songTitle: String
        var sectionName: String
        var currentChord: String
        var nextChord: String
        var keyName: String
        var tempoBPM: Int
        var isMetronomePlaying: Bool
        var setlistProgress: String
        var cueText: String
        var cueSymbol: String
        var isCountingIn: Bool
        var hideSongTitle: Bool
        var chordPosition: String
        var currentBeat: Int
        var beatsPerBar: Int
        var isAccentBeat: Bool
        var personalChartNote: String
        var isLiveChord: Bool
        var chordChangeToken: Int
        var isConnected: Bool
        var statusLine: String
    }

    var roleLabel: String
}
