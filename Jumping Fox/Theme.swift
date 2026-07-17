//
//  Theme.swift
//  Jumping Fox
//
//  Character catalog: 10 animals, each with a clearly different
//  color and a matching visual theme for the whole game.
//

import SwiftUI
import SpriteKit

struct AnimalCharacter: Identifiable, Equatable {
    let id: String
    let name: String
    let emoji: String

    // Color components (0–1), shared by SwiftUI and SpriteKit.
    let primaryRGB: (Double, Double, Double)
    let deepRGB: (Double, Double, Double)
    let skyRGB: (Double, Double, Double)
    let tintRGB: (Double, Double, Double)

    static func == (lhs: AnimalCharacter, rhs: AnimalCharacter) -> Bool {
        lhs.id == rhs.id
    }

    // SwiftUI
    var color: Color { Color(red: primaryRGB.0, green: primaryRGB.1, blue: primaryRGB.2) }
    var deepColor: Color { Color(red: deepRGB.0, green: deepRGB.1, blue: deepRGB.2) }
    var skyColor: Color { Color(red: skyRGB.0, green: skyRGB.1, blue: skyRGB.2) }
    var tintColor: Color { Color(red: tintRGB.0, green: tintRGB.1, blue: tintRGB.2) }

    // SpriteKit
    var skPrimary: SKColor { SKColor(red: primaryRGB.0, green: primaryRGB.1, blue: primaryRGB.2, alpha: 1) }
    var skDeep: SKColor { SKColor(red: deepRGB.0, green: deepRGB.1, blue: deepRGB.2, alpha: 1) }
    var skSky: SKColor { SKColor(red: skyRGB.0, green: skyRGB.1, blue: skyRGB.2, alpha: 1) }
}

enum CharacterCatalog {
    /// The fox is free; the rest are part of Premium.
    static let freeCharacterID = "fox"

    static let all: [AnimalCharacter] = [
        AnimalCharacter(id: "fox", name: "Fox", emoji: "🦊",
                        primaryRGB: (0.96, 0.55, 0.14), deepRGB: (0.80, 0.33, 0.04),
                        skyRGB: (1.00, 0.94, 0.86), tintRGB: (1.00, 0.90, 0.78)),
        AnimalCharacter(id: "frog", name: "Frog", emoji: "🐸",
                        primaryRGB: (0.36, 0.70, 0.29), deepRGB: (0.16, 0.47, 0.18),
                        skyRGB: (0.92, 0.98, 0.89), tintRGB: (0.84, 0.95, 0.80)),
        AnimalCharacter(id: "penguin", name: "Penguin", emoji: "🐧",
                        primaryRGB: (0.35, 0.68, 0.88), deepRGB: (0.13, 0.42, 0.65),
                        skyRGB: (0.90, 0.96, 1.00), tintRGB: (0.80, 0.91, 1.00)),
        AnimalCharacter(id: "pig", name: "Pig", emoji: "🐷",
                        primaryRGB: (0.95, 0.56, 0.69), deepRGB: (0.78, 0.29, 0.45),
                        skyRGB: (1.00, 0.93, 0.96), tintRGB: (1.00, 0.86, 0.92)),
        AnimalCharacter(id: "whale", name: "Whale", emoji: "🐳",
                        primaryRGB: (0.25, 0.45, 0.85), deepRGB: (0.12, 0.25, 0.60),
                        skyRGB: (0.89, 0.93, 1.00), tintRGB: (0.80, 0.87, 1.00)),
        AnimalCharacter(id: "lion", name: "Lion", emoji: "🦁",
                        primaryRGB: (0.93, 0.75, 0.18), deepRGB: (0.72, 0.52, 0.05),
                        skyRGB: (1.00, 0.97, 0.85), tintRGB: (1.00, 0.93, 0.72)),
        AnimalCharacter(id: "octopus", name: "Octopus", emoji: "🐙",
                        primaryRGB: (0.62, 0.40, 0.80), deepRGB: (0.42, 0.22, 0.60),
                        skyRGB: (0.96, 0.92, 1.00), tintRGB: (0.91, 0.84, 1.00)),
        AnimalCharacter(id: "crab", name: "Crab", emoji: "🦀",
                        primaryRGB: (0.88, 0.30, 0.25), deepRGB: (0.65, 0.15, 0.12),
                        skyRGB: (1.00, 0.92, 0.90), tintRGB: (1.00, 0.85, 0.82)),
        AnimalCharacter(id: "turtle", name: "Turtle", emoji: "🐢",
                        primaryRGB: (0.20, 0.65, 0.60), deepRGB: (0.08, 0.45, 0.42),
                        skyRGB: (0.89, 0.98, 0.96), tintRGB: (0.79, 0.95, 0.92)),
        AnimalCharacter(id: "bear", name: "Bear", emoji: "🐻",
                        primaryRGB: (0.62, 0.44, 0.28), deepRGB: (0.42, 0.28, 0.16),
                        skyRGB: (0.97, 0.93, 0.88), tintRGB: (0.93, 0.87, 0.79))
    ]

    static func character(id: String) -> AnimalCharacter {
        all.first { $0.id == id } ?? all[0]
    }

    /// The currently selected character (falls back to the fox
    /// if a premium character is selected without Premium).
    static func current(isPremium: Bool) -> AnimalCharacter {
        let selected = character(id: GameSettings.characterID)
        if selected.id != freeCharacterID && !isPremium {
            return character(id: freeCharacterID)
        }
        return selected
    }
}
