//
//  BuildRun.swift
//  SwiftStatsCore
//
//  What the `build` collector's run gave the scan (M7, design §1) before
//  its output is read: how it went, the toolchain's `swift` and the build
//  identity, and, when the build ran, what it left for the timings, the
//  warnings and the `index` and `periphery` collectors.
//

import Foundation

/// The `build` collector's run.
struct BuildRun: Sendable {
    /// How the run went.
    let status: CollectorStatus
    /// The toolchain's `swift` that ran the build (the resolved `swift`
    /// when the run failed before finding it); nil when the collector was
    /// skipped.
    let executable: URL?
    /// `swift:<first --version line of that swift>`, the build identity
    /// `diff` compares; nil when the toolchain wasn't found.
    let identity: String?
    /// Wall-clock milliseconds, from finding the toolchain to hashing the
    /// scanned files after the build.
    let milliseconds: Int
    /// Problems worth reporting that didn't fail it.
    let warnings: [ScanWarning]
    /// What the build left; nil unless it ran (a failed build's partial
    /// store is never read).
    let products: BuildSession.Products?

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
            status: AdapterResult.skipped(BuildAdapter.name, reason: reason).status,
            executable: nil,
            identity: nil,
            milliseconds: 0,
            warnings: [],
            products: nil
        )
    }
}
