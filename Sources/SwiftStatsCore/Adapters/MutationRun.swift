//
//  MutationRun.swift
//  SwiftStatsCore
//
//  What the SwiftMutator collector's run gave the scan before its mutants
//  are mapped to records (M6, design §1).
//

import Foundation

/// The SwiftMutator collector's run.
struct MutationRun: Sendable {
    /// How the run went.
    let status: CollectorStatus
    /// The `swift-mutator` SwiftStats ran; nil when the collector was
    /// skipped.
    let executable: URL?
    /// `sha256:` and the SHA-256 of the SwiftMutator build its results
    /// file's header names; nil when no header was read.
    let identity: String?
    /// Wall-clock milliseconds, from the copy to reading the results.
    let milliseconds: Int
    /// The results, when the run ran and left a results file.
    let results: MutationResults?
    /// What `swift-mutator report` judged of them; every kill unjudged
    /// when it wasn't run or failed.
    let suspects: SuspectReport
    /// The package's git state the run's copy checked out; nil when the
    /// collector was skipped.
    let git: GitState?
    /// Where the results file was kept, relative to the package root
    /// (`.swiftstats/mutation/runs/<id>/results.jsonl`); nil without
    /// results.
    let resultsFile: String?
    /// How long the warm build took; nil when it didn't run.
    let warmBuildMilliseconds: Int?
    /// How long SwiftMutator's run took; nil when it didn't run.
    let mutatorMilliseconds: Int?
    /// Problems worth reporting that didn't fail it.
    let warnings: [ScanWarning]

    /// The run as the other external collectors' runs are recorded.
    var timed: TimedAdapterResult {
        TimedAdapterResult(
            result: AdapterResult(status: status, findings: [], warnings: warnings),
            executable: executable,
            identity: identity,
            milliseconds: milliseconds
        )
    }

    /// A run that didn't happen, for `reason`.
    static func skipped(_ reason: String) -> Self {
        Self(
            status: AdapterResult.skipped(MutationAdapter.name, reason: reason).status,
            executable: nil,
            identity: nil,
            milliseconds: 0,
            results: nil,
            suspects: .unjudged,
            git: nil,
            resultsFile: nil,
            warmBuildMilliseconds: nil,
            mutatorMilliseconds: nil,
            warnings: []
        )
    }
}
