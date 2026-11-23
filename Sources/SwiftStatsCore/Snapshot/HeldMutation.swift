//
//  HeldMutation.swift
//  SwiftStatsCore
//
//  The mutation results a stored snapshot holds, as a rescan that didn't
//  run the SwiftMutator collector needs them to decide whether to carry
//  them (M6, design §6.4): where the snapshot stood in git, its swiftmutator
//  run, the results read back from its rows (never the report blob), the
//  warnings describing them, and the span each of its production records
//  covered.
//

/// A stored snapshot's mutation results and what carrying them is checked
/// against.
struct HeldMutation {
    /// Where a stored production record was.
    typealias Span = HeldCoverage.Span

    /// Where the snapshot stood in git.
    let git: GitState
    /// Its swiftmutator run: identity, version, options and duration as the
    /// run that collected the results recorded them.
    let run: CollectorRunInfo
    /// The results, which say when they were collected.
    let results: StoredMutation
    /// The warnings describing the results, which
    /// `MutationSession.describesResults` accepts, from the stored report,
    /// in its order.
    let warnings: [ScanWarning]
    /// The span of each of the snapshot's production records, by key.
    let spans: [String: Span]
}
