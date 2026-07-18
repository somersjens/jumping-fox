//
//  GameState.swift
//  Jumping Fox
//
//  Session state for one game: the active question (from the
//  QuestionEngine), life modes, score and best-score recording.
//

import Foundation
import Combine

/// How many lives a game starts with.
enum LifeMode: String, CaseIterable, Identifiable {
    case three
    case unlimited

    var id: String { rawValue }

    /// nil means unlimited.
    var startingLives: Int? {
        switch self {
        case .three: return 3
        // Unlimited also starts with three lives — the difference is that
        // running out switches to endless play instead of ending the game.
        case .unlimited: return 3
        }
    }

    var label: String {
        switch self {
        case .three: return "3 lives"
        case .unlimited: return "Unlimited"
        }
    }

    var requiresPremium: Bool { false }
}

/// Game settings, persisted in UserDefaults.
enum GameSettings {
    static let lifeModeKey = "settings.lifeMode"
    static let answerHelperKey = "settings.answerHelper"
    static let answerHintKey = "settings.answerHint"
    static let showStreakKey = "settings.showStreak"
    static let showTrophiesKey = "settings.showTrophies"
    static let capTrophiesKey = "settings.capTrophiesAtThirty"
    static let characterKey = "settings.character"
    static let playerNameKey = "profile.playerName"
    static let onboardingCompleteKey = "onboarding.complete"

    static var lifeMode: LifeMode {
        get {
            guard let raw = UserDefaults.standard.string(forKey: lifeModeKey),
                  let mode = LifeMode(rawValue: raw) else { return .three }
            return mode
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: lifeModeKey) }
    }

    /// When enabled, correct platforms are green and wrong ones red. Default off.
    static var answerHelperEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: answerHelperKey) }
        set { UserDefaults.standard.set(newValue, forKey: answerHelperKey) }
    }

    /// When enabled, tapping the equation reveals the answer for the rest of
    /// the current question, at the cost of half a life. Default on.
    static var answerHintEnabled: Bool {
        get { UserDefaults.standard.object(forKey: answerHintKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: answerHintKey) }
    }

    static var capsTrophiesAtThirty: Bool {
        get { UserDefaults.standard.object(forKey: capTrophiesKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: capTrophiesKey) }
    }

    /// Selected character id ("fox" by default).
    static var characterID: String {
        get { UserDefaults.standard.string(forKey: characterKey) ?? "fox" }
        set { UserDefaults.standard.set(newValue, forKey: characterKey) }
    }

    static var playerName: String {
        get { UserDefaults.standard.string(forKey: playerNameKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: playerNameKey) }
    }

    /// Mirror of the Premium entitlement, written by PremiumStore,
    /// readable from anywhere (including the SpriteKit scene).
    static let premiumCacheKey = "premium.unlocked"
    static var premiumUnlockedCache: Bool {
        get { UserDefaults.standard.bool(forKey: premiumCacheKey) }
        set { UserDefaults.standard.set(newValue, forKey: premiumCacheKey) }
    }
}

/// Observable state for one game session of a single level.
final class GameState: ObservableObject {
    enum GameOverReason {
        case outOfLives
        case fell
        /// Reached the 30-point goal with the "round off at 30" option on.
        case completed
    }

    let level: LevelConfig
    let lifeMode: LifeMode
    let isAnswerHelperEnabled: Bool
    private let engine: QuestionEngine

    @Published private(set) var question: Question
    @Published private(set) var score = 0
    /// Remaining lives in HALF units, so a hint can cost half a life.
    /// Both modes start at 6 (three lives).
    @Published private(set) var livesHalves: Int?
    /// Unlimited mode only: true once the three lives are used up. From then on
    /// the game never ends by lives — the HUD shows an infinity symbol instead
    /// of hearts and trophies stop counting.
    @Published private(set) var isEndless = false
    /// True once the answer has been revealed for the current question, so a
    /// second tap on the same question is free and shows the number again.
    @Published private(set) var isAnswerRevealed = false
    @Published private(set) var isGameOver = false
    @Published private(set) var gameOverReason: GameOverReason?
    @Published private(set) var isNewHighScore = false
    @Published private(set) var highScore: Int

    init(level: LevelConfig) {
        self.level = level
        let mode = GameSettings.lifeMode
        self.lifeMode = mode
        self.isAnswerHelperEnabled = GameSettings.answerHelperEnabled
        self.livesHalves = mode.startingLives.map { $0 * 2 }
        let engine = QuestionEngine(level: level)
        self.engine = engine
        self.question = engine.next()
        self.highScore = ProgressStore.bestScore(levelID: level.id, helperEnabled: isAnswerHelperEnabled)
    }

    var correctAnswer: String { question.correctAnswer }
    var questionText: String { question.prompt }
    var isRandomPractice: Bool { question.isRandomPractice }

    /// Lives left as a fraction, for the HUD (e.g. 2.5).
    var livesRemaining: Double? { livesHalves.map { Double($0) / 2 } }

    /// In unlimited mode, trophies stop counting once the three lives are gone.
    var isScoreLocked: Bool { isEndless }

    /// The hint may not be used when only half a life (or half of the
    /// unlimited-mode budget) is left — you can never spend your last half.
    var canRevealAnswer: Bool {
        guard GameSettings.answerHintEnabled, !isGameOver, !isAnswerRevealed else { return false }
        // Endless play: the lives are already gone, so the hint is free.
        if isEndless { return true }
        if let halves = livesHalves { return halves > 1 }
        return true
    }

    /// Called when the player lands on the correct platform.
    /// Only closes the current question (score); the next question is
    /// activated separately via `advanceQuestion()` so the HUD and the
    /// platforms always switch together, after the confirmation.
    func answeredCorrectly() {
        guard !isGameOver, !isScoreLocked else { return }
        score += 1
        // "Round off at 30" is on: reaching the cap finishes the level with a
        // festive completion screen instead of letting the run drag on.
        if GameSettings.capsTrophiesAtThirty,
           score >= ProgressStore.maximumTrophiesPerLevel {
            endGame(reason: .completed)
        }
    }

    /// Activates the next question in the chain. Called by the scene at a
    /// safe moment, never in the landing frame.
    func advanceQuestion() {
        guard !isGameOver else { return }
        question = engine.next()
        isAnswerRevealed = false
    }

    /// Called when the player lands on a wrong platform.
    func answeredWrong() {
        guard !isGameOver else { return }
        engine.registerWrong(question)
        applyPenalty(halves: 2)
    }

    /// Reveals the correct answer for the current question at the cost of half
    /// a life (or half a mistake in unlimited mode). Charges only the first
    /// time per question. Returns whether the answer is now revealed.
    @discardableResult
    func revealAnswer() -> Bool {
        guard !isAnswerRevealed else { return true }
        guard canRevealAnswer else { return false }
        isAnswerRevealed = true
        applyPenalty(halves: 1)
        return true
    }

    /// Deducts a penalty in half-life units, ending the game or locking the
    /// score as appropriate for the current life mode.
    private func applyPenalty(halves: Int) {
        guard let current = livesHalves else { return }
        let remaining = current - halves
        livesHalves = max(0, remaining)
        guard remaining <= 0 else { return }
        if lifeMode == .unlimited {
            // Out of lives, but unlimited: switch to endless play instead of
            // ending, and lock in the trophies earned so far.
            if !isEndless {
                isEndless = true
                recordCurrentScore()
            }
        } else {
            endGame(reason: .outOfLives)
        }
    }

    /// Called when the player falls below the screen — always game over.
    func fell() {
        guard !isGameOver else { return }
        endGame(reason: .fell)
    }

    private func endGame(reason: GameOverReason) {
        isGameOver = true
        gameOverReason = reason
        recordCurrentScore(showNewHighScore: true)
    }

    /// Paused runs should count toward the score shown on their level card.
    func recordCurrentScore(showNewHighScore: Bool = false) {
        if ProgressStore.recordScore(score, levelID: level.id, helperEnabled: isAnswerHelperEnabled) {
            highScore = score
            isNewHighScore = showNewHighScore
        }
    }

    /// Reset for a fresh game of the same level.
    func reset() {
        engine.resetRun()
        question = engine.next()
        score = 0
        livesHalves = lifeMode.startingLives.map { $0 * 2 }
        isEndless = false
        isAnswerRevealed = false
        isGameOver = false
        gameOverReason = nil
        isNewHighScore = false
        highScore = ProgressStore.bestScore(levelID: level.id, helperEnabled: isAnswerHelperEnabled)
    }

    /// A wrong answer for the current question that isn't in `used`.
    func distractor(excluding used: Set<String>) -> String {
        for candidate in question.distractors where !used.contains(candidate) {
            return candidate
        }
        // Fallback: numeric perturbation (generators supply 8 distractors,
        // so this is rarely reached).
        if let correct = Int(question.correctAnswer) {
            for offset in [3, 7, 11, 13, 17, 21] {
                let candidate = String(max(0, correct + offset))
                if !used.contains(candidate) && candidate != question.correctAnswer {
                    return candidate
                }
            }
        }
        return question.distractors.first ?? "0"
    }
}
