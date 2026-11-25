//
//  CouplingPairRow.swift
//  SwiftStatsCore
//
//  The `couplingPair` table (store v6, M7, design §9.1, PRD §9): one row
//  per change-coupling pair of a snapshot whose history was read, in the
//  history block's order. Written with history, not with the index, by
//  every scan from store v6 on; the report blob keeps the pairs too.
//

import GRDB

/// Two families that change together, as one row.
struct CouplingPairRow: Codable, Equatable, FetchableRecord, PersistableRecord {
    /// The table name.
    static let databaseTableName = "couplingPair"

    /// The snapshot.
    var snapshotId: Int64
    /// Its position in the history block's list.
    var ordinal: Int
    /// The first family.
    var familyA: String
    /// Its file.
    var fileA: String
    /// The second family.
    var familyB: String
    /// Its file.
    var fileB: String
    /// Commits in the window that changed both.
    var support: Int
    /// Commits in the window that changed the first.
    var changesA: Int
    /// Commits in the window that changed the second.
    var changesB: Int

    /// The pair this row holds.
    var pair: CouplingPair {
        CouplingPair(
            familyA: familyA,
            fileA: fileA,
            familyB: familyB,
            fileB: fileB,
            support: support,
            changesA: changesA,
            changesB: changesB
        )
    }

    /// The row for `pair`, at `ordinal`, in snapshot `snapshotId`.
    init(_ pair: CouplingPair, ordinal: Int, snapshotId: Int64) {
        self.snapshotId = snapshotId
        self.ordinal = ordinal
        familyA = pair.familyA
        fileA = pair.fileA
        familyB = pair.familyB
        fileB = pair.fileB
        support = pair.support
        changesA = pair.changesA
        changesB = pair.changesB
    }
}
