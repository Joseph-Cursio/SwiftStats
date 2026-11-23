//
//  MutationFigures.swift
//  SwiftStatsCore
//
//  What a set of counted mutants comes to (M6, design "Verdicts", §4): a
//  record's, an attachment's, a copy's or every mutant's. The mutation
//  score is SwiftMutator's: killed out of every mutant but build errors
//  and not-covered entries, timeouts and mutants whose block never ran
//  counting as survivors. The function score, the signals' figure, also
//  counts the not-covered entries (code no test ran, of which SwiftMutator
//  makes no mutant) as unkilled, so a function no test ran reads low, not
//  missing. Suspect-only kills stay kills in both; they are a signal's
//  separate arm. Both multiply before dividing.
//

/// The scores and tallies of counted mutants.
public struct MutationFigures: Hashable, Sendable {
    /// SwiftMutator's mutation score: killed of killed, survived, no
    /// coverage and timed out.
    public let score: MutationScore
    /// The function score: killed of the mutation score's mutants and the
    /// not-covered ones. Its denominator is the scored mutants the
    /// signals' minimum counts.
    public let functionScore: MutationScore
    /// Mutants not killed: survived, no coverage, timed out and not
    /// covered.
    public let unkilled: Int
    /// Mutants that ran but no test checked: survived and timed out.
    public let runButUnchecked: Int
    /// Mutants whose code never ran: no coverage and not covered.
    public let unrun: Int
    /// Kills by a failing test, crash kills left out: the kills whose
    /// suspect flag can be judged.
    public let failedKills: Int

    /// The figures of `counts`.
    public init(_ counts: MutationCounts) {
        let tested = counts.killed + counts.survived + counts.noCoverage + counts.timedOut
        score = MutationScore(killed: counts.killed, scored: tested)
        functionScore = MutationScore(killed: counts.killed, scored: tested + counts.notCovered)
        runButUnchecked = counts.survived + counts.timedOut
        unrun = counts.noCoverage + counts.notCovered
        unkilled = runButUnchecked + unrun
        failedKills = counts.killed - counts.crashKills
    }
}
