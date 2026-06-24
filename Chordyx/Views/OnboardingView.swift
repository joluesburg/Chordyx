//
//  OnboardingView.swift
//  Chordyx
//

import SwiftUI

struct OnboardingView: View {
    @AppStorage(SessionManager.displayNameKey) private var displayName = ""
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("preferredNotation") private var preferredNotationRaw = ChordNotation.symbol.rawValue

    @State private var page = 0
    @State private var nameText = ""

    private var preferredNotation: ChordNotation {
        get { ChordNotation(rawValue: preferredNotationRaw) ?? .symbol }
        set { preferredNotationRaw = newValue.rawValue }
    }

    var body: some View {
        ZStack {
            AppTheme.backgroundGradient.ignoresSafeArea()

            VStack(spacing: 24) {
                TabView(selection: $page) {
                    welcomePage.tag(0)
                    namePage.tag(1)
                    notationPage.tag(2)
                    networkPage.tag(3)
                }
                #if os(iOS)
                .tabViewStyle(.page(indexDisplayMode: .always))
                #else
                .tabViewStyle(.automatic)
                #endif

                Button(page == 3 ? "Get Started" : "Continue") {
                    if page < 3 {
                        withAnimation { page += 1 }
                    } else {
                        finish()
                    }
                }
                .font(.headline)
                .foregroundStyle(AppTheme.background)
                .frame(maxWidth: 320)
                .padding(.vertical, 16)
                .background(AppTheme.accent)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            nameText = displayName
        }
    }

    private var welcomePage: some View {
        onboardingPage(
            icon: "circle.grid.cross.fill",
            title: "Welcome to Chordyx",
            message: "Share chord progressions in real time with your band — host, join, or practice solo."
        )
    }

    private var namePage: some View {
        VStack(spacing: 20) {
            onboardingPage(
                icon: "person.crop.circle",
                title: "Your Name",
                message: "This is how other musicians see you when you host or join."
            )
            TextField("Display name", text: $nameText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 40)
        }
    }

    private var notationPage: some View {
        VStack(spacing: 16) {
            onboardingPage(
                icon: "textformat",
                title: "Default Notation",
                message: "Pick your preferred chord style. You can change this anytime in a session."
            )
            ForEach(ChordNotation.allCases) { notation in
                Button {
                    preferredNotationRaw = notation.rawValue
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(notation.label).foregroundStyle(AppTheme.textPrimary)
                            Text(notation.subtitle).font(.caption).foregroundStyle(AppTheme.textSecondary)
                        }
                        Spacer()
                        if preferredNotation.rawValue == notation.rawValue {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(AppTheme.accent)
                        }
                    }
                    .padding()
                    .background(AppTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .padding(.horizontal, 32)
            }
        }
    }

    private var networkPage: some View {
        onboardingPage(
            icon: "wifi",
            title: "Stay Nearby",
            message: "Keep Wi‑Fi and Bluetooth on. Chordyx finds nearby sessions automatically — no internet required."
        )
    }

    private func onboardingPage(icon: String, title: LocalizedStringKey, message: LocalizedStringKey) -> some View {
        VStack(spacing: 20) {
            Image(systemName: icon)
                .font(.system(size: 52))
                .foregroundStyle(AppTheme.accent)
            Text(title)
                .font(.title2.weight(.bold))
                .foregroundStyle(AppTheme.textPrimary)
            Text(message)
                .font(.body)
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .padding(.top, 40)
    }

    private func finish() {
        let trimmed = nameText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { displayName = trimmed }
        hasCompletedOnboarding = true
    }
}
