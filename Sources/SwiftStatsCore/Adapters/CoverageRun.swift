//
//  CoverageRun.swift
//  SwiftStatsCore
//
//  What the coverage collector's run gave the scan before its profiles are
//  mapped to records (M5).
//

import Foundation

/// The coverage collector's run.
struct CoverageRun: Sendable {
    /// How the run went.
    let status: CollectorStatus
    /// The toolchain's `swift` that ran the build and the tests (the
    /// resolved `swift` when the run failed before finding it); nil when
    /// the collector was skipped.
    let executable: URL?
    /// `swift:<first --version line of that swift>`, the build identity
    /// `diff` compares; nil when the collector was skipped.
    let identity: String?
    /// Wall-clock milliseconds, from the build to the last export.
    let milliseconds: Int
    /// The run's data, to map to records; nil unless it ran.
    let profiles: CoverageProfiles?

    /// The run as the other external collectors' runs are recorded.
    var timed: TimedAdapterResult {
        TimedAdapterResult(
            result: AdapterResult(status: status, findings: [], warnings: []),
            executable: executable,
            identity: identity,
            milliseconds: milliseconds
        )
    }

    /// A run that didn't happen, for `reason`.
    static func skipped(_ reason: String) -> Self {
        Self(
            status: AdapterResult.skipped(CoverageAdapter.name, reason: reason).status,
            executable: nil,
            identity: nil,
            milliseconds: 0,
            profiles: nil
        )
    }
}
