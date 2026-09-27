# Jumping Fox App Store teaser

The trailer is rendered from the native SpriteKit game using the compile-only
`TRAILER_EXPORT` condition. Production builds never enter the deterministic
capture route.

## Final masters

- `exports/jumping-fox-app-store-teaser-886x1920.mp4` — 886 × 1920, 15 seconds, 30 fps, audio
- `exports/jumping-fox-app-store-teaser-1200x1600.mp4` — 1200 × 1600, ~17.7 seconds, 30 fps, audio
- `exports/jumping-fox-app-store-menu-tour-886x1920.mp4` — 886 × 1920, 23.4 seconds, 30 fps, audio
- `exports/jumping-fox-app-store-menu-tour-1200x1600.mp4` — 1200 × 1600, 23.4 seconds, 30 fps, audio
- `exports/jumping-fox-app-store-premium-tour-886x1920.mp4` — 886 × 1920, 21.2 seconds, 30 fps, audio
- `exports/jumping-fox-app-store-premium-tour-1200x1600.mp4` — 1200 × 1600, 21.2 seconds, 30 fps, audio

The iPad cut is longer because the tablet route takes more time; both masters keep the end icon on screen for the same hold.

The simulator source captures and event traces are kept in `captures/`. Rebuild
both masters from those canonical sources with:

```sh
./promo/render-masters.sh
```

The menu tour uses the real adaptive home menu on an island-free iPhone 17e and
a 13-inch iPad Pro. The iPad hierarchy is laid out directly in visible screen
points: the capture route does not shrink the SwiftUI canvas and enlarge it
again. `render-menu-masters.sh` therefore only normalizes timing, aspect ratio,
audio and output dimensions. This keeps the capture reusable for another game
whose production menu has different margins or component sizes. Its
deterministic route is:

`Order → Random → Mixed → − → × → ÷ → % → ★ → all four ★ groups → + / Order`

Every selection owns one 1.8-second slot. The promo-only driver opens the
English description on the selecting tap, animates the fox, alternates the
total with the remaining trophies for the next character, and injects a
memory-only progression curve weighted toward completed lower levels. Capture
fresh native simulator sources and rebuild their App Store masters with:

```sh
./promo/capture-menu-tour.sh
./promo/render-menu-masters.sh
```

The Premium tour starts from zero trophies with Premium locked, previews every
character and returns to the fox. It then opens the language list, scrolls
directly to Arabic to demonstrate the mirrored interface, closes to
the complete zero-progress Arabic home menu, reopens the sheet, and returns to
English to complete the loop. The promo picker uses the same Liquid Glass
visual language as the in-game control. Capture and render it with:

```sh
./promo/capture-premium-tour.sh
./promo/render-premium-masters.sh
```

The masters use the app's bundled music and sound effects. Their visuals come
from the native game scene, including production art, characters, physics,
questions, power-ups, score transitions, and completion flight.

## Verification

```sh
xcrun swift -framework AVFoundation promo/video-info.swift promo/exports/*.mp4
xcrun swift -framework AVFoundation promo/verify-video.swift promo/exports/*.mp4
```

The trailer-only path is compile-isolated and launches only when the app is
built with `TRAILER_EXPORT` and run with `--export-app-store-teaser`.
The menu tour uses the same isolation and the `--export-menu-tour` argument.
The Premium tour uses `--export-premium-tour`.
