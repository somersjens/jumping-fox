//
//  Jumping_FoxTests.swift
//  Jumping FoxTests
//
//  Created by Jens Somers on 17/07/2026.
//

import XCTest
@testable import Jumping_Fox

final class Jumping_FoxTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var previousLifeMode: LifeMode!
    private var previousCapSetting: Bool!
    private var previousHelperSetting: Bool!
    private var previousTrophyTotal: Int!

    override func setUp() {
        super.setUp()
        previousLifeMode = GameSettings.lifeMode
        previousCapSetting = GameSettings.capsTrophiesAtThirty
        previousHelperSetting = GameSettings.answerHelperEnabled
        previousTrophyTotal = CharacterUnlockStore.trophyTotal
        GameSettings.lifeMode = .three
        GameSettings.capsTrophiesAtThirty = true
        GameSettings.answerHelperEnabled = false
        suiteName = "ReviewRequestCoordinatorTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        GameSettings.lifeMode = previousLifeMode
        GameSettings.capsTrophiesAtThirty = previousCapSetting
        GameSettings.answerHelperEnabled = previousHelperSetting
        CharacterUnlockStore.trophyTotal = previousTrophyTotal
        super.tearDown()
    }

    func testTrophyCharacterThresholdsAndPremiumExclusives() {
        XCTAssertEqual(CharacterUnlockStore.threshold(for: "frog"), 500)
        XCTAssertEqual(CharacterUnlockStore.threshold(for: "penguin"), 1_500)
        XCTAssertEqual(CharacterUnlockStore.threshold(for: "bunny"), 3_000)
        XCTAssertEqual(CharacterUnlockStore.threshold(for: "dog"), 5_000)
        XCTAssertNil(CharacterUnlockStore.threshold(for: "lion"))

        CharacterUnlockStore.trophyTotal = 499
        XCTAssertFalse(CharacterUnlockStore.canUse(characterID: "frog", isPremium: false))
        CharacterUnlockStore.trophyTotal = 500
        XCTAssertTrue(CharacterUnlockStore.canUse(characterID: "frog", isPremium: false))
        XCTAssertFalse(CharacterUnlockStore.canUse(characterID: "lion", isPremium: false))
        XCTAssertTrue(CharacterUnlockStore.canUse(characterID: "lion", isPremium: true))
        XCTAssertTrue(CharacterUnlockStore.canUse(characterID: "fox", isPremium: false))
    }

    func testHelperAnswerColorsContrastWithGreenAndRedCharacters() {
        let frog = CharacterCatalog.character(id: "frog")
        let crab = CharacterCatalog.character(id: "crab")
        let fox = CharacterCatalog.character(id: "fox")

        XCTAssertTrue(GameColors.helperCorrect(for: frog).isEqual(GameColors.contrastViolet))
        XCTAssertTrue(GameColors.helperWrong(for: crab).isEqual(fox.skPrimary))
        XCTAssertTrue(GameColors.helperCorrect(for: fox).isEqual(GameColors.correctGreen))
        XCTAssertTrue(GameColors.helperWrong(for: fox).isEqual(GameColors.wrongRed))
    }

    func testCharacterArtworkScaleCompensatesForPenguinAndOctopus() {
        for character in CharacterCatalog.all {
            let usesLargerSourceArtwork = character.id == "penguin" || character.id == "octopus"
            XCTAssertEqual(character.selectorArtworkScale, usesLargerSourceArtwork ? 1 : 1.1)
            XCTAssertEqual(character.gameplayArtworkScale, usesLargerSourceArtwork ? 0.9 : 1)
        }
    }

    func testMaximumScoreStagesCompletionBeforePresentingGameOver() {
        let level = LevelConfig(category: .addition, index: 1, cardNumber: "1")
        let state = GameState(level: level)
        let maximum = ProgressStore.maximumTrophies(for: level)
        var reachedMaximum = false

        for _ in 0..<(maximum + 2) {
            if state.answeredCorrectly() {
                reachedMaximum = true
                break
            }
        }

        XCTAssertTrue(reachedMaximum)
        XCTAssertEqual(state.score, maximum)
        XCTAssertTrue(state.isCompletingLevel)
        XCTAssertFalse(state.isGameOver)
        XCTAssertNil(state.gameOverReason)

        // The celebration handoff is input-locked: a duplicate landing cannot
        // add points or prematurely publish the result card.
        XCTAssertFalse(state.answeredCorrectly())
        XCTAssertEqual(state.score, maximum)
        XCTAssertFalse(state.canRevealAnswer)
    }

    func testDisabledScoreCapKeepsPlayingPastMaximum() {
        GameSettings.capsTrophiesAtThirty = false
        let level = LevelConfig(category: .addition, index: 1, cardNumber: "1")
        let state = GameState(level: level)
        let maximum = ProgressStore.maximumTrophies(for: level)

        while state.score < maximum {
            XCTAssertFalse(state.answeredCorrectly())
        }

        XCTAssertFalse(state.isCompletingLevel)
        XCTAssertFalse(state.isGameOver)
        XCTAssertTrue(state.isPastScoreboardCap)
    }

    func testThresholdIsNotAnExactGameNumber() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let coordinator = ReviewRequestCoordinator(defaults: defaults, now: now)

        playGames(11, with: coordinator, qualifyingLastGame: true)

        XCTAssertTrue(coordinator.menuReturnDidSettle(now: now))
    }

    func testRequiresThreeGamesInCurrentSessionAndFreshQualifiedReturn() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        defaults.set(9, forKey: "review.completedGames")
        let coordinator = ReviewRequestCoordinator(defaults: defaults, now: now)

        coordinator.recordCompletedGame(isNewHighScore: true, score: 10, maximumScore: 20)
        XCTAssertFalse(coordinator.menuReturnDidSettle(now: now))

        coordinator.recordCompletedGame(isNewHighScore: false, score: 0, maximumScore: 20)
        coordinator.recordCompletedGame(isNewHighScore: false, score: 0, maximumScore: 20)
        XCTAssertFalse(coordinator.menuReturnDidSettle(now: now))
    }

    func testHalfwayRequirementRoundsUpForOddMaximum() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        defaults.set(9, forKey: "review.completedGames")
        let coordinator = ReviewRequestCoordinator(defaults: defaults, now: now)

        coordinator.recordCompletedGame(isNewHighScore: false, score: 0, maximumScore: 21)
        coordinator.recordCompletedGame(isNewHighScore: false, score: 0, maximumScore: 21)
        coordinator.recordCompletedGame(isNewHighScore: true, score: 10, maximumScore: 21)
        XCTAssertFalse(coordinator.menuReturnDidSettle(now: now))

        coordinator.recordCompletedGame(isNewHighScore: true, score: 11, maximumScore: 21)
        XCTAssertTrue(coordinator.menuReturnDidSettle(now: now))
    }

    func testPersistsUsedPhasesAndEnforcesCooldownAcrossSessions() {
        let day: TimeInterval = 24 * 60 * 60
        let installed = Date(timeIntervalSince1970: 1_000_000)
        let firstSession = ReviewRequestCoordinator(defaults: defaults, now: installed)
        playGames(10, with: firstSession, qualifyingLastGame: true)
        XCTAssertTrue(firstSession.menuReturnDidSettle(now: installed))
        XCTAssertFalse(firstSession.menuReturnDidSettle(now: installed))

        let secondSession = ReviewRequestCoordinator(defaults: defaults, now: installed)
        playGames(20, with: secondSession, qualifyingLastGame: true)
        XCTAssertFalse(secondSession.menuReturnDidSettle(now: installed + 6 * day))

        let thirdSession = ReviewRequestCoordinator(defaults: defaults, now: installed)
        playGames(3, with: thirdSession, qualifyingLastGame: true)
        XCTAssertTrue(thirdSession.menuReturnDidSettle(now: installed + 7 * day))
        XCTAssertEqual(defaults.array(forKey: "review.usedPhases") as? [Int], [10, 30])
    }

    func testDiscardPreventsOpportunityLeakingIntoAnotherLevel() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        defaults.set(9, forKey: "review.completedGames")
        let coordinator = ReviewRequestCoordinator(defaults: defaults, now: now)
        playGames(3, with: coordinator, qualifyingLastGame: true)

        coordinator.discardPendingReturn()

        XCTAssertFalse(coordinator.menuReturnDidSettle(now: now))
    }

    private func playGames(
        _ count: Int,
        with coordinator: ReviewRequestCoordinator,
        qualifyingLastGame: Bool
    ) {
        for index in 0..<count {
            let qualifies = qualifyingLastGame && index == count - 1
            coordinator.recordCompletedGame(
                isNewHighScore: qualifies,
                score: qualifies ? 10 : 0,
                maximumScore: 20
            )
        }
    }
}
