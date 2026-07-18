//
//  ModeIntro.swift
//  Jumping Fox
//
//  Short, child-friendly descriptions of what each game mode contains,
//  shown on the pre-game intro card. All copy is resolved from the string
//  catalog (keys under "modeIntro."), so it is localized per language with
//  no language checks here. The numeric values are mirrored from
//  QuestionEngine so the copy always matches what the player actually gets —
//  including Standard vs Mix and Premium levels.
//

import Foundation

enum ModeIntro {
    /// Title + short, scannable explanation for a level's mode.
    static func info(for level: LevelConfig) -> (title: String, bullets: [String]) {
        let n = max(1, level.index)
        let mix = level.startsInMix

        // Shared bullets used by more than one mode.
        let practiceOrder = String(localized: "modeIntro.practiceOrder")
        let multiplyBy = String(localized: "modeIntro.tables.multiplyBy")

        switch level.category {
        case .addition:
            let bullets = mix
                ? [String(localized: "modeIntro.addition.varied.b1 \(n)"),
                   String(localized: "modeIntro.addition.varied.b2")]
                : [String(localized: "modeIntro.addition.std.b1 \(n)"), practiceOrder]
            return (String(localized: "modeIntro.addition.title \(n)"), bullets)

        case .additionMix:
            let m = additionMixMax(n)
            return (String(localized: "modeIntro.additionMix.title \(m)"),
                    [String(localized: "modeIntro.additionMix.b1"),
                     String(localized: "modeIntro.additionMix.b2 \(m)")])

        case .subtraction:
            let bullets = mix
                ? [String(localized: "modeIntro.subtraction.varied.b1 \(n)"),
                   String(localized: "modeIntro.subtraction.varied.b2")]
                : [String(localized: "modeIntro.subtraction.std.b1 \(n)"), practiceOrder]
            return (String(localized: "modeIntro.subtraction.title \(n)"), bullets)

        case .subtractionMix:
            let twoNumbers = String(localized: "modeIntro.subtractionMix.twoNumbers")
            if n == 7 {
                return (String(localized: "modeIntro.subtractionMix.belowZero.title"),
                        [twoNumbers, String(localized: "modeIntro.subtractionMix.belowZero.b2")])
            }
            let m = subtractionMixMax(n)
            return (String(localized: "modeIntro.subtractionMix.title \(m)"),
                    [twoNumbers, String(localized: "modeIntro.subtractionMix.b2 \(m)")])

        case .tables:
            let bullets = mix
                ? [String(localized: "modeIntro.tables.varied.b1 \(min(12, n))"), multiplyBy]
                : [String(localized: "modeIntro.tables.std.b1 \(n) \(n) \(n)"),
                   String(localized: "modeIntro.tables.std.b2")]
            return (String(localized: "modeIntro.tables.title \(n)"), bullets)

        case .tablesMix:
            let (lo, hi) = tablesMixRange(n)
            return (String(localized: "modeIntro.tablesMix.title \(lo) \(hi)"),
                    [String(localized: "modeIntro.tablesMix.b1 \(lo) \(hi)"), multiplyBy])

        case .fractions:
            let d = fractionDenominator(n)
            let bullets = mix
                ? [String(localized: "modeIntro.fractions.varied.b1 \(d)"),
                   String(localized: "modeIntro.fractions.varied.b2")]
                : [String(localized: "modeIntro.fractions.std.b1 \(d)"),
                   String(localized: "modeIntro.fractions.std.b2 \(d)")]
            return (String(localized: "modeIntro.fractions.title \(d)"), bullets)

        case .fractionsMix:
            return (String(localized: "modeIntro.fractionsMix.title"),
                    [String(localized: "modeIntro.fractionsMix.b1"),
                     String(localized: "modeIntro.fractionsMix.b2")])

        case .percentages:
            let p = percentageValue(n)
            // The percent sign travels inside the argument, so no catalog value
            // ever contains a bare "%".
            let pText = "\(p)%"
            let bullets = mix
                ? [String(localized: "modeIntro.percentages.varied.b1"),
                   String(localized: "modeIntro.percentages.varied.b2")]
                : [String(localized: "modeIntro.percentages.std.b1 \(pText)"),
                   String(localized: "modeIntro.percentages.std.b2")]
            return (String(localized: "modeIntro.percentages.title \(pText)"), bullets)

        case .percentagesMix:
            return (String(localized: "modeIntro.percentagesMix.title"),
                    [String(localized: "modeIntro.percentagesMix.b1"),
                     String(localized: "modeIntro.percentagesMix.b2")])

        case .mix:
            let bullets = mix
                ? [String(localized: "modeIntro.mix.varied.b1"),
                   String(localized: "modeIntro.mix.b2 \(n)")]
                : [String(localized: "modeIntro.mix.std.b1"),
                   String(localized: "modeIntro.mix.b2 \(n)")]
            return (String(localized: "modeIntro.mix.title \(n)"), bullets)

        case .supermix:
            return (String(localized: "modeIntro.supermix.title \(n)"),
                    [String(localized: "modeIntro.supermix.b1"),
                     String(localized: "modeIntro.supermix.b2")])
        }
    }

    // MARK: - Values mirrored from QuestionEngine (kept in sync)

    private static func additionMixMax(_ index: Int) -> Int {
        let bases = [10, 15, 20, 30, 50, 100, 150, 200, 300, 500, 750, 1000]
        return bases[min(index - 1, bases.count - 1)]
    }

    private static func subtractionMixMax(_ index: Int) -> Int {
        let bases = [10, 15, 20, 30, 50, 100, 20, 150, 200, 300, 500, 1000]
        return bases[min(index - 1, bases.count - 1)]
    }

    private static func tablesMixRange(_ index: Int) -> (Int, Int) {
        let pools: [[Int]] = [[1, 2], [1, 2, 3], Array(1...5), Array(1...8), Array(1...10), Array(1...12),
                              Array(1...12), Array(2...12), Array(3...12), Array(4...12), Array(5...12), Array(6...12)]
        let pool = pools[min(index - 1, pools.count - 1)]
        return (pool.min()!, pool.max()!)
    }

    private static func fractionDenominator(_ index: Int) -> Int {
        let d = [2, 3, 4, 5, 6, 8, 10, 12, 15, 20, 25, 30]
        return d[min(index - 1, d.count - 1)]
    }

    private static func percentageValue(_ index: Int) -> Int {
        let p = [50, 25, 10, 100, 75, 20, 5, 30, 40, 60, 15, 12]
        return p[min(index - 1, p.count - 1)]
    }
}
