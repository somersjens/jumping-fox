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
enum LifeMode: String, CaseIterable, Identifiable, Codable {
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
        case .three: return L("lives.three")
        case .unlimited: return L("lives.unlimited")
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

    /// Three-level audio preference. Existing installs migrate their old
    /// boolean switch to either all audio or fully muted.
    static let audioModeKey = "settings.audioMode"
    static let soundEnabledKey = "settings.soundEnabled"
    static var audioMode: AppAudioMode {
        get {
            if let raw = UserDefaults.standard.string(forKey: audioModeKey),
               let mode = AppAudioMode(rawValue: raw) {
                return mode
            }
            let legacyEnabled = UserDefaults.standard.object(forKey: soundEnabledKey) as? Bool ?? true
            // First download defaults to music + effects (the music-note icon),
            // with spoken sums off until the child opts into them.
            return legacyEnabled ? .musicAndEffects : .off
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: audioModeKey)
            UserDefaults.standard.set(newValue != .off, forKey: soundEnabledKey)
        }
    }

    /// Compatibility view for code that only needs to know whether any sound
    /// is active.
    static var soundEnabled: Bool {
        get { audioMode != .off }
        set { audioMode = newValue ? .all : .off }
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
    /// The portion of an unfinished run that must survive an app restart.
    struct PausedSnapshot: Codable {
        let question: Question
        let score: Int
        let livesHalves: Int?
        let isEndless: Bool
        let isAnswerRevealed: Bool
        let highScore: Int
    }
    enum GameOverReason {
        case outOfLives
        case fell
        /// The player deliberately ended an unlimited run from the done button.
        case finished
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
    /// Armed by the ×3 pickup: the next CORRECT answer scores triple; a
    /// wrong answer forfeits it. Deliberately not persisted across pauses.
    @Published private(set) var triplerArmed = false
    /// Consecutive correct answers, reset by any wrong answer. Once it reaches
    /// `streakThreshold` the answer-streak turns on and every earned trophy
    /// doubles. Not counted (nor rewarded) while the tutorial is running.
    @Published private(set) var correctStreak = 0
    /// True while the 5-in-a-row answer-streak is active: earned trophies are
    /// doubled (and a collected ×3 pickup therefore pays 6). Ends on the first
    /// wrong answer. Never turns on during the tutorial.
    @Published private(set) var isStreakActive = false
    /// Brief visual-only handoff while ×3 joins ×2 in the HUD and both coins
    /// jump to the trophy. Scoring and streak state never depend on this flag.
    @Published private(set) var isStreakComboAnimating = false
    /// The final correct answer has been scored, but the scene is still playing
    /// its short victory exit. Gameplay is locked during this handoff; the
    /// result card is presented only after the character has left the screen.
    @Published private(set) var isCompletingLevel = false
    @Published private(set) var isGameOver = false
    @Published private(set) var gameOverReason: GameOverReason?
    @Published private(set) var isNewHighScore = false
    @Published private(set) var didIncreaseMaximumCount = false
    @Published private(set) var highScore: Int
    private var hasPreparedCompletedLevel = false

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

    /// Recreates an unfinished run after the app was terminated. The engine
    /// starts a fresh question sequence after the restored current question;
    /// the player's visible progress remains exactly where it was paused.
    init(level: LevelConfig, pausedSnapshot: PausedSnapshot, lifeMode: LifeMode,
         answerHelperEnabled: Bool) {
        self.level = level
        self.lifeMode = lifeMode
        self.isAnswerHelperEnabled = answerHelperEnabled
        self.engine = QuestionEngine(level: level)
        self.question = pausedSnapshot.question
        self.score = pausedSnapshot.score
        self.livesHalves = pausedSnapshot.livesHalves
        self.isEndless = pausedSnapshot.isEndless
        self.isAnswerRevealed = pausedSnapshot.isAnswerRevealed
        self.highScore = pausedSnapshot.highScore
    }

    var pausedSnapshot: PausedSnapshot {
        PausedSnapshot(question: question,
                       score: score,
                       livesHalves: livesHalves,
                       isEndless: isEndless,
                       isAnswerRevealed: isAnswerRevealed,
                       highScore: highScore)
    }

    var correctAnswer: String { question.correctAnswer }
    var questionText: String { question.prompt }
    var isRandomPractice: Bool { question.isRandomPractice }

    /// Lives left as a fraction, for the HUD (e.g. 2.5).
    var livesRemaining: Double? { livesHalves.map { Double($0) / 2 } }

    /// In unlimited mode, trophies stop counting once the three lives are gone.
    var isScoreLocked: Bool { isEndless }

    /// True while a run keeps going after reaching the 30-trophy scoreboard cap
    /// (only possible with "cap at 30" turned off). Extra trophies no longer
    /// raise the recorded score, so the HUD shows a finish button and the
    /// "scoreboard maxed" notice — but reaching the cap under the normal
    /// completion flow ends the game, so this stays false there.
    var isPastScoreboardCap: Bool {
        !isGameOver && !isCompletingLevel
            && score >= ProgressStore.maximumTrophies(for: level)
    }

    /// The hint may not be used when only half a life (or half of the
    /// unlimited-mode budget) is left — you can never spend your last half.
    var canRevealAnswer: Bool {
        guard !isGameOver, !isCompletingLevel, !isAnswerRevealed else { return false }
        // Endless play: the lives are already gone, so the hint is free.
        if isEndless { return true }
        if let halves = livesHalves { return halves > 1 }
        return true
    }

    /// Correct answers needed in a row before the answer-streak turns on.
    static let streakThreshold = 5

    /// Called when the player lands on the correct platform.
    /// Only closes the current question (score); the next question is
    /// activated separately via `advanceQuestion()` so the HUD and the
    /// platforms always switch together, after the confirmation.
    @discardableResult
    func answeredCorrectly() -> Bool {
        guard !isGameOver, !isCompletingLevel, !isScoreLocked else { return false }
        // Base earning: a ×3 pickup triples it; an active streak then doubles
        // whatever was earned. So 1 normally, 2 on a streak, 3 with a ×3, and
        // 6 with a ×3 collected during a streak.
        var earned = triplerArmed ? 3 : 1
        if isStreakActive { earned *= 2 }
        score += earned
        triplerArmed = false
        // "Round off at 30" is on: reaching the cap finishes the level with a
        // festive completion sequence instead of letting the run drag on.
        // Do not publish `isGameOver` here: SpriteKit first gets a short,
        // input-locked victory beat in which the character exits the screen.
        if GameSettings.capsTrophiesAtThirty,
           score >= ProgressStore.maximumTrophies(for: level) {
            score = ProgressStore.maximumTrophies(for: level)
            isStreakComboAnimating = false
            isCompletingLevel = true
            return true
        }
        registerCorrectForStreak()
        return false
    }

    /// Persists the completed run while SpriteKit is already playing the
    /// victory exit. Keeping this separate from presentation means disk/cloud
    /// bookkeeping cannot hold up the first frame of the result card.
    func prepareCompletedLevel() {
        guard isCompletingLevel, !isGameOver, !hasPreparedCompletedLevel else { return }
        let result = recordCurrentScore(showNewHighScore: true)
        recordCompletedGame(using: result)
        hasPreparedCompletedLevel = true
    }

    /// Called by the scene after the character has cleared the top edge.
    /// `isGameOver` is deliberately published last so SwiftUI observes a fully
    /// prepared, internally consistent result.
    func presentCompletedLevel() {
        guard isCompletingLevel, !isGameOver else { return }
        prepareCompletedLevel()
        gameOverReason = .completed
        isCompletingLevel = false
        isGameOver = true
    }

    /// Counts one correct answer toward the streak and turns the streak on the
    /// moment it reaches the threshold. Disabled during the tutorial so the
    /// lesson stays focused, and never while the score is locked (endless).
    private func registerCorrectForStreak() {
        guard !isScoreLocked, !TutorialProgress.shared.isActive else { return }
        correctStreak += 1
        if !isStreakActive && correctStreak >= Self.streakThreshold {
            isStreakActive = true
        }
    }

    /// Clears the streak: no more doubling until five correct answers land in a
    /// row again. Triggered by a wrong answer or by entering endless play.
    private func resetStreak() {
        correctStreak = 0
        isStreakActive = false
        isStreakComboAnimating = false
    }

    /// Arms the ×3 pickup for the next answer.
    func armTripler() {
        guard !isGameOver, !isCompletingLevel, !isScoreLocked else { return }
        triplerArmed = true
    }

    func setStreakComboAnimating(_ animating: Bool) {
        guard !isCompletingLevel || !animating else { return }
        isStreakComboAnimating = animating
    }

    /// The −1 hazard: touching it costs one trophy (never below zero).
    func loseTrophy() {
        guard !isGameOver, !isCompletingLevel, !isScoreLocked, score > 0 else { return }
        score -= 1
    }

    /// Heals from a heart pickup, in half-heart units, never above the
    /// starting total. Meaningless once endless play has begun.
    func gainLifeHalves(_ halves: Int) {
        guard !isGameOver, !isCompletingLevel, !isEndless, let current = livesHalves,
              let start = lifeMode.startingLives else { return }
        livesHalves = min(start * 2, current + halves)
    }

    /// Half-hearts lost so far; nil when lives don't apply.
    var lostLifeHalves: Int? {
        guard let current = livesHalves, let start = lifeMode.startingLives else { return nil }
        return start * 2 - current
    }

    /// Activates the next question in the chain. Called by the scene at a
    /// safe moment, never in the landing frame.
    func advanceQuestion() {
        guard !isGameOver, !isCompletingLevel else { return }
        question = engine.next()
        isAnswerRevealed = false
    }

    /// Called when the player lands on a wrong platform.
    func answeredWrong() {
        guard !isGameOver, !isCompletingLevel else { return }
        engine.registerWrong(question)
        triplerArmed = false // a wrong answer forfeits the ×3
        resetStreak()        // …and ends the answer-streak
        applyPenalty(halves: 2)
    }

    /// Reveals the correct answer for the current question at the cost of half
    /// a life (or half a mistake in unlimited mode). Charges only the first
    /// time per question. Returns whether the answer is now revealed.
    @discardableResult
    func revealAnswer() -> Bool {
        guard !isGameOver, !isCompletingLevel else { return false }
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
        // The required tutorial teaches mistakes, but never ends the run.
        // Keep one full heart available until the active lesson is finished.
        let remaining = TutorialProgress.shared.isActive ? max(2, current - halves) : current - halves
        livesHalves = max(0, remaining)
        guard remaining <= 0 else { return }
        if lifeMode == .unlimited {
            // Out of lives, but unlimited: switch to endless play instead of
            // ending, and lock in the trophies earned so far.
            if !isEndless {
                isEndless = true
                resetStreak() // locked score: the streak no longer applies
                recordCurrentScore()
            }
        } else {
            endGame(reason: .outOfLives)
        }
    }

    /// Called when the player falls below the screen — always game over.
    func fell() {
        guard !isGameOver, !isCompletingLevel else { return }
        endGame(reason: .fell)
    }

    /// Ends an unlimited run from the HUD and shows the same result screen as
    /// any other finished attempt, including the trophies just earned.
    func finishEndlessRun() {
        guard isEndless, !isGameOver, !isCompletingLevel else { return }
        endGame(reason: .finished)
    }

    /// Ends the run from the HUD finish button once it is in "overtime": either
    /// endless play (lives spent in unlimited mode) or still climbing past the
    /// scoreboard cap. Shows the standard result screen with trophies earned.
    func finishRun() {
        guard !isGameOver, !isCompletingLevel, isEndless || isPastScoreboardCap else { return }
        endGame(reason: .finished)
    }

    private func endGame(reason: GameOverReason) {
        guard !isGameOver else { return }
        let result = recordCurrentScore(showNewHighScore: true)
        recordCompletedGame(using: result)
        gameOverReason = reason
        isGameOver = true
    }

    private func recordCompletedGame(using result: ProgressStore.RecordResult) {
        ReviewRequestCoordinator.shared.recordCompletedGame(
            isNewHighScore: result.isNewHighScore,
            score: score,
            maximumScore: ProgressStore.maximumTrophies(for: level)
        )
    }

    /// Paused runs should count toward the score shown on their level card.
    @discardableResult
    func recordCurrentScore(showNewHighScore: Bool = false) -> ProgressStore.RecordResult {
        let result = ProgressStore.recordScore(score, level: level, helperEnabled: isAnswerHelperEnabled)
        if result.isNewHighScore {
            highScore = score
            isNewHighScore = showNewHighScore
        }
        didIncreaseMaximumCount = showNewHighScore && result.didIncreaseMaximumCount
        return result
    }

    /// Reset for a fresh game of the same level.
    func reset() {
        engine.resetRun()
        question = engine.next()
        score = 0
        livesHalves = lifeMode.startingLives.map { $0 * 2 }
        isEndless = false
        isAnswerRevealed = false
        triplerArmed = false
        correctStreak = 0
        isStreakActive = false
        isStreakComboAnimating = false
        isCompletingLevel = false
        isGameOver = false
        gameOverReason = nil
        isNewHighScore = false
        didIncreaseMaximumCount = false
        hasPreparedCompletedLevel = false
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
