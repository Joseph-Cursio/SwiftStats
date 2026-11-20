//
//  FamilyChangeRow.swift
//  SwiftStatsCore
//
//  The `familyChange` table (store v3, PRD §7.13): one row per commit that
//  changed a family, sweeps included, naming the commit by its position in
//  the snapshot's `historyCommit` log. A family with no history has no
//  rows; its `familyHistory` row's counts are null.
//

import GRDB

/// One commit that changed one family in a snapshot.
public struct FamilyChangeRow: Codable, Hashable, Sendable, FetchableRecord, PersistableRecord {
    /// The table name.
    public static let databaseTableName = "familyChange"

    /// The snapshot.
    var snapshotId: Int64
    /// The family's id.
    public var family: String
    /// The family's file, which with its id names it as history follows it.
    public var file: String
    /// The commit's position in the snapshot's commit log.
    public var commitOrdinal: Int

    /// The rows for each commit that changed `history`'s family, in snapshot `snapshotId`.
    static func rows(for history: FamilyHistory, snapshotId: Int64) -> [Self] {
        (history.changedBy?.ordinals ?? []).map { ordinal in
            Self(snapshotId: snapshotId, family: history.family, file: history.file, commitOrdinal: ordinal)
        }
    }
}
