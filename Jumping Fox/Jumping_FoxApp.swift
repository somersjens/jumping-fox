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

#if TRAILER_EXPORT
    private var isExportingGameplayTrailer: Bool {
        ProcessInfo.processInfo.arguments.contains("--export-app-store-teaser")
    }

    private var isExportingMenuTour: Bool {
        ProcessInfo.processInfo.arguments.contains("--export-menu-tour")
    }

    private var isExportingPremiumTour: Bool {
        ProcessInfo.processInfo.arguments.contains("--export-premium-tour")
    }
#endif

    init() {
#if TRAILER_EXPORT
        if ProcessInfo.processInfo.arguments.contains("--export-app-store-teaser")
            || ProcessInfo.processInfo.arguments.contains("--export-menu-tour")
            || ProcessInfo.processInfo.arguments.contains("--export-premium-tour") {
            GameSettings.gameSoundsEnabled = true
            GameSettings.spokenSumsEnabled = false
            GameSettings.capsTrophiesAtThirty = true
            if ProcessInfo.processInfo.arguments.contains("--export-menu-tour") {
                let defaults = UserDefaults.standard
                GameSettings.characterID = CharacterCatalog.freeCharacterID
                GameSettings.playerName = "Jumping Fox"
                GameSettings.premiumUnlockedCache = true
                PremiumStore.shared.preparePromoUnlockedState()
                defaults.set(MenuFilter.addition.rawValue, forKey: "ui.menuFilter")
                defaults.set(PracticeMode.order.rawValue, forKey: "ui.menuMode")
                defaults.set(ChallengeCategory.superBasic.rawValue,
                             forKey: "ui.supermixCategory")
                LanguageManager.shared.override = .english
            } else if ProcessInfo.processInfo.arguments.contains("--export-premium-tour") {
                // Simulator audio can stall while recordVideo captures a long
                // SwiftUI scroll. The master adds the bundled soundtrack, so
                // keep this native visual take silent and deterministic.
                GameSettings.gameSoundsEnabled = false
                GameSettings.characterID = CharacterCatalog.freeCharacterID
                GameSettings.playerName = "ثعلب"
                CharacterUnlockStore.trophyTotal = 0
                GameSettings.premiumUnlockedCache = false
                PremiumStore.shared.preparePromoLockedState()
                let defaults = UserDefaults.standard
                defaults.set(MenuFilter.addition.rawValue, forKey: "ui.menuFilter")
                defaults.set(PracticeMode.order.rawValue, forKey: "ui.menuMode")
                defaults.set(ChallengeCategory.superBasic.rawValue,
                             forKey: "ui.supermixCategory")
                LanguageManager.shared.override = .english
            }
            return
        }
#endif
        // Capture the first launch date independently of when the player first
        // finishes a game; later review phases use age since installation.
        _ = ReviewRequestCoordinator.shared
        PromotedPurchaseCoordinator.shared.startListening()
        // Bring iCloud sync online at launch — not just once the home screen
        // appears. On a fresh reinstall the app opens on the onboarding welcome
        // screen (which never touches ProgressSync), so without this the saved
        // name is never pulled back from iCloud and the name field stays empty.
        // With it, the restore runs and @AppStorage fills the field the moment
        // iCloud delivers the name.
        _ = ProgressSync.shared
        // Install the notification delegate and rebuild the reminder schedule
        // for players who granted permission in an earlier session.
        NotificationManager.shared.start()
    }

    var body: some Scene {
        WindowGroup {
#if TRAILER_EXPORT
            if isExportingGameplayTrailer {
                PromoTrailerView()
            } else if isExportingMenuTour {
                ContentView(promoMenuTrailer: true)
                    .environment(\.locale, language.locale)
                    .environment(\.layoutDirection, language.layoutDirection)
                    .preferredColorScheme(.light)
                    .persistentSystemOverlays(.hidden)
                    .statusBarHidden(true)
            } else if isExportingPremiumTour {
                PremiumPromoTourView()
                    .environment(\.locale, language.locale)
                    .environment(\.layoutDirection, language.layoutDirection)
                    .preferredColorScheme(.light)
                    .persistentSystemOverlays(.hidden)
                    .statusBarHidden(true)
            } else {
                normalRoot
            }
#else
            normalRoot
#endif
        }
    }

    private var normalRoot: some View {
            ZStack {
                if onboardingComplete {
                    ContentView()
                        .transition(.opacity)
                } else {
                    OnboardingView()
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.45), value: onboardingComplete)
            // Re-renders every `Text` (and formats numbers) when the language
            // changes; combined with the bundle redirection this makes the
            // switch instant, no restart required.
            .environment(\.locale, language.locale)
            .environment(\.layoutDirection, language.layoutDirection)
            // Palettes and copy are authored for light surfaces. Without this,
            // Dark Mode turns system fills black and inverts `.primary` /
            // `.secondary` labels against those same light colours.
            .preferredColorScheme(.light)
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
                .gameEnvironment()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
    }
}
