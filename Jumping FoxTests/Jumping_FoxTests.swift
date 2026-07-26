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

    override func setUp() {
        super.setUp()
        suiteName = "ReviewRequestCoordinatorTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
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
