//
//  AdapterResult.swift
//  SwiftStatsCore
//
//  What one external tool's run gave the scan.
//

/// One adapter's status, findings and warnings.
struct AdapterResult {
    /// How the run went.
    let status: CollectorStatus
    /// Its findings, places not yet attached.
    let findings: [RawFinding]
    /// Problems worth reporting that didn't stop it.
    let warnings: [ScanWarning]

    /// A run that didn't happen, for `reason`.
    static func skipped(_ name: String, reason: String) -> Self {
        Self(
            status: CollectorStatus(name: name, state: .skipped, version: nil, reason: reason, options: []),
            findings: [],
            warnings: []
        )
    }

    /// A run that failed with `error`, after being started with `options`.
    static func failed(_ name: String, error: any Error, options: [String]) -> Self {
        Self(
            status: CollectorStatus(name: name, state: .failed, version: nil, reason: "\(error)", options: options),
            findings: [],
            warnings: []
        )
    }
}
