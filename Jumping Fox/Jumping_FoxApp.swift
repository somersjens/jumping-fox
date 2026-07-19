//
//  Jumping_FoxApp.swift
//  Jumping Fox
//

import SwiftUI

@main
struct Jumping_FoxApp: App {
    @AppStorage(GameSettings.onboardingCompleteKey) private var onboardingComplete = false
    @StateObject private var language = LanguageManager.shared

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
            // Re-renders every `Text` (and formats numbers) when the language
            // changes; combined with the bundle redirection this makes the
            // switch instant, no restart required.
            .environment(\.locale, language.locale)
        }
    }
}
