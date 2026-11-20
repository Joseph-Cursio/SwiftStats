//
//  CloneRun.swift
//  SwiftStatsCore
//
//  What the SwiftCloneDetector collector's run gave the scan before its
//  classes are merged and attached to records (PRD §7.12).
//

import Foundation

/// The SwiftCloneDetector collector's run.
struct CloneRun: Sendable {
    /// How the run went.
    let status: CollectorStatus
    /// The tool resolved, even when there were no files to give it; nil
    /// when it was skipped.
    let executable: URL?
    /// Wall-clock milliseconds for the four runs, side by side.
    let milliseconds: Int
    /// `sha256:<hex>` of the files given to the tool.
    let fileListHash: String
    /// Each run's report; empty when there were no files, or the collector
    /// didn't run.
    let outputs: [CloneDetectorPass: CloneDetectorOutput]

    /// The run as the other external collectors' runs are recorded.
    var timed: TimedAdapterResult {
        TimedAdapterResult(
            result: AdapterResult(status: status, findings: [], warnings: []),
            executable: executable,
            milliseconds: milliseconds
        )
    }

    /// A run that didn't happen, for `reason`.
    static func skipped(_ reason: String) -> Self {
        Self(
            status: AdapterResult.skipped(SwiftCloneDetectorAdapter.name, reason: reason).status,
            executable: nil,
            milliseconds: 0,
            fileListHash: "",
            outputs: [:]
        )
    }
}
