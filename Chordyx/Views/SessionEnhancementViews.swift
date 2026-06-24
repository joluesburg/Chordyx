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

    var body: some View {
        HStack(spacing: 8) {
            if isMetronomePlaying {
                Label("\(Int(tempoBPM)) BPM", systemImage: "metronome")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(AppTheme.accent)
            }
            if isAutoAdvancePaused {
                statusChip(String(localized: "HOLD"), icon: "hand.raised.fill", color: AppTheme.accentSecondary)
            }
            if isVampActive {
                statusChip(String(localized: "VAMP"), icon: "infinity.circle.fill", color: AppTheme.accent)
            }
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
        }
        .padding(14)
        .background(AppTheme.surfaceElevated.opacity(0.55), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - Backing track

struct BackingTrackStatusBanner: View {
    let title: String
    let isPlaying: Bool

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
            }
            Spacer()
            if isPlaying {
                Text(String(localized: "Playing"))
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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "Reference Track"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)
                .textCase(.uppercase)

            if viewModel.backingTrack.hasTrack || !viewModel.payload.backingTrackDisplayName.isEmpty {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(viewModel.payload.backingTrackDisplayName.isEmpty
                             ? viewModel.backingTrack.displayName
                             : viewModel.payload.backingTrackDisplayName)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Text(String(localized: "Local playback — band sees status only"))
                            .font(.caption2)
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                    Spacer()
                    Button {
                        viewModel.toggleBackingTrack()
                    } label: {
                        Image(systemName: viewModel.backingTrack.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.title2)
                    }
                    Button {
                        viewModel.stopBackingTrack()
                    } label: {
                        Image(systemName: "stop.circle")
                            .font(.title3)
                    }
                }
                .foregroundStyle(AppTheme.textPrimary)

                HStack(spacing: 10) {
                    Button(String(localized: "Replace"), action: onImport)
                        .font(.caption.weight(.semibold))
                    Button(String(localized: "Remove")) {
                        viewModel.clearBackingTrack()
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red.opacity(0.85))
                }
            } else {
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

// MARK: - Reconnect

struct ReconnectBanner: View {
    let sessionName: String
    var onReconnect: () -> Void
    var onLeave: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .foregroundStyle(AppTheme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "Connection lost"))
                    .font(.subheadline.weight(.bold))
                Text(String(format: String(localized: "Reconnect to %@"), sessionName))
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
            }
            Spacer()
            Button(String(localized: "Reconnect"), action: onReconnect)
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.accent)
            Button(String(localized: "Leave"), action: onLeave)
                .font(.caption.weight(.semibold))
        }
        .padding(14)
        .background(AppTheme.surfaceElevated, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
                    Menu {
                        Button(String(localized: "Host Again")) { onRehost(record) }
                        Button(String(localized: "Reconnect")) { onReconnect(record) }
                        Divider()
                        Button(String(localized: "Remove"), role: .destructive) { onDelete(record) }
                    } label: {
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
    var onFinish: () -> Void

    @State private var manualChecks: Set<String> = []

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

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(String(localized: "Quick check before the service starts. Auto-detected items are marked for you — tap any row to confirm manually."))
                        .font(.footnote)
                        .foregroundStyle(AppTheme.textSecondary)
                        .listRowBackground(Color.clear)
                }

                Section(String(localized: "Before You Start")) {
                    ForEach(items) { item in
                        checklistRow(item)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.backgroundGradient.ignoresSafeArea())
            .navigationTitle(String(localized: "Pre-Service Check"))
            .platformInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Go Live")) {
                        onFinish()
                    }
                    .disabled(!allReady)
                    .fontWeight(.semibold)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if allReady {
                    Label(String(localized: "Ready to lead"), systemImage: "checkmark.seal.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(.ultraThinMaterial)
                }
            }
        }
        .preferredColorScheme(.dark)
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
