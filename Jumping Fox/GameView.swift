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

struct GameView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var state: GameState
    @State private var scene: GameScene
    @AppStorage(GameSettings.answerHintKey) private var answerHintEnabled = true

    // Pre-game mode intro card. The field is frozen until the player starts.
    @State private var showingIntro = true
    @State private var isContinuingLevel: Bool
    @State private var isShowingCompletionPreview = false
    @State private var heartHintNudge: CGFloat = 0
    private let theme = CharacterCatalog.current(isPremium: GameSettings.premiumUnlockedCache)

    init(level: LevelConfig) {
        _isContinuingLevel = State(initialValue: PausedGameStore.shared.hasPausedSession(for: level, mode: GameSettings.lifeMode))
        let state = PausedGameStore.shared.gameState(for: level)
        _state = StateObject(wrappedValue: state)
        _scene = State(initialValue: GameScene(state: state))
    }

    var body: some View {
        ZStack {
            SpriteView(scene: scene)
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
                if state.gameOverReason == .completed || isShowingCompletionPreview {
                    completionOverlay
                } else {
                    gameOverOverlay
                }
            }

            if showingIntro && !state.isGameOver {
                introCard
            }
        }
        .onAppear {
            PlaytimeTracker.shared.challengeStarted()
            setScreenAwake(true)
        }
        .onDisappear {
            PlaytimeTracker.shared.challengeEnded()
            setScreenAwake(false)
        }
        .onChange(of: state.isGameOver) { _, over in
            if over {
                PausedGameStore.shared.remove(state)
                // Defer the tracker's disk write off this frame so the game-over
                // / completion overlay paints without waiting on it.
                DispatchQueue.main.async { PlaytimeTracker.shared.challengeEnded() }
            } else {
                PlaytimeTracker.shared.challengeStarted()
                // Rearm the celebration for the next completion.
                celebrate = false
                showConfetti = false
                isShowingCompletionPreview = false
                // A fresh run (Play Again / Nog een keer) shows the intro again.
                isContinuingLevel = false
                beginIntro()
            }
        }
    }

    /// Keep the display from dimming/locking during play.
    private func setScreenAwake(_ awake: Bool) {
#if canImport(UIKit)
        UIApplication.shared.isIdleTimerDisabled = awake
#endif
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

    private var introCard: some View {
        let info = ModeIntro.info(for: state.level)
        let trophyBullet = "Verdien 1 trofee per goed antwoord, met een maximum van 30."
        let unlimitedLivesBullet = "Nadat je levens op zijn, kun je geen trofeeën meer verdienen."
        let helperBullet = "Het goede antwoord is groen gemarkeerd omdat de helper aanstaat. Trofeeën worden daarom apart geteld met *."
        let bullets = info.bullets
            + [trophyBullet]
            + (state.lifeMode == .unlimited ? [unlimitedLivesBullet] : [])
            + (state.isAnswerHelperEnabled ? [helperBullet] : [])
        return ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                // Keep the header focused on the level name: the character
                // stays on the home screen and doesn't compete with the copy.
                Text(info.title)
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .foregroundStyle(theme.deepColor)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity)

                Text("Zo werkt dit level")
                    .font(.headline.weight(.heavy))
                    .foregroundStyle(theme.deepColor)

                Rectangle()
                    .fill(theme.color.opacity(0.3))
                    .frame(height: 1)

                VStack(alignment: .leading, spacing: 14) {
                    ForEach(bullets, id: \.self) { bullet in
                        HStack(alignment: .firstTextBaseline, spacing: 14) {
                            Circle()
                                .fill(theme.color)
                                .frame(width: 10, height: 10)
                            Text(bullet)
                                .font(.subheadline)
                                .foregroundStyle(theme.deepColor.opacity(0.86))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                Button(action: dismissIntro) {
                    Text(isContinuingLevel ? "Speel verder" : "Start level")
                        .font(.headline.weight(.heavy))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .foregroundStyle(.white)
                        .background(theme.deepColor, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(28)
            .frame(maxWidth: 340)
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(theme.deepColor.opacity(0.18), lineWidth: 1)
            )
            .shadow(color: theme.deepColor.opacity(0.28), radius: 18, y: 8)
            .background(.background, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .padding()
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: dismissIntro)
        .transition(.opacity)
    }

    // MARK: HUD

    private var topBar: some View {
        HStack(spacing: 0) {
            Button {
                if state.isEndless {
                    // Finishing an unlimited run still deserves the result card.
                    state.finishEndlessRun()
                } else {
                    PausedGameStore.shared.pause(state)
                }
                dismiss()
            } label: {
                // Normal pause button until the three lives run out; then a
                // checkmark "done" button of the same size.
                Image(systemName: state.isEndless ? "checkmark.circle.fill" : "pause.circle.fill")
                    .font(.title)
                    .foregroundStyle(theme.deepColor.opacity(0.85))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.snappy(duration: 0.25), value: state.isEndless)

            // Just the trophy count: the score number followed by a trophy.
            // The equal-width side columns keep it perfectly centered.
            HStack(spacing: 6) {
                Text("\(state.score)")
                    .font(.title2.weight(.heavy))
                    .foregroundStyle(theme.deepColor)
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.25), value: state.score)
                Image(systemName: "trophy.fill")
                    .font(.title3)
                    .foregroundStyle(theme.deepColor)
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
                .font(.title3)
                .foregroundStyle(theme.deepColor)
                .transition(.scale.combined(with: .opacity))
        } else if let halves = state.livesHalves {
            heartRow(filledHalves: halves)
                .font(.title3)
                .animation(.snappy(duration: 0.25), value: halves)
        }
    }

    /// A row of three hearts that can each be full, half or empty, driven by a
    /// value in HALF units (0...6). Lets a hint show as half a heart.
    private func heartRow(filledHalves: Int) -> some View {
        HStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { index in
                heartIcon(fill: min(2, max(0, filledHalves - index * 2)))
            }
        }
    }

    /// fill: 0 = empty, 1 = left half, 2 = full.
    private func heartIcon(fill: Int) -> some View {
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
        }
    }

    /// The equation the player sees. When the hint is active and the answer
    /// has been revealed, the "?" is replaced by the correct answer in place.
    private var displayedQuestion: String {
        guard answerHintEnabled, state.isAnswerRevealed else { return state.questionText }
        return state.questionText.replacingOccurrences(of: "?", with: state.correctAnswer)
    }

    /// The equation. When the hint option is on, tapping it reveals the
    /// answer in place of the "?" (staying until the next question) for the
    /// cost of half a life.
    private var equationBadge: some View {
        Text(displayedQuestion)
            .font(.system(size: 38, weight: .heavy, design: .rounded))
            .minimumScaleFactor(0.4)
            .lineLimit(1)
            .foregroundStyle(.white)
            .contentTransition(.numericText())
            .animation(.snappy(duration: 0.3), value: displayedQuestion)
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
            .background(
                LinearGradient(colors: [theme.color, theme.deepColor],
                               startPoint: .top, endPoint: .bottom),
                in: RoundedRectangle(cornerRadius: 20)
            )
            .shadow(color: theme.deepColor.opacity(0.35), radius: 8, y: 4)
            .padding(.horizontal, 12)
            .contentShape(Rectangle())
            .onTapGesture {
                guard answerHintEnabled else { return }
                if !state.revealAnswer(), state.livesHalves == 1 {
                    hintUnavailableFeedback()
                }
            }
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
            equationBadge
                .padding(.bottom, 36)

            statusLabel
                .padding(.bottom, 0)
                .animation(.snappy(duration: 0.25), value: state.isRandomPractice)
                .animation(.snappy(duration: 0.25), value: state.isScoreLocked)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 16)
    }

    /// The one status capsule shown under the equation. The trophy warning
    /// outranks MIX MODE, so they never stack — the equation stays put.
    @ViewBuilder
    private var statusLabel: some View {
        if state.isScoreLocked {
            Label("Trofeeën tellen niet meer mee nadat je levens op zijn", systemImage: "trophy.fill")
                .font(.caption.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(theme.deepColor.opacity(0.9), in: Capsule())
                .transition(.scale.combined(with: .opacity))
        } else if state.isRandomPractice {
            Label("MIX MODE", systemImage: "shuffle")
                .font(.caption.weight(.heavy))
                .tracking(1.2)
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
                emphasizesSubtitle: true
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
                score: ProgressStore.maximumTrophiesPerLevel,
                illustration: .trophy,
                titleIcon: endScreenText.menuIcon(for: state.level),
                showsMixIndicator: state.level.startsInMix,
                emphasizesSubtitle: false
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
        emphasizesSubtitle: Bool
    ) -> some View {
        VStack(spacing: 0) {
            endIllustration(illustration)
                .padding(.bottom, 18)

            HStack(spacing: 7) {
                Text(leadingTitle)
                    .font(.system(size: 29, weight: .heavy, design: .rounded))
                    .minimumScaleFactor(0.72)
                    .lineLimit(1)
                if let titleIcon {
                    endTitleIcon(titleIcon)
                }
                if showsMixIndicator {
                    Image(systemName: "shuffle.circle.fill")
                        .font(.title3.weight(.heavy))
                        .accessibilityLabel("Mix")
                }
                if let trailingTitle {
                    Text(trailingTitle)
                        .font(.system(size: 29, weight: .heavy, design: .rounded))
                        .minimumScaleFactor(0.72)
                        .lineLimit(1)
                }
            }
            .foregroundStyle(theme.deepColor)
            .frame(maxWidth: .infinity)

            Text(subtitle)
                .font(emphasizesSubtitle ? .title3.weight(.semibold) : .headline.weight(.medium))
                .foregroundStyle(theme.deepColor.opacity(0.64))
                .multilineTextAlignment(.center)
                .padding(.top, 10)
                .frame(minHeight: 30)

            Text("\(score) / \(ProgressStore.maximumTrophiesPerLevel)")
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .foregroundStyle(theme.color)
                .padding(.horizontal, 27)
                .padding(.vertical, 10)
                .background(theme.tintColor, in: Capsule())
                .overlay {
                    Capsule().stroke(theme.color.opacity(0.12), lineWidth: 1)
                }
                .padding(.top, 22)
                .accessibilityLabel("\(score) \(endScreenText.outOf) \(ProgressStore.maximumTrophiesPerLevel)")

            VStack(spacing: 12) {
                Button {
                    PausedGameStore.shared.remove(state)
                    scene.resetGame()
                } label: {
                    Label(endScreenText.playAgain, systemImage: "arrow.counterclockwise")
                        .font(.headline.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
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
                        .font(.headline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .foregroundStyle(theme.deepColor)
                        .background(theme.skyColor, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 17, style: .continuous)
                                .stroke(theme.color.opacity(0.24), lineWidth: 1.5)
                        }
                }
            }
            .padding(.top, 24)
        }
        .padding(26)
        .frame(maxWidth: 340)
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
    }

    @ViewBuilder
    private func endTitleIcon(_ icon: String) -> some View {
        if icon == "percent" {
            // `percent.circle.fill` is not an SF Symbol. This custom badge
            // mirrors the circular percentage icon in the main menu.
            Image(systemName: "percent")
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(theme.deepColor, in: Circle())
        } else {
            Image(systemName: icon)
                .font(.title3.weight(.heavy))
        }
    }

    @ViewBuilder
    private func endIllustration(_ illustration: EndIllustration) -> some View {
        switch illustration {
        case .trophy:
            ZStack {
                Text("✦")
                    .font(.system(size: 25, weight: .bold))
                    .foregroundStyle(theme.color.opacity(0.68))
                    .offset(x: -54, y: -20)
                Text("✦")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(theme.color.opacity(0.68))
                    .offset(x: 53, y: -8)
                Text("🏆")
                    .font(.system(size: 70))
                    .scaleEffect(celebrate ? 1 : 0.4)
                    .rotationEffect(.degrees(celebrate ? 0 : -25))
                    .animation(.spring(response: 0.55, dampingFraction: 0.5), value: celebrate)
            }
            .frame(height: 92)
        case .character:
            theme.artwork
                .resizable()
                .scaledToFit()
                .frame(width: 130, height: 104)
                .accessibilityHidden(true)
        }
    }

    private var endScreenText: EndScreenText {
        EndScreenText(languageCode: Locale.current.language.languageCode?.identifier)
    }
}

private struct EndScreenText {
    private let isDutch: Bool

    init(languageCode: String?) {
        isDutch = languageCode == "nl"
    }

    var completionSubtitle: String { isDutch ? "Je hebt alle punten gehaald." : "You earned every point." }
    var completionSuffix: String { isDutch ? "afgerond!" : "complete!" }
    var gameOverTitle: String { isDutch ? "Game over" : "Game over" }
    var playAgain: String { isDutch ? "Nog een keer" : "Play again" }
    var mainMenu: String { isDutch ? "Hoofdmenu" : "Main menu" }
    var outOf: String { isDutch ? "van" : "out of" }

    /// Mirrors the six symbols in the main menu, so the achievement is
    /// immediately recognisable without repeating a category name.
    func menuIcon(for level: LevelConfig) -> String {
        switch level.category {
        case .addition, .additionMix: return "plus.circle.fill"
        case .subtraction, .subtractionMix: return "minus.circle.fill"
        case .tables, .tablesMix: return "multiply.circle.fill"
        case .fractions, .fractionsMix: return "circle.lefthalf.filled"
        case .percentages, .percentagesMix: return "percent"
        case .mix: return "star.circle.fill"
        case .supermix: return "star.circle.fill"
        }
    }

    func encouragement(for score: Int) -> String {
        let messages = isDutch
            ? ["Goed geprobeerd", "Het begin is er", "Blijf oefenen", "Lang niet slecht", "Goed bezig", "Mooie prestatie", "Knap gedaan", "Heel goed gespeeld", "Het einde is in zicht", "Je bent er bijna"]
            : ["Good try", "It’s a start", "Keep practicing", "Not bad at all", "Doing well", "Nice performance", "Well done", "Very well played", "The finish is in sight", "You’re almost there"]
        return messages[min(max(score, 0) / 3, messages.count - 1)]
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
