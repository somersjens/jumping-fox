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

    func testNextCharacterMilestoneUsesADecreasingRemainingCount() {
        let first = CharacterUnlockStore.nextMilestone(after: 1)
        XCTAssertEqual(first?.characterID, "frog")
        XCTAssertEqual(
            first.map { CharacterUnlockStore.remainingTrophies(after: 1, until: $0) },
            499
        )

        let second = CharacterUnlockStore.nextMilestone(after: 500)
        XCTAssertEqual(second?.characterID, "penguin")
        XCTAssertEqual(
            second.map { CharacterUnlockStore.remainingTrophies(after: 500, until: $0) },
            1_000
        )

        XCTAssertNil(CharacterUnlockStore.nextMilestone(after: 5_000))
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

    func testSpokenMathStaysCompactAndLocalized() {
        XCTAssertEqual(AppAudio.spokenText(for: "3 + 4 = ?", languageCode: "nl"),
                       "3 plus 4")
        XCTAssertEqual(AppAudio.spokenText(for: "12 − 5 = ?", languageCode: "de"),
                       "12 minus 5")
        XCTAssertEqual(AppAudio.spokenText(for: "6 × 7 = ?", languageCode: "fr"),
                       "6 fois 7")
        XCTAssertEqual(AppAudio.spokenText(for: "3/4 × 8 = ?", languageCode: "en"),
                       "3 of 4 parts times 8")
        XCTAssertEqual(AppAudio.spokenText(for: "3 + 4 = ?", languageCode: "eu"),
                       "3 gehi 4")
        XCTAssertEqual(AppAudio.spokenText(for: "3 + 4 = ?", languageCode: "fa"),
                       "3 به‌علاوه 4")
        XCTAssertEqual(AppAudio.spokenText(for: "3 + 4 = ?", languageCode: "gl"),
                       "3 máis 4")
        XCTAssertEqual(AppAudio.spokenText(for: "3 + 4 = ?", languageCode: "mr"),
                       "3 अधिक 4")
    }

    func testSpokenPercentagesUseNaturalLanguageOrder() {
        XCTAssertEqual(AppAudio.spokenText(for: "25% × 40 = ?", languageCode: "nl"),
                       "25 procent van 40")
        XCTAssertEqual(AppAudio.spokenText(for: "25% × 40 = ?", languageCode: "hi"),
                       "40 का 25 प्रतिशत")
        XCTAssertEqual(AppAudio.spokenText(for: "25% × 40 = ?", languageCode: "zh"),
                       "40 的百分之 25")
    }

    func testSpokenEquivalentFractionsNameTheUnknown() {
        XCTAssertEqual(AppAudio.spokenText(for: "1/2 = ?/4", languageCode: "en"),
                       "1 of 2 parts is how many of 4 parts")
        XCTAssertEqual(AppAudio.spokenText(for: "1/2 = ?/4", languageCode: "nl"),
                       "1 2de is hoeveel 4den")
        XCTAssertNil(AppAudio.spokenText(for: "3 + 4 = ?", languageCode: "af"))
    }

    func testEmphasisContinuesAcrossLineBreak() {
        let result = emphasizedAttributedString("|First line\nsecond line|")
        let runs = result.runs.map {
            (
                String(result.characters[$0.range]),
                $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true
            )
        }

        XCTAssertEqual(String(result.characters), "First line\nsecond line")
        XCTAssertEqual(runs.count, 1)
        XCTAssertEqual(runs.first?.0, "First line\nsecond line")
        XCTAssertEqual(runs.first?.1, true)
    }

    func testSeparateBoldLinesStayIndependentlyEmphasized() {
        let result = emphasizedAttributedString("|First line|\n|Second line|")
        let runs = result.runs.map {
            (
                String(result.characters[$0.range]),
                $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true
            )
        }

        XCTAssertEqual(String(result.characters), "First line\nSecond line")
        XCTAssertEqual(runs.map(\.0), ["First line", "\n", "Second line"])
        XCTAssertEqual(runs.map(\.1), [true, false, true])
    }

    func testDutchFractionsUseSchoolOrdinalsRatherThanDivision() {
        XCTAssertEqual(AppAudio.spokenText(for: "1/20 × 20 = ?", languageCode: "nl"),
                       "1 20ste keer 20")
        XCTAssertEqual(AppAudio.spokenText(for: "3/8 + 2/8 = ?", languageCode: "nl"),
                       "3 8ste plus 2 8ste")
        XCTAssertEqual(AppAudio.spokenText(for: "1/128 × 256 = ?", languageCode: "nl"),
                       "1 128ste keer 256")
    }

    func testEverySpokenLanguageCoversEveryGeneratedQuestionShape() {
        let prompts = [
            "3 + 4 = ?", "9 − 2 = ?", "6 × 7 = ?", "8 ÷ 2 = ?",
            "1/20 × 20 = ?", "3/8 + 2/8 = ?", "3/8 − 1/8 = ?",
            "1/2 = ?/4", "25% × 40 = ?", "50% = ?/2", "1/2 = ?"
        ]

        for languageCode in SpokenMath.lexicons.keys {
            for prompt in prompts {
                let spoken = AppAudio.spokenText(for: prompt, languageCode: languageCode)
                XCTAssertNotNil(spoken, "\(languageCode) did not handle \(prompt)")
                XCTAssertFalse(spoken?.isEmpty ?? true, "\(languageCode) produced empty speech")
                XCTAssertFalse(spoken?.contains("/") ?? true,
                               "\(languageCode) left a fraction symbol in \(prompt)")
                XCTAssertFalse(spoken?.contains("%") ?? true,
                               "\(languageCode) left a percent symbol in \(prompt)")
            }
        }
        XCTAssertEqual(Set(SpokenMath.lexicons.keys).subtracting(["nl"]),
                       Set(SpokenMath.fractionPatternLanguageCodes))
    }

    func testArithmeticOrderRoutesUseThreeGroupsOfFive() {
        let addition = QuestionEngine(
            level: LevelConfig(category: .addition, index: 2, cardNumber: "2")
        )
        XCTAssertEqual(
            (0..<16).map { _ in addition.next().prompt },
            [
                "2 + 2 = ?", "2 + 4 = ?", "2 + 6 = ?", "2 + 8 = ?", "2 + 10 = ?",
                "2 + 3 = ?", "2 + 5 = ?", "2 + 7 = ?", "2 + 9 = ?", "2 + 11 = ?",
                "2 + 5 = ?", "2 + 7 = ?", "2 + 9 = ?", "2 + 11 = ?", "2 + 13 = ?",
                "2 + 2 = ?"
            ]
        )

        let subtraction = QuestionEngine(
            level: LevelConfig(category: .subtraction, index: 2, cardNumber: "2")
        )
        XCTAssertEqual(
            (0..<16).map { _ in subtraction.next().prompt },
            [
                "12 − 2 = ?", "10 − 2 = ?", "8 − 2 = ?", "6 − 2 = ?", "4 − 2 = ?",
                "13 − 2 = ?", "11 − 2 = ?", "9 − 2 = ?", "7 − 2 = ?", "5 − 2 = ?",
                "15 − 2 = ?", "13 − 2 = ?", "11 − 2 = ?", "9 − 2 = ?", "7 − 2 = ?",
                "12 − 2 = ?"
            ]
        )
    }

    func testArithmeticRandomRangesIncludeEveryValueBelowTheSequenceCeiling() {
        XCTAssertEqual(ChallengeScaling.additionSequenceCeiling(2), 13)
        XCTAssertEqual(ChallengeScaling.subtractionSequenceCeiling(2), 15)

        let addition = QuestionEngine(
            level: LevelConfig(category: .addition, index: 2, cardNumber: "2", mode: .random)
        )
        var additionOthers = Set<Int>()
        for _ in 0..<13 {
            let values = integers(in: addition.next().prompt)
            XCTAssertEqual(values.count, 2)
            additionOthers.insert(values[0] == 2 ? values[1] : values[0])
        }
        XCTAssertEqual(additionOthers, Set(1...13))

        let subtraction = QuestionEngine(
            level: LevelConfig(category: .subtraction, index: 2, cardNumber: "2", mode: .random)
        )
        let starts = Set((0..<14).compactMap { _ in integers(in: subtraction.next().prompt).first })
        XCTAssertEqual(starts, Set(2...15))
    }

    func testPercentageDecimalSharesAreFortyAndTwentyPercent() {
        let decimal = QuestionEngine(
            level: LevelConfig(category: .percentages, index: 1, cardNumber: "25", mode: .random)
        )
        let decimalAnswers = (0..<5)
            .map { _ in decimal.next().correctAnswer }
            .filter(hasDecimalSeparator)
        XCTAssertEqual(decimalAnswers.count, 2)

        let mixed = QuestionEngine(
            level: LevelConfig(category: .percentages, index: 1, cardNumber: "25", mode: .mixed)
        )
        let mixedDecimalAnswers = (0..<5)
            .map { _ in mixed.next().correctAnswer }
            .filter(hasDecimalSeparator)
        XCTAssertEqual(mixedDecimalAnswers.count, 1)
    }

    func testEverySupermixCategoryUsesTheSelectedValuesSequenceCeiling() {
        XCTAssertEqual(ChallengeScaling.additionSequenceCeiling(12), 63)
        XCTAssertEqual(ChallengeScaling.subtractionSequenceCeiling(12), 75)

        for category in ChallengeCategory.supermixMenu {
            for index in [1, 2, 12, 13, 99] {
                let engine = QuestionEngine(
                    level: LevelConfig(category: category, index: index, cardNumber: "\(index)")
                )
                for _ in 0..<250 {
                    let question = engine.next()
                    let values = integers(in: question.prompt)
                    if question.prompt.contains("+") {
                        XCTAssertEqual(values.count, 2)
                        let matchesSelectedValueCeiling =
                            (values[0] <= index
                                && values[1] <= ChallengeScaling.additionSequenceCeiling(values[0]))
                            || (values[1] <= index
                                && values[0] <= ChallengeScaling.additionSequenceCeiling(values[1]))
                        XCTAssertTrue(
                            matchesSelectedValueCeiling,
                            "\(category.rawValue) \(question.prompt)"
                        )
                    } else if question.prompt.contains("−") {
                        XCTAssertEqual(values.count, 2)
                        let selected = values[1]
                        XCTAssertLessThanOrEqual(selected, index)
                        XCTAssertLessThanOrEqual(
                            values[0],
                            ChallengeScaling.subtractionSequenceCeiling(selected),
                            "\(category.rawValue) \(question.prompt)"
                        )
                    }
                }
            }
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

    private func integers(in prompt: String) -> [Int] {
        prompt.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
    }

    private func hasDecimalSeparator(_ answer: String) -> Bool {
        answer.contains(".") || answer.contains(",")
    }
}
