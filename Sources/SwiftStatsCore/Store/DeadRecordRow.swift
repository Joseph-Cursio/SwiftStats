//
//  DeadRecordRow.swift
//  SwiftStatsCore
//
//  The `deadRecord` table (store v6, M7, design §5.4, §9.1): one row per
//  record an unused production entry covers, per run, naming the entry by
//  its ordinal and the rule that covered the record. The run and rule are
//  held by name.
//

import GRDB

/// A record outskirts' entry covers, as one row.
struct DeadRecordRow: Codable, Equatable, FetchableRecord, PersistableRecord {
    /// The table name.
    static let databaseTableName = "deadRecord"

    /// The snapshot.
    var snapshotId: Int64
    /// The run, by name.
    var run: String
    /// The record's key.
    var key: String
    /// The covering entry's ordinal in the run.
    var declaration: Int
    /// The rule that covered it, by name.
    var via: String

    /// The covered record this row holds; it throws when the run or rule
    /// names none.
    var record: DeadCodeRecord {
        get throws {
            DeadCodeRecord(
                key: key,
                run: try RowJSON.named(DeadCodeRun.self, from: run),
                declaration: declaration,
                via: try RowJSON.named(DeadCodeVia.self, from: via)
            )
        }
    }

    /// The row for `record` in snapshot `snapshotId`.
    init(_ record: DeadCodeRecord, snapshotId: Int64) {
        self.snapshotId = snapshotId
        run = record.run.rawValue
        key = record.key
        declaration = record.declaration
        via = record.via.rawValue
    }
}
