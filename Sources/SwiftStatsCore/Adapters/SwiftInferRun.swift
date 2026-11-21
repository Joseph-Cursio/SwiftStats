//
//  SwiftInferRun.swift
//  SwiftStatsCore
//
//  What the SwiftInferProperties collector's run gave the scan before its
//  suggestions are attached to records (PRD §7.11).
//

import Foundation

/// The SwiftInferProperties collector's run.
struct SwiftInferRun: Sendable {
    /// How the run went.
    let status: CollectorStatus
    /// The tool that ran; nil when it was skipped.
    let executable: URL?
    /// Wall-clock milliseconds, from the copy to the merge, while the
    /// scan's other steps ran.
    let milliseconds: Int
    /// The merged rows; nil unless the run succeeded.
    let merged: MergedCandidates?
    /// The SwiftEffectInference revision the binary's build directory names.
    let seiRevision: String?

    /// The run as the other external collectors' runs are recorded.
    var timed: TimedAdapterResult {
        TimedAdapterResult(
            result: AdapterResult(status: status, findings: [], warnings: []),
            executable: executable,
            identity: nil,
            milliseconds: milliseconds
        )
    }

    /// A run that didn't happen, for `reason`.
    static func skipped(_ reason: String) -> Self {
        Self(
            status: AdapterResult.skipped(SwiftInferPropertiesAdapter.name, reason: reason).status,
            executable: nil,
            milliseconds: 0,
            merged: nil,
            seiRevision: nil
        )
    }
}
