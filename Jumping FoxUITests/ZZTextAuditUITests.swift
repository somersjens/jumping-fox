//
//  ZZTextAuditUITests.swift
//  Jumping FoxUITests
//
//  TEMPORARY pre-release audit harness. Walks the app's surfaces and writes a
//  screenshot per step so long translations can be eyeballed for truncation.
//  Delete after the audit.
//

import XCTest

final class ZZTextAuditUITests: XCTestCase {

    /// Where the PNGs land inside the simulator's data container.
    private static let outDir = "/tmp/foxaudit"

    private var langCode: String {
        ProcessInfo.processInfo.environment["AUDIT_LANG"] ?? "en"
    }

    override func setUpWithError() throws {
        continueAfterFailure = true
        try? FileManager.default.createDirectory(atPath: Self.outDir,
                                                withIntermediateDirectories: true)
    }

    private func makeApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(\(langCode))",
                              "-AppleLocale", langCode,
                              // A language pinned in Settings earlier would
                              // otherwise win over the device language.
                              "-settings.languageOverride", langCode]
        app.launch()
        return app
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let png = XCUIScreen.main.screenshot().pngRepresentation
        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        attachment.name = "\(langCode)_\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
        // Best effort: also try the container, harmless if the sandbox says no.
        let path = NSTemporaryDirectory() + "\(langCode)_\(name).png"
        try? png.write(to: URL(fileURLWithPath: path))
        print("AUDIT_SHOT \(path)")
    }

    /// Tap a point given as a fraction of the screen.
    private func tap(_ app: XCUIApplication, _ x: Double, _ y: Double) {
        app.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y)).tap()
        sleep(2)
    }

    // MARK: The walk

    @MainActor
    func testAuditMenuSurfaces() throws {
        let app = makeApp()
        sleep(4)
        shot(app, "01_menu")

        // Supermix filter (the star) — its label is the longest of the six.
        tap(app, 0.868, 0.280)
        shot(app, "02_supermix")

        // Back to a normal filter so later steps start from a known state.
        tap(app, 0.128, 0.280)
        sleep(1)

        // Game options: three toggle rows whose labels sit between an icon,
        // an info button and a switch — the tightest text boxes in the app.
        tap(app, 0.50, 0.399)
        shot(app, "03_options")

        // Each info button opens a popup with the longest body copy in the app.
        tap(app, 0.43, 0.445)
        shot(app, "04_info_capAtGoal")
        tap(app, 0.5, 0.80)
        sleep(1)
        tap(app, 0.40, 0.494)
        shot(app, "05_info_unlimitedLives")
        tap(app, 0.5, 0.80)
        sleep(1)
        tap(app, 0.37, 0.542)
        shot(app, "06_info_helperMode")
    }

    @MainActor
    func testAuditCharacterAndStreak() throws {
        let app = makeApp()
        sleep(4)

        // Character picker via the avatar.
        tap(app, 0.162, 0.144)
        shot(app, "05_characters")
        tap(app, 0.5, 0.06)   // dismiss
        sleep(1)

        // Streak / daily-goal surface.
        tap(app, 0.793, 0.145)
        shot(app, "06_streak")
    }

    @MainActor
    func testAuditPremium() throws {
        let app = makeApp()
        sleep(4)
        app.swipeUp()
        sleep(1)
        app.swipeUp()
        sleep(1)
        shot(app, "07_menu_bottom")
        // The premium banner sits at the very bottom of the level grid.
        tap(app, 0.50, 0.94)
        shot(app, "08_premium")
        app.swipeUp()
        sleep(1)
        shot(app, "09_premium_scrolled")
    }

    /// Requires a freshly installed app (uninstall on the host first), so the
    /// onboarding actually runs.
    @MainActor
    func testAuditOnboarding() throws {
        let app = makeApp()
        sleep(4)
        shot(app, "20_onboarding_name")
        // Continue past the name field.
        tap(app, 0.5, 0.62)
        shot(app, "21_onboarding_subject")
        // Pick Supermix — the longest of the six topic titles.
        tap(app, 0.5, 0.75)
        shot(app, "22_onboarding_level")
    }

    @MainActor
    func testAuditGameplay() throws {
        let app = makeApp()
        sleep(4)

        // Level 1 → mode intro card → level intro card → gameplay.
        tap(app, 0.182, 0.509)
        shot(app, "10_modeIntro")
        tap(app, 0.5, 0.90)
        shot(app, "11_levelIntro")
        tap(app, 0.5, 0.5)
        sleep(3)
        shot(app, "12_gameplay")

        // Pause via the HUD control in the top corner.
        tap(app, 0.93, 0.055)
        shot(app, "13_paused")
    }

}
