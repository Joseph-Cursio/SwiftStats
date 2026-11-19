//
//  RollupMetricRow.swift
//  SwiftStatsCore
//
//  The `rollupMetric` table (PRD §9): one row per number in each roll-up.
//

import GRDB

/// One number in one roll-up of a snapshot.
public struct RollupMetricRow: Codable, Hashable, Sendable, FetchableRecord, PersistableRecord {
    /// The table name.
    public static let databaseTableName = "rollupMetric"

    /// The snapshot.
    var snapshotId: Int64
    /// Module or project.
    public var scope: RollupScope
    /// The module's name; for the project, `production` or `tests`.
    public var name: String
    /// The metric's path in the roll-up.
    public var metric: String
    /// The collector it comes from.
    public var collector: String
    /// The value.
    public var value: Double
}
