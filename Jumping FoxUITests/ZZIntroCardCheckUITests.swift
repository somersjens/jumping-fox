//
//  ZZIntroCardCheckUITests.swift
//  Jumping FoxUITests
//
//  TEMPORARY. Screenshots the level start card in a few languages so the two
//  status labels can be checked for truncation. Delete after the check.
//

import XCTest

final class ZZIntroCardCheckUITests: XCTestCase {

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func openIntroCard(language: String, unlimitedLives: Bool, helper: Bool) {
        let app = XCUIApplication()
        app.launchArguments = [
            "-AppleLanguages", "(\(language))",
            "-AppleLocale", language,
            "-settings.languageOverride", language,
            // Skip the live tutorial: it replaces the start card.
            "-tutorial.started", "YES",
            "-tutorial.complete", "YES",
            "-tutorial.lastCompletedStep", "11",
            "-onboarding.complete", "YES",
            "-settings.lifeMode", unlimitedLives ? "unlimited" : "three",
            "-settings.answerHelper", helper ? "YES" : "NO"
        ]
        app.launch()
        sleep(4)
        // First level in the grid.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.182, dy: 0.509)).tap()
        sleep(2)
        shot("\(language)_lives\(unlimitedLives ? "Off" : "On")_helper\(helper ? "On" : "Off")")
        app.terminate()
        sleep(1)
    }

    @MainActor
    func testIntroCardLabels() throws {
        for lang in ["nl", "el", "sl", "ka"] {
            openIntroCard(language: lang, unlimitedLives: false, helper: false)
            openIntroCard(language: lang, unlimitedLives: true, helper: true)
        }
    }
}
