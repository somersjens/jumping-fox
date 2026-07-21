//
//  Localization.swift
//  Jumping Fox
//
//  Runtime language switching + the little flag-and-chevron picker shown on
//  the welcome screens and the premium menu.
//
//  SwiftUI's `Text` resolves its strings from the *main bundle*, not from the
//  environment locale, so changing `\.locale` alone is not enough to swap the
//  language while the app is running. We install a tiny Bundle subclass that
//  redirects `localizedString(...)` to a chosen `.lproj`. Changing the
//  environment locale at the root then re-renders every `Text`, which now
//  reads the redirected strings — a live, no-restart language change.
//

import SwiftUI
import Combine
import ObjectiveC

// MARK: - Supported languages

/// The languages the app is actually localized into (see the string catalog).
enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case dutch = "nl"

    var id: String { rawValue }

    /// A little flag for the picker. English uses the UK flag.
    var flag: String {
        switch self {
        case .english: return "🇬🇧"
        case .dutch: return "🇳🇱"
        }
    }

    /// Language names are conventionally shown in their own language.
    var displayName: String {
        switch self {
        case .english: return "English"
        case .dutch: return "Nederlands"
        }
    }
}

// MARK: - Language manager

/// Holds the user's language choice. `nil` means "follow the device", which is
/// the default at first launch; picking a flag pins the app to that language.
final class LanguageManager: ObservableObject {
    static let shared = LanguageManager()
    private static let overrideKey = "settings.languageOverride"

    @Published var override: AppLanguage? {
        didSet {
            let defaults = UserDefaults.standard
            if let override {
                defaults.set(override.rawValue, forKey: Self.overrideKey)
            } else {
                defaults.removeObject(forKey: Self.overrideKey)
            }
            Bundle.setLanguage(override?.rawValue)
        }
    }

    private init() {
        if let raw = UserDefaults.standard.string(forKey: Self.overrideKey) {
            override = AppLanguage(rawValue: raw)
        }
        Bundle.setLanguage(override?.rawValue)
    }

    /// The language actually shown: the pinned choice, or the device's best
    /// match among the languages we support.
    var effective: AppLanguage {
        if let override { return override }
        let preferred = Bundle.main.preferredLocalizations.first ?? "en"
        return preferred.hasPrefix("nl") ? .dutch : .english
    }

    /// Drives the environment locale, which both formats numbers correctly and
    /// forces every `Text` to re-render when the language changes.
    var locale: Locale { Locale(identifier: effective.rawValue) }

    /// The `.lproj` bundle for the language currently shown. `String(localized:)`
    /// ignores the runtime bundle redirection used for `Text`, so any string
    /// resolved in code must be pointed at this bundle explicitly (see `L`).
    var bundle: Bundle {
        if let path = Bundle.main.path(forResource: effective.rawValue, ofType: "lproj"),
           let localized = Bundle(path: path) {
            return localized
        }
        return .main
    }

    func select(_ language: AppLanguage) {
        withAnimation(.easeInOut(duration: 0.2)) { override = language }
    }
}

/// Resolve a localized string in the language the user has chosen. Use this
/// everywhere instead of `String(localized:)`, which always follows the system
/// language regardless of the in-app switch.
func L(_ key: String.LocalizationValue) -> String {
    let manager = LanguageManager.shared
    return String(localized: key, bundle: manager.bundle, locale: manager.locale)
}

// MARK: - Bundle redirection (the mechanism behind a live switch)

private var languageBundleKey: UInt8 = 0

/// A Bundle that, when asked for a localized string, forwards the request to a
/// specific `.lproj` bundle if one has been set.
private final class LanguageBundle: Bundle, @unchecked Sendable {
    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        if let redirected = objc_getAssociatedObject(self, &languageBundleKey) as? Bundle {
            return redirected.localizedString(forKey: key, value: value, table: tableName)
        }
        return super.localizedString(forKey: key, value: value, table: tableName)
    }
}

extension Bundle {
    /// Swap `Bundle.main`'s class exactly once so it can redirect lookups.
    private static let installLanguageBundle: Void = {
        object_setClass(Bundle.main, LanguageBundle.self)
    }()

    /// Point `Bundle.main` at a language's `.lproj`, or pass `nil` to fall back
    /// to the device's normal resolution.
    static func setLanguage(_ language: String?) {
        _ = installLanguageBundle
        let target: Bundle?
        if let language,
           let path = Bundle.main.path(forResource: language, ofType: "lproj") {
            target = Bundle(path: path)
        } else {
            target = nil
        }
        objc_setAssociatedObject(Bundle.main, &languageBundleKey, target, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
}

// MARK: - Liquid glass styling with an iOS 16 fallback

private struct LiquidGlassCapsule: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(in: Capsule())
        } else {
            content
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.4), lineWidth: 0.8))
                .shadow(color: .black.opacity(0.12), radius: 5, y: 2)
        }
    }
}

extension View {
    /// Liquid-glass capsule background (with an iOS 16 material fallback),
    /// shared by the language picker and the onboarding back button so they
    /// match exactly.
    func liquidGlassCapsule() -> some View { modifier(LiquidGlassCapsule()) }
}

// MARK: - The picker

/// A flag with a chevron. Tap to choose a language; the current one is ticked.
struct LanguagePicker: View {
    @ObservedObject private var language = LanguageManager.shared

    /// Colour for the chevron so it can sit on light or dark backgrounds.
    var tint: Color = .secondary
    /// Callers can opt into the larger, touch-friendly iPad treatment while
    /// preserving the compact control on iPhone.
    var scale: CGFloat = 1

    var body: some View {
        Menu {
            ForEach(AppLanguage.allCases) { option in
                Button {
                    language.select(option)
                } label: {
                    if language.effective == option {
                        Label("\(option.flag)  \(option.displayName)", systemImage: "checkmark")
                    } else {
                        Text("\(option.flag)  \(option.displayName)")
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Text(language.effective.flag)
                    .font(.system(size: 20 * scale))
                Image(systemName: "chevron.down")
                    .font(.system(size: 10 * scale, weight: .bold))
                    .foregroundStyle(tint)
            }
            .padding(.horizontal, 12 * scale)
            .padding(.vertical, 8 * scale)
            .liquidGlassCapsule()
            .contentShape(Capsule())
        }
        .accessibilityLabel(Text("language.select"))
    }
}
