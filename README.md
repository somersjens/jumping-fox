# Jumping Fox 🦊

A Doodle Jump–inspired math game for iOS. An animal on a spring bounces automatically; steer with tilt (or touch) and land on the platform showing the correct answer to the question at the bottom.

## Challenge categories

Twelve categories behind a cyclic arrow selector: Addition, Addition Mix, Subtraction, Subtraction Mix, Times Tables, Tables Mix, Fractions, Fractions Mix, Percentages, Percentages Mix, Mix, Supermix. Plain variants train one concept per level; mix variants only combine skills that were already introduced. All questions come from explicit rules (allowed numbers, min/max result, term count, question form) — never pure randomness.

## Goals, playtime & streak

Adjustable daily (default 5 min) and weekly (default 35 min) play goals. Only *active* playtime counts (foreground + recent interaction, 45 s idle limit). Per-day records store date, seconds and that day's goal, so changing the goal never rewrites history; the streak is derived from those records.

## Gameplay

- Sparse, Doodle Jump–style platforms with open air between them
- Horizontal screen wrapping: leave one side, appear on the other (velocity preserved)
- Most platforms are neutral — only a few show answers (max 3 at the start, more as you climb)
- Falling below the screen is game over
- Questions in order per table (7×1, 7×2, … 7×12, then repeat)
- Super Jump button appears when the correct answer isn't reachable
- Edge grazes on wrong platforms bounce harmlessly — only clear landings count
- Tilt controls (device) with touch-drag fallback (simulator)
- Optional answer helper: correct platforms green, wrong ones red

## Modes & scores

- Life modes: 1 life, 3 lives, or Unlimited (Premium)
- High scores are tracked separately per table **and** per life mode

## Premium (one-time in-app purchase)

- Multiplication tables 13–100
- Unlimited lives
- 10 characters (fox, frog, penguin, pig, whale, lion, octopus, crab, turtle, bear)
- A matching color theme for each character

## Structure

- `Jumping_FoxApp.swift` — app entry point
- `ContentView.swift` — home screen (tables, premium banner, gear → settings)
- `SettingsView.swift` — lives, answer helper, character selector
- `PremiumView.swift` — purchase sheet
- `PremiumStore.swift` — StoreKit 2 store
- `Theme.swift` — character catalog and color themes
- `GameView.swift` — game HUD and game over overlay (SwiftUI)
- `GameScene.swift` — gameplay (SpriteKit)
- `GameState.swift` — question engine, life modes, high score persistence
- `Products.storekit` — local StoreKit test configuration

## Run

Open `Jumping Fox.xcodeproj` in Xcode and run on an iPhone simulator or device.

To test the Premium purchase locally: edit the scheme (Product → Scheme → Edit Scheme → Run → Options) and set **StoreKit Configuration** to `Products.storekit`.

## Planned

Addition, subtraction, fractions, percentages, mixed questions.
