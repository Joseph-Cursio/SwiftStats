//
//  MutationRun.swift
//  SwiftStatsCore
//
//  What the SwiftMutator collector's run gave the scan before its mutants
//  are mapped to records (M6, design §1): for a `--since` run, also the
//  base it merges with and what its copy changed (design §6.1), and the
//  parts of its reason a merge adds its own notes among.
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
    /// The stored snapshot a `--since` run merges with; nil for a full run.
    let base: MutationBase?
    /// What a `--since` run's copy changed since the base; nil otherwise.
    let changes: MutationChanges?
    /// The exit's own note, which a reason starts with; nil when it has
    /// none.
    let exitReason: String?
    /// How many files the copy took from the work tree because git
    /// checked them out with other bytes.
    let fixedFiles: Int
    /// When the collector's step started (ISO 8601, UTC): the results'
    /// date when the run left no results file to take one from.
    let startedAt: String

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
            warnings: [],
            base: nil,
            changes: nil,
            exitReason: nil,
            fixedFiles: 0,
            startedAt: ""
        )
    }

    /// The run with its status's reason made of `notes` (none when empty).
    func with(reasonNotes notes: [String]) -> Self {
        Self(
            status: CollectorStatus(
                name: status.name,
                state: status.state,
                version: status.version,
                reason: notes.isEmpty ? nil : notes.joined(separator: "; "),
                options: status.options
            ),
            executable: executable,
            identity: identity,
            milliseconds: milliseconds,
            results: results,
            suspects: suspects,
            git: git,
            resultsFile: resultsFile,
            warmBuildMilliseconds: warmBuildMilliseconds,
            mutatorMilliseconds: mutatorMilliseconds,
            warnings: warnings,
            base: base,
            changes: changes,
            exitReason: exitReason,
            fixedFiles: fixedFiles,
            startedAt: startedAt
        )
    }
}
