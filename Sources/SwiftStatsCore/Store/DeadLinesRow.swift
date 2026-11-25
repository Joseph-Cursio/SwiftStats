//
//  DeadLinesRow.swift
//  SwiftStatsCore
//
//  The `deadLines` table (store v6, M7, design §5.4, §7): the stripped
//  lines of the maximal covered units per module and run, of a snapshot
//  holding dead-code results. They can't be worked out from the
//  `deadRecord` rows alone, because a type's units take in its extensions
//  by the index's ownership, so they are stored as the mapping gave them.
//

import GRDB

/// A module's dead lines in one run, as one row.
struct DeadLinesRow: Codable, Equatable, FetchableRecord, PersistableRecord {
    /// The table name.
    static let databaseTableName = "deadLines"

    /// The snapshot.
    var snapshotId: Int64
    /// The run, by name.
    var run: String
    /// The module, a target name.
    var module: String
    /// Its dead lines.
    var lines: Int

    /// The row for `lines` of `module` in run `run`, in snapshot
    /// `snapshotId`.
    init(run: String, module: String, lines: Int, snapshotId: Int64) {
        self.snapshotId = snapshotId
        self.run = run
        self.module = module
        self.lines = lines
    }
}
