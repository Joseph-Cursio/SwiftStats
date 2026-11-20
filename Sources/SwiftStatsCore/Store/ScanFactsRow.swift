//
//  ScanFactsRow.swift
//  SwiftStatsCore
//
//  The `scanFacts` table (store v3, M4): one row per snapshot with the
//  scan outputs the M4 signals print beside their tables.
//

import GRDB

/// A snapshot's scan-wide facts.
public struct ScanFactsRow: Codable, Hashable, Sendable, FetchableRecord, PersistableRecord {
    /// The table name.
    public static let databaseTableName = "scanFacts"

    /// The snapshot.
    var snapshotId: Int64
    /// Whether the package depends on SwiftPropertyLaws (PRD §7.11).
    public var kitDependency: Bool
    /// The SwiftEffectInference revision `swift-infer` was built with;
    /// nil when SwiftInferProperties didn't run or its build directory
    /// wasn't found.
    public var sipSeiRevision: String?

    /// The row for `report` in snapshot `snapshotId`.
    init(_ report: ScanReport, snapshotId: Int64) {
        self.snapshotId = snapshotId
        kitDependency = report.laws.kitDependency
        sipSeiRevision = report.properties?.seiRevision
    }
}
