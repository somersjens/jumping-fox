//
//  PlaytimeTracker.swift
//  Jumping Fox
//
//  Measures ACTIVE playtime only, tracks daily/weekly goals and the streak.
//
//  Time counts while a challenge is active, the app is foregrounded and the
//  player interacted recently (45 s idle limit). Accrual is driven by
//  interactions — there is no per-second timer re-rendering the UI, and the
//  published minute values only change when a whole minute rolls over.
//
//  Per day we store: date, active seconds, that day's goal. The streak is
//  derived from these records, so changing today's goal never rewrites
//  history.
//

import Foundation
import Combine
#if canImport(UIKit)
import UIKit
#endif

struct DayRecord: Codable {
    var date: String        // "yyyy-MM-dd" in the user's local calendar/timezone
    var seconds: Double
    var goalMinutes: Int

    var goalMet: Bool { seconds >= Double(goalMinutes) * 60 }
}

/// Main-thread only (SwiftUI + SpriteKit both call from the main thread).
final class PlaytimeTracker: ObservableObject {
    static let shared = PlaytimeTracker()

    // Published summaries — updated only when the visible value changes.
    @Published private(set) var todayMinutes = 0
    @Published private(set) var weekMinutes = 0
    @Published private(set) var streakDays = 0

    private var days: [String: DayRecord] = [:]
    private var challengeActive = false
    private var appActive = true
    private var lastAccrual: Date?
    private var unsavedSeconds: Double = 0

    private let idleLimit: TimeInterval = 45
    private let saveInterval: Double = 30
    private let daysKey = "playtime.days"
    private let dailyKey = "goal.dailyMinutes"
    private let weeklyKey = "goal.weeklyMinutes"

    private let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.calendar = Calendar.current
        formatter.timeZone = TimeZone.current
        return formatter
    }()

    private init() {
        load()
        recomputeDisplay()
#if canImport(UIKit)
        NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.appActive = false
            self?.pauseAccrual()
        }
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.appActive = true
            self.lastAccrual = self.challengeActive ? Date() : nil
            self.recomputeDisplay() // day may have rolled over
        }
#endif
    }

    // MARK: Goals

    var dailyGoalMinutes: Int {
        let value = UserDefaults.standard.integer(forKey: dailyKey)
        return value > 0 ? value : 5
    }

    var weeklyGoalMinutes: Int {
        let value = UserDefaults.standard.integer(forKey: weeklyKey)
        return value > 0 ? value : 35
    }

    /// Changing the daily goal proposes daily × 7 as the new weekly goal;
    /// the user can adjust the weekly goal afterwards.
    func setDailyGoal(_ minutes: Int) {
        objectWillChange.send()
        UserDefaults.standard.set(minutes, forKey: dailyKey)
        UserDefaults.standard.set(minutes * 7, forKey: weeklyKey)
        touchTodayGoal()
        save(force: true)
        recomputeDisplay()
    }

    func setWeeklyGoal(_ minutes: Int) {
        objectWillChange.send()
        UserDefaults.standard.set(minutes, forKey: weeklyKey)
        recomputeDisplay()
    }

    /// Only today's record follows the current goal; past days stay frozen.
    private func touchTodayGoal() {
        let key = dayFormatter.string(from: Date())
        if var record = days[key] {
            record.goalMinutes = dailyGoalMinutes
            days[key] = record
        }
    }

    // MARK: Challenge lifecycle

    func challengeStarted() {
        challengeActive = true
        lastAccrual = Date()
    }

    /// Also called when a static screen (game over) appears.
    func challengeEnded() {
        pauseAccrual()
        challengeActive = false
    }

    /// Called on real gameplay interaction: steering, jumping on an answer,
    /// super jump, starting a challenge.
    func registerInteraction() {
        guard challengeActive, appActive else { return }
        let now = Date()
        if let last = lastAccrual {
            let delta = now.timeIntervalSince(last)
            // Gaps longer than the idle limit don't count (player walked away).
            if delta > 0 && delta <= idleLimit {
                accrue(delta, at: now)
            }
        }
        lastAccrual = now
    }

    private func pauseAccrual() {
        if challengeActive, let last = lastAccrual {
            let delta = Date().timeIntervalSince(last)
            if delta > 0 && delta <= idleLimit {
                accrue(delta, at: Date())
            }
        }
        lastAccrual = nil
        save(force: true)
    }

    private func accrue(_ delta: TimeInterval, at date: Date) {
        let key = dayFormatter.string(from: date)
        var record = days[key] ?? DayRecord(date: key, seconds: 0, goalMinutes: dailyGoalMinutes)
        record.seconds += delta
        record.goalMinutes = dailyGoalMinutes
        days[key] = record

        unsavedSeconds += delta
        if unsavedSeconds >= saveInterval {
            save(force: false)
        }
        recomputeDisplay()
    }

    // MARK: Derived values

    private func recomputeDisplay() {
        let todayKey = dayFormatter.string(from: Date())
        let today = Int((days[todayKey]?.seconds ?? 0) / 60)
        let week = Int(currentWeekSeconds() / 60)
        let streak = computeStreak()
        // Publish only when a visible value actually changed.
        if today != todayMinutes { todayMinutes = today }
        if week != weekMinutes { weekMinutes = week }
        if streak != streakDays { streakDays = streak }
    }

    private func currentWeekSeconds() -> Double {
        let calendar = Calendar.current
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: Date()) else { return 0 }
        var total = 0.0
        var day = interval.start
        while day < interval.end {
            total += days[dayFormatter.string(from: day)]?.seconds ?? 0
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return total
    }

    /// A day counts once when that day's goal was met. Today only breaks
    /// the streak after the calendar day has passed.
    private func computeStreak() -> Int {
        let calendar = Calendar.current
        var streak = 0
        var day = Date()
        if let today = days[dayFormatter.string(from: day)], today.goalMet {
            streak += 1
        }
        while true {
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
            guard let record = days[dayFormatter.string(from: day)], record.goalMet else { break }
            streak += 1
        }
        return streak
    }

    // MARK: Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: daysKey),
              let decoded = try? JSONDecoder().decode([String: DayRecord].self, from: data) else { return }
        days = decoded
    }

    private func save(force: Bool) {
        guard force || unsavedSeconds >= saveInterval else { return }
        if let data = try? JSONEncoder().encode(days) {
            UserDefaults.standard.set(data, forKey: daysKey)
        }
        unsavedSeconds = 0
    }
}
