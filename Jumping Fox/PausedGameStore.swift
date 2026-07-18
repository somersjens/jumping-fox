// Keeps an unfinished level alive while the player returns to the level menu.

import Foundation

final class PausedGameStore {
    static let shared = PausedGameStore()
    private var sessions: [String: GameState] = [:]

    private func key(levelID: String, mode: LifeMode) -> String {
        "\(levelID).\(mode.rawValue)"
    }

    func gameState(for level: LevelConfig) -> GameState {
        let sessionKey = key(levelID: level.id, mode: GameSettings.lifeMode)
        return sessions[sessionKey] ?? GameState(level: level)
    }

    func pause(_ state: GameState) {
        state.recordCurrentScore()
        sessions[key(levelID: state.level.id, mode: state.lifeMode)] = state
    }

    func remove(_ state: GameState) {
        sessions.removeValue(forKey: key(levelID: state.level.id, mode: state.lifeMode))
    }

    func hasPausedSession(for level: LevelConfig, mode: LifeMode) -> Bool {
        sessions[key(levelID: level.id, mode: mode)] != nil
    }

    /// Highest live score across any paused session for this level id. Helper
    /// runs only count when `includingHelper` is true, mirroring how helper
    /// trophies only count while helper mode is on.
    func pausedScore(forLevelID levelID: String, includingHelper: Bool) -> Int {
        LifeMode.allCases.compactMap { mode -> Int? in
            guard let session = sessions[key(levelID: levelID, mode: mode)] else { return nil }
            if session.isAnswerHelperEnabled && !includingHelper { return nil }
            return session.score
        }.max() ?? 0
    }
}
