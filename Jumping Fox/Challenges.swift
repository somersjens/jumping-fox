//
//  Challenges.swift
//  Jumping Fox
//
//  Central challenge configuration: categories, level catalog,
//  rule-based question generators, and progress/unlock logic.
//
//  Layers (kept deliberately separate):
//  - LevelConfig:    static configuration of a level (cached once)
//  - QuestionEngine: generates the active question for a session
//  - ProgressStore:  the user's persisted progress
//

import Foundation

// MARK: - Categories

enum ChallengeCategory: String, CaseIterable, Identifiable {
    case addition, additionMix
    case subtraction, subtractionMix
    case tables, tablesMix
    case fractions, fractionsMix
    case percentages, percentagesMix
    // The Supermix menu's four buttons: each combines progressively more
    // operations, with harder operations weighted more heavily.
    case superBasic, superTimes, superFraction, superAll

    var id: String { rawValue }

    /// Small secondary symbol on level cards.
    var symbol: String {
        switch self {
        case .addition, .additionMix: return "+"
        case .subtraction, .subtractionMix: return "−"
        case .tables, .tablesMix: return "×"
        case .fractions, .fractionsMix: return "½"
        case .percentages, .percentagesMix: return "%"
        case .superBasic: return "+ −"
        case .superTimes: return "+ − ×"
        case .superFraction: return "+ − × ÷"
        case .superAll: return "+ − × ÷ %"
        }
    }

    /// The four Supermix-menu categories, in their intended button order.
    static let supermixMenu: [ChallengeCategory] = [.superBasic, .superTimes, .superFraction, .superAll]

    var isSupermixMenu: Bool { Self.supermixMenu.contains(self) }

    var isMix: Bool {
        switch self {
        case .addition, .subtraction, .tables, .fractions, .percentages: return false
        default: return true
        }
    }

    var next: ChallengeCategory {
        let all = Self.allCases
        let i = all.firstIndex(of: self)!
        return all[(i + 1) % all.count]
    }

    var previous: ChallengeCategory {
        let all = Self.allCases
        let i = all.firstIndex(of: self)!
        return all[(i - 1 + all.count) % all.count]
    }
}

// MARK: - Difficulty scaling (single source of truth)

/// The ordered difficulty lists and the premium (levels 13–99) growth curves.
/// Both the level catalog (card numbers/titles) and the question engine (the
/// numbers actually generated) read from here, so the card a child sees and
/// the sums they get can never drift apart.
enum ChallengeScaling {
    /// Fraction denominators for all 99 levels, in the intended learning
    /// sequence. Each value is used both on the level card and in its sums.
    static let fractionDenominators = [
        2, 4, 8, 3, 6, 12, 5, 10, 20, 7, 14, 28, 16, 32, 64, 128, 256, 512,
        24, 48, 96, 192, 384, 768, 40, 80, 160, 320, 640, 56, 112, 224, 448, 896,
        9, 18, 36, 72, 144, 288, 576, 11, 22, 44, 88, 176, 352, 704, 13, 26, 52,
        104, 208, 416, 832, 15, 30, 60, 120, 240, 480, 960, 17, 34, 68, 136, 272,
        544, 19, 38, 76, 152, 304, 608, 21, 42, 84, 168, 336, 672, 23, 46, 92,
        184, 368, 736, 25, 50, 100, 200, 400, 800, 27, 54, 108, 216, 432, 864, 1000]

    /// Percentages for all 99 levels, in the intended learning sequence.
    /// This same list drives the cards, start/pause explanation, and sums.
    static let percentageLevels = [
        25, 50, 75, 5, 10, 15, 20, 40, 80, 30, 60, 90, 35, 45, 55, 65, 70, 85, 95,
        2, 4, 6, 8, 12, 14, 16, 18, 22, 24, 26, 28, 32, 34, 36, 38, 42, 44, 46, 48,
        52, 54, 56, 58, 62, 64, 66, 68, 72, 74, 76, 78, 82, 84, 86, 88, 92, 94, 96,
        98, 1, 3, 7, 9, 11, 13, 17, 19, 21, 23, 27, 29, 31, 33, 37, 39, 41, 43, 47,
        49, 51, 53, 57, 59, 61, 63, 67, 69, 71, 73, 77, 79, 81, 83, 87, 89, 91, 93,
        97, 99]

    /// The number of free (non-premium) levels before Premium takes over.
    static let freeLevelCount = 12

    /// Premium *mix* levels still review a friendly subset of percentages.
    static let premiumFractionDenominators = [2, 4, 5, 8, 10, 20, 25]
    static let premiumPercentages = [50, 25, 10, 20, 75, 5, 100]

    /// The big round "whole" a premium fraction/percentage *mix* level works
    /// with. Climbs in tens from 110 (level 13) toward ~970 (level 99).
    static func premiumCeiling(_ index: Int) -> Int {
        100 + max(1, index - 12) * 10
    }

    /// Addition-mix result ceiling for any level 1…99: hand-tuned for the free
    /// levels, then growing by 100 per premium level beyond 1000.
    private static let additionBases = [10, 15, 20, 30, 50, 100, 150, 200, 300, 500, 750, 1000]
    static func additionMixCeiling(_ index: Int) -> Int {
        index <= additionBases.count
            ? additionBases[index - 1]
            : 1000 + (index - additionBases.count) * 100
    }

    /// Subtraction-mix start ceiling for any level 1…99 (index 7 stays the
    /// special "below zero" card, which the engine handles separately).
    private static let subtractionBases = [10, 15, 20, 30, 50, 100, 20, 150, 200, 300, 500, 1000]
    static func subtractionMixCeiling(_ index: Int) -> Int {
        index <= subtractionBases.count
            ? subtractionBases[index - 1]
            : 1000 + (index - subtractionBases.count) * 100
    }

    /// Tables-mix pool for any level 1…99: fixed pools for the free levels,
    /// then a sliding ~12-wide window climbing toward the table of 99.
    private static let tablePools: [[Int]] = [[1, 2], [1, 2, 3], Array(1...5), Array(1...8),
                                              Array(1...10), Array(1...12), Array(1...12),
                                              Array(2...12), Array(3...12), Array(4...12),
                                              Array(5...12), Array(6...12)]
    static func tablesMixPool(_ index: Int) -> [Int] {
        guard index > tablePools.count else { return tablePools[index - 1] }
        let hi = min(99, index)
        return Array(max(2, hi - 11)...hi)
    }
}

// MARK: - Level configuration

struct LevelConfig: Identifiable, Hashable {
    /// Stable identifier, e.g. "addition.3" or "tables.7".
    let id: String
    let category: ChallengeCategory
    let index: Int
    /// Big central text on the card (table, addend, denominator, percentage, …).
    let cardNumber: String
    let isAdvanced: Bool
    let requiresPremium: Bool
    /// The Mix menu starts this familiar skill straight in varied practice.
    let startsInMix: Bool

    init(category: ChallengeCategory, index: Int, cardNumber: String,
         isAdvanced: Bool = false, requiresPremium: Bool = false,
         startsInMix: Bool = false) {
        self.id = "\(category.rawValue).\(index)\(startsInMix ? ".mix" : "")"
        self.category = category
        self.index = index
        self.cardNumber = cardNumber
        self.isAdvanced = isAdvanced
        self.requiresPremium = requiresPremium
        self.startsInMix = startsInMix
    }

    func immediateMixVersion() -> LevelConfig {
        LevelConfig(category: category, index: index, cardNumber: cardNumber,
                    isAdvanced: isAdvanced, requiresPremium: requiresPremium, startsInMix: true)
    }
}

/// Static level configurations, computed once and cached.
enum LevelCatalog {
    static let byCategory: [ChallengeCategory: [LevelConfig]] = {
        var result: [ChallengeCategory: [LevelConfig]] = [:]

        // Addition: one clear pattern per level — repeated adding of n.
        result[.addition] = (1...12).map {
            LevelConfig(category: .addition, index: $0, cardNumber: "\($0)")
        }
        // Addition mix: growing maximum result.
        result[.additionMix] = (1...12).map { i in
            let m = ChallengeScaling.additionMixCeiling(i)
            return LevelConfig(category: .additionMix, index: i, cardNumber: "\(m)")
        }
        // Subtraction: repeatedly take away n.
        result[.subtraction] = (1...12).map {
            LevelConfig(category: .subtraction, index: $0, cardNumber: "\($0)")
        }
        // Subtraction mix: each card shows the real maximum start number.
        var subMix = (1...12).map { i -> LevelConfig in
            let m = ChallengeScaling.subtractionMixCeiling(i)
            return LevelConfig(category: .subtractionMix, index: i, cardNumber: "\(m)")
        }
        subMix[6] = LevelConfig(category: .subtractionMix, index: 7, cardNumber: "20", isAdvanced: true)
        result[.subtractionMix] = subMix

        // Times tables: one table per level (13–99 with Premium).
        var tables = (1...12).map {
            LevelConfig(category: .tables, index: $0, cardNumber: "\($0)")
        }
        tables += (13...99).map {
            LevelConfig(category: .tables, index: $0, cardNumber: "\($0)", requiresPremium: true)
        }
        result[.tables] = tables

        // Tables mix: growing pool of already-practiced tables.
        result[.tablesMix] = (1...12).map { i in
            let pool = ChallengeScaling.tablesMixPool(i)
            return LevelConfig(category: .tablesMix, index: i, cardNumber: "\(pool.max()!)")
        }

        // Fractions: one denominator per level for all 99 levels. The first
        // twelve are free; Premium continues the same list (see the loop below).
        result[.fractions] = ChallengeScaling.fractionDenominators
            .prefix(ChallengeScaling.freeLevelCount).enumerated().map { i, d in
                LevelConfig(category: .fractions, index: i + 1, cardNumber: "\(d)")
            }
        // Fractions mix: only concepts that were already introduced.
        result[.fractionsMix] = (1...12).map { i in
            LevelConfig(category: .fractionsMix, index: i, cardNumber: "\(i)",
                        isAdvanced: i == 5)
        }

        // Percentages: one percentage per level for all 99 levels. First
        // twelve free; Premium continues the same list (loop below).
        result[.percentages] = ChallengeScaling.percentageLevels
            .prefix(ChallengeScaling.freeLevelCount).enumerated().map { i, p in
                LevelConfig(category: .percentages, index: i + 1, cardNumber: "\(p)")
            }
        result[.percentagesMix] = (1...12).map { i in
            LevelConfig(category: .percentagesMix, index: i, cardNumber: "\(i)",
                        isAdvanced: i == 3)
        }

        // Supermix menu: four buttons, each adding one more operation on top
        // of the last. The card number is simply the level number; difficulty
        // comes from the growing ceilings inside each operation's own
        // generator (see QuestionEngine.superQuestion).
        for category in ChallengeCategory.supermixMenu {
            result[category] = (1...12).map {
                LevelConfig(category: category, index: $0, cardNumber: "\($0)", isAdvanced: $0 >= 3)
            }
        }

        // Each menu has twelve free levels. Premium extends every topic to 99
        // levels — each with real, progressively harder content. The card
        // number is always meaningful for its menu (the number added, the table,
        // the ceiling worked toward…) and never a bare repeat of a free card.
        // Tables already run through 99 above, so they are skipped here.
        for category in ChallengeCategory.allCases where category != .tables {
            var levels = result[category, default: []]
            for index in 13...99 {
                let card: String
                switch category {
                case .addition:
                    card = "\(index)"
                case .subtraction:
                    card = "\(index)"
                case .additionMix:
                    let c = ChallengeScaling.additionMixCeiling(index)
                    card = "\(c)"
                case .subtractionMix:
                    let c = ChallengeScaling.subtractionMixCeiling(index)
                    card = "\(c)"
                case .tablesMix:
                    let m = ChallengeScaling.tablesMixPool(index).max()!
                    card = "\(m)"
                case .fractions:
                    let d = ChallengeScaling.fractionDenominators[index - 1]
                    card = "\(d)"
                case .fractionsMix:
                    let c = ChallengeScaling.premiumCeiling(index)
                    card = "\(c)"
                case .percentages:
                    let p = ChallengeScaling.percentageLevels[index - 1]
                    card = "\(p)"
                case .percentagesMix:
                    let c = ChallengeScaling.premiumCeiling(index)
                    card = "\(c)"
                case .superBasic, .superTimes, .superFraction, .superAll:
                    card = "\(index)"
                case .tables:
                    continue
                }
                levels.append(
                    LevelConfig(category: category, index: index, cardNumber: card,
                                isAdvanced: true, requiresPremium: true)
                )
            }
            result[category] = levels
        }
        return result
    }()

    static func levels(for category: ChallengeCategory) -> [LevelConfig] {
        byCategory[category] ?? []
    }

    static func level(id: String) -> LevelConfig? {
        for levels in byCategory.values {
            if let match = levels.first(where: { $0.id == id }) { return match }
        }
        return nil
    }
}

// MARK: - Progress & unlocking

enum ProgressStore {
    static let unlockThreshold = 8      // best score needed to unlock the next level
    static let completionThreshold = 12 // best score at which a level counts as completed
    static let maximumTrophiesPerLevel = 30
    static let extendedMaximumTrophiesPerLevel = 50
    static let maximumCompletionCount = 100

    /// The four Supermix-menu categories have a longer 50-trophy goal, since
    /// they are the final, hardest categories. All other levels retain their
    /// familiar 30-trophy goal.
    static func maximumTrophies(for level: LevelConfig) -> Int {
        level.category.isSupermixMenu ? extendedMaximumTrophiesPerLevel : maximumTrophiesPerLevel
    }

    static func maximumTrophies(forLevelID levelID: String) -> Int {
        let categoryID = levelID.split(separator: ".").first.map(String.init)
        guard let categoryID, let category = ChallengeCategory(rawValue: categoryID) else {
            return maximumTrophiesPerLevel
        }
        return category.isSupermixMenu ? extendedMaximumTrophiesPerLevel : maximumTrophiesPerLevel
    }

    /// Scores belong to the level, not to a life-mode variant. The legacy
    /// keys are still read so existing players keep all of their trophies.
    private static func key(_ levelID: String) -> String {
        "best.\(levelID)"
    }

    private static func helperKey(_ levelID: String) -> String {
        "best.\(levelID).helper"
    }

    private static func maximumCountKey(_ levelID: String, helperEnabled: Bool) -> String {
        "max-completions.\(levelID)\(helperEnabled ? ".helper" : "")"
    }

    private static func legacyKey(_ levelID: String, _ mode: LifeMode) -> String {
        "best.\(levelID).\(mode.rawValue)"
    }

    /// The normal score is the player's real, unassisted trophy total.
    static func bestScore(levelID: String) -> Int {
        let scores = [UserDefaults.standard.integer(forKey: key(levelID))]
            + LifeMode.allCases.map { UserDefaults.standard.integer(forKey: legacyKey(levelID, $0)) }
        let localBest = scores.max() ?? 0
        let mergedBest = ProgressSync.shared.mergedScore(for: key(levelID), localScore: localBest)
        // Consolidate legacy per-life-mode scores into the current key while
        // importing existing players' progress into iCloud.
        if UserDefaults.standard.integer(forKey: key(levelID)) < mergedBest {
            UserDefaults.standard.set(mergedBest, forKey: key(levelID))
        }
        return mergedBest
    }

    static func bestScore(levelID: String, helperEnabled: Bool) -> Int {
        guard helperEnabled else { return bestScore(levelID: levelID) }
        // Helper mode includes progress already earned without assistance,
        // while assisted trophies never inflate the normal score.
        return max(bestScore(levelID: levelID), helperOnlyBestScore(levelID: levelID))
    }

    static func helperOnlyBestScore(levelID: String) -> Int {
        let storageKey = helperKey(levelID)
        let localBest = UserDefaults.standard.integer(forKey: storageKey)
        let mergedBest = ProgressSync.shared.mergedScore(for: storageKey, localScore: localBest)
        if localBest < mergedBest {
            UserDefaults.standard.set(mergedBest, forKey: storageKey)
        }
        return mergedBest
    }

    /// Kept as a convenience for unlocking code; all modes share one score.
    static func bestAnyMode(levelID: String) -> Int {
        bestScore(levelID: levelID)
    }

    struct RecordResult {
        let isNewHighScore: Bool
        let didIncreaseMaximumCount: Bool
    }

    /// Records a run. Reaching its goal adds one max-completion badge (up to
    /// 100) without changing the level's best score or any trophy totals.
    static func recordScore(_ score: Int, level: LevelConfig, helperEnabled: Bool) -> RecordResult {
        let levelID = level.id
        let maximum = maximumTrophies(for: level)
        let cappedScore = GameSettings.capsTrophiesAtThirty
            ? min(maximum, score)
            : score
        let currentBest = helperEnabled
            ? helperOnlyBestScore(levelID: levelID)
            : bestScore(levelID: levelID)
        let isNewHighScore = cappedScore > currentBest
        // Read this before storing a newly achieved maximum so a player's
        // first ever full run becomes ×1, not ×2.
        let currentMaximumCount = score >= maximum
            ? maxCompletionCount(levelID: levelID, helperEnabled: helperEnabled)
            : 0
        if isNewHighScore {
            let storageKey = helperEnabled ? helperKey(levelID) : key(levelID)
            UserDefaults.standard.set(cappedScore, forKey: storageKey)
            _ = ProgressSync.shared.mergedScore(for: storageKey, localScore: cappedScore)
        }

        let didIncreaseMaximumCount: Bool
        if score >= maximum {
            let countKey = maximumCountKey(levelID, helperEnabled: helperEnabled)
            let nextCount = min(maximumCompletionCount, currentMaximumCount + 1)
            didIncreaseMaximumCount = nextCount > currentMaximumCount
            if didIncreaseMaximumCount {
                UserDefaults.standard.set(nextCount, forKey: countKey)
                _ = ProgressSync.shared.mergedScore(for: countKey, localScore: nextCount)
            }
        } else {
            didIncreaseMaximumCount = false
        }
        return RecordResult(isNewHighScore: isNewHighScore,
                            didIncreaseMaximumCount: didIncreaseMaximumCount)
    }

    /// Existing completed levels predate the badge, so they begin at ×1.
    static func maxCompletionCount(levelID: String, helperEnabled: Bool = false) -> Int {
        let countKey = maximumCountKey(levelID, helperEnabled: helperEnabled)
        let localCount = UserDefaults.standard.integer(forKey: countKey)
        let mergedCount = ProgressSync.shared.mergedScore(for: countKey, localScore: localCount)
        let legacyMaximum = maxCompletionCountBaseline(levelID: levelID, helperEnabled: helperEnabled)
        let result = min(maximumCompletionCount, max(mergedCount, legacyMaximum))
        if localCount < result { UserDefaults.standard.set(result, forKey: countKey) }
        return result
    }

    private static func maxCompletionCountBaseline(levelID: String, helperEnabled: Bool) -> Int {
        let maximum = maximumTrophies(forLevelID: levelID)
        let score = helperEnabled ? helperOnlyBestScore(levelID: levelID) : bestScore(levelID: levelID)
        return score >= maximum ? 1 : 0
    }

    /// Reconciles every known level at launch and whenever iCloud reports a
    /// remote change. Keeping this centralized also imports old local scores
    /// after updating from a version that did not use iCloud.
    static func reconcileAllWithCloud() {
        for category in ChallengeCategory.allCases {
            for level in LevelCatalog.levels(for: category) {
                _ = bestScore(levelID: level.id)
                _ = helperOnlyBestScore(levelID: level.id)
                _ = maxCompletionCount(levelID: level.id)
                _ = maxCompletionCount(levelID: level.id, helperEnabled: true)
            }
        }
    }

    static func isCompleted(_ level: LevelConfig) -> Bool {
        bestAnyMode(levelID: level.id) >= completionThreshold
    }

    /// The prerequisite level id that gates this level, if any.
    static func prerequisiteID(for level: LevelConfig) -> String? {
        if level.index > 1 {
            return "\(level.category.rawValue).\(level.index - 1)"
        }
        // First level of a mix category is gated on the base skill(s).
        switch level.category {
        case .additionMix: return "addition.1"
        case .subtractionMix: return "subtraction.1"
        case .tablesMix: return "tables.1"
        case .fractionsMix: return "fractions.1"
        case .percentagesMix: return "percentages.1"
        case .superBasic, .superTimes, .superFraction, .superAll:
            return nil // custom multi-gate below
        default: return nil
        }
    }

    /// The base skills each Supermix-menu button reviews, in growing order —
    /// used to gate that button's first level.
    private static func supermixGates(for category: ChallengeCategory) -> [String] {
        switch category {
        case .superBasic: return ["addition.1", "subtraction.1"]
        case .superTimes: return ["addition.1", "subtraction.1", "tables.1"]
        case .superFraction: return ["addition.1", "subtraction.1", "tables.1", "fractions.1"]
        case .superAll: return ["addition.1", "subtraction.1", "tables.1", "fractions.1", "percentages.1"]
        default: return []
        }
    }

    static func isUnlocked(_ level: LevelConfig) -> Bool {
        if level.category.isSupermixMenu, level.index == 1 {
            return supermixGates(for: level.category).allSatisfy { bestAnyMode(levelID: $0) >= unlockThreshold }
        }
        guard let prereq = prerequisiteID(for: level) else { return true }
        return bestAnyMode(levelID: prereq) >= unlockThreshold
    }

    /// 0–1 progress toward unlocking (for "almost unlocked" cards).
    static func unlockProgress(_ level: LevelConfig) -> Double {
        guard let prereq = prerequisiteID(for: level) else { return 0 }
        return min(1, Double(bestAnyMode(levelID: prereq)) / Double(unlockThreshold))
    }
}

// MARK: - Question

struct Question: Codable {
    let prompt: String
    let correctAnswer: String
    let distractors: [String]
    /// True once a guided addition chain has reached its end and the level
    /// deliberately switches to mixed practice.
    let isRandomPractice: Bool
}

// MARK: - Question engine

/// Generates questions for one level from explicit rules:
/// allowed numbers, min/max result, term count, operations,
/// question form, difficulty, and previously introduced skills.
final class QuestionEngine {
    let level: LevelConfig

    private var step = 0
    private var lastPrompt: String?
    private var wrongBag: [Question] = []

    // Per-cycle ordering: first cycle in order (calm build-up),
    // later cycles shuffled so repeats aren't identical.
    private var orderCache: [Int] = []
    private var orderCycle = -1

    init(level: LevelConfig) {
        self.level = level
    }

    func resetRun() {
        step = 0
        lastPrompt = nil
        wrongBag.removeAll()
        orderCache = []
        orderCycle = -1
    }

    /// Extra repetition of recently missed questions.
    func registerWrong(_ question: Question) {
        guard wrongBag.count < 5 else { return }
        wrongBag.append(question)
    }

    func next() -> Question {
        if !usesFixedStandardSequence, !wrongBag.isEmpty, step > 2, Double.random(in: 0...1) < 0.2,
           wrongBag.first?.prompt != lastPrompt {
            let question = wrongBag.removeFirst()
            lastPrompt = question.prompt
            step += 1
            return question
        }
        // Never show the exact same question twice in a row: keep
        // regenerating until the prompt differs (bounded for safety).
        var question = generate()
        var attempts = 0
        while question.prompt == lastPrompt, attempts < 15 {
            question = generate()
            attempts += 1
        }
        lastPrompt = question.prompt
        step += 1
        return question
    }

    /// Standard addition, subtraction and tables are fixed practice routes.
    /// Mix levels retain their varied and revision behaviour.
    private var usesFixedStandardSequence: Bool {
        !level.startsInMix && [.addition, .subtraction, .tables].contains(level.category)
    }

    /// Current cycle number (how often the level's series has wrapped).
    private func cycleCount(seriesLength: Int) -> Int {
        step / max(1, seriesLength)
    }

    /// Value from a repeating series: in order on the first cycle,
    /// shuffled on later cycles.
    private func cycled(_ values: [Int]) -> Int {
        let c = step / values.count
        if c != orderCycle || orderCache.count != values.count {
            let lastShown = orderCache.last
            orderCycle = c
            if c == 0 {
                orderCache = values
            } else {
                var shuffled = values.shuffled()
                // A new cycle must never open with the value that just
                // closed the previous one (no identical question twice).
                if shuffled.count > 1, shuffled.first == lastShown {
                    shuffled.swapAt(0, shuffled.count - 1)
                }
                orderCache = shuffled
            }
        }
        return orderCache[step % values.count]
    }

    /// Value from a repeating series that is shuffled from the very first
    /// cycle. Every value still appears exactly once per cycle (balanced
    /// practice), but answers never follow a predictable 1, 2, 3 pattern.
    private func shuffledCycled(_ values: [Int]) -> Int {
        let c = step / values.count
        if c != orderCycle || orderCache.count != values.count {
            let lastShown = orderCache.last
            orderCycle = c
            var shuffled = values.shuffled()
            if shuffled.count > 1, shuffled.first == lastShown {
                shuffled.swapAt(0, shuffled.count - 1)
            }
            orderCache = shuffled
        }
        return orderCache[step % values.count]
    }

    // MARK: Generation dispatch

    private func generate() -> Question {
        if level.startsInMix { return immediateMixQuestion() }
        switch level.category {
        case .addition: return additionQuestion()
        case .additionMix: return additionMixQuestion()
        case .subtraction: return subtractionQuestion()
        case .subtractionMix: return subtractionMixQuestion()
        case .tables: return tableQuestion(table: level.index)
        case .tablesMix: return tablesMixQuestion()
        case .fractions: return fractionsQuestion()
        case .fractionsMix: return fractionsMixQuestion()
        case .percentages: return percentagesQuestion()
        case .percentagesMix: return percentagesMixQuestion()
        case .superBasic: return superQuestion(Self.superBasicWeights)
        case .superTimes: return superQuestion(Self.superTimesWeights)
        case .superFraction: return superQuestion(Self.superFractionWeights)
        case .superAll: return superQuestion(Self.superAllWeights)
        }
    }

    /// The Mix menu uses the same subject and ceiling as Standard, but skips
    /// the guided runway and starts immediately in varied questions.
    private func immediateMixQuestion() -> Question {
        switch level.category {
        case .addition:
            // Card number = highest small operand (card 3 allows +1/+2/+3).
            return additionSmallStepQuestion(maxAdd: level.index)
        case .subtraction:
            return subtractionSmallStepQuestion(maxTake: level.index)
        case .tables:
            return tablesMixQuestion(pool: Array(1...min(99, level.index)))
        case .fractions:
            // Varied question forms over everything introduced so far —
            // clearly different from the guided Standard level.
            let introduced = Array(Self.fractionDenominators.prefix(max(1, level.index)))
            return fractionsVarietyQuestion(denominators: introduced)
        case .percentages:
            let introduced = Array(Self.percentageLevels.prefix(max(1, level.index)))
            return percentagesVarietyQuestion(percentages: introduced)
        default:
            return superQuestion(Self.superAllWeights)
        }
    }

    // MARK: Addition

    /// Fixed 30-question route, repeated from the beginning when needed.
    /// The practiced number is always first: for +2 this starts at
    /// 2+2, 2+4 … 2+20; then 2+3 … and finally 2+5 ….
    private func additionQuestion() -> Question {
        let n = level.index
        let position = step % 30
        let group = position / 10
        let other = n + [0, 1, 3][group] + (position % 10) * n
        let answer = n + other
        // Real child errors, all close to the answer: counting slips
        // (±1/±2), forgetting to add and adding n twice.
        return makeQuestion("\(n) + \(other) = ?", "\(answer)",
                            [answer + 1, answer - 1, answer + 2, answer - 2,
                             other, answer + n].filter { $0 >= 0 }.map(String.init))
    }

    /// Mix form of the addition menu. The card number is the HIGHEST small
    /// operand: every sum adds a number from 1...maxAdd (on card 3 both
    /// 12 + 3 and 9 + 1 are fine, but never 14 + 5).
    private func additionSmallStepQuestion(maxAdd: Int) -> Question {
        let cap = max(20, maxAdd * 6)
        let add = Int.random(in: 1...maxAdd)
        let left = Int.random(in: 1...(cap - add))
        let answer = left + add
        return makeQuestion("\(left) + \(add) = ?", "\(answer)",
                            [answer + 1, answer - 1, answer + 2, answer - 2,
                             left, answer + add].filter { $0 >= 0 }.map(String.init),
                            isRandomPractice: true)
    }

    private func additionMixQuestion(maxResult: Int? = nil, harder: Bool = false,
                                     isRandomPractice: Bool = false) -> Question {
        var m = maxResult ?? ChallengeScaling.additionMixCeiling(level.index)
        if harder { m = min(200, m * 2) }
        // Always exactly two numbers and one operation.
        let a = Int.random(in: 1...(m - 1))
        let b = Int.random(in: 1...(m - a))
        let answer = a + b
        // Distractors mirror the sums a child actually produces: counting
        // slips (±1/±2), a carry/place-value error (±10 for larger sums)
        // and reversed digits — never values far away from the answer.
        var wrong = [answer + 1, answer - 1, answer + 2, answer - 2]
        if answer >= 15 { wrong += [answer + 10, answer - 10] }
        if answer >= 13, answer <= 99 {
            wrong.append((answer % 10) * 10 + answer / 10)
        }
        return makeQuestion("\(a) + \(b) = ?", "\(answer)",
                            wrong.filter { $0 >= 0 }.map(String.init),
                            isRandomPractice: isRandomPractice)
    }

    // MARK: Subtraction

    /// Fixed 30-question descending route, repeated from the beginning when
    /// needed. For −2 this is 22−2 … 4−2, then 23−2 … 5−2, then 25−2 … 7−2.
    private func subtractionQuestion() -> Question {
        let n = level.index
        let position = step % 30
        let group = position / 10
        let left = 11 * n + [0, 1, 3][group] - (position % 10) * n
        let answer = left - n
        // Counting slips, forgetting to subtract (left = answer + n) and
        // subtracting n twice (answer − n) — all plausible near-misses.
        return makeQuestion("\(left) − \(n) = ?", "\(answer)",
                            [answer + 1, answer - 1, answer + 2, answer - 2,
                             left, answer - n].filter { $0 >= 0 }.map(String.init))
    }

    /// Mix form of the subtraction menu. The card number is the HIGHEST
    /// number taken away: every sum subtracts a number from 1...maxTake.
    private func subtractionSmallStepQuestion(maxTake: Int) -> Question {
        let cap = max(20, maxTake * 6)
        let take = Int.random(in: 1...maxTake)
        let left = Int.random(in: take...cap)
        let answer = left - take
        return makeQuestion("\(left) − \(take) = ?", "\(answer)",
                            [answer + 1, answer - 1, answer + 2, answer - 2,
                             left, answer - take].filter { $0 >= 0 }.map(String.init),
                            isRandomPractice: true)
    }

    private func subtractionMixQuestion(maxStart: Int? = nil, allowNegative: Bool? = nil) -> Question {
        let m = maxStart ?? ChallengeScaling.subtractionMixCeiling(level.index)
        let negative = allowNegative ?? (level.category == .subtractionMix && level.index == 7)

        if negative {
            // Explicit advanced level: small numbers, results may dip below zero.
            let a = Int.random(in: 0...10)
            let b = Int.random(in: 1...15)
            let answer = a - b
            // The sign flip (b − a) is THE classic below-zero mistake.
            return makeQuestion("\(a) − \(b) = ?", "\(answer)",
                                [answer + 1, answer - 1, b - a, answer + 2,
                                 answer - 2].map(String.init))
        }
        // Always exactly two numbers and one operation.
        let a = Int.random(in: max(5, m / 2)...m)
        let b = Int.random(in: 1...(a - 1))
        let answer = a - b
        // Counting slips, a borrow/place-value error (±10) and the classic
        // column mistake: subtracting the smaller digit from the larger
        // one per column (52 − 38 → 26 instead of 14).
        var wrong = [answer + 1, answer - 1, answer + 2, answer - 2]
        if answer >= 12 { wrong += [answer + 10, answer - 10] }
        if a >= 10, b >= 10, a % 10 < b % 10 {
            wrong.append((a / 10 - b / 10) * 10 + (b % 10 - a % 10))
        }
        return makeQuestion("\(a) − \(b) = ?", "\(answer)",
                            wrong.filter { $0 >= 0 }.map(String.init))
    }

    // MARK: Tables

    /// Roughly 2% of the time any multiplication question becomes a "× 0"
    /// reminder that anything times zero is zero.
    private static let zeroMultiplyChance = 0.02

    /// A rare "× 0 = 0" question. The distractors are the tempting mistakes:
    /// answering the number itself (as if × 0 left it unchanged) or 1.
    private func timesZeroQuestion(_ a: Int) -> Question {
        let prompt = Bool.random() ? "\(a) × 0 = ?" : "0 × \(a) = ?"
        return makeQuestion(prompt, "0",
                            [a, 1, a + 1, 2, max(2, a * 2)].map(String.init))
    }

    /// Infinite fixed loop: t×1, t×2 … t×12, then back to t×1.
    private func tableQuestion(table: Int) -> Question {
        let m = (step % 12) + 1
        let answer = table * m
        // Neighbouring multiples (one step up/down in the SAME table) and
        // the neighbouring TABLE with the same multiplier — exactly the
        // confusions children have when memorising tables.
        return makeQuestion("\(table) × \(m) = ?", "\(answer)",
                            [table * (m + 1), table * max(1, m - 1),
                             (table + 1) * m, (table - 1) * m,
                             answer + 1, answer - 1].filter { $0 >= 0 }.map(String.init))
    }

    private func tablesMixQuestion(pool: [Int]? = nil) -> Question {
        let tables = pool ?? ChallengeScaling.tablesMixPool(level.index)
        let current = tables.max()!
        // Weighted: the newest table most often, earlier tables regularly.
        let table = Double.random(in: 0...1) < 0.5 ? current : tables.randomElement()!
        if Double.random(in: 0...1) < Self.zeroMultiplyChance { return timesZeroQuestion(table) }
        let m = Int.random(in: 1...12)
        let answer = table * m
        return makeQuestion("\(table) × \(m) = ?", "\(answer)",
                            [table * (m + 1), table * max(1, m - 1),
                             (table + 1) * m, (table - 1) * m,
                             answer + 1, answer - 1].filter { $0 >= 0 }.map(String.init))
    }

    // MARK: Fractions

    private static let fractionDenominators = ChallengeScaling.fractionDenominators

    /// One denominator per level. Wholes are generated directly from
    /// multiples of the denominator: whole = denominator × factor.
    private func fractionsQuestion(denominator: Int? = nil) -> Question {
        let d = denominator ?? Self.fractionDenominators[min(level.index - 1, Self.fractionDenominators.count - 1)]
        // Each factor appears once per cycle but in shuffled order, so the
        // wholes (and answers) never count up predictably.
        let factors = Array(1...6)
        let factor = shuffledCycled(factors)
        let whole = d * factor
        let cycle = cycleCount(seriesLength: factors.count)

        // The first cycle teaches the unit fraction 1/d; afterwards the
        // numerator varies too.
        let num = (cycle == 0 || d == 2) ? 1 : Int.random(in: 1...(d - 1))
        let unit = whole / d          // first divide…
        let answer = unit * num       // …then multiply
        // Purely symbolic: a fraction of a whole written as a multiplication
        // ("num/d × whole = ?"). Near-misses only: forgot to multiply (unit),
        // numerator one off (answer ± unit), the complement, counting slips.
        return makeQuestion("\(num)/\(d) × \(whole) = ?", "\(answer)",
                            [unit, answer + unit, max(0, answer - unit),
                             whole - answer, answer + 1, answer - 1].map(String.init))
    }

    private func fractionsMixQuestion() -> Question {
        // Premium mix: everything reviewed together, on big round wholes.
        if level.index > ChallengeScaling.fractionDenominators.count {
            return Bool.random()
                ? premiumFractionsQuestion()
                : fractionsVarietyQuestion(denominators: ChallengeScaling.fractionDenominators,
                                           forms: ["equivalent", "addSame", "subSame"])
        }
        // Only concepts that were already introduced, per level. Every form
        // is a symbolic sum — no word questions.
        let denominators: [Int]
        var forms: [String] = ["fractionOf"]
        switch level.index {
        case 1: denominators = [2, 3]
        case 2: denominators = [2, 3, 4]
        case 3: denominators = [2, 3, 4, 5]; forms += ["equivalent"]
        case 4: denominators = [2, 3, 4, 5, 6]; forms += ["equivalent", "addSame", "subSame"]
        default: denominators = [2, 3, 4, 5, 6, 8, 10]; forms += ["equivalent", "addSame", "subSame"]
        }
        return fractionsVarietyQuestion(denominators: denominators, forms: forms)
    }

    /// Varied fraction practice built from several question forms. This is
    /// what makes Mix feel clearly different from the guided Standard levels.
    /// When no forms are given, sensible ones are derived from what has
    /// already been introduced.
    private func fractionsVarietyQuestion(denominators: [Int], forms: [String]? = nil) -> Question {
        let available = forms ?? {
            var f = ["fractionOf", "fractionOf", "equivalent"]
            if denominators.contains(where: { $0 >= 3 }) { f += ["addSame", "subSame"] }
            return f
        }()

        switch available.randomElement()! {
        case "equivalent":
            let d = denominators.filter { $0 <= 5 }.randomElement() ?? 2
            let s = [2, 3].randomElement()!
            return makeQuestion("1/\(d) = ?/\(d * s)", "\(s)",
                                [1, d, s + 1, s - 1, d * s].map(String.init))
        case "addSame":
            let d = (denominators.filter { $0 >= 3 }.randomElement()) ?? 4
            let n1 = Int.random(in: 1...(d - 2))
            let n2 = Int.random(in: 1...(d - 1 - n1)) // proper fraction result
            return makeQuestion("\(n1)/\(d) + \(n2)/\(d) = ?", "\(n1 + n2)/\(d)",
                                ["\(n1 + n2)/\(d * 2)", "\(min(d, n1 + n2 + 1))/\(d)",
                                 "\(max(1, n1 + n2 - 1))/\(d)", "\(n1)/\(d)"])
        case "subSame":
            let d = (denominators.filter { $0 >= 3 }.randomElement()) ?? 4
            let n1 = Int.random(in: 2...(d - 1))
            let n2 = Int.random(in: 1...(n1 - 1))
            return makeQuestion("\(n1)/\(d) − \(n2)/\(d) = ?", "\(n1 - n2)/\(d)",
                                ["\(n1 - n2)/\(max(2, d - n2))", "\(min(d, n1 - n2 + 1))/\(d)",
                                 "\(n1 + n2)/\(d)", "\(n2)/\(d)"])
        default: // fractionOf
            return fractionsQuestion(denominator: denominators.randomElement()!)
        }
    }

    // MARK: Percentages

    /// Must stay in sync with the catalog's learning-line order above.
    private static let percentageLevels = ChallengeScaling.percentageLevels

    /// The smallest whole that makes "p% of whole" a whole number. Computed so
    /// it works for every percentage 1…100, not just the friendly ones:
    /// whole = base × factor then always divides cleanly by 100.
    private static func percentageBase(_ p: Int) -> Int {
        max(1, 100 / gcd(100, p))
    }
    private static func gcd(_ a: Int, _ b: Int) -> Int { b == 0 ? a : gcd(b, a % b) }

    private static let percentageFraction: [Int: String] = [50: "1/2", 25: "1/4", 75: "3/4",
                                                            20: "1/5", 10: "1/10", 5: "1/20",
                                                            80: "4/5", 90: "9/10"]

    private func percentagesQuestion(percentage: Int? = nil) -> Question {
        let p = percentage ?? Self.percentageLevels[min(level.index - 1, Self.percentageLevels.count - 1)]
        // Shuffled factor series: balanced practice, but the wholes (and
        // answers) never count up predictably 1, 2, 3.
        let factors = Array(1...8)
        let factor = shuffledCycled(factors)
        let whole = Self.percentageBase(p) * factor
        let cycle = cycleCount(seriesLength: factors.count)

        if cycle >= 1, let fraction = Self.percentageFraction[p], Double.random(in: 0...1) < 0.15 {
            let others = Self.percentageLevels.filter { $0 != p }
            return makeQuestion("\(fraction) = ?", "\(p)%",
                                others.map { "\($0)%" })
        }
        let answer = whole * p / 100
        // Neighbouring percentages of the SAME whole (25% vs 50% mix-ups),
        // the complement, and counting slips — all plausible near-misses.
        let neighbours = Self.percentageLevels
            .filter { $0 != p && whole * $0 % 100 == 0 }
            .sorted { abs($0 - p) < abs($1 - p) }
            .prefix(3)
            .map { whole * $0 / 100 }
        return makeQuestion("\(p)% × \(whole) = ?", "\(answer)",
                            (neighbours + [whole - answer, answer + 1, answer - 1])
                                .filter { $0 >= 0 }.map(String.init))
    }

    private func percentagesMixQuestion() -> Question {
        // Premium mix: friendly percentages reviewed together, on big wholes.
        if level.index > ChallengeScaling.percentageLevels.count {
            return Bool.random()
                ? premiumPercentagesQuestion()
                : percentagesVarietyQuestion(percentages: ChallengeScaling.premiumPercentages,
                                             forms: ["fracToPct", "pctToFrac"])
        }
        let percentages: [Int]
        var forms = ["percentOf", "fracToPct"]
        switch level.index {
        case 1: percentages = [50, 25, 100]
        case 2: percentages = [50, 25, 10, 20, 75]; forms.append("pctToFrac")
        default: percentages = [50, 25, 10, 20, 75]; forms += ["pctToFrac"]
        }
        return percentagesVarietyQuestion(percentages: percentages, forms: forms)
    }

    /// Varied percentage practice: percent-of and fraction conversions, all
    /// written as symbolic sums — clearly different from the guided Standard
    /// levels. When no forms are given, sensible ones are derived from the
    /// percentages that were already introduced.
    private func percentagesVarietyQuestion(percentages: [Int], forms: [String]? = nil) -> Question {
        let convertible = percentages.contains { Self.percentageFraction[$0] != nil }
        var available = forms ?? {
            var f = ["percentOf", "percentOf"]
            if convertible { f += ["fracToPct", "pctToFrac"] }
            return f
        }()
        if !convertible { available.removeAll { $0 == "fracToPct" || $0 == "pctToFrac" } }

        switch available.randomElement()! {
        case "fracToPct":
            let p = percentages.compactMap { Self.percentageFraction[$0] != nil ? $0 : nil }.randomElement() ?? 50
            let fraction = Self.percentageFraction[p]!
            return makeQuestion("\(fraction) = ?", "\(p)%",
                                percentages.filter { $0 != p }.map { "\($0)%" } + ["30%"])
        case "pctToFrac":
            let pairs: [(Int, Int, Int)] = [(25, 1, 4), (75, 3, 4), (50, 1, 2), (20, 1, 5)]
            let (p, num, den) = pairs.filter { percentages.contains($0.0) }.randomElement() ?? (50, 1, 2)
            return makeQuestion("\(p)% = ?/\(den)", "\(num)",
                                [den, num + 1, max(1, den - num), p / 10].map(String.init))
        default: // percentOf
            let p = percentages.randomElement()!
            if p == 100 {
                let whole = Int.random(in: 2...30)
                return makeQuestion("100% × \(whole) = ?", "\(whole)",
                                    [whole / 2, whole + 1, whole - 1, whole * 2].map(String.init))
            }
            return percentagesQuestion(percentage: p)
        }
    }

    // MARK: Premium fractions & percentages (levels 13–99)

    /// Premium fractions review the friendly denominators, but on big round
    /// wholes that climb toward ~1000 — mental maths with real quantities.
    /// The whole is always an exact multiple of the denominator, so every
    /// answer stays a whole number.
    private func premiumFractionsQuestion() -> Question {
        let ceiling = ChallengeScaling.premiumCeiling(level.index)
        let d = ChallengeScaling.premiumFractionDenominators.randomElement()!
        let target = max(2, ceiling / d)
        let factor = Int.random(in: max(1, target - 2)...(target + 2))
        let whole = d * factor
        let unit = whole / d              // first divide…
        let num = Int.random(in: 1...(d - 1))
        let answer = unit * num           // …then multiply
        // Near-misses only: forgot to multiply (unit), numerator one off
        // (answer ± unit), the complement, and a rounding-style ±10 slip.
        return makeQuestion("\(num)/\(d) × \(whole) = ?", "\(answer)",
                            [unit, answer + unit, max(0, answer - unit),
                             whole - answer, answer + 10, max(0, answer - 10)].map(String.init))
    }

    /// Premium percentages apply the friendly percentages to big round wholes.
    /// base × factor keeps every answer whole (25% of 480, 10% of 730, …).
    private func premiumPercentagesQuestion() -> Question {
        let ceiling = ChallengeScaling.premiumCeiling(level.index)
        let p = ChallengeScaling.premiumPercentages.randomElement()!
        let base = Self.percentageBase(p)
        let target = max(1, ceiling / base)
        let factor = Int.random(in: max(1, target - 2)...(target + 2))
        let whole = base * factor
        let answer = whole * p / 100
        // Neighbouring percentages of the SAME whole (25% vs 50% mix-ups),
        // the complement, and a ±10 slip.
        let neighbours = ChallengeScaling.percentageLevels
            .filter { $0 != p && whole * $0 % 100 == 0 }
            .sorted { abs($0 - p) < abs($1 - p) }
            .prefix(3)
            .map { whole * $0 / 100 }
        return makeQuestion("\(p)% × \(whole) = ?", "\(answer)",
                            (neighbours + [whole - answer, answer + 10, max(0, answer - 10)])
                                .filter { $0 >= 0 }.map(String.init))
    }

    // MARK: Supermix

    /// One operation in a Supermix button, with its relative weight (out of
    /// 100) for that button — harder operations are weighted more heavily.
    private enum SuperOp { case add, sub, mul, fraction, percent }

    private static let superBasicWeights: [(SuperOp, Double)] =
        [(.add, 50), (.sub, 50)]
    private static let superTimesWeights: [(SuperOp, Double)] =
        [(.add, 20), (.sub, 30), (.mul, 50)]
    private static let superFractionWeights: [(SuperOp, Double)] =
        [(.add, 10), (.sub, 15), (.mul, 25), (.fraction, 50)]
    private static let superAllWeights: [(SuperOp, Double)] =
        [(.add, 10), (.sub, 15), (.mul, 20), (.fraction, 25), (.percent, 30)]

    /// Picks an operation according to its relative weight.
    private func weightedOperation(_ weights: [(SuperOp, Double)]) -> SuperOp {
        let total = weights.reduce(0) { $0 + $1.1 }
        var r = Double.random(in: 0..<total)
        for (op, weight) in weights {
            if r < weight { return op }
            r -= weight
        }
        return weights.last!.0
    }

    /// A Supermix button: only the operations named in `weights` appear,
    /// harder ones proportionally more often. Every sum still shows exactly
    /// two numbers and one operation, and difficulty climbs with the level
    /// exactly like the other 99-level menus.
    private func superQuestion(_ weights: [(SuperOp, Double)]) -> Question {
        let idx = level.index
        switch weightedOperation(weights) {
        case .add:
            return additionMixQuestion(maxResult: 30 + idx * 30, harder: idx >= 2)
        case .sub:
            return subtractionMixQuestion(maxStart: 30 + idx * 30, allowNegative: idx >= 3)
        case .mul:
            return tablesMixQuestion(pool: Array(1...min(99, 8 + idx)))
        case .fraction:
            return fractionsQuestion(denominator: Self.fractionDenominators[min(idx - 1, Self.fractionDenominators.count - 1)])
        case .percent:
            return percentagesQuestion(percentage: Self.percentageLevels[min(idx - 1, Self.percentageLevels.count - 1)])
        }
    }

    // MARK: Question assembly

    /// Deduplicates distractors, removes the correct answer from them,
    /// and pads with safe numeric variants so there are always enough.
    private func makeQuestion(_ prompt: String, _ correct: String, _ raw: [String],
                              isRandomPractice: Bool = false) -> Question {
        var seen: Set<String> = [correct]
        var list: [String] = []
        for candidate in raw where !seen.contains(candidate) {
            seen.insert(candidate)
            list.append(candidate)
        }
        var salt = 1
        while list.count < 8 && salt < 40 {
            let candidate: String
            if let c = Int(correct) {
                let offset = salt % 2 == 0 ? salt : -salt
                candidate = String(max(level.isAdvanced ? -99 : 0, c + offset))
            } else if correct.contains("/") {
                candidate = "\(Int.random(in: 1...9))/\(Int.random(in: 2...10))"
            } else {
                candidate = "\(Int.random(in: 1...9))0%"
            }
            if !seen.contains(candidate) {
                seen.insert(candidate)
                list.append(candidate)
            }
            salt += 1
        }
        return Question(prompt: prompt, correctAnswer: correct, distractors: list.shuffled(),
                        isRandomPractice: isRandomPractice)
    }
}
