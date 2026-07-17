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

    init(category: ChallengeCategory, index: Int, cardNumber: String, title: String,
         isAdvanced: Bool = false, requiresPremium: Bool = false) {
        self.id = "\(category.rawValue).\(index)"
        self.category = category
        self.index = index
        self.cardNumber = cardNumber
        self.title = title
        self.isAdvanced = isAdvanced
        self.requiresPremium = requiresPremium
    }
}

/// Static level configurations, computed once and cached.
enum LevelCatalog {
    static let byCategory: [ChallengeCategory: [LevelConfig]] = {
        var result: [ChallengeCategory: [LevelConfig]] = [:]

        // Addition: one clear pattern per level — repeated adding of n.
        result[.addition] = (1...10).map {
            LevelConfig(category: .addition, index: $0, cardNumber: "\($0)", title: "Add +\($0)")
        }
        // Addition mix: growing maximum result.
        result[.additionMix] = [10, 15, 20, 30, 50, 100].enumerated().map { i, m in
            LevelConfig(category: .additionMix, index: i + 1, cardNumber: "\(m)", title: "Up to \(m)")
        }
        // Subtraction: repeatedly take away n.
        result[.subtraction] = (1...10).map {
            LevelConfig(category: .subtraction, index: $0, cardNumber: "\($0)", title: "Take −\($0)")
        }
        // Subtraction mix: growing start numbers; the last level allows negatives.
        var subMix = [10, 15, 20, 30, 50, 100].enumerated().map { i, m in
            LevelConfig(category: .subtractionMix, index: i + 1, cardNumber: "\(m)", title: "From \(m)")
        }
        subMix.append(LevelConfig(category: .subtractionMix, index: 7, cardNumber: "±",
                                  title: "Below zero", isAdvanced: true))
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
        let pools: [[Int]] = [[1, 2], [1, 2, 3], Array(1...5), Array(1...8), Array(1...10), Array(1...12)]
        result[.tablesMix] = pools.enumerated().map { i, pool in
            LevelConfig(category: .tablesMix, index: i + 1, cardNumber: "\(pool.max()!)",
                        title: "Tables 1–\(pool.max()!)")
        }

        // Fractions: one denominator per level, learning-line order (no denominator 1).
        let fractionLevels: [(Int, String)] = [(2, "Halves"), (3, "Thirds"), (4, "Quarters"),
                                               (5, "Fifths"), (6, "Sixths"), (8, "Eighths"), (10, "Tenths")]
        result[.fractions] = fractionLevels.enumerated().map { i, item in
            LevelConfig(category: .fractions, index: i + 1, cardNumber: "\(item.0)", title: item.1)
        }
        // Fractions mix: only concepts that were already introduced.
        let fracMixTitles = ["Halves & thirds", "Compare", "Equivalent", "Add & take", "All together"]
        result[.fractionsMix] = fracMixTitles.enumerated().map { i, t in
            LevelConfig(category: .fractionsMix, index: i + 1, cardNumber: "\(i + 1)", title: t,
                        isAdvanced: i == 4)
        }

        // Percentages: fraction-friendly percentages first.
        let pctLevels = [50, 25, 10, 20, 75]
        result[.percentages] = pctLevels.enumerated().map { i, p in
            LevelConfig(category: .percentages, index: i + 1, cardNumber: "\(p)", title: "\(p)%")
        }
        let pctMixTitles = ["Halves & quarters", "All percentages", "Discounts"]
        result[.percentagesMix] = pctMixTitles.enumerated().map { i, t in
            LevelConfig(category: .percentagesMix, index: i + 1, cardNumber: "\(i + 1)", title: t,
                        isAdvanced: i == 2)
        }

        // Mix: combines topics that were already practiced.
        let mixTitles = ["Add & take", "+ Tables", "+ Fractions", "+ Percentages", "Everything"]
        result[.mix] = mixTitles.enumerated().map { i, t in
            LevelConfig(category: .mix, index: i + 1, cardNumber: "\(i + 1)", title: t)
        }
        // Supermix: everything, harder.
        result[.supermix] = (1...3).map {
            LevelConfig(category: .supermix, index: $0, cardNumber: "\($0)", title: "Supermix \($0)",
                        isAdvanced: $0 == 3)
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

    private static func key(_ levelID: String, _ mode: LifeMode) -> String {
        "best.\(levelID).\(mode.rawValue)"
    }

    static func bestScore(levelID: String, mode: LifeMode) -> Int {
        UserDefaults.standard.integer(forKey: key(levelID, mode))
    }

    /// Best across all life modes — used for unlocking, so switching
    /// life mode never re-locks levels.
    static func bestAnyMode(levelID: String) -> Int {
        LifeMode.allCases.map { bestScore(levelID: levelID, mode: $0) }.max() ?? 0
    }

    /// Returns true when this run set a new best for the mode.
    @discardableResult
    static func recordScore(_ score: Int, levelID: String, mode: LifeMode) -> Bool {
        guard score > bestScore(levelID: levelID, mode: mode) else { return false }
        UserDefaults.standard.set(score, forKey: key(levelID, mode))
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
        if !wrongBag.isEmpty, step > 2, Double.random(in: 0...1) < 0.2 {
            return wrongBag.removeFirst()
        }
        var question = generate()
        if question.prompt == lastPrompt {
            question = generate() // avoid the exact same question twice in a row
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
            orderCycle = c
            orderCache = c == 0 ? values : values.shuffled()
        }
        return orderCache[step % values.count]
    }

    // MARK: Generation dispatch

    private func generate() -> Question {
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

    // MARK: Addition

    /// One pattern per level: only repeated adding of the same number.
    private func additionQuestion() -> Question {
        let n = level.index
        let maxTerms = n <= 3 ? 5 : (n <= 6 ? 4 : 3)
        let terms = cycled(Array(2...maxTerms))
        let answer = n * terms
        let prompt = Array(repeating: "\(n)", count: terms).joined(separator: " + ") + " = ?"
        return makeQuestion(prompt, "\(answer)",
                            [n * (terms + 1), n * max(1, terms - 1), answer + 1, answer - 1,
                             answer + n, answer - n, answer + 2].map(String.init))
    }

    private func additionMixQuestion(maxResult: Int? = nil, harder: Bool = false) -> Question {
        let bases = [10, 15, 20, 30, 50, 100]
        var m = maxResult ?? bases[min(level.index - 1, bases.count - 1)]
        if harder { m = min(200, m * 2) }
        let threeTerms = m >= 15 && Double.random(in: 0...1) < 0.3
        if threeTerms {
            let a = Int.random(in: 1...(m - 2))
            let b = Int.random(in: 1...max(1, m - a - 1))
            let c = Int.random(in: 1...max(1, m - a - b))
            let answer = a + b + c
            return makeQuestion("\(a) + \(b) + \(c) = ?", "\(answer)",
                                [answer + 1, answer - 1, answer + 2, answer - 2,
                                 answer + 10, a + b, answer + 3].map(String.init))
        }
        let a = Int.random(in: 1...(m - 1))
        let b = Int.random(in: 1...(m - a))
        let answer = a + b
        return makeQuestion("\(a) + \(b) = ?", "\(answer)",
                            [answer + 1, answer - 1, answer + 2, answer - 2,
                             answer + 10, abs(a - b), answer + 3].map(String.init))
    }

    // MARK: Subtraction

    /// One pattern per level: repeatedly take away the same number.
    /// Never negative; every intermediate result stays valid.
    private func subtractionQuestion() -> Question {
        let n = level.index
        let series = Array(1...8) // the answers, in a calm build-up
        let value = cycled(series)
        let doubleStep = cycleCount(seriesLength: series.count) >= 2 && n <= 5
            && Double.random(in: 0...1) < 0.3
        if doubleStep {
            let a = value + 2 * n // both intermediates stay ≥ 0
            return makeQuestion("\(a) − \(n) − \(n) = ?", "\(value)",
                                [value + n, value - 1, value + 1, value + 2 * n,
                                 a - n, value + 2].map(String.init))
        }
        let a = value + n
        return makeQuestion("\(a) − \(n) = ?", "\(value)",
                            [value + 1, value - 1, value + n, a + n,
                             value + 2, a].map(String.init))
    }

    private func subtractionMixQuestion(maxStart: Int? = nil, allowNegative: Bool? = nil) -> Question {
        let bases = [10, 15, 20, 30, 50, 100, 20]
        let m = maxStart ?? bases[min(level.index - 1, bases.count - 1)]
        let negative = allowNegative ?? (level.category == .subtractionMix && level.index == 7)

        if negative {
            // Explicit advanced level: small numbers, results may dip below zero.
            let a = Int.random(in: 0...10)
            let b = Int.random(in: 1...15)
            let answer = a - b
            return makeQuestion("\(a) − \(b) = ?", "\(answer)",
                                [answer + 1, answer - 1, b - a, answer + 2,
                                 answer - 2, a + b].map(String.init))
        }
        let a = Int.random(in: max(5, m / 2)...m)
        let twoSteps = m >= 15 && Double.random(in: 0...1) < 0.35
        if twoSteps, a >= 4 {
            let b = Int.random(in: 1...(a - 2))
            let c = Int.random(in: 1...(a - b))
            let answer = a - b - c
            return makeQuestion("\(a) − \(b) − \(c) = ?", "\(answer)",
                                [answer + 1, answer - 1, a - b, answer + 2,
                                 answer + c, answer + 10].map(String.init))
        }
        let b = Int.random(in: 1...(a - 1))
        let answer = a - b
        return makeQuestion("\(a) − \(b) = ?", "\(answer)",
                            [answer + 1, answer - 1, answer + 2, answer - 2,
                             a + b, answer + 10].map(String.init))
    }

    // MARK: Tables

    /// Questions continue in order: t×1, t×2 … t×12, then repeat (shuffled).
    private func tableQuestion(table: Int) -> Question {
        let m = cycled(Array(1...12))
        let answer = table * m
        return makeQuestion("\(table) × \(m) = ?", "\(answer)",
                            [table * (m + 1), table * max(1, m - 1), answer + table,
                             answer - table, answer + 1, answer - 1,
                             answer + 10].map(String.init))
    }

    private func tablesMixQuestion(pool: [Int]? = nil) -> Question {
        let pools: [[Int]] = [[1, 2], [1, 2, 3], Array(1...5), Array(1...8), Array(1...10), Array(1...12)]
        let tables = pool ?? pools[min(level.index - 1, pools.count - 1)]
        let current = tables.max()!
        // Weighted: the newest table most often, earlier tables regularly.
        let table = Double.random(in: 0...1) < 0.5 ? current : tables.randomElement()!
        let m = Int.random(in: 1...12)
        let answer = table * m
        return makeQuestion("\(table) × \(m) = ?", "\(answer)",
                            [table * (m + 1), table * max(1, m - 1), answer + table,
                             answer - table, answer + 1, answer - 1].map(String.init))
    }

    // MARK: Fractions

    private static let fractionDenominators = [2, 3, 4, 5, 6, 8, 10]

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
        return makeQuestion("\(num)/\(d) of \(whole) = ?", "\(answer)",
                            [whole, unit, unit * min(d, num + 1), max(0, answer - unit),
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

    private static let percentageLevels = [50, 25, 10, 20, 75]
    /// whole = base × factor keeps every answer a whole number.
    private static let percentageBase: [Int: Int] = [50: 2, 25: 4, 10: 10, 20: 5, 75: 4, 100: 1]
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
        return makeQuestion("\(p)% of \(whole) = ?", "\(answer)",
                            [whole, whole - answer, answer + 1, answer - 1,
                             answer * 2, max(0, answer / 2)].map(String.init))
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

    /// 60% newest skill, 25% earlier repetition, 15% a slightly harder question.
    private func mixQuestion() -> Question {
        // Topics in unlock order; each level adds the next one.
        let topicsPerLevel: [[String]] = [
            ["addition", "subtraction"],
            ["addition", "subtraction", "tables"],
            ["addition", "subtraction", "tables", "fractions"],
            ["addition", "subtraction", "tables", "fractions", "percentages"],
            ["addition", "subtraction", "tables", "fractions", "percentages"]
        ]
        let topics = topicsPerLevel[min(level.index - 1, topicsPerLevel.count - 1)]
        let harderRanges = level.index >= 5

        let roll = Double.random(in: 0...1)
        let topic: String
        var harder = false
        if roll < 0.60 {
            topic = topics.last!
        } else if roll < 0.85 {
            topic = topics.dropLast().randomElement() ?? topics.last!
        } else {
            topic = topics.last!
            harder = true
        }

        switch topic {
        case "addition":
            return additionMixQuestion(maxResult: harderRanges ? 50 : 20, harder: harder)
        case "subtraction":
            return subtractionMixQuestion(maxStart: harderRanges ? 50 : 20, allowNegative: false)
        case "tables":
            return tablesMixQuestion(pool: harderRanges ? Array(1...10) : Array(1...5))
        case "fractions":
            return fractionsQuestion(denominator: (harderRanges ? [2, 3, 4, 5, 6] : [2, 3, 4]).randomElement()!)
        default:
            return percentagesQuestion(percentage: (harderRanges ? [50, 25, 10, 20, 75] : [50, 25, 10]).randomElement()!)
        }
    }

    /// Everything that has been unlocked, faster and harder — but always
    /// solvable with previously introduced skills.
    private func supermixQuestion() -> Question {
        let idx = level.index
        // Occasional two-step bonus question with explicit brackets.
        if Double.random(in: 0...1) < 0.2 {
            let a = Int.random(in: 2...(3 + idx * 2))
            let b = Int.random(in: 2...(3 + idx))
            let c = Int.random(in: 1...10)
            let answer = a * b + c
            return makeQuestion("(\(a) × \(b)) + \(c) = ?", "\(answer)",
                                [a * b, a * (b + c), answer + 1, answer - 1,
                                 a * b - c, answer + 10].map(String.init))
        }
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
    private func makeQuestion(_ prompt: String, _ correct: String, _ raw: [String]) -> Question {
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
        return Question(prompt: prompt, correctAnswer: correct, distractors: list.shuffled())
    }
}
