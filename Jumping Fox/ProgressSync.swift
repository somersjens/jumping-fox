//
//  ProgressSync.swift
//  Jumping Fox
//
//  Keeps level scores in iCloud's key-value store. Scores are monotonic: if
//  two devices update the same level independently, the highest score wins.
//
//  The player's name rides along in the same store so that — like the scores —
//  it survives deleting and reinstalling the app. A restored account then shows
//  its name again instead of coming back nameless.
//

import Foundation
import Combine

final class ProgressSync: ObservableObject {
    static let shared = ProgressSync()

    @Published private(set) var revision = 0

    private let cloudStore = NSUbiquitousKeyValueStore.default
    private var notificationToken: NSObjectProtocol?
    private var defaultsToken: NSObjectProtocol?

    /// iCloud key for the player's name. Kept distinct from the local
    /// UserDefaults key so the mirroring below is always explicit.
    private let playerNameCloudKey = "profile.playerName.cloud"
    /// The last name we reconciled, so a UserDefaults change can be checked
    /// cheaply and we never echo our own restore back to the cloud.
    private var lastKnownPlayerName = ""

    private init() {
        notificationToken = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: cloudStore,
            queue: .main
        ) { [weak self] _ in
            self?.reconcileAllScores()
            self?.restorePlayerNameFromCloudIfNeeded()
        }

        // Push local name edits up to iCloud as they happen. @AppStorage writes
        // the name straight to UserDefaults, so we watch that store rather than
        // every individual edit site.
        defaultsToken = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: UserDefaults.standard,
            queue: .main
        ) { [weak self] _ in
            self?.pushPlayerNameToCloudIfChanged()
        }

        cloudStore.synchronize()
        lastKnownPlayerName = UserDefaults.standard.string(forKey: GameSettings.playerNameKey) ?? ""
        // Let the singleton finish initializing before ProgressStore accesses it.
        DispatchQueue.main.async { [weak self] in
            self?.reconcileAllScores()
            self?.syncPlayerNameAtLaunch()
        }
    }

    deinit {
        if let notificationToken {
            NotificationCenter.default.removeObserver(notificationToken)
        }
        if let defaultsToken {
            NotificationCenter.default.removeObserver(defaultsToken)
        }
    }

    /// Merges a local score with iCloud and writes the winner to both stores.
    /// This is intentionally a maximum, rather than last-write-wins, so a
    /// score earned on either device can never erase a better score elsewhere.
    /// `NSUbiquitousKeyValueStore` propagates `set` operations automatically;
    /// forcing `synchronize()` here can block the gameplay/main thread for
    /// several seconds on a slow iCloud connection.
    func mergedScore(for key: String, localScore: Int) -> Int {
        let cloudScore = (cloudStore.object(forKey: key) as? NSNumber)?.intValue ?? 0
        let winner = max(localScore, cloudScore)

        if cloudScore < winner {
            cloudStore.set(NSNumber(value: winner), forKey: key)
        }
        return winner
    }

    private func reconcileAllScores() {
        ProgressStore.reconcileAllWithCloud()
        revision &+= 1
    }

    // MARK: - Player name

    /// On launch, reconcile the local name with iCloud: a name saved in the
    /// cloud (e.g. from before a reinstall) is restored locally; otherwise an
    /// existing local name seeds the cloud for the first time.
    private func syncPlayerNameAtLaunch() {
        let localName = UserDefaults.standard.string(forKey: GameSettings.playerNameKey) ?? ""
        let cloudName = cloudStore.string(forKey: playerNameCloudKey) ?? ""

        if !cloudName.isEmpty, cloudName != localName {
            UserDefaults.standard.set(cloudName, forKey: GameSettings.playerNameKey)
            lastKnownPlayerName = cloudName
        } else if !localName.isEmpty, cloudName != localName {
            cloudStore.set(localName, forKey: playerNameCloudKey)
            lastKnownPlayerName = localName
        }
    }

    /// Applies a name that arrived from another device — or synced down after a
    /// reinstall — but never overwrites a local name with an empty one.
    private func restorePlayerNameFromCloudIfNeeded() {
        let cloudName = cloudStore.string(forKey: playerNameCloudKey) ?? ""
        guard !cloudName.isEmpty else { return }
        let localName = UserDefaults.standard.string(forKey: GameSettings.playerNameKey) ?? ""
        guard cloudName != localName else { return }
        UserDefaults.standard.set(cloudName, forKey: GameSettings.playerNameKey)
        lastKnownPlayerName = cloudName
    }

    /// Mirrors a local name edit up to iCloud. Any UserDefaults change triggers
    /// this, so a cheap guard limits the work to real name changes and stops a
    /// restore from being echoed straight back.
    private func pushPlayerNameToCloudIfChanged() {
        let localName = UserDefaults.standard.string(forKey: GameSettings.playerNameKey) ?? ""
        guard localName != lastKnownPlayerName else { return }
        lastKnownPlayerName = localName
        guard !localName.isEmpty else { return }
        cloudStore.set(localName, forKey: playerNameCloudKey)
    }
}
