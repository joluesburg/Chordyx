//
//  ChordyxBubbleMark.swift
//  ChordyxLiveActivity
//
//  Small brand mark for Live Activity / Dynamic Island chrome.
//

import SwiftUI

struct ChordyxBubbleMark: View {
    var size: CGFloat = 22

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.98, green: 0.72, blue: 0.28),
                            Color(red: 0.45, green: 0.55, blue: 0.98)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Image(systemName: "music.note")
                .font(.system(size: max(8, size * 0.42), weight: .bold))
                .foregroundStyle(.black.opacity(0.85))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
