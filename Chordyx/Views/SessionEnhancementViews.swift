//
//  SessionEnhancementViews.swift
//  Chordyx
//

import SwiftUI
#if canImport(CoreImage)
import CoreImage.CIFilterBuiltins
#endif
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Setlist timeline

struct SetlistTimelineBanner: View {
    let titles: [String]
    let currentIndex: Int

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(titles.enumerated()), id: \.offset) { index, title in
                    HStack(spacing: 6) {
                        if index == currentIndex {
                            Image(systemName: "play.fill")
                                .font(.caption2)
                        }
                        Text(title)
                            .font(.caption.weight(index == currentIndex ? .bold : .medium))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background {
                        Capsule()
                            .fill(index == currentIndex ? AppTheme.accent.opacity(0.22) : AppTheme.surfaceElevated)
                    }
                    .foregroundStyle(index == currentIndex ? AppTheme.accent : AppTheme.textSecondary)
                }
            }
            .padding(.horizontal, 4)
        }
        .accessibilityLabel(String(localized: "Setlist timeline"))
    }
}

// MARK: - Song ending

struct SongEndingOverlay: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "flag.checkered")
                .font(.system(size: 36, weight: .bold))
            Text(String(localized: "Final"))
                .font(.title.weight(.heavy))
        }
        .foregroundStyle(AppTheme.accent)
        .padding(28)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: AppTheme.accent.opacity(0.35), radius: 16, y: 4)
        .accessibilityLabel(String(localized: "End of song"))
    }
}

// MARK: - Count-in

struct CountInOverlay: View {
    let beatsRemaining: Int
    let beatInBar: Int
    let beatsPerBar: Int

    var body: some View {
        VStack(spacing: 10) {
            Text(String(localized: "COUNT IN"))
                .font(.caption.weight(.bold))
                .foregroundStyle(AppTheme.textSecondary)
                .tracking(2)

            Text("\(beatsRemaining)")
                .font(.system(size: 96, weight: .heavy, design: .rounded))
                .foregroundStyle(AppTheme.accent)
                .contentTransition(.numericText())

            HStack(spacing: 8) {
                ForEach(0..<beatsPerBar, id: \.self) { index in
                    Circle()
                        .fill(index == beatInBar ? AppTheme.accent : AppTheme.chordInactive)
                        .frame(width: index == beatInBar ? 12 : 8, height: index == beatInBar ? 12 : 8)
                }
            }
        }
        .padding(.horizontal, 36)
        .padding(.vertical, 28)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: AppTheme.accent.opacity(0.25), radius: 20, y: 6)
        .accessibilityLabel(String(format: String(localized: "Count in: %lld"), beatsRemaining))
    }
}

// MARK: - Chord change warning

struct ChordChangeWarningBanner: View {
    let beatsRemaining: Int

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.right.circle.fill")
                .font(.subheadline.weight(.bold))
            Text(String(format: String(localized: "Chord change in %lld beats"), beatsRemaining))
                .font(.subheadline.weight(.bold))
        }
        .foregroundStyle(AppTheme.background)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(AppTheme.accentSecondary)
        .clipShape(Capsule())
        .accessibilityLabel(String(format: String(localized: "Chord change in %lld beats"), beatsRemaining))
    }
}

// MARK: - Live status chips

struct LiveSessionStatusBar: View {
    let isAutoAdvancePaused: Bool
    let isVampActive: Bool
    let tempoBPM: Double
    let isMetronomePlaying: Bool
    var syncQuality: SyncQuality = .unknown
    var showSyncQuality: Bool = false
    var hostLiveGrooveActive: Bool = false
    var hostLiveGrooveStyle: LiveMusicStyle = .unknown
    var hostLiveGroovePhase: SoloDrumWorkflowPhase = .idle

    private var displayBPM: Int {
        Int(tempoBPM.rounded())
    }

    private var tempoMarking: TempoMarking {
        TempoMarking.forBPM(tempoBPM)
    }

    var body: some View {
        HStack(spacing: 8) {
            if showSyncQuality, syncQuality == .poor || syncQuality == .fair {
                Label(syncQuality.label, systemImage: "wifi.exclamationmark")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(syncQuality == .poor ? .orange : AppTheme.textSecondary)
            }
            if hostLiveGrooveActive {
                hostGrooveChip
            }
            if isMetronomePlaying || (hostLiveGrooveActive && displayBPM > 0) {
                Label(TempoMarking.caption(for: tempoBPM), systemImage: "metronome")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(AppTheme.accent)
            } else if hostLiveGrooveActive, hostLiveGroovePhase != .playing, displayBPM > 0 {
                Label(TempoMarking.caption(for: tempoBPM), systemImage: "waveform")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)
            }
            if isAutoAdvancePaused {
                statusChip(String(localized: "HOLD"), icon: "hand.raised.fill", color: AppTheme.accentSecondary)
            }
            if isVampActive {
                statusChip(String(localized: "VAMP"), icon: "infinity.circle.fill", color: AppTheme.accent)
            }
        }
    }

    @ViewBuilder
    private var hostGrooveChip: some View {
        if hostLiveGrooveStyle != .unknown {
            Label(hostLiveGrooveStyle.label, systemImage: "music.mic")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(AppTheme.accentSecondary)
        } else if hostLiveGroovePhase == .listening || hostLiveGroovePhase == .awaitingConfirmation {
            Label(String(localized: "Host listening"), systemImage: "ear")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)
        } else if hostLiveGroovePhase == .playing {
            Label(String(localized: "Live groove"), systemImage: "repeat")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(AppTheme.accentSecondary)
        }
    }

    private func statusChip(_ title: String, icon: String, color: Color) -> some View {
        Label(title, systemImage: icon)
            .font(.caption2.weight(.bold))
            .foregroundStyle(AppTheme.background)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color)
            .clipShape(Capsule())
    }
}

// MARK: - Guest host live groove (Mac → iPhone)

struct GuestHostLiveGrooveBanner: View {
    let payload: SessionSyncPayload

    private var phaseLabel: String {
        switch payload.hostLiveGroovePhase {
        case .listening, .awaitingConfirmation:
            String(localized: "Host is listening to your groove")
        case .playing:
            String(localized: "Live drum loop from host")
        case .awaitingTempoShiftConfirmation:
            String(localized: "Host adjusting tempo")
        case .idle:
            String(localized: "Live groove")
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "desktopcomputer")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.accentSecondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(phaseLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                HStack(spacing: 8) {
                    if let bpm = payload.guestLiveGrooveDisplayBPM {
                        Label(TempoMarking.caption(for: bpm), systemImage: "metronome")
                    }
                    if let genre = payload.guestGlobalGenreDisplayLabel {
                        Label(genre, systemImage: "globe.americas.fill")
                    } else if payload.hostLiveGrooveStyle != .unknown {
                        Label(payload.hostLiveGrooveStyle.label, systemImage: "music.mic")
                    }
                }
                .font(.caption2)
                .foregroundStyle(AppTheme.textSecondary)
            }

            Spacer(minLength: 0)

            if payload.hostLiveGroovePhase == .playing {
                Image(systemName: "repeat")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.accent)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(AppTheme.accentSecondary.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Live section jumps

struct LiveSectionJumpBar: View {
    @Bindable var viewModel: SessionViewModel

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "Jump to Section"))
                .font(.caption.weight(.bold))
                .foregroundStyle(AppTheme.textSecondary)
                .textCase(.uppercase)
                .tracking(1)

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(viewModel.sectionsInOrder) { section in
                    sectionButton(section)
                }
            }
        }
    }

    private func sectionButton(_ section: SectionMarker) -> some View {
        let isActive = viewModel.activeSection?.id == section.id
        let chordCount = viewModel.chords(for: section).count

        return Button {
            viewModel.jumpToSection(section)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: section.kind.icon)
                    .font(.title3.weight(.semibold))
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(section.name)
                        .font(.headline.weight(.bold))
                        .lineLimit(1)
                    Text(String(format: String(localized: "%lld chords"), chordCount))
                        .font(.caption.weight(.medium))
                        .opacity(0.85)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
            .background(isActive ? AppTheme.accent : AppTheme.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                if isActive {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(AppTheme.background.opacity(0.25), lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(isActive ? AppTheme.background : AppTheme.textPrimary)
    }
}

// MARK: - Live setlist controls

struct LiveSetlistControlBar: View {
    @Bindable var viewModel: SessionViewModel
    let store: ProgressionStore

    var body: some View {
        VStack(spacing: 10) {
            if let current = viewModel.currentSetlistSongTitle,
               let index = viewModel.payload.setlistSongIndex,
               let count = viewModel.payload.setlistSongCount {
                HStack {
                    Text(current)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(1)
                    Spacer()
                    Text("\(index + 1)/\(count)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppTheme.accent)
                }
            }

            HStack(spacing: 10) {
                Button {
                    viewModel.previousSetlistSong(store: store)
                } label: {
                    Image(systemName: "backward.fill")
                        .font(.headline)
                        .frame(width: 52, height: 52)
                        .background(AppTheme.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .disabled((viewModel.payload.setlistSongIndex ?? 0) == 0)

                if let nextTitle = viewModel.nextSetlistSongTitle {
                    Button {
                        viewModel.loadSetlistSongAnimated(store: store)
                    } label: {
                        VStack(spacing: 4) {
                            Text(String(localized: "Next Song"))
                                .font(.caption.weight(.bold))
                                .textCase(.uppercase)
                            Text(nextTitle)
                                .font(.headline.weight(.bold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(AppTheme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                } else {
                    Label(String(localized: "Last Song"), systemImage: "flag.checkered")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(AppTheme.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
            .foregroundStyle(AppTheme.textPrimary)
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(AppTheme.surfaceElevated.opacity(0.55), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - Backing track

struct BackingTrackStatusBanner: View {
    let title: String
    let isPlaying: Bool
    var isGuestView: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isPlaying ? "waveform.circle.fill" : "waveform.circle")
                .foregroundStyle(AppTheme.accentSecondary)
                .symbolEffect(.pulse, isActive: isPlaying)
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "Reference Track"))
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(AppTheme.textSecondary)
                    .textCase(.uppercase)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                if isGuestView {
                    Text(String(localized: "Audio on host device only"))
                        .font(.caption2)
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
            Spacer()
            if isPlaying {
                Text(isGuestView
                     ? String(localized: "Host playing")
                     : String(localized: "Playing"))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.accent)
            }
        }
        .padding(12)
        .background(AppTheme.surfaceElevated.opacity(0.95), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct BackingTrackPanel: View {
    @Bindable var viewModel: SessionViewModel
    var onImport: () -> Void
    var style: Style = .standard

    enum Style {
        case standard
        case compact
    }

    @State private var isScrubbing = false
    @State private var scrubTime: TimeInterval = 0
    @State private var isExpanded = true
    @State private var didApplyStyle = false
    @State private var isTrackMenuPresented = false

    private var trackTitle: String {
        viewModel.payload.backingTrackDisplayName.isEmpty
            ? viewModel.backingTrack.displayName
            : viewModel.payload.backingTrackDisplayName
    }

    private var trackDuration: TimeInterval {
        max(viewModel.backingTrack.duration, 0.01)
    }

    private var displayedTime: TimeInterval {
        isScrubbing ? scrubTime : viewModel.backingTrack.currentTime
    }

    var body: some View {
        Group {
            if viewModel.backingTrack.hasTrack || !viewModel.payload.backingTrackDisplayName.isEmpty {
                if isExpanded {
                    expandedPlayer
                } else {
                    compactPlayer
                }
            } else if style == .compact {
                compactImportPrompt
            } else {
                importPrompt
            }
        }
        .onAppear {
            guard !didApplyStyle else { return }
            didApplyStyle = true
            if style == .compact {
                isExpanded = false
            }
        }
    }

    private var compactImportPrompt: some View {
        Button(action: onImport) {
            HStack(spacing: 10) {
                Image(systemName: "waveform")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(AppTheme.accentSecondary)
                Text(String(localized: "Reference Track"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                Spacer(minLength: 0)
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                    .foregroundStyle(AppTheme.accent)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .glassCard()
        }
        .accessibilityHint(String(localized: "Import MP3 or WAV backing track"))
    }

    private var importPrompt: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "Reference Track"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)
                .textCase(.uppercase)

            Button(action: onImport) {
                Label(String(localized: "Import MP3 / WAV"), systemImage: "square.and.arrow.down")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(AppTheme.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .foregroundStyle(AppTheme.textPrimary)
        }
    }

    private var expandedPlayer: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerRow

            playbackScrubber

            HStack(spacing: 0) {
                transportButton(icon: "gobackward.15", label: String(localized: "Rewind 15 seconds")) {
                    viewModel.skipBackingTrack(by: -BackingTrackEngine.defaultSkipInterval)
                }

                Spacer()

                Button {
                    viewModel.toggleBackingTrack()
                } label: {
                    Image(systemName: viewModel.backingTrack.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(AppTheme.accent)
                }
                .accessibilityLabel(viewModel.backingTrack.isPlaying
                                    ? String(localized: "Pause")
                                    : String(localized: "Play"))

                Spacer()

                transportButton(icon: "goforward.15", label: String(localized: "Forward 15 seconds")) {
                    viewModel.skipBackingTrack(by: BackingTrackEngine.defaultSkipInterval)
                }

                Spacer()

                transportButton(icon: "stop.fill", label: String(localized: "Stop")) {
                    viewModel.stopBackingTrack()
                }
            }
        }
        .padding(14)
        .glassCard()
    }

    private var compactPlayer: some View {
        HStack(spacing: 12) {
            Button {
                viewModel.toggleBackingTrack()
            } label: {
                Image(systemName: viewModel.backingTrack.isPlaying ? "pause.fill" : "play.fill")
                    .font(.body.weight(.bold))
                    .frame(width: 36, height: 36)
                    .background(AppTheme.accent.opacity(0.18), in: Circle())
            }
            .foregroundStyle(AppTheme.accent)
            .accessibilityLabel(viewModel.backingTrack.isPlaying
                                ? String(localized: "Pause")
                                : String(localized: "Play"))

            VStack(alignment: .leading, spacing: 4) {
                Text(trackTitle)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                playbackScrubber
            }

            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded = true }
            } label: {
                Image(systemName: "chevron.up")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.textSecondary)
                    .frame(width: 28, height: 28)
            }
            .accessibilityLabel(String(localized: "Expand player"))
        }
        .padding(12)
        .glassCard()
    }

    private var headerRow: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "Reference Track"))
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(AppTheme.textSecondary)
                    .textCase(.uppercase)
                Text(trackTitle)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded = false }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.textSecondary)
                    .frame(width: 28, height: 28)
            }
            .accessibilityLabel(String(localized: "Collapse player"))

            trackOptionsMenu
        }
        .foregroundStyle(AppTheme.textPrimary)
    }

    private var trackOptionsMenu: some View {
        Button {
            isTrackMenuPresented = true
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title3)
                .foregroundStyle(AppTheme.textSecondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "Track options"))
        .liquidGlassMenuPresentation(
            isPresented: $isTrackMenuPresented,
            sheetTitle: "Track options",
            arrowEdge: .bottom,
            minWidth: 200
        ) {
            VStack(alignment: .leading, spacing: 0) {
                LiquidGlassMenuRow(
                    title: String(localized: "Replace"),
                    icon: "arrow.triangle.2.circlepath"
                ) {
                    onImport()
                    isTrackMenuPresented = false
                }
                LiquidGlassMenuRow(
                    title: String(localized: "Remove"),
                    icon: "trash",
                    isDestructive: true
                ) {
                    viewModel.clearBackingTrack()
                    isTrackMenuPresented = false
                }
            }
        }
    }

    private var playbackScrubber: some View {
        VStack(spacing: 4) {
            Slider(
                value: Binding(
                    get: { displayedTime },
                    set: { scrubTime = $0 }
                ),
                in: 0...trackDuration,
                onEditingChanged: { editing in
                    isScrubbing = editing
                    if editing {
                        scrubTime = viewModel.backingTrack.currentTime
                    } else {
                        viewModel.seekBackingTrack(to: scrubTime)
                    }
                }
            )
            .tint(AppTheme.accent)

            HStack {
                Text(BackingTrackEngine.formatTime(displayedTime))
                Spacer()
                Text(BackingTrackEngine.formatTime(viewModel.backingTrack.duration))
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(AppTheme.textSecondary)
        }
    }

    private func transportButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.title3)
                .frame(width: 44, height: 44)
                .background(AppTheme.surfaceElevated, in: Circle())
        }
        .foregroundStyle(AppTheme.textPrimary)
        .accessibilityLabel(label)
    }
}

// MARK: - Rehearsal notes

struct RehearsalNotesBanner: View {
    let notes: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "note.text")
                .foregroundStyle(AppTheme.accentSecondary)
            Text(notes)
                .font(.caption)
                .foregroundStyle(AppTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(AppTheme.surfaceElevated.opacity(0.95), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Internet join code (host)

struct HostRemoteJoinCodeBanner: View {
    let code: String
    var cloudError: String?
    var isCloudReady: Bool = true
    var isRelayLive: Bool = false
    var transportName: String?
    var onCopy: () -> Void
    var onHide: () -> Void
    var onRetry: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Label(String(localized: "Internet join code"), systemImage: statusIcon)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(statusColor)
                    Text(RemoteJoinCode.formatted(code))
                        .font(.system(.title, design: .monospaced).weight(.bold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .accessibilityLabel(String(localized: "Join code \(RemoteJoinCode.formatted(code))"))
                }
                Spacer(minLength: 8)
                HStack(spacing: 8) {
                    if !isRelayLive, let onRetry {
                        Button(action: onRetry) {
                            Image(systemName: "arrow.clockwise")
                                .font(.subheadline.weight(.semibold))
                        }
                        .buttonStyle(.bordered)
                        .tint(AppTheme.accentSecondary)
                        .accessibilityLabel(String(localized: "Retry Internet backup"))
                    }

                    Button(action: onHide) {
                        Image(systemName: "eye.slash")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .tint(AppTheme.textSecondary)
                    .accessibilityLabel(String(localized: "Hide join code"))

                    Button(String(localized: "Copy"), action: onCopy)
                        .font(.subheadline.weight(.semibold))
                        .buttonStyle(.borderedProminent)
                        .tint(AppTheme.accent)
                }
            }

            if isRelayLive {
                if let transportName {
                    Text(String(format: String(localized: "Live on %@ — share this code so guests can join on cellular or weak Wi‑Fi."), transportName))
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                } else {
                    Text(String(localized: "Share this code so guests can join on cellular or weak Wi‑Fi."))
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                }
            } else if let cloudError {
                Text(cloudError)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                Text(String(localized: "Guests cannot use this code until you see the green checkmark. Same Wi‑Fi still works with Nearby."))
                    .font(.caption2)
                    .foregroundStyle(AppTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if isCloudReady {
                Text(String(localized: "Connecting Internet backup…"))
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.surfaceElevated, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(statusColor.opacity(0.35), lineWidth: 1)
        }
    }

    private var statusIcon: String {
        isRelayLive ? "checkmark.icloud.fill" : "icloud.fill"
    }

    private var statusColor: Color {
        isRelayLive ? AppTheme.accent : AppTheme.accentSecondary
    }
}

struct HostRemoteJoinCodeCollapsed: View {
    var onShow: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Label(String(localized: "Internet join code hidden"), systemImage: "icloud")
                .font(.caption.weight(.medium))
                .foregroundStyle(AppTheme.textSecondary)
            Spacer(minLength: 8)
            Button(String(localized: "Show"), action: onShow)
                .font(.caption.weight(.semibold))
                .buttonStyle(.bordered)
                .tint(AppTheme.accentSecondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.surface.opacity(0.85), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// One-line join code for live tools — stays out of the stage header.
struct HostRemoteJoinCodeCompactChip: View {
    let code: String
    var isRelayLive: Bool = false
    var onCopy: () -> Void
    var onShowQR: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isRelayLive ? "checkmark.icloud.fill" : "icloud.fill")
                .font(.subheadline)
                .foregroundStyle(isRelayLive ? AppTheme.accent : AppTheme.accentSecondary)

            VStack(alignment: .leading, spacing: 1) {
                Text(String(localized: "Internet join code"))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(AppTheme.textSecondary)
                Text(RemoteJoinCode.formatted(code))
                    .font(.system(.subheadline, design: .monospaced).weight(.bold))
                    .foregroundStyle(AppTheme.textPrimary)
            }

            Spacer(minLength: 4)

            Button(String(localized: "Copy"), action: onCopy)
                .font(.caption.weight(.semibold))
                .buttonStyle(.bordered)
                .tint(AppTheme.accent)

            if let onShowQR {
                Button(action: onShowQR) {
                    Image(systemName: "qrcode")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .tint(AppTheme.accentSecondary)
                .accessibilityLabel(String(localized: "Show Join QR"))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(AppTheme.surfaceElevated.opacity(0.95), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Reconnect

struct ReconnectBanner: View {
    let sessionName: String
    var onReconnect: () -> Void
    var onLeave: () -> Void

    private var usesCompactActions: Bool {
        PlatformDevice.isPhone
    }

    var body: some View {
        Group {
            if usesCompactActions {
                compactLayout
            } else {
                wideLayout
            }
        }
        .padding(14)
        .background(AppTheme.surfaceElevated, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var messageBlock: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .foregroundStyle(AppTheme.accent)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "Connection lost"))
                    .font(.subheadline.weight(.bold))
                Text(String(format: String(localized: "Reconnect to %@"), sessionName))
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(String(localized: "Trying nearby Wi‑Fi and iCloud backup…"))
                    .font(.caption2)
                    .foregroundStyle(AppTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 10) {
            Button(String(localized: "Reconnect"), action: onReconnect)
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.accent)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            Button(String(localized: "Leave"), action: onLeave)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: 0)
        }
    }

    private var compactLayout: some View {
        VStack(alignment: .leading, spacing: 12) {
            messageBlock
            actionButtons
        }
    }

    private var wideLayout: some View {
        HStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .foregroundStyle(AppTheme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "Connection lost"))
                    .font(.subheadline.weight(.bold))
                Text(String(format: String(localized: "Reconnect to %@"), sessionName))
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
                Text(String(localized: "Trying nearby Wi‑Fi and iCloud backup…"))
                    .font(.caption2)
                    .foregroundStyle(AppTheme.textSecondary)
            }
            Spacer(minLength: 0)
            Button(String(localized: "Reconnect"), action: onReconnect)
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.accent)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            Button(String(localized: "Leave"), action: onLeave)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
    }
}

// MARK: - External display

struct ExternalDisplayGuide: View {
    var onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "tv")
                .foregroundStyle(AppTheme.accentSecondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "External Display"))
                    .font(.caption.weight(.bold))
                Text(String(localized: "Mirror this device with AirPlay to show the chord ring on a projector or TV."))
                    .font(.caption2)
                    .foregroundStyle(AppTheme.textSecondary)
            }
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
            }
        }
        .padding(12)
        .background(AppTheme.surfaceElevated.opacity(0.95), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Scale hint

struct ScaleHintBadge: View {
    let hint: String

    var body: some View {
        Label(hint, systemImage: "sparkles")
            .font(.caption.weight(.semibold))
            .foregroundStyle(AppTheme.accentSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(AppTheme.surfaceElevated, in: Capsule())
    }
}

// MARK: - Recent sessions (home)

struct RecentSessionOptionsMenu<Label: View>: View {
    let isOwnSession: Bool
    var onPrimary: () -> Void
    var onDelete: () -> Void
    @ViewBuilder var label: () -> Label
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            label()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "Recent session options"))
        .liquidGlassMenuPresentation(
            isPresented: $isPresented,
            sheetTitle: "Recent session options",
            arrowEdge: .top,
            minWidth: 200
        ) {
            RecentSessionOptionsPanel(
                isOwnSession: isOwnSession,
                onPrimary: {
                    onPrimary()
                    isPresented = false
                },
                onDelete: {
                    onDelete()
                    isPresented = false
                }
            )
        }
    }
}

private struct RecentSessionOptionsPanel: View {
    let isOwnSession: Bool
    let onPrimary: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            LiquidGlassMenuRow(
                title: isOwnSession ? String(localized: "Host Again") : String(localized: "Reconnect"),
                icon: isOwnSession ? "music.mic.circle.fill" : "arrow.triangle.2.circlepath.circle.fill"
            ) {
                onPrimary()
            }

            LiquidGlassMenuRow(
                title: String(localized: "Remove"),
                icon: "trash",
                isDestructive: true
            ) {
                onDelete()
            }
        }
    }
}

struct RecentSessionsSection: View {
    let records: [RecentSessionRecord]
    var onRehost: (RecentSessionRecord) -> Void
    var onReconnect: (RecentSessionRecord) -> Void
    var onDelete: (RecentSessionRecord) -> Void
    var onClearAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(String(localized: "Recent Sessions"))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(AppTheme.textSecondary)
                Spacer()
                if !records.isEmpty {
                    Button(String(localized: "Clear All"), role: .destructive) {
                        onClearAll()
                    }
                    .font(.caption.weight(.semibold))
                }
            }

            ForEach(records.prefix(4)) { record in
                let isOwnSession = record.hostDeviceName == SessionManager.currentDisplayName()
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(record.sessionName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.textPrimary)
                        Text("Key \(record.key.displayName) · \(record.hostDeviceName)")
                            .font(.caption)
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                    Spacer()
                    RecentSessionOptionsMenu(
                        isOwnSession: isOwnSession,
                        onPrimary: {
                            if isOwnSession {
                                onRehost(record)
                            } else {
                                onReconnect(record)
                            }
                        },
                        onDelete: { onDelete(record) }
                    ) {
                        Image(systemName: "ellipsis.circle")
                            .foregroundStyle(AppTheme.accent)
                    }
                }
                .padding(12)
                .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }
}

// MARK: - QR share

struct ProgressionQRShareSheet: View {
    let title: String
    let payloadData: Data
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                qrCodeView
                Text(String(localized: "Share this chart pack via AirDrop or save the file on another device running Chordyx."))
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                shareButton
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppTheme.background)
            .navigationTitle(String(localized: "Share Chart"))
            .platformInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done")) { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var qrCodeView: some View {
        #if canImport(CoreImage) && canImport(UIKit)
        if let image = makeQRImage() {
            Image(uiImage: image)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 260, maxHeight: 260)
                .padding()
                .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
        }
        #else
        Image(systemName: "qrcode")
            .font(.system(size: 80))
            .foregroundStyle(AppTheme.textSecondary)
        #endif
    }

    @ViewBuilder
    private var shareButton: some View {
        if let url = temporaryShareURL {
            ShareLink(item: url) {
                Label(String(localized: "Share Pack File"), systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.accent)
        }
    }

    private var temporaryShareURL: URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(title).chordyxpack")
        try? payloadData.write(to: url)
        return url
    }

    #if canImport(CoreImage) && canImport(UIKit)
    private func makeQRImage() -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data("chordyx-pack".utf8) + payloadData
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
    #endif
}

// MARK: - Pre-service checklist

struct PreServiceChecklistView: View {
    @Bindable var viewModel: SessionViewModel
    var store: ProgressionStore? = nil
    var onFinish: () -> Void

    @State private var manualChecks: Set<String> = []
    @State private var showBeforeEachSession = GuestDisplaySettings.preServiceChecklistAutoShowEnabled
    @State private var readinessReport: ReadinessReport?
    @State private var readinessRefreshTask: Task<Void, Never>?

    private struct Item: Identifiable {
        let id: String
        let title: String
        let detail: String
        let icon: String
        let isAutoSatisfied: Bool
    }

    private var items: [Item] {
        [
            Item(
                id: "chords",
                title: String(localized: "Chords loaded"),
                detail: chordDetail,
                icon: "music.note.list",
                isAutoSatisfied: hasChords
            ),
            Item(
                id: "tempo",
                title: String(localized: "Tempo confirmed"),
                detail: String(format: String(localized: "%lld BPM · %lld/%lld"), Int(viewModel.payload.tempoBPM), viewModel.payload.beatsPerBar, viewModel.payload.beatUnit),
                icon: "metronome",
                isAutoSatisfied: false
            ),
            Item(
                id: "countin",
                title: String(localized: "Count-in ready"),
                detail: countInDetail,
                icon: "123.rectangle",
                isAutoSatisfied: viewModel.payload.countInBars > 0
            ),
            Item(
                id: "sections",
                title: String(localized: "Sections mapped"),
                detail: sectionsDetail,
                icon: "square.grid.2x2",
                isAutoSatisfied: !viewModel.payload.sections.isEmpty
            ),
            Item(
                id: "band",
                title: String(localized: "Band connected"),
                detail: bandDetail,
                icon: "person.2.fill",
                isAutoSatisfied: !viewModel.sessionManager.connectedPeers.isEmpty
            ),
            Item(
                id: "lyrics",
                title: String(localized: "Lyrics chart ready"),
                detail: lyricsDetail,
                icon: "text.quote",
                isAutoSatisfied: hasLyrics
            )
        ]
    }

    private var hasChords: Bool {
        viewModel.payload.isLiveChordsOnly || !viewModel.sortedChords.isEmpty
    }

    private var hasLyrics: Bool {
        !viewModel.payload.lyricsLines.isEmpty || !viewModel.payload.lyrics.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var chordDetail: String {
        if viewModel.payload.isLiveChordsOnly {
            return String(localized: "Live piano / MIDI mode")
        }
        return String(format: String(localized: "%lld chords in progression"), viewModel.sortedChords.count)
    }

    private var countInDetail: String {
        if viewModel.payload.countInBars > 0 {
            return String(format: String(localized: "%lld bar count-in"), viewModel.payload.countInBars)
        }
        return String(localized: "Tap to confirm or set count-in in metronome")
    }

    private var sectionsDetail: String {
        if viewModel.payload.sections.isEmpty {
            return String(localized: "Tap if sections aren’t needed")
        }
        return String(format: String(localized: "%lld sections"), viewModel.payload.sections.count)
    }

    private var bandDetail: String {
        let count = viewModel.sessionManager.connectedPeers.count
        if count == 0 {
            return String(localized: "Tap when solo or band is ready")
        }
        return String(format: String(localized: "%lld musician(s) connected"), count)
    }

    private var lyricsDetail: String {
        if hasLyrics { return String(localized: "Lyrics available in chart view") }
        return String(localized: "Tap if you don’t need lyrics")
    }

    private var allReady: Bool {
        items.allSatisfy { $0.isAutoSatisfied || manualChecks.contains($0.id) }
    }

    private var smartItems: [SmartChecklistItem] {
        let setlist: Setlist? = {
            guard let name = viewModel.payload.setlistName else { return nil }
            return store?.setlists.first { $0.name == name }
        }()
        return SetlistIntelligenceEngine.smartChecklist(
            setlist: setlist,
            store: store ?? ProgressionStore(),
            payload: viewModel.payload,
            connectedPeerCount: viewModel.sessionManager.connectedPeers.count
        )
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Spacer()
                        Button(String(localized: "Skip checklist")) {
                            onFinish()
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.accentSecondary)
                    }
                    .listRowBackground(Color.clear)

                    Text(String(localized: "Quick check before the service starts. Auto-detected items are marked for you — tap any row to confirm manually."))
                        .font(.footnote)
                        .foregroundStyle(AppTheme.textSecondary)
                        .listRowBackground(Color.clear)

                    if let readinessReport {
                        ReadinessScoreBanner(report: readinessReport)
                            .listRowBackground(Color.clear)
                    }
                }

                SmartSetlistChecklistSection(items: smartItems)

                Section(String(localized: "Before You Start")) {
                    ForEach(items) { item in
                        checklistRow(item)
                    }
                }

                Section {
                    Toggle(String(localized: "Show before each live session"), isOn: $showBeforeEachSession)
                        .onChange(of: showBeforeEachSession) { _, enabled in
                            GuestDisplaySettings.preServiceChecklistAutoShowEnabled = enabled
                        }
                } footer: {
                    Text(String(localized: "Turn off to skip this check when hosting. Open Pre-Service anytime from session controls."))
                        .font(.footnote)
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.backgroundGradient.ignoresSafeArea())
            .navigationTitle(String(localized: "Pre-Service Check"))
            .platformInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Skip")) {
                        onFinish()
                    }
                    #if os(macOS)
                    .keyboardShortcut(.cancelAction)
                    #endif
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Go Live")) {
                        onFinish()
                    }
                    .disabled(!allReady)
                    .fontWeight(.semibold)
                    #if os(macOS)
                    .keyboardShortcut(.defaultAction)
                    #endif
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                preServiceActionBar
            }
        }
        .preferredColorScheme(.dark)
        .onAppear(perform: scheduleReadinessRefresh)
        .onChange(of: manualChecks) { _, _ in scheduleReadinessRefresh() }
    }

    private func scheduleReadinessRefresh() {
        readinessRefreshTask?.cancel()
        readinessRefreshTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            refreshReadinessReport()
        }
    }

    private func refreshReadinessReport() {
        let report = viewModel.evaluateReadinessReport(
            checklistSatisfied: items.filter { $0.isAutoSatisfied || manualChecks.contains($0.id) }.count,
            checklistTotal: items.count,
            unrehearsedSongs: smartItems.filter { !$0.isAutoSatisfied && $0.id == "rehearsal" }.count
        )
        readinessReport = report
        viewModel.publishReadinessScore(report.score)
    }

    private var preServiceActionBar: some View {
        VStack(spacing: 10) {
            if allReady {
                Label(String(localized: "Ready to lead"), systemImage: "checkmark.seal.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.accent)
            }

            HStack(spacing: 12) {
                Button(String(localized: "Skip")) {
                    onFinish()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                #if os(macOS)
                .keyboardShortcut(.cancelAction)
                #endif

                Button(String(localized: "Go Live")) {
                    onFinish()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!allReady)
                .fontWeight(.semibold)
                #if os(macOS)
                .keyboardShortcut(.defaultAction)
                #endif
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    private func checklistRow(_ item: Item) -> some View {
        let satisfied = item.isAutoSatisfied || manualChecks.contains(item.id)
        return Button {
            if manualChecks.contains(item.id) {
                manualChecks.remove(item.id)
            } else {
                manualChecks.insert(item.id)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: satisfied ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(satisfied ? AppTheme.accent : AppTheme.textSecondary)
                VStack(alignment: .leading, spacing: 2) {
                    Label(item.title, systemImage: item.icon)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                    Text(item.detail)
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                }
                Spacer()
                if item.isAutoSatisfied {
                    Text(String(localized: "Auto"))
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(AppTheme.accentSecondary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
