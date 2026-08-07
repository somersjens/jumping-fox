import Foundation
import Combine

/// Small, durable state machine for the in-game tutorial.  The current step
/// is saved immediately, so an interrupted run always resumes at the next
/// unfinished instruction instead of starting over.
final class TutorialProgress: ObservableObject {
    static let shared = TutorialProgress()
    private enum Key {
        static let started = "tutorial.started"
        static let step = "tutorial.lastCompletedStep"
        static let complete = "tutorial.complete"
        static let scoreHint = "tutorial.scoreHintShown"
        static let triplerAnswer = "tutorial.triplerAnswerPending"
    }

    /// A replay: the player has already finished the tutorial and is watching
    /// it again from the start screen's tutorial button. It runs entirely in
    /// memory, so their real (completed) progress is never rewritten.
    @Published private(set) var isReplaying = false
    @Published private(set) var started: Bool
    @Published private(set) var lastCompletedStep: Int
    @Published private(set) var isComplete: Bool
    @Published private(set) var scoreHintShown: Bool
    @Published private(set) var shouldShowScoreHint = false
    @Published private(set) var triplerAnswerPending: Bool

    private init(defaults: UserDefaults = .standard) {
        let storedStep = defaults.integer(forKey: Key.step)
        started = defaults.bool(forKey: Key.started)
        lastCompletedStep = storedStep
        isComplete = defaults.bool(forKey: Key.complete) || storedStep >= 11
        scoreHintShown = defaults.bool(forKey: Key.scoreHint)
        triplerAnswerPending = defaults.bool(forKey: Key.triplerAnswer)
    }

    /// A replay starts a fresh tutorial, but once step 11 is done it must obey
    /// normal gameplay rules just like a real player run.
    var isActive: Bool { !isComplete }
    var currentStep: Int { min(12, lastCompletedStep + 1) }

    func beginIfNeeded(helperEnabled: Bool) {
        guard isActive else { return }
        if !started {
            started = true
            if !isReplaying { UserDefaults.standard.set(true, forKey: Key.started) }
        }
        // The green-answer lesson is redundant when the helper is enabled.
        if helperEnabled && lastCompletedStep == 4 { complete(step: 5, helperEnabled: true) }
        // Landing on a neutral stone is unavoidable in ordinary play, so the
        // former stone-only lesson is no longer shown.
        if lastCompletedStep == 1 { complete(step: 2, helperEnabled: helperEnabled) }
        // The recovery-heart lesson was removed from the guided flow. A run
        // saved while it was active continues at the star lesson instead.
        if lastCompletedStep == 9 { complete(step: 10, helperEnabled: helperEnabled) }
    }

    func complete(step: Int, helperEnabled: Bool) {
        guard isActive, step == currentStep else { return }
        lastCompletedStep = step
        if step >= 11 { isComplete = true }
        if !isReplaying {
            UserDefaults.standard.set(lastCompletedStep, forKey: Key.step)
            UserDefaults.standard.set(isComplete, forKey: Key.complete)
        }
        if step == 8 { setTriplerAnswerPending(false) }
        if helperEnabled && currentStep == 5 { complete(step: 5, helperEnabled: true) }
    }

    func setTriplerAnswerPending(_ pending: Bool) {
        triplerAnswerPending = pending
        if !isReplaying { UserDefaults.standard.set(pending, forKey: Key.triplerAnswer) }
    }

    /// Play the guided tutorial again from its first lesson, on request from
    /// the level start screen. A player who already finished it replays in
    /// memory only, so their completed state (and normal scoring) survives; an
    /// unfinished tutorial genuinely starts over and is saved as such.
    func restart() {
        isReplaying = isComplete
        started = true
        lastCompletedStep = 0
        isComplete = false
        triplerAnswerPending = false
        guard !isReplaying else { return }
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: Key.started)
        defaults.set(0, forKey: Key.step)
        defaults.set(false, forKey: Key.complete)
        defaults.set(false, forKey: Key.triplerAnswer)
    }

    /// Leaving the game screen ends a replay: the stored, real progress of the
    /// player takes over again.
    func endReplay() {
        guard isReplaying else { return }
        isReplaying = false
        reloadPersistedState()
    }

    func markGameOver() {
        // A replay is a repeat viewing; the one-off "this is your score" hint
        // belongs to the very first real run only.
        guard !isReplaying, isComplete, !scoreHintShown else { return }
        shouldShowScoreHint = true
    }

    func consumeScoreHint() {
        guard shouldShowScoreHint else { return }
        shouldShowScoreHint = false
        scoreHintShown = true
        UserDefaults.standard.set(true, forKey: Key.scoreHint)
    }

    private func reloadPersistedState() {
        let d = UserDefaults.standard
        started = d.bool(forKey: Key.started); lastCompletedStep = d.integer(forKey: Key.step)
        isComplete = d.bool(forKey: Key.complete); scoreHintShown = d.bool(forKey: Key.scoreHint)
        triplerAnswerPending = d.bool(forKey: Key.triplerAnswer)
    }
}
