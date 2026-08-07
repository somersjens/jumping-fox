//
//  Prewarm.swift
//  Jumping Fox
//
//  First-use costs that would otherwise land in the middle of the guided
//  tutorial, paid off early — while the player is still reading a welcome
//  screen or a level's start card, where a few milliseconds cost nothing.
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif

enum Prewarm {
    /// Every SF Symbol the tutorial and the play HUD raise mid-lesson. The
    /// first symbol the app draws pays for loading the symbol database and
    /// its font; the ones below are all first drawn at a moment where that
    /// hitch is visible — the cue popping out beside the question mark, or an
    /// instruction capsule swapping its icon as a step is completed.
    private static let tutorialSymbols = [
        "arrow.down.left.circle",   // "tap the question mark" cue
        "arrow.left.arrow.right",   // step 1: move left and right
        "arrow.up.circle.fill",     // the plain instruction steps
        "hand.tap.fill",            // step 6: tap the question mark
        "heart.fill",               // steps 7 and 10: hearts
        "star.fill",                // step 11: the star
        "trophy.fill",              // score HUD and the start card
        "graduationcap.fill",       // tutorial button on the start card
        "text.bubble.fill",
        "music.note"
    ]

    private static var hasWarmedSymbols = false

    /// Rasterizes the tutorial's glyphs once, off the main thread. Calling it
    /// again is free, so every screen that could precede a tutorial is welcome
    /// to ask for it.
    static func tutorialGlyphs() {
#if canImport(UIKit)
        guard !hasWarmedSymbols else { return }
        hasWarmedSymbols = true
        let names = tutorialSymbols
        DispatchQueue.global(qos: .utility).async {
            // A heavy, reasonably large configuration: the sizes actually used
            // are smaller, and the shared symbol/font machinery each lookup
            // loads is the expensive part, not the pixels.
            let configuration = UIImage.SymbolConfiguration(pointSize: 34, weight: .black)
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: 48, height: 48))
            for name in names {
                guard let symbol = UIImage(systemName: name, withConfiguration: configuration)
                else { continue }
                // Drawing forces the glyph all the way through to pixels; the
                // result itself is not needed, only the warmed caches.
                _ = renderer.image { _ in symbol.draw(at: .zero) }
            }
        }
#endif
    }
}
