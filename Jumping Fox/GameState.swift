//
//  GameState.swift
//  Jumping Fox
//
//  Session state for one game: the active question (from the
//  QuestionEngine), life modes, score and best-score recording.
//

import Foundation
import Combine

/// How many lives a game starts with. Unlimited requires Premium.
enum LifeMode: String, CaseIterable, Identifiable {
    case one
    case three
    case unlimited

    var id: String { rawValue }

    /// nil means unlimited.
    var startingLives: Int? {
        switch self {
        case .one: return 1
        case .three: return 3
        case .unlimited: return nil
        }
    }

    var label: String {
        switch self {
        case .one: return "1 life"
        case .three: return "3 lives"
        case .unlimited: return "Unlimited"
        }
    }

    var requiresPremium: Bool { self == .unlimited }
}

/// Game settings, persisted in UserDefaults.
enum GameSettings {
    static let lifeModeKey = "settings.lifeMode"
    static let answerHelperKey = "settings.answerHelper"
    static let characterKey = "settings.character"

    static var lifeMode: LifeMode {
        get {
            guard let raw = UserDefaults.standard.string(forKey: lifeModeKey),
                  let mode = LifeMode(rawValue: raw) else { return .one }
            return mode
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: lifeModeKey) }
    }

    /// When enabled, correct platforms are green and wrong ones red. Default off.
    static var answerHelperEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: answerHelperKey) }
        set { UserDefaults.standard.set(newValue, forKey: answerHelperKey) }
    }

    /// Selected character id ("fox" by default).
    static var characterID: String {
        get { UserDefaults.standard.string(forKey: characterKey) ?? "fox" }
        set { UserDefaults.standard.set(newValue, forKey: characterKey) }
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
    private let engine: QuestionEngine

    @Published private(set) var question: Question
    @Published private(set) var score = 0
    /// nil means unlimited lives.
    @Published private(set) var lives: Int?
    @Published var superJumpAvailable = false
    @Published private(set) var isGameOver = false
    @Published private(set) var gameOverReason: GameOverReason?
    @Published private(set) var isNewHighScore = false
    @Published private(set) var highScore: Int

    init(level: LevelConfig) {
        self.level = level
        let mode = GameSettings.lifeMode
        self.lifeMode = mode
        self.lives = mode.startingLives
        let engine = QuestionEngine(level: level)
        self.engine = engine
        self.question = engine.next()
        self.highScore = ProgressStore.bestScore(levelID: level.id, mode: mode)
    }

    var correctAnswer: String { question.correctAnswer }
    var questionText: String { question.prompt }

    /// Called when the player lands on the correct platform.
    func answeredCorrectly() {
        guard !isGameOver else { return }
        score += 1
        question = engine.next()
    }

    /// Called when the player lands on a wrong platform.
    func answeredWrong() {
        guard !isGameOver else { return }
        engine.registerWrong(question)
        guard let currentLives = lives else { return } // unlimited
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
        superJumpAvailable = false
        if ProgressStore.recordScore(score, levelID: level.id, mode: lifeMode) {
            highScore = score
            isNewHighScore = true
        }
    }

    /// Reset for a fresh game of the same level.
    func reset() {
        engine.resetRun()
        question = engine.next()
        score = 0
        lives = lifeMode.startingLives
        superJumpAvailable = false
        isGameOver = false
        gameOverReason = nil
        isNewHighScore = false
        highScore = ProgressStore.bestScore(levelID: level.id, mode: lifeMode)
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
