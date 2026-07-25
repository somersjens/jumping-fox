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

        // Shared across the two Tables mix cards.
        let multiplyBy = L("modeIntro.tables.multiplyBy")

        // Each of the five core skills shows the same intro line for all three
        // modes (what you practise) plus one mode-specific detail line (how the
        // order/variation works).
        switch level.category {
        case .addition:
            let detail: String
            switch mode {
            case .order:  detail = L("modeIntro.addition.order \(n)")
            case .random: detail = L("modeIntro.addition.random \(n)")
            case .mixed:  detail = L("modeIntro.addition.mixed \(n)")
            }
            return (L("modeIntro.addition.title \(n)"),
                    [L("modeIntro.addition.intro"), detail])

        case .additionMix:
            let m = additionMixMax(n)
            return (L("modeIntro.additionMix.title \(m)"),
                    [L("modeIntro.additionMix.b1"),
                     L("modeIntro.additionMix.b2 \(m)")])

        case .subtraction:
            let detail: String
            switch mode {
            case .order:  detail = L("modeIntro.subtraction.order \(n)")
            case .random: detail = L("modeIntro.subtraction.random \(n)")
            case .mixed:  detail = L("modeIntro.subtraction.mixed \(n)")
            }
            return (L("modeIntro.subtraction.title \(n)"),
                    [L("modeIntro.subtraction.intro"), detail])

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
            let detail: String
            switch mode {
            case .order:  detail = L("modeIntro.tables.order \(n)")
            case .random: detail = L("modeIntro.tables.random \(min(99, n))")
            case .mixed:  detail = L("modeIntro.tables.mixed \(min(99, n))")
            }
            return (L("modeIntro.tables.title \(n)"),
                    [L("modeIntro.tables.intro"), detail])

        case .tablesMix:
            let (lo, hi) = tablesMixRange(n)
            return (L("modeIntro.tablesMix.title \(lo) \(hi)"),
                    [L("modeIntro.tablesMix.b1 \(lo) \(hi)"), multiplyBy])

        case .fractions:
            // One denominator per level for all 99 levels; the start screen
            // always names the exact denominator the player will practise.
            let d = fractionDenominator(n)
            let detail: String
            switch mode {
            case .order:  detail = L("modeIntro.fractions.order \(d)")
            case .random: detail = L("modeIntro.fractions.random \(d)")
            case .mixed:  detail = L("modeIntro.fractions.mixed")
            }
            return (L("modeIntro.fractions.title \(d)"),
                    [L("modeIntro.fractions.intro"), detail])

        case .fractionsMix:
            return (L("modeIntro.fractionsMix.title"),
                    [L("modeIntro.fractionsMix.b1"),
                     L("modeIntro.fractionsMix.b2")])

        case .percentages:
            // One percentage per level for all 99 levels. The percent sign
            // travels inside the argument, so no catalog value contains a bare "%".
            let pText = "\(percentageValue(n))%"
            let detail: String
            switch mode {
            case .order:  detail = L("modeIntro.percentages.order \(pText)")
            case .random: detail = L("modeIntro.percentages.random \(pText)")
            case .mixed:  detail = L("modeIntro.percentages.mixed")
            }
            return (L("modeIntro.percentages.title \(pText)"),
                    [L("modeIntro.percentages.intro"), detail])

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
