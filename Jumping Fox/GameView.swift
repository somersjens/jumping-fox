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

struct GameView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var state: GameState
    @State private var scene: GameScene

    private let theme = CharacterCatalog.current(isPremium: GameSettings.premiumUnlockedCache)

    init(level: LevelConfig) {
        let state = GameState(level: level)
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
                gameOverOverlay
            }
        }
        .onAppear { PlaytimeTracker.shared.challengeStarted() }
        .onDisappear { PlaytimeTracker.shared.challengeEnded() }
        .onChange(of: state.isGameOver) { _, over in
            if over {
                PlaytimeTracker.shared.challengeEnded()
            } else {
                PlaytimeTracker.shared.challengeStarted()
            }
        }
    }

    // MARK: HUD

    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
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
        if let lives = state.lives {
            HStack(spacing: 2) {
                ForEach(0..<max(lives, 0), id: \.self) { _ in
                    Image(systemName: "heart.fill")
                        .foregroundStyle(.red)
                }
            }
            .font(.title3)
            .animation(.snappy(duration: 0.25), value: lives)
        } else {
            HStack(spacing: 3) {
                Image(systemName: "heart.fill")
                    .foregroundStyle(.red)
                Image(systemName: "infinity")
                    .foregroundStyle(theme.deepColor)
            }
            .font(.title3)
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 12) {
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
            Text(state.questionText)
                .font(.system(size: 38, weight: .heavy, design: .rounded))
                .minimumScaleFactor(0.4)
                .lineLimit(1)
                .foregroundStyle(.white)
                .contentTransition(.numericText())
                .animation(.snappy(duration: 0.3), value: state.questionText)
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
                .background(
                    LinearGradient(colors: [theme.color, theme.deepColor],
                                   startPoint: .top, endPoint: .bottom),
                    in: RoundedRectangle(cornerRadius: 20)
                )
                .shadow(color: theme.deepColor.opacity(0.35), radius: 8, y: 4)
                .padding(.horizontal, 12)
        }
        .animation(.snappy(duration: 0.25), value: state.isRandomPractice)
        .padding(.bottom, 16)
    }

    // MARK: Game over

    private var gameOverReasonText: String {
        switch state.gameOverReason {
        case .fell: return "You fell off the screen!"
        case .outOfLives: return "Out of lives!"
        case nil: return ""
        }
    }

    private var gameOverOverlay: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()

            VStack(spacing: 18) {
                Text(theme.emoji)
                    .font(.system(size: 52))

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
}

#Preview {
    GameView(level: LevelCatalog.levels(for: .tables)[6])
}
