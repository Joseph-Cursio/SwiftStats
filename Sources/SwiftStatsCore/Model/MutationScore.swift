//
//  MutationScore.swift
//  SwiftStatsCore
//
//  Mutants killed out of mutants scored, with the percentage (M6, design
//  "Verdicts", §4). SwiftMutator's formula multiplies before it divides
//  (`mutationScoring.swift:18-21`), so a share that is a whole percent
//  comes out whole: 29 of 100 is 29, where 29 ÷ 100 × 100 truncates to
//  28. The percentage keeps two decimal places, as coverage's do; the
//  whole percent SwiftMutator's reports print is the truncated quotient
//  of the integers. Null when nothing was scored, or when the results are
//  incomplete above the records, never 0.
//

/// Killed of scored, with the percentage.
public struct MutationScore: Codable, Hashable, Sendable {
    /// Percentages are out of this.
    private static let wholePercent = 100
    /// Percentages keep this many hundredths: two decimal places.
    private static let hundredths = 100

    /// Mutants killed.
    public let killed: Int
    /// Mutants scored: what the score is out of.
    public let scored: Int
    /// `killed` as a percentage of `scored`, multiplied first, to two
    /// decimal places; nil when nothing was scored, or left out because
    /// the results are incomplete.
    public let percent: Double?

    /// The whole percent SwiftMutator's reports print: `killed × 100 ÷
    /// scored` in integers, truncated; nil when nothing was scored.
    public var truncatedPercent: Int? {
        scored > 0 ? killed * Self.wholePercent / scored : nil
    }

    /// The score of `killed` out of `scored`.
    init(killed: Int, scored: Int) {
        self.killed = killed
        self.scored = scored
        percent = Self.percent(killed: killed, scored: scored)
    }

    /// The score of `killed` out of `scored` with `percent` as given.
    private init(killed: Int, scored: Int, percent: Double?) {
        self.killed = killed
        self.scored = scored
        self.percent = percent
    }

    /// `killed` as a percentage of `scored`, multiplied before dividing and
    /// rounded to two decimal places; nil when `scored` is 0: a score of
    /// nothing is not 0%.
    static func percent(killed: Int, scored: Int) -> Double? {
        guard scored > 0 else {
            return nil
        }
        let hundredthsOfPercent = Double(killed * wholePercent * hundredths) / Double(scored)
        return hundredthsOfPercent.rounded() / Double(hundredths)
    }

    /// The score with its counts and no percentage: how a roll-up gives a
    /// score over incomplete results.
    func withoutPercent() -> Self {
        Self(killed: killed, scored: scored, percent: nil)
    }
}
