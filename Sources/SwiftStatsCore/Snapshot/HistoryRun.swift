//
//  HistoryRun.swift
//  SwiftStatsCore
//
//  The history collector's run, as its snapshot entry records it.
//

/// The history collector's run, as its snapshot entry records it.
struct HistoryRun {
    /// The git that read the history.
    let gitVersion: String?
    /// How long it took.
    let milliseconds: Int

    /// The snapshot's record of the run whose status is `status`. Its
    /// identity is git's version, compared only when SwiftStats' own build
    /// is, like the dependency graph's (PRD §6.2).
    func info(_ status: CollectorStatus) -> CollectorRunInfo {
        CollectorRunInfo(
            name: status.name,
            state: status.state,
            reason: status.reason,
            version: status.version,
            identity: status.state == .ran ? gitVersion.map { "git:\($0)" } : nil,
            identityLabel: nil,
            options: status.options,
            durationMilliseconds: milliseconds
        )
    }
}
