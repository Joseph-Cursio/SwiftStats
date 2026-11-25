//
//  SnapshotStore+Index.swift
//  SwiftStatsCore
//
//  The T1 group's rows (store v6, M7, design §9.1): a snapshot's index,
//  build and dead-code results are written with it, each block as its
//  rows (`IndexRows`, `BuildRows`, `DeadCodeRows`) and each record's
//  columns with its function row, all three dated when the T1 build ran;
//  and whether a snapshot holds T1 results is read without reading them,
//  so results too damaged to read can still be dropped. A snapshot holds
//  T1 results when its `build` collector ran and it has a `buildScan` row:
//  a build that ran always replaces held T1 results, even when the index
//  or outskirts then failed.
//

import GRDB

extension SnapshotStore {
    /// Inserts the T1 blocks of `report`, collected at `collectedAt`, as
    /// rows of snapshot `snapshotId` in `database`: each block that is
    /// there, but for the records' columns, which go with the function
    /// rows.
    static func insertIndexRows(
        of report: ScanReport,
        collectedAt: String,
        snapshotId: Int64,
        in database: Database
    ) throws {
        if let index = report.index {
            try IndexRows(index, collectedAt: collectedAt, snapshotId: snapshotId).insert(database)
        }
        if let build = report.build {
            try BuildRows(build, collectedAt: collectedAt, snapshotId: snapshotId).insert(database)
        }
        if let deadCode = report.deadCode {
            try DeadCodeRows(deadCode, collectedAt: collectedAt, snapshotId: snapshotId).insert(database)
        }
    }

    /// Whether snapshot `id` holds T1 results, read in `database`: a
    /// `buildScan` row beside a `build` collector that ran. Nothing of the
    /// results themselves is read.
    static func holdsIndex(id: Int64, in database: Database) throws -> Bool {
        try Bool.fetchOne(
            database,
            sql: """
                SELECT EXISTS (SELECT 1 FROM buildScan WHERE snapshotId = ?)
                    AND EXISTS (SELECT 1 FROM collectorRun WHERE snapshotId = ? AND name = ? AND state = ?)
                """,
            arguments: [id, id, BuildAdapter.name, CollectorState.ran.rawValue]
        ) ?? false
    }

    /// When the T1 results snapshot `id` holds were collected, read in
    /// `database` from its `buildScan` row alone; nil when it holds none.
    static func indexCollectedAt(id: Int64, in database: Database) throws -> String? {
        guard try holdsIndex(id: id, in: database) else {
            return nil
        }
        return try String.fetchOne(
            database,
            sql: "SELECT collectedAt FROM buildScan WHERE snapshotId = ?",
            arguments: [id]
        )
    }
}
