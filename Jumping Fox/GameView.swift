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
    case heart(Int)
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

    // Pre-game mode intro card. The field is frozen until the player starts.
    @State private var showingIntro: Bool
    @State private var isContinuingLevel: Bool
    @State private var isPausedAtIntro = false
    @State private var isShowingCompletionPreview = false
    @State private var heartHintNudge: CGFloat = 0
    @State private var isAnswerHintFlying = false
    @State private var suppressIntroTap = false
    @State private var isTutorialArrowBouncing = false
    @State private var showsTutorialCompletion = false
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
    private var introTitleScale: CGFloat { 0.9 }
    private var introFeatureIconScale: CGFloat { 0.8 }
    private var introFeatureTextScale: CGFloat { isPad ? 1.1 : 0.88 }

    init(level: LevelConfig) {
        // A maxed card also shows its paused score, so an in-progress run can
        // be resumed regardless of the recorded best score.
        let canResume = PausedGameStore.shared.hasPausedSession(for: level, mode: GameSettings.lifeMode)
        _isContinuingLevel = State(initialValue: canResume)
        let state = canResume ? PausedGameStore.shared.gameState(for: level) : GameState(level: level)
        _state = StateObject(wrappedValue: state)
        _scene = State(initialValue: GameScene(state: state))
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

            // Warm up the status-banner symbols so the very first time the
            // trophy warning (or MIX MODE) animates in, there's no one-off
            // glyph-rasterisation hitch. Rendered invisibly from the start.
            ZStack {
                Image(systemName: "trophy.fill")
                Image(systemName: "shuffle")
            }
            .font(.caption.weight(.bold))
            .opacity(0)
            .allowsHitTesting(false)

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
        }
        .onDisappear {
            if tutorial.developerMode { tutorial.leaveDeveloperMode() }
            PlaytimeTracker.shared.challengeEnded()
            setScreenAwake(false)
        }
        .onChange(of: tutorial.isComplete) { complete in
            guard complete else { return }
            withAnimation(.snappy) { showsTutorialCompletion = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                withAnimation(.easeOut(duration: 0.25)) { showsTutorialCompletion = false }
            }
        }
        .onChange(of: state.isGameOver) { over in
            if over {
                PausedGameStore.shared.remove(state)
                TutorialProgress.shared.markGameOver()
                // Defer the tracker's disk write off this frame so the game-over
                // / completion overlay paints without waiting on it.
                DispatchQueue.main.async { PlaytimeTracker.shared.challengeEnded() }
            } else {
                PlaytimeTracker.shared.challengeStarted()
                // Rearm the celebration for the next completion.
                celebrate = false
                showConfetti = false
                isShowingCompletionPreview = false
                // After the tutorial, fresh runs use the normal level start
                // screen again (including its route back to the main menu).
                isContinuingLevel = false
                showingIntro = !tutorial.isActive
                scene.isFrozen = !tutorial.isActive
            }
        }
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
        let hearts = Dictionary(uniqueKeysWithValues: (0..<3).compactMap { index in
            anchors[.heart(index)].map { (index, globalRect(for: $0)) }
        })
        scene.setHUDTargets(trophy: trophy, hearts: hearts, viewSize: proxy.size)
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
        guard !suppressIntroTap else {
            suppressIntroTap = false
            return
        }
        dismissIntro()
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
            IntroFeature(icon: featureIcon, text: practiceDescription(info: info)),
            IntroFeature(number: state.level.cardNumber, text: detailDescription(info: info)),
            IntroFeature(icon: "trophy.fill", text: trophyDescription)
        ]
        return ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()

            GeometryReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .bottom, spacing: 14) {
                            characterPortrait
                            VStack(alignment: .leading, spacing: 8) {
                                Text(info.title)
                                    .font(.system(size: 33 * gameTextScale * introTitleScale, weight: .heavy, design: .rounded))
                                    .foregroundStyle(theme.deepColor)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.80)
                                    .layoutPriority(1)
                                HStack(spacing: 7) {
                                    introStatusLabel(icon: state.lifeMode == .unlimited ? "infinity" : "heart.fill",
                                                     text: state.lifeMode == .unlimited ? L("game.intro.livesOff") : L("game.intro.livesOn"))
                                    introStatusLabel(icon: "lightbulb.fill", text: state.isAnswerHelperEnabled ? L("game.intro.helperOn") : L("game.intro.helperOff"))
                                }
                            }
                            Spacer(minLength: 0)
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
        .contentShape(Rectangle())
        .onTapGesture(perform: dismissIntroFromTap)
        .transition(.opacity)
    }

    private var characterPortrait: some View {
        theme.artwork
            .resizable()
            .scaledToFit()
            .padding(8)
            // The feature cards inset their 54 pt icon by 10 pt. Keeping this
            // card 64 pt wide makes its trailing edge meet the icon edge while
            // the following title column starts exactly with the feature copy.
            .frame(width: 64 * gameScale, height: 64 * gameScale)
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

    private func introStatusLabel(icon: String, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: (icon == "infinity" ? 12 : 10) * gameTextScale, weight: .heavy, design: .rounded))
            Text(text)
        }
            .font(.system(size: 10 * gameTextScale, weight: .bold))
            .foregroundStyle(theme.deepColor.opacity(0.82))
            .lineLimit(1)
            .padding(.horizontal, 8 * gameScale)
            .padding(.vertical, 5 * gameScale)
            .background(theme.skyColor.opacity(0.72), in: Capsule())
            .overlay(Capsule().stroke(theme.deepColor.opacity(0.15), lineWidth: 1))
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

    /// Localized descriptions use **bold** markers. Keeping the markers in
    /// the string catalog lets each language choose its own emphasis.
    private func emphasizedText(_ copy: String) -> Text {
        let parts = copy.components(separatedBy: "**")
        var result = Text("")
        for (index, part) in parts.enumerated() {
            result = result + (index.isMultiple(of: 2)
                ? Text(part)
                : Text(part).fontWeight(.bold))
        }
        return result
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

    private func practiceDescription(info: (title: String, bullets: [String])) -> String {
        // The Supermix menu is deliberately an all-in-one introduction. The
        // five skill menus instead explain the current skill and its order clearly.
        guard !state.level.category.isSupermixMenu else {
            return info.bullets[0]
        }
        let order = state.level.startsInMix || state.level.category.isMix
            ? L("game.intro.orderRandom")
            : L("game.intro.orderAscending")
        return L("game.intro.practiceOrdered \(practiceSubject) \(order)")
    }

    private func detailDescription(info: (title: String, bullets: [String])) -> String {
        switch state.level.category {
        case .addition, .subtraction, .tables:
            // The first mode-specific bullet is intentionally shown on the
            // second card; the first card keeps its shared practice-order copy.
            return info.bullets[0]
        default:
            return info.bullets[1]
        }
    }

    private var practiceSubject: String {
        switch state.level.category {
        case .addition, .additionMix: return L("game.intro.subject.addition")
        case .subtraction, .subtractionMix: return L("game.intro.subject.subtraction")
        case .tables, .tablesMix: return L("game.intro.subject.tables")
        case .fractions, .fractionsMix: return L("game.intro.subject.fractions")
        case .percentages, .percentagesMix: return L("game.intro.subject.percentages")
        case .superBasic, .superTimes, .superFraction, .superAll: return ""
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
        state.isEndless || state.isPastScoreboardCap
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
            }
            .fixedSize()

            livesBadge
                .frame(maxWidth: .infinity, alignment: .trailing)
                .offset(x: heartHintNudge)
                .animation(.snappy(duration: 0.3), value: state.isEndless)
        }
        .padding(.horizontal)
        .padding(.top, 8)
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

#if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
#endif
        isAnswerHintFlying = true
    }

    private func finishAnswerHintFlight() {
        guard isAnswerHintFlying else { return }
        isAnswerHintFlying = false
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
            return tutorial.doublerAnswerPending
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
    private var equationPieces: [EquationPiece] {
        displayedQuestion.split(separator: " ").map { word in
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
        if displayedQuestion.contains("/") {
            ViewThatFits(in: .horizontal) {
                equationRow(fontSize: 38)
                equationRow(fontSize: 30)
                equationRow(fontSize: 24)
                equationRow(fontSize: 19)
            }
        } else {
            equationRow(fontSize: 38)
                .minimumScaleFactor(0.4)
        }
    }

    private func equationRow(fontSize: CGFloat) -> some View {
        HStack(alignment: .center, spacing: fontSize * 0.18) {
            let pieces = equationPieces
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
                    .animation(.snappy(duration: 0.25), value: state.isPastScoreboardCap)
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
        if state.isPastScoreboardCap {
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
                leadingTitle: endScreenText.gameOverTitle,
                trailingTitle: nil,
                subtitle: endScreenText.encouragement(for: state.score),
                score: state.score,
                illustration: .character,
                titleIcon: nil,
                showsMixIndicator: false,
                emphasizesSubtitle: true,
                showsNewHighScore: state.isNewHighScore && state.score > 0
            )
            // Useful while refining the UI: a deliberate long press on the
            // game-over card previews the 30/30 completion version.
            .onLongPressGesture(minimumDuration: 2) {
                isShowingCompletionPreview = true
            }
        }
    }

    // MARK: Completion (reached the 30-point goal)

    @State private var celebrate = false
    @State private var showConfetti = false

    private var completionOverlay: some View {
        ZStack {
            popoverBackdrop

            if showConfetti {
                ConfettiView()
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }

            endGameCard(
                leadingTitle: "\(state.level.index)",
                trailingTitle: endScreenText.completionSuffix,
                subtitle: endScreenText.completionSubtitle,
                // The real tally, so a run carried past the cap reads e.g. 31/30.
                // The debug preview keeps its clean 30/30 sample.
                score: isShowingCompletionPreview ? ProgressStore.maximumTrophies(for: state.level) : state.score,
                illustration: .trophy,
                titleIcon: endScreenText.menuIcon(for: state.level),
                showsMixIndicator: state.level.startsInMix,
                emphasizesSubtitle: false,
                showsNewHighScore: state.isNewHighScore && state.score > 0
            )
        }
        .onAppear {
            celebrate = true
#if canImport(UIKit)
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
#endif
            // Let the completion card paint on this frame; bring the confetti in
            // on the next runloop so building its nodes never delays the popup.
            DispatchQueue.main.async { showConfetti = true }
        }
    }

    /// The result remains a pop-over: the playing field stays subtly visible,
    /// while the dark scrim separates it from the solid result card.
    private var popoverBackdrop: some View {
        Color.black.opacity(0.56).ignoresSafeArea()
    }

    private enum EndIllustration {
        case trophy
        case character
    }

    /// Shared visual treatment for a completed level and a game over. Keeping
    /// the two outcomes structurally identical lets the score be the focus.
    private func endGameCard(
        leadingTitle: String,
        trailingTitle: String?,
        subtitle: String,
        score: Int,
        illustration: EndIllustration,
        titleIcon: String?,
        showsMixIndicator: Bool,
        emphasizesSubtitle: Bool,
        showsNewHighScore: Bool
    ) -> some View {
        // SF Symbols use their full em square, while rounded digits only fill
        // their cap height. Keep the circular category sign optically as high
        // as the level number instead of making its diameter equal to the
        // number's point size.
        let titleFontSize: CGFloat = 29 * gameTextScale
        let titleIconSize = titleFontSize * 0.76

        return GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
            endIllustration(illustration)
                .padding(.bottom, 18 * gameScale)

            HStack(spacing: 7 * gameScale) {
                Text(leadingTitle)
                    .font(.system(size: titleFontSize, weight: .heavy, design: .rounded))
                    .minimumScaleFactor(0.72)
                    .lineLimit(1)
                if let titleIcon {
                    // Sized to the visible height of the rounded number. In
                    // Mix mode the badge scales from this same icon size.
                    endTitleIcon(titleIcon, size: titleIconSize, showsMix: showsMixIndicator)
                }
                if let trailingTitle {
                    Text(trailingTitle)
                        .font(.system(size: titleFontSize, weight: .heavy, design: .rounded))
                        .minimumScaleFactor(0.72)
                        .lineLimit(1)
                }
            }
            .foregroundStyle(theme.deepColor)
            .frame(maxWidth: .infinity)

            Text(subtitle)
                .font(.system(size: (emphasizesSubtitle ? 20 : 17) * gameTextScale,
                              weight: emphasizesSubtitle ? .semibold : .medium))
                .foregroundStyle(theme.deepColor.opacity(0.64))
                .multilineTextAlignment(.center)
                .padding(.top, 10 * gameScale)
                .frame(minHeight: 30 * gameScale)

            Text(verbatim: "\(score) / \(ProgressStore.maximumTrophies(for: state.level))")
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
            Image(systemName: "trophy.fill")
        }
        .font(.system(size: 13 * gameTextScale, weight: .bold, design: .rounded))
        // Match the score digits exactly, for every selected character theme.
        .foregroundStyle(.white)
        .padding(.horizontal, 10 * gameTextScale)
        .padding(.vertical, 6 * gameTextScale)
        .background(theme.color, in: Capsule())
        .overlay {
            Capsule().stroke(.white.opacity(0.45), lineWidth: 1)
        }
        .shadow(color: theme.deepColor.opacity(0.22), radius: 4, y: 2)
        .scaleEffect(0.8, anchor: .topTrailing)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("game.highScore")
    }

    @ViewBuilder
    private func endTitleIcon(_ icon: String, size: CGFloat, showsMix: Bool) -> some View {
        let mixBadgeSize = size * 0.62
        let mixBadgeOffset = size * 0.31

        Group {
            if icon == "percent" {
                // `percent.circle.fill` is not an SF Symbol. This custom badge
                // mirrors the circular percentage icon in the main menu.
                Image(systemName: "percent")
                    .font(.system(size: size * 0.5, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(width: size, height: size)
                    .background(theme.deepColor, in: Circle())
            } else {
                Image(systemName: icon)
                    .font(.system(size: size, weight: .heavy))
            }
        }
        .overlay(alignment: .topTrailing) {
            if showsMix {
                // Mix badge keeps its own (smaller) size, laid over the
                // category sign's top-right corner, about half overlapping.
                Image(systemName: "shuffle.circle.fill")
                    .font(.system(size: mixBadgeSize, weight: .heavy))
                    .foregroundStyle(theme.deepColor)
                    .background(Circle().fill(.white).padding(-1.5))
                    .offset(x: mixBadgeOffset, y: -mixBadgeOffset)
                    .accessibilityLabel("game.accessibility.mix")
            }
        }
        // Reserve room so the overhanging mix badge never touches the next word.
        .padding(.trailing, showsMix ? mixBadgeOffset : 0)
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

    /// Mirrors the six symbols in the main menu, so the achievement is
    /// immediately recognisable without repeating a category name.
    func menuIcon(for level: LevelConfig) -> String {
        switch level.category {
        case .addition, .additionMix: return "plus.circle.fill"
        case .subtraction, .subtractionMix: return "minus.circle.fill"
        case .tables, .tablesMix: return "multiply.circle.fill"
        case .fractions, .fractionsMix: return "circle.lefthalf.filled"
        case .percentages, .percentagesMix: return "percent"
        case .superBasic, .superTimes, .superFraction, .superAll: return "star.circle.fill"
        }
    }

    func encouragement(for score: Int) -> String {
        // Ten graded messages, keyed game.encouragement.0 … .9 in the catalog.
        let index = min(max(score, 0) / 3, 9)
        return Bundle.main.localizedString(forKey: "game.encouragement.\(index)", value: nil, table: nil)
    }
}

/// Lightweight falling-confetti burst for the completion screen.
private struct ConfettiView: View {
    private let pieces = (0..<44).map { _ in ConfettiPiece() }
    @State private var fallen = false

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
            // Composite all pieces into one Metal layer so the fall animates
            // smoothly instead of stuttering as it starts.
            .drawingGroup()
        }
        .onAppear { fallen = true }
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
