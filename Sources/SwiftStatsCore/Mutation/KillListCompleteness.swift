//
//  KillListCompleteness.swift
//  SwiftStatsCore
//
//  Whether a mutant's `killedBy` names every failing test (M6, design §2
//  item 7; SwiftMutator's `Docs/results-file.md` "When the list is
//  complete"): a tri-state, since a not-covered mutant never ran and a
//  line with no `killedBy` (a survivor, a build error, an older session
//  whose failed-test lines weren't reliable) records no list, and what
//  wasn't collected is null, not false.
//

/// Whether a mutant's `killedBy` list is whole.
enum KillListCompleteness: String, Sendable {
    /// The run exited by itself and `failedTestCount` is the list's length.
    case complete
    /// The list may leave tests out: the run was stopped (at a failure or
    /// the time limit), or `failedTestCount` is missing or larger.
    case incomplete
    /// No list was recorded.
    case notRecorded

    /// The completeness of a line's list `killedBy`, not recorded when the
    /// line has no `killedBy` (`listed` false), for a run that ended by
    /// `endedBy` with `failedTestCount`.
    init(killedBy: [String], listed: Bool, endedBy: String, failedTestCount: Int?) {
        guard listed else {
            self = .notRecorded
            return
        }
        self = endedBy == "exited" && failedTestCount == killedBy.count ? .complete : .incomplete
    }
}
