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
        let mode = level.mode

        // Shared bullets used by more than one mode.
        let practiceOrder = L("modeIntro.practiceOrder")
        let multiplyBy = L("modeIntro.tables.multiplyBy")
        // Random-mode second bullet: swappable subjects vs the fixed-order minus.
        let eitherSide = L("modeIntro.random.eitherSide")
        let fixedOrder = L("modeIntro.random.fixedOrder")

        switch level.category {
        case .addition:
            let bullets: [String]
            switch mode {
            case .order:  bullets = [L("modeIntro.addition.std.b1 \(n)"), practiceOrder]
            case .random: bullets = [L("modeIntro.addition.random.b1 \(n)"), eitherSide]
            case .mixed:  bullets = [L("modeIntro.addition.varied.b1 \(n)"),
                                     L("modeIntro.addition.varied.b2")]
            }
            return (L("modeIntro.addition.title \(n)"), bullets)

        case .additionMix:
            let m = additionMixMax(n)
            return (L("modeIntro.additionMix.title \(m)"),
                    [L("modeIntro.additionMix.b1"),
                     L("modeIntro.additionMix.b2 \(m)")])

        case .subtraction:
            let bullets: [String]
            switch mode {
            case .order:  bullets = [L("modeIntro.subtraction.std.b1 \(n)"), practiceOrder]
            case .random: bullets = [L("modeIntro.subtraction.random.b1 \(n)"), fixedOrder]
            case .mixed:  bullets = [L("modeIntro.subtraction.varied.b1 \(n)"),
                                     L("modeIntro.subtraction.varied.b2")]
            }
            return (L("modeIntro.subtraction.title \(n)"), bullets)

        case .subtractionMix:
            let twoNumbers = L("modeIntro.subtractionMix.twoNumbers")
            if n == 7 {
                return (L("modeIntro.subtractionMix.belowZero.title"),
                        [twoNumbers, L("modeIntro.subtractionMix.belowZero.b2")])
            }
            let m = subtractionMixMax(n)
            return (L("modeIntro.subtractionMix.title \(m)"),
                    [twoNumbers, L("modeIntro.subtractionMix.b2 \(m)")])

        case .tables:
            let bullets: [String]
            switch mode {
            case .order:  bullets = [L("modeIntro.tables.std.b1 \(n) \(n) \(n)"),
                                     L("modeIntro.tables.std.b2")]
            case .random: bullets = [L("modeIntro.tables.random.b1 \(min(99, n))"), eitherSide]
            case .mixed:  bullets = [L("modeIntro.tables.varied.b1 \(min(99, n))"), multiplyBy]
            }
            return (L("modeIntro.tables.title \(n)"), bullets)

        case .tablesMix:
            let (lo, hi) = tablesMixRange(n)
            return (L("modeIntro.tablesMix.title \(lo) \(hi)"),
                    [L("modeIntro.tablesMix.b1 \(lo) \(hi)"), multiplyBy])

        case .fractions:
            // One denominator per level for all 99 levels — the start screen
            // always names the exact denominator the player will practise.
            let d = fractionDenominator(n)
            let bullets: [String]
            switch mode {
            case .order:  bullets = [L("modeIntro.fractions.std.b1 \(d)"),
                                     L("modeIntro.fractions.std.b2 \(d)")]
            case .random: bullets = [L("modeIntro.fractions.random.b1 \(d)"),
                                     L("modeIntro.fractions.random.b2")]
            case .mixed:  bullets = [L("modeIntro.fractions.varied.b1"),
                                     L("modeIntro.fractions.varied.b2 \(d)")]
            }
            return (L("modeIntro.fractions.title \(d)"), bullets)

        case .fractionsMix:
            return (L("modeIntro.fractionsMix.title"),
                    [L("modeIntro.fractionsMix.b1"),
                     L("modeIntro.fractionsMix.b2")])

        case .percentages:
            // One percentage per level for all 99 levels.
            let p = percentageValue(n)
            // The percent sign travels inside the argument, so no catalog value
            // ever contains a bare "%".
            let pText = "\(p)%"
            let bullets: [String]
            switch mode {
            case .order:  bullets = [L("modeIntro.percentages.std.b1 \(pText)"),
                                     L("modeIntro.percentages.std.b2")]
            case .random: bullets = [L("modeIntro.percentages.random.b1"),
                                     L("modeIntro.percentages.random.b2")]
            case .mixed:  bullets = [L("modeIntro.percentages.varied.b1"),
                                     L("modeIntro.percentages.varied.b2")]
            }
            return (L("modeIntro.percentages.title \(pText)"), bullets)

        case .percentagesMix:
            return (L("modeIntro.percentagesMix.title"),
                    [L("modeIntro.percentagesMix.b1"),
                     L("modeIntro.percentagesMix.b2")])

        case .superBasic:
            return (L("modeIntro.superBasic.title \(n)"),
                    [L("modeIntro.superBasic.b1"),
                     L("modeIntro.super.b2 \(n)")])

        case .superTimes:
            return (L("modeIntro.superTimes.title \(n)"),
                    [L("modeIntro.superTimes.b1"),
                     L("modeIntro.super.b2 \(n)")])

        case .superFraction:
            return (L("modeIntro.superFraction.title \(n)"),
                    [L("modeIntro.superFraction.b1"),
                     L("modeIntro.super.b2 \(n)")])

        case .superAll:
            return (L("modeIntro.superAll.title \(n)"),
                    [L("modeIntro.superAll.b1"),
                     L("modeIntro.super.b2 \(n)")])
        }
    }

    // MARK: - Values read straight from ChallengeScaling (single source of truth)

    private static func additionMixMax(_ index: Int) -> Int {
        ChallengeScaling.additionMixCeiling(index)
    }

    private static func subtractionMixMax(_ index: Int) -> Int {
        ChallengeScaling.subtractionMixCeiling(index)
    }

    private static func tablesMixRange(_ index: Int) -> (Int, Int) {
        let pool = ChallengeScaling.tablesMixPool(index)
        return (pool.min()!, pool.max()!)
    }

    private static func fractionDenominator(_ index: Int) -> Int {
        let d = ChallengeScaling.fractionDenominators
        return d[min(index - 1, d.count - 1)]
    }

    private static func percentageValue(_ index: Int) -> Int {
        let p = ChallengeScaling.percentageLevels
        return p[min(index - 1, p.count - 1)]
    }
}
