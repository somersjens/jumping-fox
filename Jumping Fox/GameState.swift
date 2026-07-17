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
        case .unlimited: return nil
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
    }

    let level: LevelConfig
    let lifeMode: LifeMode
    let isAnswerHelperEnabled: Bool
    private let engine: QuestionEngine

    @Published private(set) var question: Question
    @Published private(set) var score = 0
    /// nil means unlimited lives.
    @Published private(set) var lives: Int?
    @Published private(set) var isGameOver = false
    @Published private(set) var gameOverReason: GameOverReason?
    @Published private(set) var isNewHighScore = false
    @Published private(set) var highScore: Int
    @Published private(set) var wrongAnswerCount = 0

    init(level: LevelConfig) {
        self.level = level
        let mode = GameSettings.lifeMode
        self.lifeMode = mode
        self.isAnswerHelperEnabled = GameSettings.answerHelperEnabled
        self.lives = mode.startingLives
        let engine = QuestionEngine(level: level)
        self.engine = engine
        self.question = engine.next()
        self.highScore = ProgressStore.bestScore(levelID: level.id, helperEnabled: isAnswerHelperEnabled)
    }

    var correctAnswer: String { question.correctAnswer }
    var questionText: String { question.prompt }
    var isRandomPractice: Bool { question.isRandomPractice }
    var isScoreLocked: Bool { lifeMode == .unlimited && wrongAnswerCount >= 3 }

    /// Called when the player lands on the correct platform.
    /// Only closes the current question (score); the next question is
    /// activated separately via `advanceQuestion()` so the HUD and the
    /// platforms always switch together, after the confirmation.
    func answeredCorrectly() {
        guard !isGameOver, !isScoreLocked else { return }
        score += 1
    }

    /// Activates the next question in the chain. Called by the scene at a
    /// safe moment, never in the landing frame.
    func advanceQuestion() {
        guard !isGameOver else { return }
        question = engine.next()
    }

    /// Called when the player lands on a wrong platform.
    func answeredWrong() {
        guard !isGameOver else { return }
        engine.registerWrong(question)
        wrongAnswerCount += 1
        guard let currentLives = lives else {
            if wrongAnswerCount == 3 { recordCurrentScore() }
            return
        }
        let remaining = currentLives - 1
        lives = remaining
        if remaining <= 0 {
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
        lives = lifeMode.startingLives
        wrongAnswerCount = 0
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
