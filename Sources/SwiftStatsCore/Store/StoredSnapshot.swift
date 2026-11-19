//
//  StoredSnapshot.swift
//  SwiftStatsCore
//
//  A snapshot read back from the store's tables, as `diff` uses it.
//

/// A snapshot's metadata and its rows.
public struct StoredSnapshot: Hashable, Sendable {
    /// The row id.
    public let id: Int64
    /// The metadata and collector runs.
    public let info: SnapshotInfo
    /// Its function records.
    public let functions: [FunctionRow]
    /// Its finding locations.
    public let findings: [FindingRow]
    /// Its roll-up numbers.
    public let rollups: [RollupMetricRow]
}
