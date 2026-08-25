//
//  LiveChordPadView.swift
//  Chordyx
//
//  Host tap pad — broadcast a chord to the band without piano/MIDI.
//

import SwiftUI

struct LiveChordPadView: View {
    @ObservedObject var viewModel: SessionViewModel

    private var symbols: [String] { viewModel.liveChordPadSymbols }

    private var activeSymbol: String? {
        viewModel.payload.liveChordSymbol.map { LiveRing.normalize($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label(String(localized: "Live Chord Pad"), systemImage: "square.grid.3x3.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.textSecondary)
                    .textCase(.uppercase)
                Spacer(minLength: 0)
                if viewModel.payload.livePlayInputMode == .guitar {
                    Text(String(localized: "Tap while you strum"))
                        .font(.caption2)
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 8)], spacing: 8) {
                ForEach(symbols, id: \.self) { symbol in
                    chordButton(symbol)
                }
            }
        }
    }

    private func chordButton(_ symbol: String) -> some View {
        let normalized = LiveRing.normalize(symbol)
        let isActive = activeSymbol == normalized
        return Button {
            viewModel.broadcastLiveChord(symbol)
        } label: {
            Text(displayName(for: symbol))
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .foregroundStyle(isActive ? AppTheme.background : AppTheme.textPrimary)
                .background(
                    isActive ? AppTheme.accent : AppTheme.surfaceElevated.opacity(0.85),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(isActive ? AppTheme.accent : Color.white.opacity(0.08), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private func displayName(for symbol: String) -> String {
        switch viewModel.payload.notation {
        case .symbol:
            return symbol
        case .latin:
            return ChordCatalog.latinName(forSymbol: symbol)
        case .nashville:
            return NashvilleConverter.number(for: symbol, in: viewModel.payload.key)
        }
    }
}
