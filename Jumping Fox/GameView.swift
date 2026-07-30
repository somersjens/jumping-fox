//
//  GameView.swift
//  Jumping Fox
//
//  Game screen: SpriteKit scene plus HUD (question, lives, score)
//  and the game over overlay. Themed to the
//  selected character. Reports challenge lifecycle to the
//  playtime tracker (game over is a static screen — no time counts).
//

import SwiftUI
import SpriteKit
#if canImport(UIKit)
import UIKit
#endif

/// The exact points used by the paid-answer animation. Anchors keep the
/// flight attached to the real rendered heart and question mark on every
/// screen size, Dynamic Type setting and equation width.
private enum AnswerHintAnchor: Hashable {
    case heart
    case question
}

/// The play HUD uses one square canvas for every top-row asset. Keeping this
/// metric shared also gives SpriteKit a sensible fallback before SwiftUI has
/// reported the rendered anchors.
enum GameHUDMetrics {
    /// Direct metrics, shared by SwiftUI and SpriteKit fallback calculations.
    /// Flights still target the rendered SwiftUI anchors, so the larger iPad
    /// HUD remains attached to the exact visible trophy and hearts.
    static var scale: CGFloat { AppLayout.isPad ? 1.2 : 1 }
    static var assetSize: CGFloat { 28 * scale }
    static var pauseAssetSize: CGFloat { assetSize * 1.1 }
    static var heartSpacing: CGFloat { 2 * scale }
    static var horizontalPadding: CGFloat { 16 * scale }
    static var scoreFontSize: CGFloat { 28 * scale }
}

/// Exact rendered destinations for SpriteKit flights. The visual HUD is
/// SwiftUI, so anchors are more reliable than duplicating its typography and
/// layout maths in the scene.
private enum GameHUDAnchor: Hashable {
    case trophy
    case streakCoin
    case heart(Int)
}

/// Frame of the read-aloud toggle on the start/pause card, so the
/// "not available in your language" pop-out can anchor its caret to it.
private struct SpokenBubbleAnchorKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

private struct AnswerHintAnchors: PreferenceKey {
    static var defaultValue: [AnswerHintAnchor: Anchor<CGRect>] = [:]

    static func reduce(value: inout [AnswerHintAnchor: Anchor<CGRect>],
                       nextValue: () -> [AnswerHintAnchor: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct GameHUDAnchors: PreferenceKey {
    static var defaultValue: [GameHUDAnchor: Anchor<CGRect>] = [:]

    static func reduce(value: inout [GameHUDAnchor: Anchor<CGRect>],
                       nextValue: () -> [GameHUDAnchor: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

struct GameView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var state: GameState
    @State private var scene: GameScene
    // Refreshes the intro/end-menu copy when the language is switched.
    @ObservedObject private var language = LanguageManager.shared
    @ObservedObject private var tutorial = TutorialProgress.shared
    @ObservedObject private var audio = AppAudio.shared
    @Environment(\.layoutDirection) private var layoutDirection
    @AppStorage(GameSettings.lifeModeKey) private var selectedLifeModeRaw = LifeMode.three.rawValue
    @AppStorage(GameSettings.answerHelperKey) private var selectedAnswerHelper = false

    // Pre-game mode intro card. The field is frozen until the player starts.
    @State private var showingIntro: Bool
    @State private var isContinuingLevel: Bool
    @State private var isPausedAtIntro = false
    @State private var isShowingCompletionPreview = false
    @State private var showEndScreen = false
    /// Drives the "new record" badge's entrance: it stays hidden while the
    /// result card settles, then springs in on its own a beat later.
    @State private var showHighScoreBadge = false
    /// When automatic finishing is off, reaching the scoreboard maximum swaps
    /// two HUD regions at once. Stage that swap just after the score animation
    /// begins so the landing frame itself remains light.
    @State private var showsScoreboardFinishControls: Bool
    @State private var heartHintNudge: CGFloat = 0
    @State private var isAnswerHintFlying = false
    @State private var suppressIntroTap = false
    /// Shown when the read-aloud toggle on the start/pause card is tapped while
    /// spoken sums are unavailable in the current language.
    @State private var showSpokenUnavailablePopup = false
    @State private var isTutorialArrowBouncing = false
    @State private var showsTutorialCompletion = false
    /// The tutorial keeps one stable sum, and its equation is hidden during the
    /// movement lesson (step 1). Read that sum aloud once — the first time the
    /// equation actually appears — instead of at gameplay start when nothing is
    /// on screen yet. `false` until it has been announced.
    @State private var hasAnnouncedTutorialSum = false
    /// One-shot celebratory caption explaining why the streak coin just
    /// appeared ("5 in a row! Trophies ×2"). Auto-dismisses after a beat.
    @State private var showStreakBanner = false
    /// Identifies the streak caption currently on screen, so a retract timer
    /// from an earlier streak can never cut a newer caption short.
    @State private var streakBannerGeneration = 0
    private let theme = CharacterCatalog.current(isPremium: GameSettings.premiumUnlockedCache)
    private var isPad: Bool { AppLayout.isPad }
    private var gameScale: CGFloat { isPad ? 1.2 : 1 }
    /// Text on the large iPad cards gets one additional readability step;
    /// buttons intentionally keep their established touch proportions.
    private var gameTextScale: CGFloat { isPad ? 1.296 : 1 }
    private var introActionScale: CGFloat { isPad ? 1.2 : 1 }
    /// The card heading should lead the copy, without competing with the
    /// character portrait on iPad. The feature tiles step down separately so
    /// their explanatory text retains the established readable size.
    private var introTitleScale: CGFloat { 1.2 }
    private var introFeatureIconScale: CGFloat { 0.8 }
    /// Keep the established iPad copy size, while giving the three explanatory
    /// lines a 10% readability lift on the more compact iPhone card.
    private var introFeatureTextScale: CGFloat {
        isPad ? (1.1 * 0.9) : (0.88 * 0.9 * 1.1)
    }

    init(level: LevelConfig) {
        // A maxed card also shows its paused score, so an in-progress run can
        // be resumed regardless of the recorded best score.
        let canResume = PausedGameStore.shared.hasPausedSession(for: level, mode: GameSettings.lifeMode)
        _isContinuingLevel = State(initialValue: canResume)
        let state = canResume ? PausedGameStore.shared.gameState(for: level) : GameState(level: level)
        _state = StateObject(wrappedValue: state)
        _scene = State(initialValue: GameScene(state: state))
        _showsScoreboardFinishControls = State(
            initialValue: state.score >= ProgressStore.maximumTrophies(for: level)
                && !GameSettings.capsTrophiesAtThirty
        )
        // The first ever level starts straight in the live tutorial. Normal
        // runs restore the start screen; developer runs use it as an explicit
        // launch gate so the game cannot start behind the test menu.
        _showingIntro = State(initialValue: TutorialProgress.shared.developerMode
                              || !TutorialProgress.shared.isActive)
    }

    var body: some View {
        ZStack {
            // SpriteKit's backing view can briefly be visible before its
            // scene has received a size. Keeping the game's sky behind it
            // avoids the system-grey flash when reopening a paused tutorial.
            theme.skyColor
                .ignoresSafeArea()

            // ignoresSiblingOrder lets SpriteKit batch draw calls by texture
            // (layering is driven by explicit zPosition, not sibling order);
            // shouldCullNonVisibleNodes skips the platforms buffered far above
            // the viewport. Together these cut draw calls and GPU work.
            SpriteView(scene: scene,
                       options: [.shouldCullNonVisibleNodes, .ignoresSiblingOrder])
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                Spacer()
                bottomBar
            }
            // The game is full-screen already, so let the result/equation lane
            // use the otherwise empty lower safe area too. This leaves room for
            // the status beneath the equation without lifting the equation.
            .ignoresSafeArea(.container, edges: .bottom)

            if state.isGameOver {
                // Reaching the 30 goal — whether it ended the run or the player
                // kept climbing past it and then finished — earns the festive
                // completion card (showing the real tally, e.g. 31/30).
                if state.gameOverReason == .completed
                    || isShowingCompletionPreview
                    || state.score >= ProgressStore.maximumTrophies(for: state.level) {
                    completionOverlay
                } else {
                    gameOverOverlay
                }
            }

            if showingIntro && !state.isGameOver {
                introCard
            }

            if tutorial.isActive, (1...11).contains(tutorial.currentStep),
               tutorial.currentStep != 1 && !state.isGameOver && !showingIntro {
                VStack {
                    Spacer()
                    tutorialPrompt.padding(.bottom, 132)
                }
                .allowsHitTesting(false)
            }

            if showStreakBanner {
                VStack(spacing: 0) {
                    streakBanner
                        .padding(.top, 8 + GameHUDMetrics.assetSize + 12)
                    Spacer()
                }
                .allowsHitTesting(false)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            if showsTutorialCompletion {
                ConfettiView()
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                Text(L("tutorial.complete"))
                    .font(.headline.weight(.heavy))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .background(theme.deepColor.opacity(0.94), in: Capsule())
                    .overlay(Capsule().stroke(.white.opacity(0.85), lineWidth: 2))
                    .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
                    .padding(.horizontal, 24)
                    .allowsHitTesting(false)
            }
        }
        .overlayPreferenceValue(AnswerHintAnchors.self) { anchors in
            GeometryReader { proxy in
                if isAnswerHintFlying,
                   let heartAnchor = anchors[.heart],
                   let questionAnchor = anchors[.question] {
                    let heart = proxy[heartAnchor]
                    let question = proxy[questionAnchor]
                    // The spent half is the right half of a full heart, or
                    // the left half of an already half-filled heart.
                    let leavesRightHalf = (state.livesHalves ?? 0).isMultiple(of: 2)
                    AnswerHintFlight(
                        source: CGPoint(x: heart.midX + (leavesRightHalf ? heart.width * 0.22 : -heart.width * 0.22),
                                        y: heart.midY),
                        destination: CGPoint(x: question.midX, y: question.midY),
                        canvasWidth: proxy.size.width,
                        sourceIsRightHalf: leavesRightHalf,
                        color: theme.deepColor,
                        onArrival: finishAnswerHintFlight
                    )
                    .allowsHitTesting(false)
                }
            }
        }
        .overlayPreferenceValue(GameHUDAnchors.self) { anchors in
            GeometryReader { proxy in
                Color.clear
                    .onAppear { updateSceneHUDTargets(anchors, in: proxy) }
                    .onChange(of: state.score) { _ in updateSceneHUDTargets(anchors, in: proxy) }
                    .onChange(of: state.livesHalves) { _ in updateSceneHUDTargets(anchors, in: proxy) }
                    .onChange(of: state.isStreakActive) { _ in updateSceneHUDTargets(anchors, in: proxy) }
                    .onChange(of: state.isStreakComboAnimating) { _ in
                        updateSceneHUDTargets(anchors, in: proxy)
                    }
                    .onChange(of: proxy.size) { _ in updateSceneHUDTargets(anchors, in: proxy) }
            }
        }
        .onAppear {
            scene.isFrozen = showingIntro
            // SpriteKit may lay out its initial scene just after onAppear.
            // Reapply the gate on the next runloop so that layout cannot
            // accidentally release the field behind the start screen.
            DispatchQueue.main.async { scene.isFrozen = showingIntro }
            isTutorialArrowBouncing = true
            PlaytimeTracker.shared.challengeStarted()
            setScreenAwake(true)
            AppAudio.shared.prepare()   // ensure players are loaded before play
            updateGameplayAudio()
        }
        .onDisappear {
            if tutorial.developerMode { tutorial.leaveDeveloperMode() }
            PlaytimeTracker.shared.challengeEnded()
            setScreenAwake(false)
            AppAudio.shared.setGameplayActive(false, questionText: nil)
        }
        .onChange(of: tutorial.currentStep) { step in
            // Warm the soft haptic the moment the "tap the question mark" step
            // appears, so the first tap doesn't cold-start the Taptic Engine.
            if step == 6 { scene.prepareHintHaptic() }
            // Step 1 hides the equation; the moment it first appears (any later
            // step), read the sum aloud once. The tutorial's sum never changes,
            // so it is deliberately not repeated on the following steps.
            if step != 1, !hasAnnouncedTutorialSum, !showingIntro, !state.isGameOver {
                hasAnnouncedTutorialSum = true
                AppAudio.shared.speakQuestion(state.questionText)
            }
        }
        .onChange(of: tutorial.isComplete) { complete in
            guard complete else { return }
            withAnimation(.snappy) { showsTutorialCompletion = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                withAnimation(.easeOut(duration: 0.25)) { showsTutorialCompletion = false }
            }
        }
        .onChange(of: state.isStreakActive) { active in
            guard !state.isCompletingLevel, !state.isGameOver else {
                showStreakBanner = false
                return
            }
            guard active else {
                // The streak just broke: retract any lingering caption too.
                if showStreakBanner {
                    withAnimation(.easeOut(duration: 0.3)) { showStreakBanner = false }
                }
                return
            }
            // Streak just turned on: show the "why" caption for a beat.
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                showStreakBanner = true
            }
            streakBannerGeneration += 1
            let generation = streakBannerGeneration
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) {
                guard generation == streakBannerGeneration else { return }
                withAnimation(.easeOut(duration: 0.35)) { showStreakBanner = false }
            }
        }
        .onChange(of: state.isCompletingLevel) { completing in
            if completing {
                showStreakBanner = false
            }
        }
        .onChange(of: state.isPastScoreboardCap) { reachedCap in
            guard reachedCap else {
                showsScoreboardFinishControls = false
                return
            }
            // Separate the finish affordance from the numeric score transition.
            // The glyph is prewarmed above, so this later swap is inexpensive.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                guard state.isPastScoreboardCap, !state.isGameOver else { return }
                showsScoreboardFinishControls = true
            }
        }
        .onChange(of: state.isGameOver) { over in
            if over {
                // Completed levels remove their paused snapshot during the
                // victory exit. Other endings still clean it up here.
                if state.gameOverReason != .completed {
                    PausedGameStore.shared.remove(state)
                }
                TutorialProgress.shared.markGameOver()
                PlaytimeTracker.shared.challengeEnded(deferPersistence: true)
            } else {
                PlaytimeTracker.shared.challengeStarted()
                // Rearm the celebration for the next completion.
                celebrate = false
                showConfetti = false
                showEndScreen = false
                showHighScoreBadge = false
                showsScoreboardFinishControls = false
                isShowingCompletionPreview = false
                // After the tutorial, fresh runs use the normal level start
                // screen again (including its route back to the main menu).
                isContinuingLevel = false
                showingIntro = !tutorial.isActive
                scene.isFrozen = !tutorial.isActive
            }
        }
        // Music only plays while a level is actually being played: it starts
        // when the start/pause card is dismissed and stops on pause, game over
        // or when leaving the screen.
        .onChange(of: showingIntro) { _ in updateGameplayAudio() }
        .onChange(of: state.isGameOver) { _ in updateGameplayAudio() }
        // Read each new sum aloud when the selected audio mode and language
        // support it; AppAudio handles both checks.
        .onChange(of: state.question.prompt) { newPrompt in
            guard !showingIntro, !state.isGameOver else { return }
            AppAudio.shared.speakQuestion(newPrompt)
        }
        // Turning spoken sums on during a level renders the visible sum away
        // from the gameplay and audio-output threads before playback begins.
        .onChange(of: audio.spokenSumsEnabled) { enabled in
            guard enabled, !showingIntro, !state.isGameOver,
                  !tutorialEquationHidden else { return }
            AppAudio.shared.speakQuestion(state.questionText)
        }
    }

    /// Turns the game's music and spoken sums on or off to match the play
    /// state: audible only while a level is live (no intro card, not over).
    private func updateGameplayAudio() {
        let active = !showingIntro && !state.isGameOver
        // Don't read the sum aloud while its equation is still hidden behind the
        // step-1 movement instruction; `tutorialSumBecameVisible()` speaks it the
        // moment it appears instead.
        let questionText = tutorialEquationHidden ? nil : state.questionText
        AppAudio.shared.setGameplayActive(active, questionText: questionText)
    }

    /// The equation is replaced by the instruction during the tutorial's
    /// movement lesson (step 1); it is on screen for every other step.
    private var tutorialEquationHidden: Bool {
        tutorial.isActive && tutorial.currentStep == 1
    }

    /// Keep the display from dimming/locking during play.
    private func setScreenAwake(_ awake: Bool) {
#if canImport(UIKit)
        UIApplication.shared.isIdleTimerDisabled = awake
#endif
    }

    /// Supplies window-coordinate rectangles to SpriteKit. The scene converts
    /// them through its actual SKView, avoiding any assumptions about safe
    /// areas, Dynamic Island or the SwiftUI overlay's local origin.
    private func updateSceneHUDTargets(_ anchors: [GameHUDAnchor: Anchor<CGRect>],
                                       in proxy: GeometryProxy) {
        let globalOrigin = proxy.frame(in: .global).origin
        func globalRect(for anchor: Anchor<CGRect>) -> CGRect {
            proxy[anchor].offsetBy(dx: globalOrigin.x, dy: globalOrigin.y)
        }
        let trophy = anchors[.trophy].map { globalRect(for: $0) }
        let streakCoin = anchors[.streakCoin].map { globalRect(for: $0) }
        let hearts = Dictionary(uniqueKeysWithValues: (0..<3).compactMap { index in
            anchors[.heart(index)].map { (index, globalRect(for: $0)) }
        })
        scene.isRTL = layoutDirection == .rightToLeft
        scene.setHUDTargets(trophy: trophy, streakCoin: streakCoin,
                            hearts: hearts, viewSize: proxy.size)
    }

    // MARK: Mode intro card

    private func beginIntro() {
        scene.isFrozen = true
        showingIntro = true
    }

    private func dismissIntro() {
        guard showingIntro else { return }
        // Release the field the instant the card starts to leave.
        scene.isFrozen = false
        withAnimation(.snappy(duration: 0.25)) { showingIntro = false }
    }

    private func dismissIntroFromTap() {
        // While the read-aloud explanation is up, a tap anywhere just closes it
        // — it must not fall through and start/continue the game.
        if showSpokenUnavailablePopup {
            dismissSpokenUnavailable()
            return
        }
        guard !suppressIntroTap else {
            suppressIntroTap = false
            return
        }
        dismissIntro()
    }

    private func showSpokenUnavailable() {
#if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
#endif
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            showSpokenUnavailablePopup = true
        }
    }

    private func dismissSpokenUnavailable() {
        withAnimation(.easeOut(duration: 0.16)) { showSpokenUnavailablePopup = false }
    }

    /// Hidden developer entry point: it belongs to the character on the
    /// level's own start screen, not to the character on the main menu.
    private func activateDeveloperTutorial() {
        guard showingIntro else { return }
        tutorial.enterDeveloperMode()
        isContinuingLevel = false
        isPausedAtIntro = false
        PausedGameStore.shared.remove(state)
        scene.resetGame()
        scene.isFrozen = true
    }

    private func pauseToIntro() {
        guard !showingIntro else { return }
        PausedGameStore.shared.pause(state)
        scene.isFrozen = true
        isPausedAtIntro = true
        withAnimation(.snappy(duration: 0.25)) { showingIntro = true }
    }

    private func returnToMainMenu() {
        // Returning through the level start/pause screen should still point
        // out the newly earned score after a completed tutorial run.
        if tutorial.isComplete && state.score > 0 {
            tutorial.markGameOver()
        }
        dismiss()
    }

    private var isPausedIntro: Bool {
        isPausedAtIntro || isContinuingLevel
    }

    private var introCard: some View {
        let info = ModeIntro.info(for: state.level)
        let featureCards = [
            // Row 1 is the shared intro line; row 2 is the mode-specific detail.
            IntroFeature(icon: featureIcon, text: info.bullets[0]),
            IntroFeature(number: state.level.cardNumber, text: info.bullets[1]),
            IntroFeature(icon: "trophy.fill", text: trophyDescription)
        ]
        return ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()

            GeometryReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .top, spacing: 14) {
                            characterPortrait
                            // The title and the status labels together span the
                            // exact height of the character box: title pinned to
                            // the top, labels to the bottom (the Spacer fills
                            // between). Both share this single column, which runs
                            // as wide as possible while the HStack spacing leaves
                            // a safety margin to the sound toggle on the right.
                            VStack(alignment: .leading, spacing: 0) {
                                Text(info.title)
                                    .font(.system(size: 33 * gameTextScale * introTitleScale, weight: .heavy, design: .rounded))
                                    .foregroundStyle(theme.deepColor)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.5)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Spacer(minLength: 0)
                                // Status labels sit on their own row, sharing the
                                // title's width and stopping short of the toggle.
                                HStack(spacing: 7) {
                                    introSettingButton(
                                        icon: selectedLifeMode == .unlimited ? "infinity" : "heart.fill",
                                        text: selectedLifeMode == .unlimited
                                            ? L("game.intro.livesOff") : L("game.intro.livesOn"),
                                        action: toggleIntroLifeMode
                                    )
                                    introSettingButton(
                                        icon: "lightbulb.fill",
                                        text: selectedAnswerHelper
                                            ? L("game.intro.helperOn") : L("game.intro.helperOff"),
                                        action: toggleIntroAnswerHelper
                                    )
                                    Spacer(minLength: 0)
                                }
                            }
                            .frame(height: introPortraitSize)
                            // Both audio choices share one outlined column with
                            // exactly the same height as the character portrait.
                            audioControlColumn
                        }
                        DashedDivider(color: theme.color.opacity(0.45))
                            .padding(.vertical, 4)

                        ForEach(featureCards) { feature in
                            introFeatureCard(feature)
                        }

                        VStack(spacing: 10) {
                            Button(action: dismissIntro) {
                                Group {
                                    if tutorial.developerMode {
                                        Text("developerMode.title")
                                    } else {
                                        Text(isPausedIntro ? "game.intro.continue" : "game.intro.start")
                                    }
                                }
                                .font(.system(size: 17 * introActionScale, weight: .heavy))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 15 * introActionScale)
                                .foregroundStyle(.white)
                                .background(theme.deepColor, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            }
                            .buttonStyle(.plain)

                            Button(action: returnToMainMenu) {
                                Text("game.intro.backToMainMenu")
                                    .font(.system(size: 17 * introActionScale, weight: .heavy))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 15 * introActionScale)
                                    .foregroundStyle(theme.deepColor)
                                    .background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .stroke(theme.deepColor.opacity(0.14), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }

                        if isPausedIntro {
                            pausedIntroMessage
                        }
                    }
                    .padding(28 * gameScale)
                    .padding(.top, 4)
                    .frame(maxWidth: 420 * gameScale)
                    .background(.background, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(theme.deepColor.opacity(0.14), lineWidth: 1))
                    .shadow(color: theme.deepColor.opacity(0.28), radius: 18, y: 8)
                    .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .onTapGesture(perform: dismissIntroFromTap)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: proxy.size.height, alignment: .center)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .overlayPreferenceValue(SpokenBubbleAnchorKey.self) { anchor in
            spokenUnavailableOverlay(anchor)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: dismissIntroFromTap)
        .transition(.opacity)
    }

    /// The caret-topped card explaining that read-aloud is not available in the
    /// current language, anchored beneath the tapped toggle. Styled like the
    /// home-menu info pop-out, without a header.
    @ViewBuilder
    private func spokenUnavailableOverlay(_ anchor: Anchor<CGRect>?) -> some View {
        GeometryReader { geo in
            if showSpokenUnavailablePopup, let anchor {
                let rect = geo[anchor]
                let cardWidth = min(240 * gameScale, geo.size.width - 24)
                let anchorMidX = rect.midX
                let rawX = anchorMidX - cardWidth / 2
                let x = min(max(12, rawX), max(12, geo.size.width - cardWidth - 12))
                let caretLimit = cardWidth / 2 - 18
                let caret = min(max(anchorMidX - (x + cardWidth / 2), -caretLimit), caretLimit)
                let y = rect.maxY + 6

                SpokenUnavailableCard(message: L("game.intro.spokenUnavailable"),
                                      caretOffset: caret,
                                      theme: theme,
                                      isPad: isPad)
                    .frame(width: cardWidth)
                    .offset(x: x, y: y)
                    .onTapGesture(perform: dismissSpokenUnavailable)
                    .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .top)))
            }
        }
    }

    /// Size of the character portrait on the start/pause card. The title and
    /// its status labels are laid out to exactly this height.
    private var introPortraitSize: CGFloat { 70 * gameScale }

    private var characterPortrait: some View {
        theme.artwork
            .resizable()
            .scaledToFit()
            // Tighter inset renders the character ~10% larger inside the same
            // box — the outline/background frame below is unchanged.
            .padding(5)
            .frame(width: introPortraitSize, height: introPortraitSize)
            .background(theme.skyColor, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(theme.deepColor.opacity(0.12), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .highPriorityGesture(
                LongPressGesture(minimumDuration: 2)
                    .onEnded { _ in
                        suppressIntroTap = true
                        activateDeveloperTutorial()
                    }
            )
    }

    private var audioControlColumn: some View {
        VStack(spacing: 0) {
            introAudioButton(
                icon: "music.note",
                isOn: audio.gameSoundsEnabled,
                isAvailable: true,
                accessibilityLabel: audio.gameSoundsEnabled
                    ? "Music and effects on" : "Music and effects off"
            ) {
                withAnimation(.snappy(duration: 0.2)) { audio.toggleGameSounds() }
            }

            Rectangle()
                .fill(theme.deepColor.opacity(0.15))
                .frame(height: 1)
                .padding(.horizontal, 7 * gameScale)

            introAudioButton(
                icon: "text.bubble.fill",
                isOn: audio.spokenSumsEnabled && audio.isSpokenMathAvailable,
                isAvailable: audio.isSpokenMathAvailable,
                accessibilityLabel: audio.spokenSumsEnabled
                    ? "Spoken sums on" : "Spoken sums off",
                // Tapping it while spoken sums are unavailable explains why,
                // rather than doing nothing.
                unavailableAction: showSpokenUnavailable
            ) {
                withAnimation(.snappy(duration: 0.2)) { audio.toggleSpokenSums() }
            }
            .anchorPreference(key: SpokenBubbleAnchorKey.self,
                              value: .bounds) { $0 }
        }
        .frame(width: 44 * gameScale, height: introPortraitSize)
        .background(theme.skyColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(theme.deepColor.opacity(0.15), lineWidth: 1))
    }

    private func introAudioButton(icon: String, isOn: Bool, isAvailable: Bool,
                                  accessibilityLabel: String,
                                  unavailableAction: (() -> Void)? = nil,
                                  action: @escaping () -> Void) -> some View {
        // When unavailable but given an explanation to show, the button stays
        // tappable so the pop-out can appear; otherwise it is truly disabled.
        let handlesUnavailableTap = !isAvailable && unavailableAction != nil
        return Button(action: isAvailable ? action : (unavailableAction ?? {})) {
            ZStack {
                Image(systemName: icon)
                    .font(.system(size: 17 * gameTextScale, weight: .heavy))
                if !isOn {
                    Capsule()
                        .fill(theme.deepColor)
                        .frame(width: 23 * gameScale, height: 2.3 * gameScale)
                        .rotationEffect(.degrees(-45))
                }
            }
            .foregroundStyle(theme.deepColor.opacity(isAvailable ? (isOn ? 1 : 0.55) : 0.28))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.plain)
        .disabled(!isAvailable && !handlesUnavailableTap)
        .accessibilityLabel(Text(verbatim: accessibilityLabel))
    }

    private var selectedLifeMode: LifeMode {
        LifeMode(rawValue: selectedLifeModeRaw) ?? .three
    }

    private func toggleIntroLifeMode() {
        let newMode: LifeMode = selectedLifeMode == .three ? .unlimited : .three
        selectedLifeModeRaw = newMode.rawValue
        AppAudio.shared.playSwitch(on: newMode == .unlimited)
        guard !isPausedIntro else { return }
        scene.applyPreGameSettings(lifeMode: newMode,
                                   answerHelperEnabled: selectedAnswerHelper)
    }

    private func toggleIntroAnswerHelper() {
        selectedAnswerHelper.toggle()
        AppAudio.shared.playSwitch(on: selectedAnswerHelper)
        guard !isPausedIntro else { return }
        scene.applyPreGameSettings(lifeMode: selectedLifeMode,
                                   answerHelperEnabled: selectedAnswerHelper)
    }

    private func introSettingButton(icon: String, text: String,
                                    action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: (icon == "infinity" ? 12 : 10) * gameTextScale,
                                  weight: .heavy, design: .rounded))
                Text(text)
            }
            .font(.system(size: 10 * gameTextScale, weight: .bold))
            .foregroundStyle(theme.deepColor.opacity(0.82))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .allowsTightening(true)
            .padding(.horizontal, 8 * gameScale)
            .padding(.vertical, 5 * gameScale)
            .frame(maxWidth: 118 * gameScale)
            .background(theme.skyColor.opacity(0.72), in: Capsule())
            .overlay(Capsule().stroke(theme.deepColor.opacity(0.15), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var pausedIntroMessage: some View {
        Group {
            if isPausedAtIntro && state.score > 0 {
                Text("game.intro.scorePaused")
            } else if isContinuingLevel && state.score > 0 {
                HStack(spacing: 6) {
                    Text("game.intro.continueFrom \(state.score)")
                    Image(systemName: "trophy.fill")
                }
            }
        }
        .font(.system(size: 13 * gameTextScale, weight: .semibold))
        .foregroundStyle(theme.deepColor.opacity(0.62))
        .frame(maxWidth: .infinity)
        .padding(.top, 2)
    }

    private func introFeatureCard(_ feature: IntroFeature) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Group {
                if let number = feature.number {
                    Text(number)
                        .font(.system(size: 34 * gameTextScale * introFeatureIconScale, weight: .heavy, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.48)
                        .allowsTightening(true)
                } else {
                    Image(systemName: feature.icon)
                        .font(.system(size: (feature.icon == "multiply" ? 34 : 28) * gameTextScale * introFeatureIconScale, weight: .bold))
                }
            }
            .foregroundStyle(theme.deepColor)
            // Keep the generous feature-tile hit area and visual rhythm; only
            // its glyph is intentionally smaller than before.
            .frame(width: 54 * gameScale, height: 54 * gameScale)
            .background(theme.skyColor, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(theme.deepColor.opacity(0.14), lineWidth: 1))

            emphasizedText(feature.text)
                .font(.system(size: 15 * gameTextScale * introFeatureTextScale, weight: .regular))
                .foregroundStyle(theme.deepColor.opacity(0.84))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
            .padding(.horizontal, 10 * gameScale)
        .padding(.vertical, 6 * gameScale)
        .background(theme.skyColor.opacity(0.32), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(theme.deepColor.opacity(0.10), lineWidth: 1))
    }

    /// Localized descriptions mark emphasis by wrapping words in |pipes|.
    /// A single attributed string preserves that emphasis when a bold span
    /// wraps onto a second line, as well as for multiple separate bold spans.
    private func emphasizedText(_ copy: String) -> Text {
        Text(emphasizedAttributedString(copy))
    }

    private var featureIcon: String {
        switch state.level.category {
        case .addition, .additionMix: return "plus"
        case .subtraction, .subtractionMix: return "minus"
        case .tables, .tablesMix: return "multiply"
        case .fractions, .fractionsMix: return "divide"
        case .percentages, .percentagesMix: return "percent"
        case .superBasic, .superTimes, .superFraction, .superAll: return "shuffle"
        }
    }

    private var trophyDescription: String {
        return L("game.intro.trophyBullet \(ProgressStore.maximumTrophies(for: state.level))")
    }

    private struct IntroFeature: Identifiable {
        let icon: String
        let number: String?
        let text: String
        init(icon: String, text: String) {
            self.icon = icon
            self.number = nil
            self.text = text
        }
        init(number: String, text: String) {
            self.icon = "number"
            self.number = number
            self.text = text
        }
        var id: String { "\(icon)-\(number ?? "")-\(text)" }
    }

    /// A single-stroke divider avoids the doubled edge a dashed rectangle
    /// creates at this small height.
    private struct DashedDivider: View {
        let color: Color

        var body: some View {
            GeometryReader { proxy in
                Path { path in
                    path.move(to: CGPoint(x: 0, y: proxy.size.height / 2))
                    path.addLine(to: CGPoint(x: proxy.size.width, y: proxy.size.height / 2))
                }
                .stroke(color, style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
            }
            .frame(height: 2)
        }
    }

    // MARK: HUD

    /// The run is in "overtime" — endless play, or still climbing past the
    /// scoreboard cap — so the HUD button finishes it (result screen) instead
    /// of pausing to the menu.
    private var isRunFinishable: Bool {
        state.isEndless || showsScoreboardFinishControls
    }

    private var topBar: some View {
        HStack(spacing: 0) {
            Button {
                if isRunFinishable {
                    // Finishing an overtime run shows the result card and stays
                    // put — the player leaves via its Play Again / Menu buttons.
                    state.finishRun()
                } else {
                    pauseToIntro()
                }
            } label: {
                // Normal pause button during regular play; a checkmark "done"
                // button of the same size once the run is finishable.
                Image(systemName: isRunFinishable ? "checkmark.circle.fill" : "pause.circle.fill")
                    .font(.system(size: GameHUDMetrics.pauseAssetSize, weight: .regular))
                    .foregroundStyle(theme.deepColor)
                    .frame(width: GameHUDMetrics.pauseAssetSize,
                           height: GameHUDMetrics.pauseAssetSize)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.snappy(duration: 0.25), value: isRunFinishable)
            .disabled(
                state.isCompletingLevel
                    || (state.isPastScoreboardCap && !showsScoreboardFinishControls)
            )

            // Just the trophy count: the score number followed by a trophy.
            // The equal-width side columns keep it perfectly centered.
            HStack(spacing: 6) {
                Text(verbatim: "\(state.score)")
                    .font(.system(size: GameHUDMetrics.scoreFontSize, weight: .heavy, design: .rounded))
                    .foregroundStyle(theme.deepColor)
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.25), value: state.score)
                Image(systemName: "trophy.fill")
                    .font(.system(size: GameHUDMetrics.assetSize, weight: .regular))
                    .foregroundStyle(theme.deepColor)
                    .frame(width: GameHUDMetrics.assetSize, height: GameHUDMetrics.assetSize)
                    .anchorPreference(key: GameHUDAnchors.self, value: .bounds) { [.trophy: $0] }

                // The answer-streak coin: appears just right of the trophy while
                // the 5-in-a-row ×2 bonus is live, and pops away on the first
                // wrong answer that ends the streak.
                if state.isStreakActive {
                    StreakCoin(ink: theme.tintColor,
                               coinFill: theme.deepColor,
                               size: GameHUDMetrics.assetSize)
                        .anchorPreference(key: GameHUDAnchors.self, value: .bounds) {
                            [.streakCoin: $0]
                        }
                        // Keep its layout slot and anchor alive during the
                        // SpriteKit combo, so neither the trophy nor the exact
                        // ×2 destination shifts while the real coin is hidden.
                        .opacity(state.isStreakComboAnimating ? 0 : 1)
                        .animation(.easeOut(duration: 0.16),
                                   value: state.isStreakComboAnimating)
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.15).combined(with: .opacity),
                            removal: .streakCoinBreak))
                }
            }
            .fixedSize()
            .animation(.spring(response: 0.45, dampingFraction: 0.62),
                       value: state.isStreakActive)

            livesBadge
                .frame(maxWidth: .infinity, alignment: .trailing)
                .offset(x: heartHintNudge)
                .animation(.snappy(duration: 0.3), value: state.isEndless)
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    /// The caption that punctuates a fresh streak, naming its cause (five
    /// correct answers in a row) and its effect (trophies now double).
    private var streakBanner: some View {
        HStack(spacing: 7) {
            Text(verbatim: "\(L("game.streak.title"))  \(L("game.streak.subtitle"))")
                .font(.subheadline.weight(.heavy))
                .foregroundStyle(.white)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(theme.color.opacity(0.94), in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.85), lineWidth: 1.5))
        .shadow(color: .black.opacity(0.22), radius: 7, y: 3)
    }

    @ViewBuilder
    private var livesBadge: some View {
        if state.isEndless {
            // Lives used up in unlimited mode: swap the hearts for infinity.
            Image(systemName: "infinity")
                .font(.system(size: GameHUDMetrics.assetSize, weight: .heavy, design: .rounded))
                .foregroundStyle(theme.deepColor)
                .frame(width: GameHUDMetrics.assetSize, height: GameHUDMetrics.assetSize)
                .transition(.scale.combined(with: .opacity))
        } else if let halves = state.livesHalves {
            heartRow(filledHalves: halves)
                .font(.system(size: GameHUDMetrics.assetSize, weight: .regular))
                .animation(.snappy(duration: 0.25), value: halves)
        }
    }

    /// A row of three hearts that can each be full, half or empty, driven by a
    /// value in HALF units (0...6). Lets a hint show as half a heart.
    private func heartRow(filledHalves: Int) -> some View {
        let spendingIndex = (filledHalves - 1) / 2
        let spendingRightHalf = filledHalves.isMultiple(of: 2)
        return HStack(spacing: GameHUDMetrics.heartSpacing) {
            ForEach(0..<3, id: \.self) { index in
                heartIcon(fill: min(2, max(0, filledHalves - index * 2)),
                          spendingHalf: isAnswerHintFlying && index == spendingIndex,
                          spendingRightHalf: spendingRightHalf)
                    .frame(width: GameHUDMetrics.assetSize, height: GameHUDMetrics.assetSize)
                    .anchorPreference(key: GameHUDAnchors.self, value: .bounds) {
                        [.heart(index): $0]
                    }
                    .anchorPreference(key: AnswerHintAnchors.self, value: .bounds) { anchor in
                        guard isAnswerHintFlying,
                              index == (filledHalves - 1) / 2 else { return [:] }
                        // An even number of half-lives ends at the right side
                        // of a full heart; an odd amount ends at the left side.
                        return [.heart: anchor]
                    }
            }
        }
    }

    /// fill: 0 = empty, 1 = left half, 2 = full.
    private func heartIcon(fill: Int, spendingHalf: Bool = false,
                           spendingRightHalf: Bool = false) -> some View {
        ZStack {
            Image(systemName: "heart.fill")
                .foregroundStyle(theme.deepColor.opacity(0.28))
            if fill == 2 {
                Image(systemName: "heart.fill")
                    .foregroundStyle(theme.deepColor)
            } else if fill == 1 {
                Image(systemName: "heart.fill")
                    .foregroundStyle(theme.deepColor)
                    .mask(alignment: .leading) {
                        GeometryReader { geo in
                            Rectangle().frame(width: geo.size.width / 2)
                        }
                    }
            }
            // The flying piece has already left its slot. Painting this half
            // back with the empty-heart colour makes the deduction readable
            // from the first frame of the curved flight.
            if spendingHalf {
                Image(systemName: "heart.fill")
                    .foregroundStyle(theme.deepColor.opacity(0.28))
                    .mask(alignment: spendingRightHalf ? .trailing : .leading) {
                        GeometryReader { geo in
                            Rectangle().frame(width: geo.size.width / 2)
                        }
                    }
            }
        }
    }

    /// The equation the player sees. When the answer
    /// has been revealed, the "?" is replaced by the correct answer in place.
    private var displayedQuestion: String {
        guard state.isAnswerRevealed else { return state.questionText }
        return state.questionText.replacingOccurrences(of: "?", with: state.correctAnswer)
    }

    /// The equation. Tapping it reveals the
    /// answer in place of the "?" (staying until the next question) for the
    /// cost of half a life.
    private var equationBadge: some View {
        equationContent
            .foregroundStyle(.white)
            .animation(.snappy(duration: 0.3), value: displayedQuestion)
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
            .background(
                LinearGradient(colors: [theme.color, theme.deepColor],
                               startPoint: .top, endPoint: .bottom),
                in: RoundedRectangle(cornerRadius: 20)
            )
            .shadow(color: theme.deepColor.opacity(0.35), radius: 8, y: 4)
            .overlay(alignment: .topTrailing) {
                if tutorial.isActive && tutorial.currentStep == 6 {
                    ZStack {
                        Circle()
                            .fill(.white)
                        Image(systemName: "arrow.down.left.circle")
                            .foregroundStyle(theme.deepColor)
                    }
                    .font(.title.weight(.black))
                    .frame(width: 34, height: 34)
                        // The question mark sits down and to the left of this
                        // top-trailing overlay.  Move the cue in that same
                        // direction, rather than further along the edge.
                        .offset(x: isTutorialArrowBouncing ? 2 : 14,
                                y: isTutorialArrowBouncing ? -13.5 : -27)
                        .scaleEffect(isTutorialArrowBouncing ? 1.15 : 0.94)
                        .animation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true),
                                   value: isTutorialArrowBouncing)
                        .onAppear {
                            // This cue appears after the screen itself, so it
                            // needs its own state transition to start the
                            // repeating animation.
                            isTutorialArrowBouncing = false
                            DispatchQueue.main.async {
                                isTutorialArrowBouncing = true
                            }
                        }
                        .allowsHitTesting(false)
                }
            }
            .padding(.horizontal, 12)
            .contentShape(Rectangle())
            .onTapGesture {
                scene.tutorialQuestionWasTapped()
                requestAnswerHint()
            }
    }

    /// Delay the state change until the flying half-heart reaches the question
    /// mark. That makes the visible deduction and the revealed answer read as
    /// one cause-and-effect gesture instead of two unrelated animations.
    private func requestAnswerHint() {
        guard !isAnswerHintFlying else { return }
        guard state.canRevealAnswer else {
            if state.livesHalves == 1 { hintUnavailableFeedback() }
            return
        }

        guard let halves = state.livesHalves, halves > 1 else {
            // Endless play has no remaining heart to spend, so it keeps the
            // established instant reveal rather than inventing a fake flight.
            _ = state.revealAnswer()
            return
        }

        // Use the scene's retained, pre-warmed generator rather than a freshly
        // allocated one: a cold generator here cold-starts the Taptic Engine and
        // hitches on the first "tap the question mark" of the tutorial.
        scene.hintHaptic()
        isAnswerHintFlying = true
    }

    private func finishAnswerHintFlight() {
        guard isAnswerHintFlying else { return }
        isAnswerHintFlying = false
        AppAudio.shared.playAnswerInfo()
        _ = state.revealAnswer()
    }

    private var tutorialPrompt: some View {
        HStack(spacing: 10) {
            Image(systemName: tutorialIcon)
                .font(.title2.weight(.black))
            Text(tutorialText)
                .font(.callout.weight(.bold))
                .multilineTextAlignment(.leading)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
        .frame(maxWidth: 500)
        .background(theme.deepColor.opacity(0.92), in: Capsule())
        .shadow(color: .black.opacity(0.22), radius: 8, y: 3)
        .padding(.horizontal, 18)
        .animation(.snappy, value: tutorial.currentStep)
    }

    private var tutorialIcon: String {
        switch tutorial.currentStep {
        case 1: return "arrow.left.arrow.right"
        case 6: return "hand.tap.fill"
        case 7, 10: return "heart.fill"
        case 11: return "star.fill"
        default: return "arrow.up.circle.fill"
        }
    }

    private var tutorialText: String {
        switch tutorial.currentStep {
        case 1: return L("tutorial.move")
        case 2: return L("tutorial.platforms")
        case 3: return L("tutorial.correctAnswer")
        case 4: return L("tutorial.wrongAnswer")
        case 5: return L("tutorial.correctAnswerGreen")
        case 6: return L("tutorial.answerHint")
        case 7: return L("tutorial.lifePickup")
        case 8:
            return tutorial.triplerAnswerPending
                ? L("tutorial.doubler.answer")
                : L("tutorial.doubler.collect")
        case 9: return L("tutorial.minusOne")
        case 11: return L("tutorial.star")
        default: return ""
        }
    }

    // MARK: Equation rendering

    /// One piece of an equation: plain text, or a fraction to stack vertically.
    private enum EquationPiece: Identifiable {
        case text(String)
        case fraction(numerator: String, denominator: String)
        var id: String {
            switch self {
            case .text(let s): return "t:\(s)"
            case .fraction(let n, let d): return "f:\(n)/\(d)"
            }
        }
    }

    /// Splits the equation on spaces; any token containing a "/" becomes a
    /// stacked fraction (numerator over a bar over denominator).
    private func equationPieces(from question: String) -> [EquationPiece] {
        question.split(separator: " ").map { word in
            if let slash = word.firstIndex(of: "/") {
                let num = String(word[word.startIndex..<slash])
                let den = String(word[word.index(after: slash)...])
                return .fraction(numerator: num, denominator: den)
            }
            return .text(String(word))
        }
    }

    /// The equation, drawn with real stacked fractions when one is present and
    /// with the original single-line numeric text otherwise (so addition,
    /// tables, etc. keep their smooth digit transitions).
    @ViewBuilder
    private var equationContent: some View {
        let question = displayedQuestion
        let pieces = equationPieces(from: question)
        if question.contains("/") {
            ViewThatFits(in: .horizontal) {
                equationRow(fontSize: 38, pieces: pieces)
                equationRow(fontSize: 30, pieces: pieces)
                equationRow(fontSize: 24, pieces: pieces)
                equationRow(fontSize: 19, pieces: pieces)
            }
        } else {
            equationRow(fontSize: 38, pieces: pieces)
                .minimumScaleFactor(0.4)
        }
    }

    private func equationRow(fontSize: CGFloat, pieces: [EquationPiece]) -> some View {
        HStack(alignment: .center, spacing: fontSize * 0.18) {
            ForEach(Array(pieces.enumerated()), id: \.offset) { index, piece in
                switch piece {
                case .text(let s):
                    Text(s)
                        .font(.system(size: fontSize, weight: .heavy, design: .rounded))
                        .contentTransition(.numericText())
                        .anchorPreference(key: AnswerHintAnchors.self, value: .bounds) { anchor in
                            index == pieces.count - 1 ? [.question: anchor] : [:]
                        }
                case .fraction(let num, let den):
                    fractionView(numerator: num, denominator: den, fontSize: fontSize)
                }
            }
        }
        .lineLimit(1)
        .fixedSize()
    }

    /// A single stacked fraction: numerator, a bar, then the denominator.
    private func fractionView(numerator: String, denominator: String, fontSize: CGFloat) -> some View {
        let digit = fontSize * 0.55
        return VStack(spacing: digit * 0.14) {
            Text(numerator)
            RoundedRectangle(cornerRadius: 1)
                .frame(height: max(2, digit * 0.1))
            Text(denominator)
        }
        .font(.system(size: digit, weight: .heavy, design: .rounded))
        .fixedSize()
        .padding(.horizontal, 2)
        // The stack's geometric centre sits a touch high relative to where the
        // "−" and the middle of "=" fall on the operator line, so nudge the
        // whole fraction down a hair to line the bar up with them.
        .offset(y: fontSize * 0.07)
    }

    /// When the last remaining half-heart cannot pay for a hint, make that
    /// constraint visible without interrupting play or adding another label.
    private func hintUnavailableFeedback() {
#if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
#endif
        withAnimation(.easeInOut(duration: 0.07).repeatCount(3, autoreverses: true)) {
            heartHintNudge = 4
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
            withAnimation(.easeOut(duration: 0.08)) {
                heartHintNudge = 0
            }
        }
    }

    private var bottomBar: some View {
        // The equation and its status message share a fixed bottom lane rather
        // than being stacked. The warning is laid out beneath the equation and
        // never gets to change the equation's position when it appears.
        ZStack(alignment: .bottom) {
            if tutorial.isActive && tutorial.currentStep == 1 {
                // The first instruction occupies the equation lane below the
                // jump line, leaving every part of the playfield clear.
                tutorialPrompt
                    .padding(.bottom, 12)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else {
                equationBadge
                    .padding(.bottom, 36)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            if !(tutorial.isActive && tutorial.currentStep == 1) {
                statusLabel
                    .padding(.bottom, 0)
                    .animation(.snappy(duration: 0.25), value: state.isScoreLocked)
                    .animation(.snappy(duration: 0.25),
                               value: showsScoreboardFinishControls)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 16)
        .animation(.easeInOut(duration: 0.28), value: tutorial.currentStep)
    }

    /// The one status capsule shown under the equation. Priority, so they never
    /// stack and the equation stays put: past-the-cap → lives gone. The
    /// cap notice only shows while genuinely playing ON past 30 (never at the
    /// 30/30 completion, which ends the game instead).
    @ViewBuilder
    private var statusLabel: some View {
        if showsScoreboardFinishControls {
            Label("game.status.leaderboardMaxed", systemImage: "trophy.fill")
                .font(.caption.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(theme.deepColor.opacity(0.9), in: Capsule())
                .transition(.scale.combined(with: .opacity))
        } else if state.isScoreLocked {
            Label("game.status.scoreLocked", systemImage: "trophy.fill")
                .font(.caption.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(theme.deepColor.opacity(0.9), in: Capsule())
                .transition(.scale.combined(with: .opacity))
        }
    }

    // MARK: Game over

    private var gameOverOverlay: some View {
        ZStack {
            popoverBackdrop

            endGameCard(
                title: .plain(endScreenText.gameOverTitle),
                subtitle: endScreenText.encouragement(for: state.score),
                score: state.score,
                illustration: .character,
                emphasizesSubtitle: true,
                showsNewHighScore: state.beatsPreviousHighScore && state.score > 0
            )
            .opacity(showEndScreen ? 1 : 0)
            .scaleEffect(showEndScreen ? 1 : 0.93)
            .offset(y: showEndScreen ? 0 : 18)
            .animation(.spring(response: 0.46, dampingFraction: 0.82),
                       value: showEndScreen)
            // Useful while refining the UI: a deliberate long press on the
            // game-over card previews the 30/30 completion version.
            .onLongPressGesture(minimumDuration: 2) {
                isShowingCompletionPreview = true
            }

            // A matched-or-beaten best rains the same confetti as a completion,
            // layered above the card. `presentEndScreen` only arms it when this
            // run earned the celebration.
            if showConfetti {
                ConfettiView()
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
        // Any run that matches or beats the earlier best (including a first
        // score) rains confetti; only a lower score ends quietly.
        .onAppear { presentEndScreen(celebrating: state.didMatchOrBeatBest) }
    }

    // MARK: Completion (reached the 30-point goal)

    @State private var celebrate = false
    @State private var showConfetti = false

    private var completionOverlay: some View {
        ZStack {
            popoverBackdrop

            endGameCard(
                title: .completion(state.level),
                subtitle: endScreenText.completionSubtitle,
                // The real tally, so a run carried past the cap reads e.g. 31/30.
                // The debug preview keeps its clean 30/30 sample.
                score: isShowingCompletionPreview ? ProgressStore.maximumTrophies(for: state.level) : state.score,
                illustration: .trophy,
                emphasizesSubtitle: false,
                showsNewHighScore: state.beatsPreviousHighScore && state.score > 0
            )
            .opacity(showEndScreen ? 1 : 0)
            .scaleEffect(showEndScreen ? 1 : 0.93)
            .offset(y: showEndScreen ? 0 : 18)
            .animation(.spring(response: 0.46, dampingFraction: 0.82),
                       value: showEndScreen)

            // Layered above the card — like the tutorial celebration — so the
            // burst rains over the result screen rather than behind it. It
            // starts only after the card entrance is visibly underway.
            if showConfetti {
                ConfettiView()
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
        .onAppear {
            presentEndScreen(celebrating: true)
        }
    }

    /// Paints the scrim and card first, then starts the optional celebration
    /// after the entrance is visibly underway. Delays are long enough to cross
    /// a real display frame rather than relying on runloop coalescing.
    private func presentEndScreen(celebrating: Bool) {
        showEndScreen = false
        showConfetti = false
        showHighScoreBadge = false
        if celebrating { celebrate = false }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
            guard state.isGameOver else { return }
            showEndScreen = true
            if celebrating { celebrate = true }
        }

        // The personal-best sound plays whenever the run matched or beat the
        // earlier best — first scores and ties included (neither shows a badge).
        // Layered just after the card so it lands with the result.
        if state.didMatchOrBeatBest && state.score > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                guard state.isGameOver else { return }
                AppAudio.shared.playHighScore()
            }
        }

        // The record badge springs in on its own, a beat after the card has
        // settled, so it reads as an earned reward rather than static card text.
        if state.beatsPreviousHighScore && state.score > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                guard state.isGameOver else { return }
                // The badge view owns its own spring/shine animations, keyed on
                // this flag, so a plain assignment triggers the full entrance.
                showHighScoreBadge = true
            }
        }

        guard celebrating else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.34) {
            guard state.isGameOver else { return }
            showConfetti = true
        }
    }

    /// The result remains a pop-over: the playing field stays subtly visible,
    /// while the dark scrim separates it from the solid result card.
    private var popoverBackdrop: some View {
        Color.black.opacity(showEndScreen ? 0.56 : 0)
            .ignoresSafeArea()
            .animation(.easeOut(duration: 0.24), value: showEndScreen)
    }

    private enum EndIllustration {
        case trophy
        case character
    }

    private enum EndTitle {
        /// Plain heading, e.g. the "Game over" card.
        case plain(String)
        /// A finished level, rendered as its own operation — "+1 afgerond!",
        /// "×7 afgerond!", "25% afgerond!", "1 ⭐ afgerond!", or a stacked
        /// ¹⁄₂ fraction — instead of a bare level number with a category icon.
        case completion(LevelConfig)
    }

    /// Shared visual treatment for a completed level and a game over. Keeping
    /// the two outcomes structurally identical lets the score be the focus.
    private func endGameCard(
        title: EndTitle,
        subtitle: String,
        score: Int,
        illustration: EndIllustration,
        emphasizesSubtitle: Bool,
        showsNewHighScore: Bool
    ) -> some View {
        return GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
            endIllustration(illustration)
                .padding(.bottom, 18 * gameScale)

            endTitleView(title)
                .frame(maxWidth: .infinity)

            Text(subtitle)
                .font(.system(size: (emphasizesSubtitle ? 20 : 17) * gameTextScale,
                              weight: emphasizesSubtitle ? .semibold : .medium))
                .foregroundStyle(theme.deepColor.opacity(0.64))
                .multilineTextAlignment(.center)
                .padding(.top, 10 * gameScale)
                .frame(minHeight: 30 * gameScale)

            Text(verbatim: "\(score) / \(ProgressStore.maximumTrophies(for: state.level))")
                .environment(\.layoutDirection, .leftToRight) // keep "x / y" from flipping in RTL
                .font(.system(size: 30 * gameTextScale, weight: .heavy, design: .rounded))
                .foregroundStyle(theme.color)
                .padding(.horizontal, 27 * gameScale)
                .padding(.vertical, 10 * gameScale)
                .background(theme.tintColor, in: Capsule())
                .overlay {
                    Capsule().stroke(theme.color.opacity(0.12), lineWidth: 1)
                }
                // The smaller capsule deliberately sits just beyond the score's
                // top-right corner, leaving the tally itself unobscured.
                .overlay(alignment: .topTrailing) {
                    if showsNewHighScore {
                        newHighScoreBadge
                            .offset(x: 30, y: -16)
                    }
                }
                .padding(.top, 22 * gameScale)
                .accessibilityLabel("game.accessibility.scoreOutOf \(score) \(ProgressStore.maximumTrophies(for: state.level))")

            VStack(spacing: 12 * gameScale) {
                Button {
                    PausedGameStore.shared.remove(state)
                    scene.resetGame()
                } label: {
                    Label(endScreenText.playAgain, systemImage: "arrow.counterclockwise")
                        .font(isPad ? .title3.weight(.bold) : .headline.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14 * gameScale)
                        .foregroundStyle(.white)
                        .background(
                            LinearGradient(colors: [theme.color, theme.deepColor],
                                           startPoint: .top, endPoint: .bottom),
                            in: RoundedRectangle(cornerRadius: 17, style: .continuous)
                        )
                }

                Button {
                    dismiss()
                } label: {
                    Label(endScreenText.mainMenu, systemImage: "house.fill")
                        .font(isPad ? .title3.weight(.semibold) : .headline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14 * gameScale)
                        .foregroundStyle(theme.deepColor)
                        .background(theme.skyColor, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 17, style: .continuous)
                                .stroke(theme.color.opacity(0.24), lineWidth: 1.5)
                        }
                }
            }
            .padding(.top, 24 * gameScale)
            }
            .padding(26 * gameScale)
            .frame(maxWidth: 400 * gameScale)
            .background(
            LinearGradient(
                colors: [theme.skyColor, .white, theme.tintColor],
                startPoint: .top,
                endPoint: .bottom
            ),
            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(.white.opacity(0.82), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.22), radius: 24, y: 12)
                .padding(24)
                .frame(maxWidth: .infinity)
                // Match the intro card: centre whenever the card fits, but
                // preserve vertical scrolling in compact landscape sizes.
                .frame(minHeight: proxy.size.height, alignment: .center)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private var newHighScoreBadge: some View {
        HStack(spacing: 4) {
            Text("game.highScore")
                .lineLimit(1)
            Image(systemName: "trophy.fill")
        }
        // The badge is an overlay pinned to the score capsule's width, so a long
        // translation would wrap to two lines; fixedSize lets the capsule grow to
        // fit the label on a single line instead.
        .fixedSize()
        .font(.system(size: 13 * gameTextScale, weight: .bold, design: .rounded))
        // Match the score digits exactly, for every selected character theme.
        .foregroundStyle(.white)
        .padding(.horizontal, 10 * gameTextScale)
        .padding(.vertical, 6 * gameTextScale)
        .background(theme.color, in: Capsule())
        // A soft diagonal highlight sweeps across the badge once as it lands.
        // Clipped to the capsule, it starts and ends off the badge, so it is
        // invisible before and after the single pass — no fade bookkeeping.
        .overlay {
            Rectangle()
                .fill(LinearGradient(
                    colors: [.white.opacity(0), .white.opacity(0.75), .white.opacity(0)],
                    startPoint: .leading, endPoint: .trailing))
                .frame(width: 26)
                .rotationEffect(.degrees(22))
                .offset(x: showHighScoreBadge ? 130 : -130)
                .animation(.easeIn(duration: 0.5).delay(0.16), value: showHighScoreBadge)
        }
        .clipShape(Capsule())
        .overlay {
            Capsule().stroke(.white.opacity(0.45), lineWidth: 1)
        }
        .shadow(color: theme.deepColor.opacity(0.22), radius: 4, y: 2)
        // Entrance: a springy pop with a little overshoot and an unwinding tilt,
        // settling at the 0.8 scale the pinned overlay is sized for.
        .scaleEffect(showHighScoreBadge ? 0.8 : 0.12, anchor: .topTrailing)
        .rotationEffect(.degrees(showHighScoreBadge ? 0 : -28), anchor: .topTrailing)
        .opacity(showHighScoreBadge ? 1 : 0)
        .animation(.spring(response: 0.5, dampingFraction: 0.5), value: showHighScoreBadge)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("game.highScore")
    }

    /// The heading row of an end-of-game card. "Game over" is plain text; a
    /// finished level spells out the operation it practised followed by the
    /// localized "afgerond!" suffix.
    @ViewBuilder
    private func endTitleView(_ title: EndTitle) -> some View {
        let titleFontSize: CGFloat = 29 * gameTextScale
        let titleFont = Font.system(size: titleFontSize, weight: .heavy, design: .rounded)

        switch title {
        case .plain(let text):
            Text(text)
                .font(titleFont)
                .minimumScaleFactor(0.72)
                .lineLimit(1)
                .foregroundStyle(theme.deepColor)
        case .completion(let level):
            HStack(spacing: 7 * gameScale) {
                completionOperationLabel(for: level, fontSize: titleFontSize)
                Text(endScreenText.completionSuffix)
                    .font(titleFont)
                    .minimumScaleFactor(0.72)
                    .lineLimit(1)
            }
            .foregroundStyle(theme.deepColor)
        }
    }

    /// A finished level shown as the sum it stands for: "+1", "−1", "×25",
    /// "25%", a stacked ¹⁄₂ fraction, or the Supermix level number with a star.
    @ViewBuilder
    private func completionOperationLabel(for level: LevelConfig, fontSize: CGFloat) -> some View {
        let font = Font.system(size: fontSize, weight: .heavy, design: .rounded)
        let n = level.cardNumber

        switch level.category {
        case .addition, .additionMix:
            Text(verbatim: "+\(n)").font(font).lineLimit(1).minimumScaleFactor(0.72)
        case .subtraction, .subtractionMix:
            Text(verbatim: "−\(n)").font(font).lineLimit(1).minimumScaleFactor(0.72)
        case .tables, .tablesMix:
            Text(verbatim: "×\(n)").font(font).lineLimit(1).minimumScaleFactor(0.72)
        case .percentages, .percentagesMix:
            Text(verbatim: "\(n)%").font(font).lineLimit(1).minimumScaleFactor(0.72)
        case .fractions, .fractionsMix:
            completionFraction(numerator: "1", denominator: n, fontSize: fontSize)
        case .superBasic, .superTimes, .superFraction, .superAll:
            HStack(spacing: 5 * gameScale) {
                Text(verbatim: n).font(font).lineLimit(1).minimumScaleFactor(0.72)
                Image(systemName: "star.fill")
                    .font(.system(size: fontSize * 0.7, weight: .heavy))
            }
        }
    }

    /// A stacked fraction — numerator over a rule over the denominator — so a
    /// division level reads as "¹⁄₂" rather than a flat "1/2".
    private func completionFraction(numerator: String, denominator: String, fontSize: CGFloat) -> some View {
        let fracFont = Font.system(size: fontSize * 0.6, weight: .heavy, design: .rounded)
        let thickness = max(2, fontSize * 0.07)

        return VStack(spacing: thickness + 3 * gameScale) {
            Text(verbatim: numerator).font(fracFont).lineLimit(1)
            Text(verbatim: denominator).font(fracFont).lineLimit(1).minimumScaleFactor(0.5)
        }
        // The rule centers vertically in the gap and spans the wider of the two
        // numbers, since the overlay inherits the stack's natural width.
        .overlay {
            Rectangle()
                .fill(theme.deepColor)
                .frame(height: thickness)
        }
        .fixedSize()
        .padding(.horizontal, 2 * gameScale)
    }

    @ViewBuilder
    private func endIllustration(_ illustration: EndIllustration) -> some View {
        switch illustration {
        case .trophy:
            ZStack {
                Text(verbatim: "✦")
                    .font(.system(size: 25 * gameScale, weight: .bold))
                    .foregroundStyle(theme.color.opacity(0.68))
                    .offset(x: -54, y: -20)
                Text(verbatim: "✦")
                    .font(.system(size: 20 * gameScale, weight: .bold))
                    .foregroundStyle(theme.color.opacity(0.68))
                    .offset(x: 53, y: -8)
                Text(verbatim: "🏆")
                    .font(.system(size: 70 * gameScale))
                    .scaleEffect(celebrate ? 1 : 0.4)
                    .rotationEffect(.degrees(celebrate ? 0 : -25))
                    .animation(.spring(response: 0.55, dampingFraction: 0.5), value: celebrate)
            }
            .frame(height: 92 * gameScale)
        case .character:
            theme.artwork
                .resizable()
                .scaledToFit()
                .frame(width: 130 * gameScale, height: 104 * gameScale)
                .accessibilityHidden(true)
        }
    }

    private var endScreenText: EndScreenText { EndScreenText() }
}

/// The answer-streak coin shown in the HUD while the 5-in-a-row ×2 bonus is
/// live. It flips into place with a spinning pop, glints once, then breathes
/// gently for as long as the streak lasts — echoing the in-game ×3 pickup's
/// look so the reward reads as "another coin, now in your pocket".
private struct StreakCoin: View {
    let ink: Color
    let coinFill: Color
    let size: CGFloat

    @State private var spin = -170.0
    @State private var pulse = false
    @State private var glint = false

    var body: some View {
        ZStack {
            // Arrival glint: a ring that expands past the coin and fades once.
            Circle()
                .stroke(ink.opacity(0.55), lineWidth: 2)
                .frame(width: size, height: size)
                .scaleEffect(glint ? 2.1 : 0.7)
                .opacity(glint ? 0 : 0.9)

            Circle()
                .fill(coinFill)
                .overlay(
                    Text(verbatim: "×2")
                        .font(.system(size: size * 0.5, weight: .heavy, design: .rounded))
                        .foregroundStyle(ink)
                )
                .frame(width: size, height: size)
                .rotation3DEffect(.degrees(spin), axis: (x: 0, y: 1, z: 0))
                .scaleEffect(pulse ? 1.08 : 1.0)
                .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.55)) { spin = 0 }
            withAnimation(.easeOut(duration: 0.55)) { glint = true }
            withAnimation(.easeInOut(duration: 0.9)
                .repeatForever(autoreverses: true).delay(0.45)) { pulse = true }
        }
    }
}

extension AnyTransition {
    /// The streak coin breaking away when the streak ends: it swells, spins a
    /// little and fades while a red ring bursts outward. Used as a removal
    /// transition, so SwiftUI animates identity (progress 0) → active (1).
    static var streakCoinBreak: AnyTransition {
        .modifier(active: StreakCoinBreakModifier(progress: 1),
                  identity: StreakCoinBreakModifier(progress: 0))
    }
}

private struct StreakCoinBreakModifier: ViewModifier {
    let progress: Double
    func body(content: Content) -> some View {
        content
            .scaleEffect(1 + progress * 0.7)
            .rotationEffect(.degrees(progress * 40))
            .opacity(1 - progress)
            .overlay(
                Circle()
                    .stroke(Color.red, lineWidth: 2)
                    .scaleEffect(0.8 + progress * 1.7)
                    .opacity(progress < 0.5 ? progress * 1.8 : (1 - progress) * 1.8)
            )
    }
}

/// A half-heart that travels along the same gently bowed path used by the
/// game's shooting stars. Its endpoint is supplied by view anchors, rather
/// than hard-coded screen coordinates, so it lands on the actual question
/// mark even when the equation is resized for fractions or a small phone.
private struct AnswerHintFlight: View {
    let source: CGPoint
    let destination: CGPoint
    let canvasWidth: CGFloat
    let sourceIsRightHalf: Bool
    let color: Color
    let onArrival: () -> Void

    @State private var progress: CGFloat = 0
    @State private var hasArrived = false
    @State private var arrivalRingScale: CGFloat = 0.35
    @State private var arrivalRingOpacity = 0.0

    /// A broad, two-control-point curve: it first moves out along the right
    /// edge, travels down that edge, then turns toward the question mark.
    private var rightEdge: CGFloat { canvasWidth - 26 }
    private var firstControl: CGPoint {
        CGPoint(x: rightEdge, y: source.y + 72)
    }
    private var secondControl: CGPoint {
        CGPoint(x: rightEdge, y: destination.y - 94)
    }

    /// Stay at full size for almost the whole flight, then shrink rapidly into
    /// the question mark during the final tenth of the path.
    private var heartScale: CGFloat {
        let finalSegment = max(CGFloat.zero, min(1, (progress - 0.90) / 0.10))
        return 1 - finalSegment
    }

    private func point(at t: CGFloat) -> CGPoint {
        let inverse = 1 - t
        return CGPoint(
            x: inverse * inverse * inverse * source.x
                + 3 * inverse * inverse * t * firstControl.x
                + 3 * inverse * t * t * secondControl.x
                + t * t * t * destination.x,
            y: inverse * inverse * inverse * source.y
                + 3 * inverse * inverse * t * firstControl.y
                + 3 * inverse * t * t * secondControl.y
                + t * t * t * destination.y
        )
    }

    var body: some View {
        ZStack {
            // Same arrival language as the ×2 bubble reaching the trophy:
            // a compact ring expands exactly where the object lands.
            Circle()
                .stroke(color, lineWidth: 3)
                .frame(width: 18, height: 18)
                .scaleEffect(arrivalRingScale)
                .opacity(arrivalRingOpacity)
                .position(destination)

            Image(systemName: "heart.fill")
                .font(.system(size: GameHUDMetrics.assetSize, weight: .heavy))
                .foregroundStyle(color)
                .frame(width: GameHUDMetrics.assetSize, height: GameHUDMetrics.assetSize)
                // Clip the actual glyph, instead of masking it. This keeps a
                // spent RIGHT half visibly right-handed (and vice versa) on
                // every OS rendering of SF Symbols.
                .frame(width: GameHUDMetrics.assetSize / 2, height: GameHUDMetrics.assetSize,
                       alignment: sourceIsRightHalf ? .trailing : .leading)
                .clipped()
                .shadow(color: .white.opacity(0.7), radius: 1.5)
                .shadow(color: color.opacity(0.38), radius: 6, y: 3)
                .scaleEffect(heartScale)
                .rotationEffect(.degrees(-18 + Double(progress) * 44))
                .opacity(1)
                .position(point(at: progress))

        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            // Give the player an extra half-second to follow the heart all
            // the way down the right-hand arc before the answer replaces '?'.
            // A uniform flight keeps the last scale-down phase aligned with
            // the actual arrival, instead of leaving an empty pause before
            // the answer appears.
            withAnimation(.linear(duration: 0.53)) {
                progress = 1
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.53) {
                guard !hasArrived else { return }
                hasArrived = true
                arrivalRingScale = 0.35
                arrivalRingOpacity = 0.95
                withAnimation(.easeOut(duration: 0.11)) {
                    arrivalRingScale = 2.2
                    arrivalRingOpacity = 0
                }
                // Keep the heart fully visible through the landing ping; the
                // state changes only after the feedback has registered.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
                    onArrival()
                }
            }
        }
    }
}

/// All copy is resolved from the string catalog, so there are no
/// language checks in the code — a new language is added purely in the catalog.
private struct EndScreenText {
    var completionSubtitle: String { L("game.end.completionSubtitle") }
    var completionSuffix: String { L("game.end.completionSuffix") }
    var gameOverTitle: String { L("game.end.gameOverTitle") }
    var playAgain: String { L("game.end.playAgain") }
    var mainMenu: String { L("game.end.mainMenu") }

    func encouragement(for score: Int) -> String {
        // Ten graded messages, keyed game.encouragement.0 … .9 in the catalog.
        let index = min(max(score, 0) / 3, 9)
        return L(key: "game.encouragement.\(index)")
    }
}

/// Lightweight falling-confetti burst for the completion screen.
private struct ConfettiView: View {
    @State private var pieces: [ConfettiPiece]
    @State private var fallen = false

    init() {
        _pieces = State(initialValue: (0..<44).map { _ in ConfettiPiece() })
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(pieces) { piece in
                    Rectangle()
                        .fill(piece.color)
                        .frame(width: piece.size, height: piece.size * 0.5)
                        .rotationEffect(.degrees(fallen ? piece.spin : 0))
                        .position(
                            x: piece.x * geo.size.width,
                            y: fallen ? geo.size.height + 40 : -40
                        )
                        .opacity(fallen ? 0 : 1)
                        .animation(
                            .easeIn(duration: piece.duration).delay(piece.delay),
                            value: fallen
                        )
                }
            }
        }
        // A short real-time gap guarantees the initial above-screen positions
        // have been presented before the fall begins. The pieces live in State,
        // so their UUIDs and random paths remain stable across body updates.
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                fallen = true
            }
        }
    }
}

/// A small caret-topped card matching the home-menu info pop-out styling — a
/// white fill, a hairline theme stroke and a soft shadow — but headerless. The
/// message is kept to two lines and shrinks to fit when a translation is long.
private struct SpokenUnavailableCard: View {
    let message: String
    let caretOffset: CGFloat
    let theme: AnimalCharacter
    let isPad: Bool

    var body: some View {
        VStack(spacing: 0) {
            SpokenCaretTriangle()
                .fill(.white)
                .frame(width: 18, height: 9)
                .overlay(alignment: .bottom) {
                    // Hide the seam where the caret meets the card body.
                    Rectangle().fill(.white).frame(height: 1).padding(.horizontal, 2)
                }
                .offset(x: caretOffset)

            Text(message)
                .font(.system(size: isPad ? 18 : 15, weight: .bold))
                .foregroundStyle(theme.deepColor)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.5)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, isPad ? 18 : 14)
                .padding(.vertical, isPad ? 14 : 11)
                .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(theme.deepColor.opacity(0.18), lineWidth: 1))
        }
        .shadow(color: theme.deepColor.opacity(0.22), radius: 14, y: 6)
    }
}

/// An upward-pointing triangle for the pop-out caret.
private struct SpokenCaretTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct ConfettiPiece: Identifiable {
    let id = UUID()
    let x = CGFloat.random(in: 0...1)
    let size = CGFloat.random(in: 7...13)
    let spin = Double.random(in: 180...900)
    let duration = Double.random(in: 1.4...2.6)
    let delay = Double.random(in: 0...0.5)
    let color: Color = [
        .red, .orange, .yellow, .green, .blue, .purple, .pink
    ].randomElement()!
}

#Preview {
    GameView(level: LevelCatalog.levels(for: .tables)[6])
}
