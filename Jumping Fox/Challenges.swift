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

    /// One-line description of which operations a Supermix button practises,
    /// shown in the tap-again info pop-out under the "Types of problems" header.
    var supermixInfoBody: String {
        switch self {
        case .superBasic:    return L("info.super.basic")
        case .superTimes:    return L("info.super.times")
        case .superFraction: return L("info.super.fraction")
        case .superAll:      return L("info.super.all")
        default:             return ""
        }
    }

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

/// The three ways each of the five skill menus can practise a level:
/// - `order`  (Reeks / Order):  the calm ascending sequence, as it always was.
/// - `random` (Hussel / Random): only this level's own number, shuffled — and
///   free to sit on either side of the sum (never for a minus, where it can't).
/// - `mixed`  (Gemixt / Mixed):  this number *or a lower one*, all mixed up,
///   still leaning toward the harder (higher) end.
/// The id suffixes are deliberately kept as they were ("" and ".mix") so every
/// existing player keeps all of their earned trophies; only `.random` is new.
enum PracticeMode: String, CaseIterable, Identifiable {
    // rawValues preserve the values previously stored under "ui.menuMode".
    case order = "standard"
    case random = "random"
    case mixed = "mix"

    var id: String { rawValue }

    /// Suffix appended to a level id so each mode keeps its own score.
    var idSuffix: String {
        switch self {
        case .order: return ""
        case .random: return ".random"
        case .mixed: return ".mix"
        }
    }

    /// Localized button label (Reeks · Hussel · Gemixt / Order · Random · Mixed).
    var title: String {
        switch self {
        case .order: return L("mode.order")
        case .random: return L("mode.random")
        case .mixed: return L("mode.mixed")
        }
    }

    /// One-line "how this level is sequenced" summary, shown in the tap-again
    /// info pop-out under the shared `info.mode.header` ("Order").
    var infoBody: String {
        switch self {
        case .order: return L("info.mode.order")
        case .random: return L("info.mode.random")
        case .mixed: return L("info.mode.mixed")
        }
    }

    /// Fractions and Percentages don't sequence their three sub-levels by
    /// *order*; they change *what kind* of sum you get. So those two menus show
    /// their own button labels, info header and info body, while every other
    /// menu keeps the shared Order · Random · Mixed wording.

    /// Button label for this mode within a given topic.
    func title(for category: ChallengeCategory) -> String {
        switch category {
        case .fractions, .fractionsMix:
            switch self {
            case .order:  return L("mode.fractions.single")
            case .random: return L("mode.fractions.multiple")
            case .mixed:  return L("mode.mixed")
            }
        case .percentages, .percentagesMix:
            switch self {
            case .order:  return L("mode.percentages.whole")
            case .random: return L("mode.percentages.decimal")
            case .mixed:  return L("mode.mixed")
            }
        default:
            return title
        }
    }

    /// Grouping label above the info body ("Order" / "Parts" / "Type").
    func infoHeader(for category: ChallengeCategory) -> String {
        switch category {
        case .fractions, .fractionsMix:     return L("info.mode.fractions.header")
        case .percentages, .percentagesMix: return L("info.mode.percentages.header")
        default:                            return L("info.mode.header")
        }
    }

    /// One-line description of this mode within a given topic.
    func infoBody(for category: ChallengeCategory) -> String {
        switch category {
        case .fractions, .fractionsMix:
            switch self {
            case .order:  return L("info.mode.fractions.single")
            case .random: return L("info.mode.fractions.multiple")
            case .mixed:  return infoBody   // shared "Mixed with lower levels"
            }
        case .percentages, .percentagesMix:
            switch self {
            case .order:  return L("info.mode.percentages.whole")
            case .random: return L("info.mode.percentages.decimal")
            case .mixed:  return infoBody   // shared "Mixed with lower levels"
            }
        default:
            return infoBody
        }
    }
}

struct LevelConfig: Identifiable, Hashable {
    /// Stable identifier, e.g. "addition.3" or "tables.7".
    let id: String
    let category: ChallengeCategory
    let index: Int
    /// Big central text on the card (table, addend, denominator, percentage, …).
    let cardNumber: String
    let isAdvanced: Bool
    let requiresPremium: Bool
    /// Which of the three practice modes this level was opened in.
    let mode: PracticeMode

    /// Legacy convenience: "mix" historically meant the varied (now Mixed) form.
    var startsInMix: Bool { mode == .mixed }

    init(category: ChallengeCategory, index: Int, cardNumber: String,
         isAdvanced: Bool = false, requiresPremium: Bool = false,
         mode: PracticeMode = .order) {
        self.id = "\(category.rawValue).\(index)\(mode.idSuffix)"
        self.category = category
        self.index = index
        self.cardNumber = cardNumber
        self.isAdvanced = isAdvanced
        self.requiresPremium = requiresPremium
        self.mode = mode
    }

    /// The same level opened in a different practice mode.
    func variant(_ mode: PracticeMode) -> LevelConfig {
        LevelConfig(category: category, index: index, cardNumber: cardNumber,
                    isAdvanced: isAdvanced, requiresPremium: requiresPremium, mode: mode)
    }

    /// All three mode variants of this level (used to total a level's trophies).
    var allModeVariants: [LevelConfig] { PracticeMode.allCases.map { variant($0) } }
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
    // Each harder practice mode carries a larger trophy goal, so climbing to the
    // toughest mode is also worth more. Supermix keeps its own, highest goal.
    static let orderMaximumTrophies = 20
    static let randomMaximumTrophies = 30
    static let mixedMaximumTrophies = 40
    static let extendedMaximumTrophiesPerLevel = 50
    static let maximumCompletionCount = 100

    /// The trophy goal for a level depends on its practice mode: Order 20,
    /// Random 30, Mixed 40. The four Supermix-menu categories keep their own
    /// 50-trophy goal, since they are the final, hardest categories.
    static func maximumTrophies(for level: LevelConfig) -> Int {
        if level.category.isSupermixMenu { return extendedMaximumTrophiesPerLevel }
        switch level.mode {
        case .order: return orderMaximumTrophies
        case .random: return randomMaximumTrophies
        case .mixed: return mixedMaximumTrophies
        }
    }

    static func maximumTrophies(forLevelID levelID: String) -> Int {
        let categoryID = levelID.split(separator: ".").first.map(String.init)
        guard let categoryID, let category = ChallengeCategory(rawValue: categoryID) else {
            return orderMaximumTrophies
        }
        if category.isSupermixMenu { return extendedMaximumTrophiesPerLevel }
        // The id suffix encodes the mode (see PracticeMode.idSuffix).
        if levelID.hasSuffix(PracticeMode.mixed.idSuffix) { return mixedMaximumTrophies }
        if levelID.hasSuffix(PracticeMode.random.idSuffix) { return randomMaximumTrophies }
        return orderMaximumTrophies
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

    /// Order addition, subtraction and tables are fixed practice routes.
    /// Random and Mixed levels retain their varied and revision behaviour.
    private var usesFixedStandardSequence: Bool {
        level.mode == .order && [.addition, .subtraction, .tables].contains(level.category)
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
        switch level.mode {
        case .order:  break                          // fall through to the guided routes
        case .random: return randomQuestion()
        case .mixed:  return immediateMixQuestion()
        }
        switch level.category {
        case .addition: return additionQuestion()
        case .additionMix: return additionMixQuestion()
        case .subtraction: return subtractionQuestion()
        case .subtractionMix: return subtractionMixQuestion()
        case .tables: return tableQuestion(table: level.index)
        case .tablesMix: return tablesMixQuestion()
        case .fractions: return fractionsSingleQuestion()   // Order = "Single"
        case .fractionsMix: return fractionsMixQuestion()
        case .percentages: return percentagesWholeQuestion() // Order = "Whole"
        case .percentagesMix: return percentagesMixQuestion()
        case .superBasic: return superQuestion(Self.superBasicWeights)
        case .superTimes: return superQuestion(Self.superTimesWeights)
        case .superFraction: return superQuestion(Self.superFractionWeights)
        case .superAll: return superQuestion(Self.superAllWeights)
        }
    }

    /// The Mixed menu uses this level's number *or a lower one*, all mixed up.
    /// It leans toward the harder (higher) end — for the table of 12, ×3 still
    /// turns up now and then, but ×8 far more often (see `weightedHard`).
    private func immediateMixQuestion() -> Question {
        switch level.category {
        case .addition:
            // Card number = highest small operand (card 3 allows +1/+2/+3).
            return additionSmallStepQuestion(maxAdd: level.index, weightedHard: true)
        case .subtraction:
            return subtractionSmallStepQuestion(maxTake: level.index, weightedHard: true)
        case .tables:
            return tablesMixQuestion(pool: Array(1...min(99, level.index)), weightedHard: true)
        case .fractions:
            // "Gemixt": this denominator mixed with the easier parts that
            // divide into it (8 → also halves and quarters).
            return fractionsMixedQuestion()
        case .percentages:
            // "Gemixt": this percentage mixed with the percentages of the
            // levels before it, back to whole answers.
            return percentagesMixedQuestion()
        default:
            return superQuestion(Self.superAllWeights)
        }
    }

    // MARK: Random (Hussel)

    /// The Random menu drills only this level's own number, but in shuffled
    /// order — and, wherever the maths allows, with that number free to sit on
    /// either side of the sum. A minus keeps its fixed order (a−b ≠ b−a).
    private func randomQuestion() -> Question {
        switch level.category {
        case .addition:    return additionRandomQuestion()
        case .subtraction: return subtractionRandomQuestion()
        case .tables:      return tablesRandomQuestion()
        case .fractions:   return fractionsMultipleQuestion() // "Meerdere"
        case .percentages: return percentagesDecimalQuestion() // "Komma"
        default:           return immediateMixQuestion()
        }
    }

    /// Picks from an ordered easy→hard list, biased toward the hard (later)
    /// end so a Mixed level keeps its weight up high: the top values appear
    /// most, everything below still shows up occasionally. Weight grows
    /// linearly with position, so the bias scales itself across all 99 levels
    /// with no per-level tuning.
    private func weightedHardPick<T>(_ items: [T]) -> T {
        guard items.count > 1 else { return items[items.count - 1] }
        let n = items.count
        let total = n * (n + 1) / 2          // 1 + 2 + … + n
        var r = Int.random(in: 1...total)
        for i in 0..<n {
            r -= (i + 1)                     // position i carries weight i+1
            if r <= 0 { return items[i] }
        }
        return items[n - 1]
    }

    /// This level's own table, every multiplier 1…12 shuffled, and the table
    /// free to appear before or after the ×.
    private func tablesRandomQuestion() -> Question {
        let table = min(99, level.index)
        let m = shuffledCycled(Array(1...12))
        let answer = table * m
        let (a, b) = Bool.random() ? (table, m) : (m, table)
        return makeQuestion("\(a) × \(b) = ?", "\(answer)",
                            [table * (m + 1), table * max(1, m - 1),
                             (table + 1) * m, (table - 1) * m,
                             answer + 1, answer - 1].filter { $0 >= 0 }.map(String.init),
                            isRandomPractice: true)
    }

    /// Always add this level's number, shuffled through the same value set as
    /// the Order route, with the two numbers free to swap sides.
    private func additionRandomQuestion() -> Question {
        let n = level.index
        let pos = shuffledCycled(Array(0..<30))
        let group = pos / 10
        let other = n + [0, 1, 3][group] + (pos % 10) * n
        let answer = n + other
        let (a, b) = Bool.random() ? (n, other) : (other, n)
        return makeQuestion("\(a) + \(b) = ?", "\(answer)",
                            [answer + 1, answer - 1, answer + 2, answer - 2,
                             other, answer + n].filter { $0 >= 0 }.map(String.init),
                            isRandomPractice: true)
    }

    /// Always subtract this level's number, shuffled through the Order route's
    /// value set. The order never swaps — a minus is not commutative.
    private func subtractionRandomQuestion() -> Question {
        let n = level.index
        let pos = shuffledCycled(Array(0..<30))
        let group = pos / 10
        let left = 11 * n + [0, 1, 3][group] - (pos % 10) * n
        let answer = left - n
        return makeQuestion("\(left) − \(n) = ?", "\(answer)",
                            [answer + 1, answer - 1, answer + 2, answer - 2,
                             left, answer - n].filter { $0 >= 0 }.map(String.init),
                            isRandomPractice: true)
    }

    // MARK: Fractions & percentages sub-levels
    //
    // Fractions and Percentages both have three sub-levels that change *what
    // kind* of sum you get rather than how it is ordered:
    //
    //   Fractions   Single (1/d) · Multiple (n/d) · Mixed (also easier parts)
    //   Percentages Whole answer · Decimal answer · Mixed (earlier percentages)
    //
    // These map onto the three PracticeModes (order · random · mixed).

    /// This level's own fraction denominator.
    private var currentDenominator: Int {
        Self.fractionDenominators[min(level.index - 1, Self.fractionDenominators.count - 1)]
    }

    /// This level's own percentage.
    private var currentPercentage: Int {
        Self.percentageLevels[min(level.index - 1, Self.percentageLevels.count - 1)]
    }

    /// The denominators the Mixed ("Gemixt") fraction level reviews: this
    /// level's own denominator plus the denominators of *earlier* levels that
    /// divide evenly into it (8 → [2, 4, 8], 12 → [2, 3, 4, 6, 12]). It never
    /// reaches for a harder new part — a 7th of a level-3 whole would be harder,
    /// not easier — so the parts always come from this level and earlier ones.
    private func fractionMixedPool() -> [Int] {
        let d = currentDenominator
        let earlier = Set(Self.fractionDenominators.prefix(level.index))
        let pool = (2...max(2, d)).filter { d % $0 == 0 && earlier.contains($0) }
        return pool.isEmpty ? [d] : pool
    }

    /// Builds one "num/den × whole = ?" fraction question with child-plausible
    /// near-miss distractors.
    private func fractionOfWhole(num: Int, den: Int, whole: Int) -> Question {
        let unit = whole / den            // first divide…
        let answer = unit * num           // …then multiply
        return makeQuestion("\(num)/\(den) × \(whole) = ?", "\(answer)",
                            [unit, whole, answer + unit, max(0, answer - unit),
                             whole - answer, answer + 1, answer - 1]
                                .filter { $0 >= 0 }.map(String.init),
                            isRandomPractice: true)
    }

    /// Single ("Eén deel"): always the unit fraction 1/d of a whole, with the
    /// whole shuffled so the answers never count up predictably.
    private func fractionsSingleQuestion() -> Question {
        let d = currentDenominator
        let whole = d * shuffledCycled(Array(1...6))
        return fractionOfWhole(num: 1, den: d, whole: whole)
    }

    /// Multiple ("Meerdere"): mostly several parts of d (3/8, 6/8…), with a
    /// single part 1/d turning up about a quarter of the time.
    private func fractionsMultipleQuestion() -> Question {
        let d = currentDenominator
        let whole = d * shuffledCycled(Array(1...6))
        let num: Int
        if d <= 2 {
            num = 1                                   // 1/2 is the only proper part
        } else if Double.random(in: 0..<1) < 0.25 {
            num = 1                                   // 25% single parts
        } else {
            num = Int.random(in: 2...(d - 1))         // 75% multiple parts
        }
        return fractionOfWhole(num: num, den: d, whole: whole)
    }

    /// Mixed ("Gemixt"): this denominator mixed with the easier parts that
    /// divide into it — leaning toward d itself, the earlier ones still return.
    private func fractionsMixedQuestion() -> Question {
        let den = weightedHardPick(fractionMixedPool().sorted())
        let whole = den * Int.random(in: 1...6)
        let num = den <= 2 ? 1 : Int.random(in: 1...(den - 1))
        return fractionOfWhole(num: num, den: den, whole: whole)
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
    private func additionSmallStepQuestion(maxAdd: Int, weightedHard: Bool = false) -> Question {
        let cap = max(20, maxAdd * 6)
        // Mixed mode leans toward the higher added numbers (harder), but the
        // smaller ones still appear now and then.
        let add = weightedHard ? weightedHardPick(Array(1...maxAdd)) : Int.random(in: 1...maxAdd)
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
    private func subtractionSmallStepQuestion(maxTake: Int, weightedHard: Bool = false) -> Question {
        let cap = max(20, maxTake * 6)
        // Mixed mode leans toward the higher numbers taken away (harder).
        let take = weightedHard ? weightedHardPick(Array(1...maxTake)) : Int.random(in: 1...maxTake)
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

    private func tablesMixQuestion(pool: [Int]? = nil, weightedHard: Bool = false) -> Question {
        let tables = pool ?? ChallengeScaling.tablesMixPool(level.index)
        let table: Int
        if weightedHard {
            // Mixed mode: the highest tables (nearest this level's own) come up
            // most, but lower ones still appear from time to time.
            table = weightedHardPick(tables.sorted())
        } else {
            // Supermix/legacy weighting: the newest table half the time.
            let current = tables.max()!
            table = Double.random(in: 0...1) < 0.5 ? current : tables.randomElement()!
        }
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
    private func fractionsVarietyQuestion(denominators: [Int], forms: [String]? = nil,
                                          weightedHard: Bool = false) -> Question {
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
            // Mixed mode leans toward the most recently introduced (harder)
            // denominators; the earlier ones still return regularly.
            let d = weightedHard ? weightedHardPick(denominators) : denominators.randomElement()!
            return fractionsQuestion(denominator: d)
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

    /// Whole ("Heel"): p% of a number that always divides cleanly, so the
    /// answer is a whole number.
    private func percentagesWholeQuestion() -> Question {
        let p = currentPercentage
        let whole = Self.percentageBase(p) * shuffledCycled(Array(1...8))
        let answer = whole * p / 100
        let neighbours = Self.percentageLevels
            .filter { $0 != p && whole * $0 % 100 == 0 }
            .sorted { abs($0 - p) < abs($1 - p) }
            .prefix(3)
            .map { whole * $0 / 100 }
        return makeQuestion("\(p)% × \(whole) = ?", "\(answer)",
                            (neighbours + [whole - answer, answer + 1, answer - 1])
                                .filter { $0 >= 0 }.map(String.init),
                            isRandomPractice: true)
    }

    /// The only fractional parts a Decimal answer may end in, in hundredths:
    /// the tenths 0,1–0,9, the quarters 0,25/0,75 and the (rounded) thirds
    /// 0,33/0,67. Nothing messier, so the answers stay readable.
    private static let decimalRemainders: Set<Int> = [10, 20, 30, 40, 50, 60, 70, 80, 90, 25, 75, 33, 67]

    /// Decimal ("Komma"): the same percentage as the Whole level. Half the
    /// questions keep a clean whole answer, the other half land behind the
    /// comma — always on one of the friendly decimals in `decimalRemainders`.
    /// The whole itself stays an ordinary integer.
    private func percentagesDecimalQuestion() -> Question {
        // 50/50 split between whole-number and decimal answers.
        if Bool.random() { return percentagesWholeQuestion() }
        let p = currentPercentage
        // Every integer whole whose "p% of whole" lands on a friendly decimal
        // with a small, readable answer (≤ 60). Working in hundredths keeps the
        // maths exact — no floating-point rounding anywhere.
        var candidates: [(whole: Int, hundredths: Int)] = []
        for whole in 1...600 {
            let hundredths = whole * p            // = answer × 100
            guard hundredths <= 6000 else { break }
            if Self.decimalRemainders.contains(hundredths % 100) {
                candidates.append((whole, hundredths))
            }
        }
        // Degenerate safety net (e.g. p a multiple of 100): fall back to whole.
        guard let pick = candidates.randomElement() else { return percentagesWholeQuestion() }
        let answerText = Self.decimalString(hundredths: pick.hundredths)
        // Near-misses a child actually produces: dropped the decimal (rounded
        // to a whole), the tenth above/below, and one whole off.
        let roundedDown = (pick.hundredths / 100) * 100
        let wrong = [roundedDown, roundedDown + 100,
                     pick.hundredths + 10, pick.hundredths - 10,
                     pick.hundredths + 100, pick.hundredths - 100]
            .filter { $0 >= 0 && $0 != pick.hundredths }
            .map { Self.decimalString(hundredths: $0) }
        return makeQuestion("\(p)% × \(pick.whole) = ?", answerText, wrong,
                            isRandomPractice: true)
    }

    /// Mixed ("Gemixt"): this percentage together with the percentages of the
    /// levels before it — back to whole answers, leaning toward this level's own.
    private func percentagesMixedQuestion() -> Question {
        let pool = Array(Self.percentageLevels.prefix(max(1, level.index)))
        let p = weightedHardPick(pool)
        let whole = Self.percentageBase(p) * Int.random(in: 1...8)
        let answer = whole * p / 100
        let neighbours = pool
            .filter { $0 != p && whole * $0 % 100 == 0 }
            .sorted { abs($0 - p) < abs($1 - p) }
            .prefix(3)
            .map { whole * $0 / 100 }
        return makeQuestion("\(p)% × \(whole) = ?", "\(answer)",
                            (neighbours + [whole - answer, answer + 1, answer - 1])
                                .filter { $0 >= 0 }.map(String.init),
                            isRandomPractice: true)
    }

    /// Formats a hundredths value as a readable decimal in the player's
    /// language (comma in Dutch, dot in English), trimming a trailing zero so
    /// 3,50 shows as 3,5 while 3,25 keeps both places.
    private static func decimalString(hundredths: Int) -> String {
        let whole = hundredths / 100
        let frac = hundredths % 100
        if frac == 0 { return "\(whole)" }
        let separator = LanguageManager.shared.effective == .dutch ? "," : "."
        if frac % 10 == 0 { return "\(whole)\(separator)\(frac / 10)" }
        return "\(whole)\(separator)" + String(format: "%02d", frac)
    }

    /// The inverse of `decimalString`: reads a "3,25"/"3.5"/"4" string back
    /// into hundredths so padded distractors can be nudged numerically.
    private static func hundredths(from text: String) -> Int {
        let parts = text.replacingOccurrences(of: ",", with: ".").split(separator: ".")
        let whole = Int(parts.first ?? "0") ?? 0
        guard parts.count > 1 else { return whole * 100 }
        var digits = String(parts[1])
        if digits.count == 1 { digits += "0" }          // "5" → 50 hundredths
        return whole * 100 + (Int(digits.prefix(2)) ?? 0)
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
    private func percentagesVarietyQuestion(percentages: [Int], forms: [String]? = nil,
                                            weightedHard: Bool = false) -> Question {
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
            // Mixed mode leans toward the most recently introduced (harder)
            // percentages; the earlier ones still return regularly.
            let p = weightedHard ? weightedHardPick(percentages) : percentages.randomElement()!
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
            return superAdditionQuestion()
        case .sub:
            return superSubtractionQuestion()
        case .mul:
            // Same rule as addition/subtraction: the table itself is at most
            // this level's own number (weighted toward it), so level 1 only
            // ever gives ×1 sums — never something like 4×7.
            return tablesMixQuestion(pool: Array(1...idx), weightedHard: true)
        case .fraction:
            let introduced = Array(Self.fractionDenominators.prefix(max(1, idx)))
            return fractionsQuestion(denominator: weightedHardPick(introduced))
        case .percent:
            let introduced = Array(Self.percentageLevels.prefix(max(1, idx)))
            return percentagesQuestion(percentage: weightedHardPick(introduced))
        }
    }

    /// One operand is always at most this level's own number — weighted
    /// toward it, so lower numbers fade out as the level grows (level 12
    /// mostly gives 8…12, rarely 3…7, never 1…2) — while the other operand's
    /// range reuses Addition Mix's own ceiling, the same "max height" every
    /// other menu already scales by.
    private func superAdditionQuestion() -> Question {
        let idx = level.index
        let small = weightedHardPick(Array(1...idx))
        let ceiling = ChallengeScaling.additionMixCeiling(idx)
        let big = Int.random(in: 1...max(1, ceiling - small))
        let (a, b) = Bool.random() ? (small, big) : (big, small)
        let answer = a + b
        return makeQuestion("\(a) + \(b) = ?", "\(answer)",
                            [answer + 1, answer - 1, answer + 2, answer - 2,
                             big, answer + small].filter { $0 >= 0 }.map(String.init),
                            isRandomPractice: true)
    }

    /// Mirrors `superAdditionQuestion`, but the subtracted number is
    /// guaranteed small (weighted toward this level's own number) and the
    /// result's range reuses Subtraction Mix's own ceiling.
    private func superSubtractionQuestion() -> Question {
        let idx = level.index
        let small = weightedHardPick(Array(1...idx))
        let ceiling = ChallengeScaling.subtractionMixCeiling(idx)
        let a = Int.random(in: (small + 1)...(small + ceiling))
        let answer = a - small
        return makeQuestion("\(a) − \(small) = ?", "\(answer)",
                            [answer + 1, answer - 1, answer + 2, answer - 2,
                             a, answer - small].filter { $0 >= 0 }.map(String.init),
                            isRandomPractice: true)
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
            } else if correct.contains(",") || correct.contains(".") {
                // Decimal answer (percentages "Komma"): nudge by tenths so the
                // padded options are still plausible decimals, never "%".
                let base = Self.hundredths(from: correct)
                let offset = (salt % 2 == 0 ? salt : -salt) * 10
                candidate = Self.decimalString(hundredths: max(0, base + offset))
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
