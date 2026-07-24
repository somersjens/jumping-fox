//
//  Jumping_FoxApp.swift
//  Jumping Fox
//

import SwiftUI

@main
struct Jumping_FoxApp: App {
    @AppStorage(GameSettings.onboardingCompleteKey) private var onboardingComplete = false
    @StateObject private var language = LanguageManager.shared
    @StateObject private var promotedPurchase = PromotedPurchaseCoordinator.shared

    init() {
        PromotedPurchaseCoordinator.shared.startListening()
        // Bring iCloud sync online at launch — not just once the home screen
        // appears. On a fresh reinstall the app opens on the onboarding welcome
        // screen (which never touches ProgressSync), so without this the saved
        // name is never pulled back from iCloud and the name field stays empty.
        // With it, the restore runs and @AppStorage fills the field the moment
        // iCloud delivers the name.
        _ = ProgressSync.shared
    }

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
            .sheet(isPresented: Binding(
                get: { promotedPurchase.isAwaitingParentApproval },
                set: { isPresented in
                    if !isPresented { promotedPurchase.cancelDeferredPurchase() }
                }
            ),
                   onDismiss: { promotedPurchase.cancelDeferredPurchase() }) {
                let character = CharacterCatalog.current(isPremium: PremiumStore.shared.isPremium)
                ParentApprovalGate(
                    accent: character.color,
                    deepColor: character.deepColor,
                    onApproved: { promotedPurchase.approveDeferredPurchase() }
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        }
    }
}
