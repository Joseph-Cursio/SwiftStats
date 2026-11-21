//
//  HeldCoverage.swift
//  SwiftStatsCore
//
//  The coverage a stored snapshot holds, as a rescan that didn't run the
//  coverage collector needs it to decide whether to carry it (M5, design
//  §6): where the snapshot stood in git, its coverage run, the coverage
//  read back from its rows (never the report blob), the warnings mapping
//  it gave, and the span each of its production records covered.
//

/// A stored snapshot's coverage and what carrying it is checked against.
struct HeldCoverage {
    /// Where a stored production record was.
    struct Span: Hashable {
        /// Its file, relative to the package root.
        let file: String
        /// Its first line.
        let startLine: Int
        /// Its last line.
        let endLine: Int
    }

    /// Where the snapshot stood in git.
    let git: GitState
    /// Its coverage run: identity, version, options and duration as the
    /// run that collected the coverage recorded them.
    let run: CollectorRunInfo
    /// The coverage and when it was collected.
    let coverage: StoredCoverage
    /// The warnings mapping the coverage gave, from the stored report, sorted.
    let warnings: [ScanWarning]
    /// The span of each of the snapshot's production records, by key.
    let spans: [String: Span]
}
