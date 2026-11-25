//
//  DeadScanRow.swift
//  SwiftStatsCore
//
//  The `deadScan` row (store v6, M7, design §5, §9.1): one per snapshot
//  holding dead-code results, with when outskirts ran, its version and
//  each run's result count.
//

import GRDB

/// A snapshot's dead-code results, as one row.
struct DeadScanRow: Codable, Equatable, FetchableRecord, PersistableRecord {
    /// The table name.
    static let databaseTableName = "deadScan"

    /// The snapshot.
    var snapshotId: Int64
    /// When outskirts ran.
    var collectedAt: String
    /// `outskirts version`'s output.
    var version: String
    /// The `roots` run's results.
    var rootsResults: Int
    /// The `production` run's results.
    var productionResults: Int

    /// Each run's result count, roots first.
    var runs: [DeadCodeRunResults] {
        [
            DeadCodeRunResults(name: .roots, results: rootsResults),
            DeadCodeRunResults(name: .production, results: productionResults)
        ]
    }

    /// The row for `report`, collected at `collectedAt`, in snapshot
    /// `snapshotId`.
    init(_ report: DeadCodeReport, collectedAt: String, snapshotId: Int64) {
        self.snapshotId = snapshotId
        self.collectedAt = collectedAt
        version = report.version
        let results = Dictionary(report.runs.map { ($0.name, $0.results) }) { first, _ in first }
        rootsResults = results[.roots] ?? 0
        productionResults = results[.production] ?? 0
    }
}
