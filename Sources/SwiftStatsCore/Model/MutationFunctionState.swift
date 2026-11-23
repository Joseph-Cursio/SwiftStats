//
//  MutationFunctionState.swift
//  SwiftStatsCore
//
//  What a production function's mutation results come to (M6, design §4),
//  for the roll-ups, the signals' pools and their funnels: the first that
//  applies of no results (its file is unresolved after a merge), not
//  listed (its file changed but SwiftMutator tested nothing in it, so its
//  code no test ran isn't listed), scored (a mutant killed, survived, with
//  no coverage or timed out), only not-covered mutants, only build
//  errors, or no mutant at all (nothing to mutate, mutants only in inactive
//  `#if` branches, a target no test builds). When the results don't list
//  code no test ran, such functions read as having no mutant.
//

/// A production function's mutation state.
public enum MutationFunctionState: String, CaseIterable, Sendable {
    /// Only build errors.
    case buildErrorsOnly
    /// No mutant at all.
    case noMutant
    /// Its file is unresolved, so it has no results.
    case noResults
    /// Only not-covered mutants: code no test ran.
    case notCoveredOnly
    /// Its file changed, but SwiftMutator tested no mutant in it, so its
    /// code no test ran isn't listed.
    case notListed
    /// At least one mutant killed, survived, with no coverage or timed out.
    case scored

    /// The state of a function whose mutants are counted by `counts` (nil
    /// when it has none) in a file whose results are `disposition` (nil
    /// when the results don't name the file).
    public init(counts: MutationCounts?, disposition: MutationFileDisposition?) {
        if disposition == .unresolved {
            self = .noResults
        } else if disposition == .unlisted {
            self = .notListed
        } else if let counts, MutationFigures(counts).score.scored > 0 {
            self = .scored
        } else if let counts, counts.notCovered > 0 {
            self = .notCoveredOnly
        } else if let counts, counts.buildErrors > 0 {
            self = .buildErrorsOnly
        } else {
            self = .noMutant
        }
    }
}
