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

    private let theme = CharacterCatalog.current(isPremium: GameSettings.premiumUnlockedCache)

    init(level: LevelConfig) {
        let state = PausedGameStore.shared.gameState(for: level)
        _state = StateObject(wrappedValue: state)
        _scene = State(initialValue: GameScene(state: state))
    }

    var body: some View {
        ZStack {
            SpriteView(scene: scene)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                Spacer()
                bottomBar
            }

            if state.isGameOver {
                if state.gameOverReason == .completed {
                    completionOverlay
                } else {
                    gameOverOverlay
                }
            }
        }
        .onAppear { PlaytimeTracker.shared.challengeStarted() }
        .onDisappear { PlaytimeTracker.shared.challengeEnded() }
        .onChange(of: state.isGameOver) { _, over in
            if over {
                PlaytimeTracker.shared.challengeEnded()
                PausedGameStore.shared.remove(state)
            } else {
                PlaytimeTracker.shared.challengeStarted()
            }
        }
    }

    // MARK: HUD

    private var topBar: some View {
        HStack {
            Button {
                PausedGameStore.shared.pause(state)
                dismiss()
            } label: {
                Image(systemName: "pause.circle.fill")
                    .font(.title)
                    .foregroundStyle(theme.deepColor.opacity(0.85))
            }

            Spacer()

            VStack(spacing: 2) {
                Text("\(state.level.category.displayName) · \(state.level.title)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.deepColor.opacity(0.75))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("Score: \(state.score)")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(theme.deepColor)
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.25), value: state.score)
            }

            Spacer()

            livesBadge
                .frame(minWidth: 44, alignment: .trailing)
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var livesBadge: some View {
        if let halves = state.livesHalves {
            heartRow(filledHalves: halves)
                .font(.title3)
                .animation(.snappy(duration: 0.25), value: halves)
        } else {
            // Unlimited: no lives to show — just a clean infinity symbol.
            // The crossed-out trophy only appears once trophies stop counting.
            HStack(spacing: 6) {
                Image(systemName: "infinity")
                    .font(.title3)
                    .foregroundStyle(theme.deepColor)
                if state.isScoreLocked {
                    excludedTrophy
                }
            }
            .animation(.snappy(duration: 0.25), value: state.isScoreLocked)
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

    private var excludedTrophy: some View {
        Image(systemName: "trophy.fill")
            .font(.subheadline.weight(.bold))
            .foregroundStyle(theme.deepColor.opacity(0.42))
            .overlay {
                Rectangle()
                    .fill(theme.deepColor)
                    .frame(width: 23, height: 2.5)
                    .rotationEffect(.degrees(-45))
            }
            .accessibilityLabel("Trofeeën tellen niet meer mee")
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
                state.revealAnswer()
            }
    }

    private var bottomBar: some View {
        VStack(spacing: 12) {
            equationBadge
            if state.isRandomPractice {
                Label("MIX MODE", systemImage: "shuffle")
                    .font(.caption.weight(.heavy))
                    .tracking(1.2)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(theme.deepColor.opacity(0.9), in: Capsule())
                    .transition(.scale.combined(with: .opacity))
            }
            if state.isScoreLocked {
                Label("Trofeeën tellen niet meer mee na 3 fouten", systemImage: "trophy.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.black.opacity(0.35), in: Capsule())
            }
        }
        .animation(.snappy(duration: 0.25), value: state.isRandomPractice)
        .animation(.snappy(duration: 0.25), value: state.isAnswerRevealed)
        .padding(.bottom, 16)
    }

    // MARK: Game over

    private var gameOverReasonText: String {
        switch state.gameOverReason {
        case .fell: return "You fell off the screen!"
        case .outOfLives: return "Out of lives!"
        case .completed: return ""
        case nil: return ""
        }
    }

    private var gameOverOverlay: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()

            VStack(spacing: 18) {
                theme.artwork
                    .resizable()
                    .scaledToFit()
                    .frame(width: 76, height: 76)

                Text("Game Over")
                    .font(.system(size: 36, weight: .heavy, design: .rounded))
                    .foregroundStyle(theme.deepColor)

                Text(gameOverReasonText)
                    .font(.headline)
                    .foregroundStyle(.secondary)

                if state.isNewHighScore {
                    Text("🎉 New high score!")
                        .font(.headline)
                        .foregroundStyle(theme.color)
                }

                VStack(spacing: 6) {
                    Text("Score: \(state.score)")
                        .font(.title2.weight(.bold))
                    Text("Best (\(state.lifeMode.label)): \(state.highScore)")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }

                Button {
                    PausedGameStore.shared.remove(state)
                    scene.resetGame()
                } label: {
                    Label("Play Again", systemImage: "arrow.counterclockwise")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            LinearGradient(colors: [theme.color, theme.deepColor],
                                           startPoint: .top, endPoint: .bottom),
                            in: RoundedRectangle(cornerRadius: 14)
                        )
                        .foregroundStyle(.white)
                }

                Button {
                    dismiss()
                } label: {
                    Label("Main Menu", systemImage: "house.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(theme.skyColor, in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(theme.deepColor)
                }
            }
            .padding(28)
            .frame(maxWidth: 340)
            .background(.background, in: RoundedRectangle(cornerRadius: 24))
            .padding()
        }
    }

    // MARK: Completion (reached the 30-point goal)

    @State private var celebrate = false

    private var completionOverlay: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()

            ConfettiView()
                .ignoresSafeArea()
                .allowsHitTesting(false)

            VStack(spacing: 16) {
                Text("🏆")
                    .font(.system(size: 68))
                    .scaleEffect(celebrate ? 1 : 0.4)
                    .rotationEffect(.degrees(celebrate ? 0 : -25))
                    .animation(.spring(response: 0.55, dampingFraction: 0.5), value: celebrate)

                Text("Gehaald! 🎉")
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .foregroundStyle(theme.deepColor)
                    .multilineTextAlignment(.center)

                Text("Je hebt alle 30 punten voor\n\(state.level.title) gehaald!")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Text("30 / 30")
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundStyle(theme.color)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 8)
                    .background(theme.skyColor, in: Capsule())

                Button {
                    PausedGameStore.shared.remove(state)
                    scene.resetGame()
                } label: {
                    Label("Nog een keer", systemImage: "arrow.counterclockwise")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            LinearGradient(colors: [theme.color, theme.deepColor],
                                           startPoint: .top, endPoint: .bottom),
                            in: RoundedRectangle(cornerRadius: 14)
                        )
                        .foregroundStyle(.white)
                }

                Button {
                    dismiss()
                } label: {
                    Label("Hoofdmenu", systemImage: "house.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(theme.skyColor, in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(theme.deepColor)
                }
            }
            .padding(28)
            .frame(maxWidth: 340)
            .background(.background, in: RoundedRectangle(cornerRadius: 24))
            .padding()
        }
        .onAppear {
            celebrate = true
#if canImport(UIKit)
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
#endif
        }
    }
}

/// Lightweight falling-confetti burst for the completion screen.
private struct ConfettiView: View {
    private let pieces = (0..<70).map { _ in ConfettiPiece() }
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
