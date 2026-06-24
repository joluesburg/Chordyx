//
//  SongImportReviewComponents.swift
//  Chordyx
//

import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

enum ImportClipboard {
    static var string: String? {
        #if os(iOS)
        UIPasteboard.general.string
        #elseif os(macOS)
        NSPasteboard.general.string(forType: .string)
        #else
        nil
        #endif
    }

    static var likelyURL: String? {
        guard let text = string?.trimmingCharacters(in: .whitespacesAndNewlines),
              text.lowercased().hasPrefix("http") else { return nil }
        return text
    }
}

struct SongImportQualityCard: View {
    let quality: SongImportQuality
    let warnings: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: quality.readiness.icon)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(readinessColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(quality.readiness.label)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(AppTheme.textPrimary)
                    Text("Import quality \(quality.score)%")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.textSecondary)
                }

                Spacer()
            }

            ForEach(quality.checks) { check in
                HStack(spacing: 8) {
                    Image(systemName: check.passed ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .foregroundStyle(check.passed ? .green : .orange)
                        .font(.caption.weight(.bold))
                    Text(check.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                    Spacer()
                    Text(check.detail)
                        .font(.caption2)
                        .foregroundStyle(AppTheme.textSecondary)
                        .multilineTextAlignment(.trailing)
                }
            }

            ForEach(warnings, id: \.self) { warning in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "lightbulb.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                    Text(warning)
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .padding(14)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var readinessColor: Color {
        switch quality.readiness {
        case .ready: .green
        case .review: .orange
        case .incomplete: .red
        }
    }
}

struct SongImportReviewFields: View {
    @Binding var title: String
    @Binding var key: MusicalKey
    @Binding var tempoText: String
    var artist: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Review before saving")
                .font(.headline.weight(.bold))
                .foregroundStyle(AppTheme.textPrimary)

            TextField("Song title", text: $title)
                .textFieldStyle(.roundedBorder)
                #if os(iOS)
                .textInputAutocapitalization(.words)
                #endif

            if let artist, !artist.isEmpty {
                Text(artist)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Key")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.textSecondary)
                    Picker("Key", selection: $key) {
                        ForEach(MusicalKey.allCases) { item in
                            Text(item.displayName).tag(item)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(AppTheme.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Tempo (BPM)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.textSecondary)
                    TextField("100", text: $tempoText)
                        .textFieldStyle(.roundedBorder)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                        .frame(maxWidth: 100)
                }
            }
        }
        .padding(14)
        .background(AppTheme.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct SongImportSectionReviewList: View {
    let draft: SongImportDraft
    @State private var expandedSectionIDs: Set<UUID> = []

    private var breakdown: [(section: SectionMarker, chords: [ChordEntry])] {
        SongSectionAnalyzer.sectionBreakdown(chords: draft.chords, sections: draft.sections)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Section rings")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)

            Text("Each section becomes its own ring in session. Expand to preview.")
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)

            ForEach(breakdown, id: \.section.id) { item in
                sectionCard(item.section, chords: item.chords)
            }
        }
    }

    private func sectionCard(_ section: SectionMarker, chords: [ChordEntry]) -> some View {
        let isExpanded = expandedSectionIDs.contains(section.id)

        return VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                    if isExpanded {
                        expandedSectionIDs.remove(section.id)
                    } else {
                        expandedSectionIDs.insert(section.id)
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: section.kind.icon)
                        .foregroundStyle(AppTheme.accentSecondary)
                    Text(section.name)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(AppTheme.textPrimary)
                    Text("\(chords.count) chords")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                ImportSectionMiniRingView(
                    chords: chords,
                    key: draft.key,
                    notation: .symbol
                )
                .frame(height: 150)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(chords.enumerated()), id: \.element.id) { index, chord in
                            Text(chord.symbolName)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(index == 0 ? AppTheme.background : AppTheme.textPrimary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(index == 0 ? AppTheme.accent : AppTheme.surface)
                                .clipShape(Capsule())
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(AppTheme.surface.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct ImportSectionMiniRingView: View {
    let chords: [ChordEntry]
    let key: MusicalKey
    let notation: ChordNotation

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            ChordRingView(
                chords: chords,
                notation: notation,
                key: key,
                activeChordID: chords.first?.id,
                isInteractive: false,
                containerSize: CGSize(width: size, height: size),
                radius: size * 0.34,
                bubbleSize: chords.count > 8 ? 34 : 40,
                onTap: { _ in }
            )
            .frame(width: size, height: size)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct SongImportSavedSuccessView: View {
    let saved: SavedProgression
    var onHost: () -> Void
    var onImportAnother: () -> Void
    var onDone: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(.green)

            Text("Saved to Library")
                .font(.title2.weight(.bold))
                .foregroundStyle(AppTheme.textPrimary)

            Text(saved.name)
                .font(.headline)
                .foregroundStyle(AppTheme.accent)
                .multilineTextAlignment(.center)

            if !saved.sections.isEmpty {
                Text("\(saved.sections.count) section rings · \(saved.chords.count) chords")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
            }

            Button(action: onHost) {
                Label("Host Now", systemImage: "play.fill")
                    .font(.headline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.accent)

            Button(action: onImportAnother) {
                Label("Import Another", systemImage: "square.and.arrow.down")
                    .font(.headline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(AppTheme.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .foregroundStyle(AppTheme.textPrimary)

            Button("Done", action: onDone)
                .foregroundStyle(AppTheme.textSecondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(AppTheme.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct ClipboardPasteButton: View {
    let label: String
    let systemImage: String
    var onPaste: (String) -> Void

    var body: some View {
        if let text = ImportClipboard.string, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Button {
                onPaste(text)
            } label: {
                Label(label, systemImage: systemImage)
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(AppTheme.accent)
        }
    }
}
