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
    case mix, supermix

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .addition: return "Addition"
        case .additionMix: return "Addition Mix"
        case .subtraction: return "Subtraction"
        case .subtractionMix: return "Subtraction Mix"
        case .tables: return "Times Tables"
        case .tablesMix: return "Tables Mix"
        case .fractions: return "Fractions"
        case .fractionsMix: return "Fractions Mix"
        case .percentages: return "Percentages"
        case .percentagesMix: return "Percentages Mix"
        case .mix: return "Mix"
        case .supermix: return "Supermix"
        }
    }

    /// Small secondary symbol on level cards.
    var symbol: String {
        switch self {
        case .addition, .additionMix: return "+"
        case .subtraction, .subtractionMix: return "−"
        case .tables, .tablesMix: return "×"
        case .fractions, .fractionsMix: return "½"
        case .percentages, .percentagesMix: return "%"
        case .mix: return "🔀"
        case .supermix: return "🌟"
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

// MARK: - Level configuration

struct LevelConfig: Identifiable, Hashable {
    /// Stable identifier, e.g. "addition.3" or "tables.7".
    let id: String
    let category: ChallengeCategory
    let index: Int
    /// Big central text on the card (table, addend, denominator, percentage, …).
    let cardNumber: String
    let title: String
    let isAdvanced: Bool
    let requiresPremium: Bool
    /// The Mix menu starts this familiar skill straight in varied practice.
    let startsInMix: Bool

    init(category: ChallengeCategory, index: Int, cardNumber: String, title: String,
         isAdvanced: Bool = false, requiresPremium: Bool = false,
         startsInMix: Bool = false) {
        self.id = "\(category.rawValue).\(index)\(startsInMix ? ".mix" : "")"
        self.category = category
        self.index = index
        self.cardNumber = cardNumber
        self.title = title
        self.isAdvanced = isAdvanced
        self.requiresPremium = requiresPremium
        self.startsInMix = startsInMix
    }

    func immediateMixVersion() -> LevelConfig {
        LevelConfig(category: category, index: index, cardNumber: cardNumber, title: title,
                    isAdvanced: isAdvanced, requiresPremium: requiresPremium, startsInMix: true)
    }
}

/// Static level configurations, computed once and cached.
enum LevelCatalog {
    static let byCategory: [ChallengeCategory: [LevelConfig]] = {
        var result: [ChallengeCategory: [LevelConfig]] = [:]

        // Addition: one clear pattern per level — repeated adding of n.
        result[.addition] = (1...12).map {
            LevelConfig(category: .addition, index: $0, cardNumber: "\($0)", title: "Add +\($0)")
        }
        // Addition mix: growing maximum result.
        result[.additionMix] = [10, 15, 20, 30, 50, 100, 150, 200, 300, 500, 750, 1000].enumerated().map { i, m in
            LevelConfig(category: .additionMix, index: i + 1, cardNumber: "\(m)", title: "Up to \(m)")
        }
        // Subtraction: repeatedly take away n.
        result[.subtraction] = (1...12).map {
            LevelConfig(category: .subtraction, index: $0, cardNumber: "\($0)", title: "Take −\($0)")
        }
        // Subtraction mix: each card shows the real maximum start number.
        var subMix = [10, 15, 20, 30, 50, 100, 20, 150, 200, 300, 500, 1000].enumerated().map { i, m in
            LevelConfig(category: .subtractionMix, index: i + 1, cardNumber: "\(m)", title: "From \(m)")
        }
        subMix[6] = LevelConfig(category: .subtractionMix, index: 7, cardNumber: "20",
                                title: "Below zero", isAdvanced: true)
        result[.subtractionMix] = subMix

        // Times tables: one table per level (13–100 with Premium).
        var tables = (1...12).map {
            LevelConfig(category: .tables, index: $0, cardNumber: "\($0)", title: "Table of \($0)")
        }
        tables += (13...100).map {
            LevelConfig(category: .tables, index: $0, cardNumber: "\($0)",
                        title: "Table of \($0)", requiresPremium: true)
        }
        result[.tables] = tables

        // Tables mix: growing pool of already-practiced tables.
        let pools: [[Int]] = [[1, 2], [1, 2, 3], Array(1...5), Array(1...8), Array(1...10), Array(1...12),
                              Array(1...12), Array(2...12), Array(3...12), Array(4...12), Array(5...12), Array(6...12)]
        result[.tablesMix] = pools.enumerated().map { i, pool in
            LevelConfig(category: .tablesMix, index: i + 1, cardNumber: "\(pool.max()!)",
                        title: "Tables \(pool.min()!)–\(pool.max()!)")
        }

        // Fractions: one denominator per level, learning-line order (no denominator 1).
        let fractionLevels: [(Int, String)] = [(2, "Halves"), (3, "Thirds"), (4, "Quarters"),
                                               (5, "Fifths"), (6, "Sixths"), (8, "Eighths"), (10, "Tenths"),
                                               (12, "Twelfths"), (15, "Fifteenths"), (20, "Twentieths"),
                                               (25, "Twenty-fifths"), (30, "Thirtieths")]
        result[.fractions] = fractionLevels.enumerated().map { i, item in
            LevelConfig(category: .fractions, index: i + 1, cardNumber: "\(item.0)", title: item.1)
        }
        // Fractions mix: only concepts that were already introduced.
        let fracMixTitles = ["Halves & thirds", "Compare", "Equivalent", "Add & take", "All together",
                             "Up to eighths", "Up to tenths", "Up to twelfths", "Up to fifteenths",
                             "Up to twentieths", "Up to twenty-fifths", "All fractions"]
        result[.fractionsMix] = fracMixTitles.enumerated().map { i, t in
            LevelConfig(category: .fractionsMix, index: i + 1, cardNumber: "\(i + 1)", title: t,
                        isAdvanced: i == 4)
        }

        // Percentages in learning-line order: the fraction-friendly ones
        // first (half, quarter, tenth, whole, three quarters, fifth), then
        // the derived ones, ending with the genuinely hard 15% and 12%.
        let pctLevels = [50, 25, 10, 100, 75, 20, 5, 30, 40, 60, 15, 12]
        result[.percentages] = pctLevels.enumerated().map { i, p in
            LevelConfig(category: .percentages, index: i + 1, cardNumber: "\(p)", title: "\(p)%")
        }
        let pctMixTitles = ["Halves & quarters", "All percentages", "Discounts", "Increases",
                            "Up to 50%", "Up to 75%", "Everyday percentages", "Find the part",
                            "Find the whole", "Sales", "Changes", "All percentages"]
        result[.percentagesMix] = pctMixTitles.enumerated().map { i, t in
            LevelConfig(category: .percentagesMix, index: i + 1, cardNumber: "\(i + 1)", title: t,
                        isAdvanced: i == 2)
        }

        // Mix: the card number is a promise — every sum keeps at least one
        // operand at or below that number (2 + 12 or 8 − 2 are both fine on
        // card 2), so the number itself tells how hard the level is.
        result[.mix] = (1...12).map {
            LevelConfig(category: .mix, index: $0, cardNumber: "\($0)", title: "With \($0)")
        }
        // Supermix: everything, harder.
        result[.supermix] = (1...12).map {
            LevelConfig(category: .supermix, index: $0, cardNumber: "\($0)", title: "Supermix \($0)",
                        isAdvanced: $0 >= 3)
        }

        // Each menu has its own genuine set of twelve configured free
        // levels. Premium continues that same progression with levels 13–24.
        for category in ChallengeCategory.allCases {
            var levels = result[category, default: []]
            // Tables already continue through 100 as Premium content. Every
            // other menu gets its own "more with Premium" set as well.
            if category != .tables {
                for index in 13...24 {
                    levels.append(
                        LevelConfig(category: category, index: index,
                                    cardNumber: "\(index)", title: "Premium practice \(index)",
                                    isAdvanced: true, requiresPremium: true)
                    )
                }
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

    /// Scores belong to the level, not to a life-mode variant. The legacy
    /// keys are still read so existing players keep all of their trophies.
    private static func key(_ levelID: String) -> String {
        "best.\(levelID)"
    }

    private static func helperKey(_ levelID: String) -> String {
        "best.\(levelID).helper"
    }

    private static func legacyKey(_ levelID: String, _ mode: LifeMode) -> String {
        "best.\(levelID).\(mode.rawValue)"
    }

    /// The normal score is the player's real, unassisted trophy total.
    static func bestScore(levelID: String) -> Int {
        let scores = [UserDefaults.standard.integer(forKey: key(levelID))]
            + LifeMode.allCases.map { UserDefaults.standard.integer(forKey: legacyKey(levelID, $0)) }
        return scores.max() ?? 0
    }

    static func bestScore(levelID: String, helperEnabled: Bool) -> Int {
        guard helperEnabled else { return bestScore(levelID: levelID) }
        // Helper mode includes progress already earned without assistance,
        // while assisted trophies never inflate the normal score.
        return max(bestScore(levelID: levelID), helperOnlyBestScore(levelID: levelID))
    }

    static func helperOnlyBestScore(levelID: String) -> Int {
        UserDefaults.standard.integer(forKey: helperKey(levelID))
    }

    /// Kept as a convenience for unlocking code; all modes share one score.
    static func bestAnyMode(levelID: String) -> Int {
        bestScore(levelID: levelID)
    }

    /// Returns true when this run set a new best for the level.
    @discardableResult
    static func recordScore(_ score: Int, levelID: String, helperEnabled: Bool) -> Bool {
        let cappedScore = GameSettings.capsTrophiesAtThirty
            ? min(maximumTrophiesPerLevel, score)
            : score
        let currentBest = helperEnabled
            ? helperOnlyBestScore(levelID: levelID)
            : bestScore(levelID: levelID)
        guard cappedScore > currentBest else { return false }
        UserDefaults.standard.set(cappedScore, forKey: helperEnabled ? helperKey(levelID) : key(levelID))
        return true
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
        case .mix: return "subtraction.1" // plus addition.1, checked below
        case .supermix: return nil        // custom multi-gate below
        default: return nil
        }
    }

    static func isUnlocked(_ level: LevelConfig) -> Bool {
        switch level.category {
        case .mix where level.index == 1:
            return bestAnyMode(levelID: "addition.1") >= unlockThreshold
                && bestAnyMode(levelID: "subtraction.1") >= unlockThreshold
        case .supermix where level.index == 1:
            let gates = ["addition.1", "subtraction.1", "tables.1", "fractions.1", "percentages.1"]
            return gates.allSatisfy { bestAnyMode(levelID: $0) >= unlockThreshold }
        default:
            guard let prereq = prerequisiteID(for: level) else { return true }
            return bestAnyMode(levelID: prereq) >= unlockThreshold
        }
    }

    /// 0–1 progress toward unlocking (for "almost unlocked" cards).
    static func unlockProgress(_ level: LevelConfig) -> Double {
        guard let prereq = prerequisiteID(for: level) else { return 0 }
        return min(1, Double(bestAnyMode(levelID: prereq)) / Double(unlockThreshold))
    }
}

// MARK: - Question

struct Question {
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

    // Running chain for addition/subtraction: the previous correct answer
    // becomes the next left operand, so every visible sum has exactly two
    // numbers while the difficulty still builds up.
    private var chainValue: Int?
    private var chainCycle = 0
    private var additionSeriesComplete = false

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
        chainValue = nil
        chainCycle = 0
        additionSeriesComplete = false
    }

    /// Extra repetition of recently missed questions.
    func registerWrong(_ question: Question) {
        guard wrongBag.count < 5 else { return }
        wrongBag.append(question)
    }

    func next() -> Question {
        if !wrongBag.isEmpty, step > 2, Double.random(in: 0...1) < 0.2,
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
        case .mix: return mixQuestion()
        case .supermix: return supermixQuestion()
        }
    }

    /// The Mix menu uses the same subject and ceiling as Standard, but skips
    /// the guided runway and starts immediately in varied questions.
    private func immediateMixQuestion() -> Question {
        switch level.category {
        case .addition:
            return additionMixQuestion(maxResult: max(20, level.index * 6), isRandomPractice: true)
        case .subtraction:
            return subtractionMixQuestion(maxStart: max(10, level.index * 5), allowNegative: false)
        case .tables:
            return tablesMixQuestion(pool: Array(1...min(12, level.index)))
        case .fractions:
            let introduced = Array(Self.fractionDenominators.prefix(max(1, level.index)))
            return fractionsQuestion(denominator: introduced.randomElement()!)
        case .percentages:
            let introduced = Array(Self.percentageLevels.prefix(max(1, level.index)))
            return percentagesQuestion(percentage: introduced.randomElement()!)
        case .mix:
            // Mix mode of the Mix menu: same small-operand rule, but with
            // division and percentages added on top of + − ×.
            return mixQuestion(withDivisionAndPercentages: true)
        default:
            return supermixQuestion()
        }
    }

    // MARK: Addition

    /// One pattern per level, as a running chain with exactly two numbers:
    /// level +1: 1+1, 2+1, 3+1 …  level +3: 3+3, 6+3, 9+3 …
    /// (nextLeftOperand = previousCorrectAnswer, right operand fixed.)
    private func additionQuestion() -> Question {
        let n = level.index
        // +2 now visibly continues through 20 (2+2 ... 18+2). After a
        // completed guided chain, this level intentionally becomes mixed
        // practice and the HUD labels that switch.
        let cap = max(20, n * 6)
        if additionSeriesComplete {
            return additionMixQuestion(maxResult: cap, isRandomPractice: true)
        }
        let left = chainValue ?? n
        let answer = left + n
        chainValue = (answer + n > cap) ? nil : answer
        if answer + n > cap { additionSeriesComplete = true }
        // Real child errors, all close to the answer: counting slips
        // (±1/±2), forgetting to add (left) and adding n twice (answer+n).
        return makeQuestion("\(left) + \(n) = ?", "\(answer)",
                            [answer + 1, answer - 1, answer + 2, answer - 2,
                             left, answer + n].filter { $0 >= 0 }.map(String.init))
    }

    private func additionMixQuestion(maxResult: Int? = nil, harder: Bool = false,
                                     isRandomPractice: Bool = false) -> Question {
        let bases = [10, 15, 20, 30, 50, 100, 150, 200, 300, 500, 750, 1000]
        var m = maxResult ?? bases[min(level.index - 1, bases.count - 1)]
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

    /// One pattern per level, as a descending chain with exactly two
    /// numbers: 10−1=9, 9−1=8, 8−1=7 … Never negative: when the lower
    /// bound is reached the chain restarts from a (slightly varied) start.
    private func subtractionQuestion() -> Question {
        let n = level.index
        let base = max(n * 5, 10)
        let start = base + (chainCycle % 3) * n // vary the start per cycle
        let left = chainValue ?? start
        let answer = left - n
        if answer - n >= 0 {
            chainValue = answer
        } else {
            chainValue = nil // restart a new valid series next time
            chainCycle += 1
        }
        // Counting slips, forgetting to subtract (left = answer + n) and
        // subtracting n twice (answer − n) — all plausible near-misses.
        return makeQuestion("\(left) − \(n) = ?", "\(answer)",
                            [answer + 1, answer - 1, answer + 2, answer - 2,
                             left, answer - n].filter { $0 >= 0 }.map(String.init))
    }

    private func subtractionMixQuestion(maxStart: Int? = nil, allowNegative: Bool? = nil) -> Question {
        let bases = [10, 15, 20, 30, 50, 100, 20, 150, 200, 300, 500, 1000]
        let m = maxStart ?? bases[min(level.index - 1, bases.count - 1)]
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

    /// Questions continue in order: t×1, t×2 … t×12, then repeat (shuffled).
    private func tableQuestion(table: Int) -> Question {
        let m = cycled(Array(1...12))
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
        let pools: [[Int]] = [[1, 2], [1, 2, 3], Array(1...5), Array(1...8), Array(1...10), Array(1...12),
                              Array(1...12), Array(2...12), Array(3...12), Array(4...12), Array(5...12), Array(6...12)]
        let tables = pool ?? pools[min(level.index - 1, pools.count - 1)]
        let current = tables.max()!
        // Weighted: the newest table most often, earlier tables regularly.
        let table = Double.random(in: 0...1) < 0.5 ? current : tables.randomElement()!
        let m = Int.random(in: 1...12)
        let answer = table * m
        return makeQuestion("\(table) × \(m) = ?", "\(answer)",
                            [table * (m + 1), table * max(1, m - 1),
                             (table + 1) * m, (table - 1) * m,
                             answer + 1, answer - 1].filter { $0 >= 0 }.map(String.init))
    }

    // MARK: Fractions

    private static let fractionDenominators = [2, 3, 4, 5, 6, 8, 10, 12, 15, 20, 25, 30]

    /// One denominator per level. Wholes are generated directly from
    /// multiples of the denominator: whole = denominator × factor.
    private func fractionsQuestion(denominator: Int? = nil) -> Question {
        let d = denominator ?? Self.fractionDenominators[min(level.index - 1, Self.fractionDenominators.count - 1)]
        let factors = Array(1...5)
        let factor = cycled(factors)
        let whole = d * factor // series d → 2d → … → 5d, then restarts
        let cycle = cycleCount(seriesLength: factors.count)

        // Later cycles vary the question form and the numerator.
        if cycle >= 1, Double.random(in: 0...1) < 0.2 {
            let num = d >= 3 ? Int.random(in: 1...(d - 1)) : 1
            if Bool.random() {
                return makeQuestion("Numerator of \(num)/\(d)?", "\(num)",
                                    [d, num + 1, max(1, num - 1), d - num].map(String.init))
            }
            return makeQuestion("Denominator of \(num)/\(d)?", "\(d)",
                                [num, d + 1, d - 1, d * 2].map(String.init))
        }

        let num = (cycle == 0 || d == 2) ? 1 : Int.random(in: 1...(d - 1))
        let unit = whole / d          // first divide…
        let answer = unit * num       // …then multiply
        // Near-misses only: forgot to multiply (unit), numerator one off
        // (answer ± unit), the complement, and counting slips — never the
        // faraway whole itself.
        return makeQuestion("\(num)/\(d) of \(whole) = ?", "\(answer)",
                            [unit, answer + unit, max(0, answer - unit),
                             whole - answer, answer + 1, answer - 1].map(String.init))
    }

    private func fractionsMixQuestion() -> Question {
        // Only concepts that were already introduced, per level.
        let denominators: [Int]
        var forms: [String] = ["fractionOf", "numerator"]
        switch level.index {
        case 1: denominators = [2, 3]
        case 2: denominators = [2, 3, 4]; forms.append("compare")
        case 3: denominators = [2, 3, 4, 5]; forms += ["compare", "equivalent"]
        case 4: denominators = [2, 3, 4, 5, 6]; forms += ["compare", "equivalent", "addSame", "subSame"]
        default: denominators = [2, 3, 4, 5, 6, 8, 10]; forms += ["compare", "equivalent", "addSame", "subSame"]
        }

        switch forms.randomElement()! {
        case "compare":
            var a = denominators.randomElement()!
            var b = denominators.randomElement()!
            while b == a { b = Self.fractionDenominators.filter { denominators.contains($0) }.randomElement()! }
            let smaller = min(a, b) // 1/2 > 1/3: smaller denominator wins
            if a > b { swap(&a, &b) }
            return makeQuestion("Bigger: 1/\(a) or 1/\(b)?", "1/\(smaller)",
                                ["1/\(max(a, b))", "1/\(smaller + 1)", "1/\(smaller * 2)"])
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
        case "numerator":
            let d = denominators.randomElement()!
            let num = d >= 3 ? Int.random(in: 1...(d - 1)) : 1
            if Bool.random() {
                return makeQuestion("Numerator of \(num)/\(d)?", "\(num)",
                                    [d, num + 1, max(1, num - 1), d * 2].map(String.init))
            }
            return makeQuestion("Denominator of \(num)/\(d)?", "\(d)",
                                [num, d + 1, max(2, d - 1), d * 2].map(String.init))
        default: // fractionOf
            return fractionsQuestion(denominator: denominators.randomElement()!)
        }
    }

    // MARK: Percentages

    /// Must stay in sync with the catalog's learning-line order above.
    private static let percentageLevels = [50, 25, 10, 100, 75, 20, 5, 30, 40, 60, 15, 12]
    /// whole = base × factor keeps every answer a whole number.
    private static let percentageBase: [Int: Int] = [50: 2, 25: 4, 10: 10, 20: 5, 75: 4,
                                                     5: 20, 40: 5, 60: 5, 12: 25, 15: 20,
                                                     30: 10, 100: 1]
    private static let percentageFraction: [Int: String] = [50: "1/2", 25: "1/4", 75: "3/4", 20: "1/5", 10: "1/10"]

    private func percentagesQuestion(percentage: Int? = nil) -> Question {
        let p = percentage ?? Self.percentageLevels[min(level.index - 1, Self.percentageLevels.count - 1)]
        let factors = Array(1...6)
        let factor = cycled(factors)
        let whole = (Self.percentageBase[p] ?? 4) * factor
        let cycle = cycleCount(seriesLength: factors.count)

        if cycle >= 1, let fraction = Self.percentageFraction[p], Double.random(in: 0...1) < 0.15 {
            let others = Self.percentageLevels.filter { $0 != p }
            return makeQuestion("\(fraction) = ?%", "\(p)%",
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
        return makeQuestion("\(p)% of \(whole) = ?", "\(answer)",
                            (neighbours + [whole - answer, answer + 1, answer - 1])
                                .filter { $0 >= 0 }.map(String.init))
    }

    private func percentagesMixQuestion() -> Question {
        let percentages: [Int]
        var forms = ["percentOf", "fracToPct"]
        switch level.index {
        case 1: percentages = [50, 25, 100]
        case 2: percentages = [50, 25, 10, 20, 75]; forms.append("pctToFrac")
        default: percentages = [50, 25, 10, 20, 75]; forms += ["pctToFrac", "discount", "increase"]
        }

        switch forms.randomElement()! {
        case "fracToPct":
            let p = percentages.compactMap { Self.percentageFraction[$0] != nil ? $0 : nil }.randomElement() ?? 50
            let fraction = Self.percentageFraction[p]!
            return makeQuestion("\(fraction) = ?%", "\(p)%",
                                percentages.filter { $0 != p }.map { "\($0)%" } + ["30%"])
        case "pctToFrac":
            let pairs: [(Int, Int, Int)] = [(25, 1, 4), (75, 3, 4), (50, 1, 2), (20, 1, 5)]
            let (p, num, den) = pairs.filter { percentages.contains($0.0) }.randomElement()!
            return makeQuestion("\(p)% = ?/\(den)", "\(num)",
                                [den, num + 1, max(1, den - num), p / 10].map(String.init))
        case "discount":
            let p = [10, 25, 50].randomElement()!
            let base = (Self.percentageBase[p] ?? 4) * Int.random(in: 2...6)
            let answer = base - base * p / 100
            return makeQuestion("\(base) with \(p)% off = ?", "\(answer)",
                                [base, base * p / 100, answer + 1, answer - 1,
                                 base + base * p / 100].map(String.init))
        case "increase":
            let p = [10, 25, 50].randomElement()!
            let base = (Self.percentageBase[p] ?? 4) * Int.random(in: 2...6)
            let answer = base + base * p / 100
            return makeQuestion("\(base) plus \(p)% = ?", "\(answer)",
                                [base, base * p / 100, answer + 1, answer - 1,
                                 base - base * p / 100].map(String.init))
        default: // percentOf
            let p = percentages.randomElement()!
            if p == 100 {
                let whole = Int.random(in: 2...30)
                return makeQuestion("100% of \(whole) = ?", "\(whole)",
                                    [whole / 2, whole + 1, whole - 1, whole * 2].map(String.init))
            }
            return percentagesQuestion(percentage: p)
        }
    }

    // MARK: Mix & Supermix

    /// Mix: the card number n is a hard rule — every sum has at least one
    /// operand of at most n (2 + 12 and 8 − 2 are both valid on card 2).
    /// Standard uses only + − ×; the Mix mode additionally brings in
    /// ÷ and % questions.
    private func mixQuestion(withDivisionAndPercentages: Bool = false) -> Question {
        let n = level.index
        let small = Int.random(in: 1...n)   // the guaranteed small operand (≤ card number)
        let bigCap = 10 + n * 5             // the free operand grows with the level

        var operations = ["+", "−", "×"]
        if withDivisionAndPercentages { operations += ["÷", "%"] }

        switch operations.randomElement()! {
        case "+":
            let big = Int.random(in: 1...bigCap)
            let (a, b) = Bool.random() ? (small, big) : (big, small)
            let answer = a + b
            return makeQuestion("\(a) + \(b) = ?", "\(answer)",
                                [answer + 1, answer - 1, answer + 2, answer - 2,
                                 big, answer + small].filter { $0 >= 0 }.map(String.init))
        case "−":
            // The small operand is subtracted, so the result never goes negative.
            let a = Int.random(in: (small + 1)...(small + bigCap))
            let answer = a - small
            return makeQuestion("\(a) − \(small) = ?", "\(answer)",
                                [answer + 1, answer - 1, answer + 2, answer - 2,
                                 a, answer - small].filter { $0 >= 0 }.map(String.init))
        case "×":
            let m = Int.random(in: 1...12)
            let (a, b) = Bool.random() ? (small, m) : (m, small)
            let answer = small * m
            return makeQuestion("\(a) × \(b) = ?", "\(answer)",
                                [small * (m + 1), small * max(1, m - 1),
                                 (small + 1) * m, max(0, (small - 1) * m),
                                 answer + 1, answer - 1].filter { $0 >= 0 }.map(String.init))
        case "÷":
            // Divisor is the small operand; the answer is always whole.
            let quotient = Int.random(in: 1...12)
            let dividend = small * quotient
            return makeQuestion("\(dividend) ÷ \(small) = ?", "\(quotient)",
                                [quotient + 1, max(0, quotient - 1), quotient + 2,
                                 small, max(0, dividend - small)].filter { $0 >= 0 }.map(String.init))
        default: // %
            // Percentages follow the learning line: low cards use only the
            // easiest percentages, higher cards unlock more of them.
            let introduced = Self.percentageLevels.prefix(max(3, min(n, Self.percentageLevels.count)))
            return percentagesQuestion(percentage: introduced.randomElement()!)
        }
    }

    /// Everything that has been unlocked, faster and harder — but every
    /// visible sum still shows exactly two numbers and one operation.
    private func supermixQuestion() -> Question {
        let idx = level.index
        switch ["addition", "subtraction", "tables", "fractions", "percentages"].randomElement()! {
        case "addition":
            return additionMixQuestion(maxResult: 30 + idx * 30, harder: idx >= 2)
        case "subtraction":
            return subtractionMixQuestion(maxStart: 30 + idx * 30, allowNegative: idx >= 3)
        case "tables":
            return tablesMixQuestion(pool: Array(1...(8 + idx)))
        case "fractions":
            return fractionsQuestion(denominator: Self.fractionDenominators.randomElement()!)
        default:
            return percentagesQuestion(percentage: Self.percentageLevels.randomElement()!)
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
