//
//  IndexFileRow.swift
//  SwiftStatsCore
//
//  The `indexFile` table (store v6, M7, design §9.1): every scanned file
//  of a snapshot holding index results, with its SHA-256 after the build;
//  null when the file couldn't be read then.
//

import GRDB

/// A scanned file hashed after the build, as one row.
struct IndexFileRow: Codable, Equatable, FetchableRecord, PersistableRecord {
    /// The table name.
    static let databaseTableName = "indexFile"

    /// The snapshot.
    var snapshotId: Int64
    /// The file, relative to the package root.
    var path: String
    /// Its SHA-256 after the build.
    var sha256: String?

    /// The hash this row holds.
    var file: IndexFileHash {
        IndexFileHash(path: path, sha256: sha256)
    }

    /// The row for `file` in snapshot `snapshotId`.
    init(_ file: IndexFileHash, snapshotId: Int64) {
        self.snapshotId = snapshotId
        path = file.path
        sha256 = file.sha256
    }
}
