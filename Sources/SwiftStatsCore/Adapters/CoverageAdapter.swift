//
//  CoverageAdapter.swift
//  SwiftStatsCore
//
//  The coverage collector (M5, PRD §7.8). It runs only when asked for with
//  `scan --coverage`, never in `backfill` or in `diff`'s exports, since it
//  builds and runs the package's tests: minutes on a real package. It uses
//  the toolchain of the `swift` it resolves (`collectors.coverage.path`,
//  else PATH), and `collectors.coverage.arguments` may add `--skip <regex>`
//  pairs to `swift test`.
//

/// The coverage collector's name, statuses and identity.
enum CoverageAdapter {
    /// The collector's name in a snapshot.
    static let name = "coverage"
    /// Why a scan that didn't ask for coverage skipped it.
    static let notRequestedReason = "not requested; scan --coverage runs it"
    /// Why a requested run is skipped until the run itself is built (M5's
    /// second step replaces this with the run).
    static let notBuiltReason = "the coverage run is not built yet"

    /// The build identity of a run whose `swift` prints `versionLine`
    /// first for `--version`: the toolchain is the tool, as for the
    /// dependency graph.
    static func identity(versionLine: String) -> String {
        "swift:\(versionLine)"
    }
}
