//
//  ContentView.swift
//  Chordyx
//
//  Created by Jose L. Espinosa Burgos on 6/8/26.
//

import SwiftUI

struct ContentView: View {
    /// Created only after the first Home paint. Instantiating it during launch
    /// overflowed the iPhone main-thread stack (`EXC_BAD_ACCESS code=2` at 0x16…).
    @State private var viewModel: SessionViewModel?
    @State private var store: ProgressionStore?
    @State private var pendingRemoteJoinCode: String?
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var didStartLaunch = false

    var body: some View {
        Group {
            if !hasCompletedOnboarding {
                OnboardingView()
            } else if let store {
                HomeView(
                    viewModel: $viewModel,
                    pendingRemoteJoinCode: $pendingRemoteJoinCode,
                    store: store
                )
            } else {
                launchPlaceholder
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            startLaunchIfNeeded()
        }
        .onOpenURL { url in
            if let code = SessionJoinQR.parseCode(from: url) {
                pendingRemoteJoinCode = code
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard let viewModel, viewModel.hasBootstrapped else { return }
            switch newPhase {
            case .active:
                viewModel.sessionManager.refreshHostingIfNeeded()
                viewModel.handleAppDidBecomeActive()
            case .background:
                viewModel.handleAppDidEnterBackground()
            case .inactive:
                break
            @unknown default:
                break
            }
        }
    }

    /// No nested gradients / brand mark — those ran on the same stack as launch.
    private var launchPlaceholder: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Text("Chordyx")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
    }

    private func startLaunchIfNeeded() {
        guard !didStartLaunch else { return }
        didStartLaunch = true
        DispatchQueue.main.async {
            store = ProgressionStore()
        }
    }
}

#Preview {
    ContentView()
}
