//
//  HistoryCommitRow.swift
//  SwiftStatsCore
//
//  The `historyCommit` table (store v3, PRD §7.13): a snapshot's commit
//  log, one row per commit that changed the package's Swift files.
//

import GRDB

/// One commit of a snapshot's commit log.
struct HistoryCommitRow: Codable, FetchableRecord, PersistableRecord {
    /// The table name.
    static let databaseTableName = "historyCommit"

    /// The snapshot.
    var snapshotId: Int64
    /// Its position in the log, from 0, newest first.
    var ordinal: Int
    /// The commit hash.
    var hash: String
    /// Its committer date.
    var date: String
    /// Whether it counts as a sweep.
    var sweep: Bool
    /// Whether it counts as a fix.
    var fix: Bool

    /// The entry this row records.
    var entry: HistoryLogEntry {
        HistoryLogEntry(hash: hash, date: date, sweep: sweep, fix: fix)
    }

    /// The row for `entry`, the log's `ordinal`th, in snapshot `snapshotId`.
    init(_ entry: HistoryLogEntry, ordinal: Int, snapshotId: Int64) {
        self.snapshotId = snapshotId
        self.ordinal = ordinal
        hash = entry.hash
        date = entry.date
        sweep = entry.sweep
        fix = entry.fix
    }
}
