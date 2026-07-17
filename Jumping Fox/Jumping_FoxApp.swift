//
//  Jumping_FoxApp.swift
//  Jumping Fox
//

import SwiftUI

@main
struct Jumping_FoxApp: App {
    @AppStorage(GameSettings.onboardingCompleteKey) private var onboardingComplete = false

    var body: some Scene {
        WindowGroup {
            ZStack {
                if onboardingComplete {
                    ContentView()
                        .transition(.opacity.combined(with: .scale(scale: 1.03)))
                } else {
                    OnboardingView()
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.55), value: onboardingComplete)
        }
    }
}
