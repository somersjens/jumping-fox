// Keeps an unfinished level alive while the player returns to the level menu.

import Foundation

final class PausedGameStore {
    static let shared = PausedGameStore()
    private static let storageKey = "game.pausedSessions"

    private struct StoredSession: Codable {
        let levelID: String
        let lifeMode: LifeMode
        let answerHelperEnabled: Bool
        let snapshot: GameState.PausedSnapshot
    }

    private var sessions: [String: GameState] = [:]
    private var storedSessions: [String: StoredSession]

    private init() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let saved = try? JSONDecoder().decode([String: StoredSession].self, from: data) else {
            storedSessions = [:]
            return
        }
        storedSessions = saved
    }

    private func key(levelID: String, mode: LifeMode) -> String {
        "\(levelID).\(mode.rawValue)"
    }

    func gameState(for level: LevelConfig) -> GameState {
        let sessionKey = key(levelID: level.id, mode: GameSettings.lifeMode)
        if let session = sessions[sessionKey] { return session }
        guard let saved = storedSessions[sessionKey] else { return GameState(level: level) }

        let session = GameState(level: level,
                                pausedSnapshot: saved.snapshot,
                                lifeMode: saved.lifeMode,
                                answerHelperEnabled: saved.answerHelperEnabled)
        sessions[sessionKey] = session
        return session
    }

    func pause(_ state: GameState) {
        state.recordCurrentScore()
        let sessionKey = key(levelID: state.level.id, mode: state.lifeMode)
        sessions[sessionKey] = state
        storedSessions[sessionKey] = StoredSession(levelID: state.level.id,
                                                    lifeMode: state.lifeMode,
                                                    answerHelperEnabled: state.isAnswerHelperEnabled,
                                                    snapshot: state.pausedSnapshot)
        save()
    }

    func remove(_ state: GameState) {
        let sessionKey = key(levelID: state.level.id, mode: state.lifeMode)
        sessions.removeValue(forKey: sessionKey)
        storedSessions.removeValue(forKey: sessionKey)
        save()
    }

    func hasPausedSession(for level: LevelConfig, mode: LifeMode) -> Bool {
        let sessionKey = key(levelID: level.id, mode: mode)
        return sessions[sessionKey] != nil || storedSessions[sessionKey] != nil
    }

    /// Highest live score across any paused session for this level id. Helper
    /// runs only count when `includingHelper` is true, mirroring how helper
    /// trophies only count while helper mode is on.
    func pausedScore(forLevelID levelID: String, includingHelper: Bool) -> Int {
        LifeMode.allCases.compactMap { mode -> Int? in
            let sessionKey = key(levelID: levelID, mode: mode)
            if let session = sessions[sessionKey] {
                if session.isAnswerHelperEnabled && !includingHelper { return nil }
                return session.score
            }
            guard let saved = storedSessions[sessionKey] else { return nil }
            if saved.answerHelperEnabled && !includingHelper { return nil }
            return saved.snapshot.score
        }.max() ?? 0
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(storedSessions) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
}
