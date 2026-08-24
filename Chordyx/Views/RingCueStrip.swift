//
//  RingCueStrip.swift
//  Chordyx
//
//  Compact band cues under the chord ring — host sends, guests see the banner.
//

import SwiftUI

struct RingCueStrip: View {
    @ObservedObject var viewModel: SessionViewModel
    var isHost: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if isHost {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(LiveCue.ringPresets, id: \.0) { text, symbol in
                            Button {
                                viewModel.sendLiveCue(text, symbol: symbol)
                            } label: {
                                Label {
                                    Text(String(localized: String.LocalizationValue(text)))
                                        .lineLimit(1)
                                } icon: {
                                    Image(systemName: symbol)
                                }
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(chipBackground(for: text))
                                .clipShape(Capsule())
                                .overlay {
                                    if isActive(text) {
                                        Capsule().stroke(AppTheme.accent, lineWidth: 1.5)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(isActive(text) ? AppTheme.accent : AppTheme.textPrimary)
                        }
                    }
                    .padding(.horizontal, 2)
                }
                .accessibilityLabel(String(localized: "Band cues"))
            }

            if let cue = viewModel.payload.activeCue {
                HStack(spacing: 8) {
                    Image(systemName: cue.symbol)
                        .font(.caption.weight(.bold))
                    Text(String(localized: String.LocalizationValue(cue.text)))
                        .font(.caption.weight(.bold))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(AppTheme.background)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(AppTheme.accent)
                .clipShape(Capsule())
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: viewModel.payload.activeCue?.sentAt)
    }

    private func chipBackground(for text: String) -> Color {
        isActive(text) ? AppTheme.accent.opacity(0.22) : AppTheme.surfaceElevated.opacity(0.92)
    }

    private func isActive(_ text: String) -> Bool {
        switch text {
        case "Hold": viewModel.payload.isAutoAdvancePaused
        case "Vamp": viewModel.payload.isVampActive
        case "Drums out":
            false
        case "Soft", "Full", "Build":
            viewModel.payload.activeCue?.text == text
        default:
            viewModel.payload.activeCue?.text == text
        }
    }
}
