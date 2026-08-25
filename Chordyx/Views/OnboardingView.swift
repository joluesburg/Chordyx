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

    private let lastPage = 4

    private var preferredNotation: ChordNotation {
        get { ChordNotation(rawValue: preferredNotationRaw) ?? .symbol }
        set { preferredNotationRaw = newValue.rawValue }
    }

    var body: some View {
        ZStack {
            Color.clear.appShellBackground()

            VStack(spacing: 24) {
                TabView(selection: $page) {
                    welcomePage.tag(0)
                    pathsPage.tag(1)
                    namePage.tag(2)
                    notationPage.tag(3)
                    networkPage.tag(4)
                }
                #if os(iOS)
                .tabViewStyle(.page(indexDisplayMode: .always))
                #else
                .tabViewStyle(.automatic)
                #endif

                Button(page == lastPage ? String(localized: "Get Started") : String(localized: "Continue")) {
                    if page < lastPage {
                        withAnimation { page += 1 }
                    } else {
                        finish()
                    }
                }
                .buttonStyle(.chordyxProminent)
                .frame(maxWidth: 320)
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

    private var pathsPage: some View {
        VStack(spacing: 20) {
            onboardingPage(
                icon: "person.3.fill",
                title: "Host, join, or practice",
                message: "Host a session for the band, join a nearby host, or practice solo with the chord ring."
            )

            VStack(alignment: .leading, spacing: 12) {
                pathRow(icon: "dot.radiowaves.left.and.right", title: "Host a Session", detail: "You lead the chords; the band follows.")
                pathRow(icon: "person.badge.plus", title: "Join a Session", detail: "Same Wi‑Fi nearby, or Internet join code with iCloud.")
                pathRow(icon: "metronome", title: "Practice Solo", detail: "Rehearse with the ring and metronome.")
            }
            .padding(.horizontal, 28)
        }
    }

    private func pathRow(icon: String, title: LocalizedStringKey, detail: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
            title: "Ready for Sunday",
            message: "Use the same Wi‑Fi as your band. Allow Local Network access when prompted. Run the pre-service checklist before going live."
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
