//
//  MutationFileRow.swift
//  SwiftStatsCore
//
//  The `mutationFile` table (M6, design §5): the tree a snapshot's
//  mutation results describe, one row per Swift path with SwiftMutator's
//  hash (null for a path deleted since the base), its disposition, whether
//  it is a test file changed since the base, and the run that tested it.
//  A later merge compares against it.
//

import GRDB

/// One path of a snapshot's mutation tree.
struct MutationFileRow: Codable, Equatable, FetchableRecord, PersistableRecord {
    /// The table name.
    static let databaseTableName = "mutationFile"

    /// The snapshot.
    var snapshotId: Int64
    /// The path, relative to the package.
    var path: String
    /// Its SHA-256 as SwiftMutator records it; null for a deleted path.
    var sha256: String?
    /// Where its results come from.
    var disposition: MutationFileDisposition
    /// Whether it is a test file changed since the base.
    var changedTest: Bool
    /// The ordinal of the run that tested it; null when none did.
    var run: Int?

    /// The path's entry this row records.
    var file: MutationFile {
        MutationFile(path: path, sha256: sha256, disposition: disposition, changedTest: changedTest, run: run)
    }

    /// The row for `file` in snapshot `snapshotId`.
    init(_ file: MutationFile, snapshotId: Int64) {
        self.snapshotId = snapshotId
        path = file.path
        sha256 = file.sha256
        disposition = file.disposition
        changedTest = file.changedTest
        run = file.run
    }
}
