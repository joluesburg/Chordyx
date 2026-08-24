//
//  PreferencesHubView.swift
//  Chordyx
//
//  Single hub for MIDI, click, guest display, and stage cues.
//

import SwiftUI

struct PreferencesHubView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: SessionViewModel
    var showsSessionLinks: Bool = true

    @AppStorage(ChordyxPreferences.separateClickVolumeKey) private var separateClickVolume = false
    @AppStorage(ChordyxPreferences.clickVolumeKey) private var clickVolume = 0.85
    @AppStorage(ChordyxPreferences.showBandCuePadByDefaultKey) private var showBandCuePadByDefault = false
    @AppStorage(ChordyxPreferences.showRingCuesKey) private var showRingCues = true
    @AppStorage(ChordyxPreferences.midiOutputEnabledKey) private var midiOutputEnabled = false
    @AppStorage(GuestDisplaySettings.bandCuePadVisibleKey) private var bandCuePadVisible = false
    @AppStorage(GuestDisplaySettings.acousticRoomModeKey) private var acousticRoomMode = false
    @AppStorage("guestMetronomeAudioEnabled") private var guestMetronomeAudioEnabled = true

    @State private var showMIDIDetail = false
    @State private var showGuestDetail = false
    @State private var showBandChatDetail = false

    var body: some View {
        NavigationStack {
            List {
                clickSection
                midiSection
                stageSection
                guestSection
                if showsSessionLinks {
                    shortcutsSection
                }
            }
            .navigationTitle(String(localized: "Preferences"))
            .platformInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done")) { dismiss() }
                }
            }
            .platformSheet(isPresented: $showMIDIDetail) {
                MIDISettingsView(viewModel: viewModel)
            }
            .platformSheet(isPresented: $showGuestDetail) {
                GuestMusicianSettingsView()
            }
            .platformSheet(isPresented: $showBandChatDetail) {
                BandChatSettingsView()
            }
            .onChange(of: midiOutputEnabled) { _, enabled in
                MIDIOutputManager.shared.setEnabled(enabled)
            }
            .onChange(of: showBandCuePadByDefault) { _, enabled in
                if enabled { bandCuePadVisible = true }
            }
        }
    }

    // MARK: - Sections

    private var clickSection: some View {
        Section {
            Toggle(isOn: $separateClickVolume) {
                preferenceLabel(
                    title: String(localized: "Separate click volume"),
                    subtitle: String(localized: "For IEMs / host monitors vs kit level.")
                )
            }
            if separateClickVolume {
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "Click level"))
                        .font(.caption.weight(.semibold))
                    Slider(value: $clickVolume, in: 0...1)
                }
            }
            Toggle(isOn: $acousticRoomMode) {
                preferenceLabel(
                    title: String(localized: "Acoustic room mode"),
                    subtitle: String(localized: "Mutes local metronome audio for open stages.")
                )
            }
            Toggle(isOn: $guestMetronomeAudioEnabled) {
                preferenceLabel(
                    title: String(localized: "Guest metronome audio"),
                    subtitle: String(localized: "Guests hear the click on their device.")
                )
            }
        } header: {
            Text(String(localized: "Click & monitors"))
        }
    }

    private var midiSection: some View {
        Section {
            Toggle(isOn: $midiOutputEnabled) {
                preferenceLabel(
                    title: String(localized: "MIDI output"),
                    subtitle: String(localized: "Send chord / cue events to external gear.")
                )
            }
            Button {
                showMIDIDetail = true
            } label: {
                preferenceLabel(
                    title: String(localized: "MIDI input & pedals…"),
                    subtitle: String(localized: "Sources, foot switches, Bluetooth MIDI.")
                )
            }
        } header: {
            Text(String(localized: "MIDI"))
        } footer: {
            Text(String(localized: "Input drives the live piano. Output is optional for lighting / MainStage."))
        }
    }

    private var stageSection: some View {
        Section {
            Toggle(isOn: $bandCuePadVisible) {
                preferenceLabel(
                    title: String(localized: "Show band cue pad"),
                    subtitle: String(localized: "Build / break / tag chips visible to the band.")
                )
            }
            Toggle(isOn: $showRingCues) {
                preferenceLabel(
                    title: String(localized: "Cues on chord ring"),
                    subtitle: String(localized: "Compact Hold / Build / Soft / Drums out under the ring.")
                )
            }
            Toggle(isOn: $showBandCuePadByDefault) {
                preferenceLabel(
                    title: String(localized: "Cue pad on by default"),
                    subtitle: String(localized: "Turn cues on automatically for new sessions.")
                )
            }
            Button {
                showBandChatDetail = true
            } label: {
                preferenceLabel(
                    title: String(localized: "Band chat…"),
                    subtitle: String(localized: "Badges, haptics, quiet during live.")
                )
            }
        } header: {
            Text(String(localized: "Stage cues"))
        }
    }

    private var guestSection: some View {
        Section {
            Button {
                showGuestDetail = true
            } label: {
                preferenceLabel(
                    title: String(localized: "Musician display…"),
                    subtitle: String(localized: "Capo, transpose, notation, role presets.")
                )
            }
        } header: {
            Text(String(localized: "Guest display"))
        }
    }

    private var shortcutsSection: some View {
        Section {
            if viewModel.canDriveSession {
                Text(String(localized: "These apply to the current live session immediately."))
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
            }
            LabeledContent(String(localized: "Device name")) {
                Text(SessionManager.currentDisplayName())
                    .foregroundStyle(AppTheme.textSecondary)
            }
        } header: {
            Text(String(localized: "Session"))
        }
    }

    private func preferenceLabel(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
        }
    }
}
