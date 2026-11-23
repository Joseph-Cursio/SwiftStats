//
//  MutationStop.swift
//  SwiftStatsCore
//
//  A results file holding only a `stopped` line (M6, design §2 item 3):
//  SwiftMutator stopped before its first mutant, as when the baseline
//  fails (exit 3) or a signal stops it early. It has no results and can't
//  be resumed.
//

/// Why a SwiftMutator run stopped before its first mutant.
struct MutationStop: Equatable, Sendable {
    /// The step it was in (`baseline`, `coverageRun`, …).
    let step: String
    /// Why: `failed`, `timedOut` or `interrupted`.
    let reason: String
    /// The abort's code, or the signal's name.
    let detail: String?
    /// The tests the step's log showed failing, by name; at most 20.
    let failedTests: [String]
    /// How many tests failed, uncapped; nil when the step had no log.
    let failedTestCount: Int?
}
