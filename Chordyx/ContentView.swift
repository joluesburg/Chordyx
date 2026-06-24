//
//  ContentView.swift
//  Chordyx
//
//  Created by Jose L. Espinosa Burgos on 6/8/26.
//

import SwiftUI

struct ContentView: View {
    @State private var viewModel = SessionViewModel()
    @State private var store = ProgressionStore()
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSplash = true

    var body: some View {
        Group {
            if showSplash {
                SplashView {
                    withAnimation(.easeInOut(duration: 0.35)) {
                        showSplash = false
                    }
                }
            } else if hasCompletedOnboarding {
                HomeView(viewModel: viewModel, store: store)
            } else {
                OnboardingView()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
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
}

#Preview {
    ContentView()
}
