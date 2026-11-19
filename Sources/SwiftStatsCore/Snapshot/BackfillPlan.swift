//
//  BackfillPlan.swift
//  SwiftStatsCore
//
//  What a backfill does: which commits, from when, how many, and whether it
//  rescans and runs the external tools.
//

/// What a backfill does.
public struct BackfillPlan: Sendable {
    /// Which commits.
    public let selection: BackfillSelection
    /// Only commits from this time on (seconds since 1970).
    public let since: Int?
    /// At most this many picks, the newest.
    public let maximumCommits: Int?
    /// Rescan picks whose snapshot came from another SwiftStats build.
    public let rerun: Bool
    /// Run the external tool adapters too.
    public let withTools: Bool

    /// A plan. Fields are documented on their properties.
    public init(selection: BackfillSelection, since: Int?, maximumCommits: Int?, rerun: Bool, withTools: Bool) {
        self.selection = selection
        self.since = since
        self.maximumCommits = maximumCommits
        self.rerun = rerun
        self.withTools = withTools
    }
}
