//
//  FamilyReferenceRow.swift
//  SwiftStatsCore
//
//  The `familyReference` table (store v6, M7, design §4.4, §9.1): one row
//  per production family referencing another, directly or through a
//  protocol requirement, in a snapshot holding index results.
//

import GRDB

/// A family's reference to another, as one row.
struct FamilyReferenceRow: Codable, Equatable, FetchableRecord, PersistableRecord {
    /// The table name.
    static let databaseTableName = "familyReference"

    /// The snapshot.
    var snapshotId: Int64
    /// The referencing family.
    var fromFamily: String
    /// The referenced family.
    var toFamily: String
    /// `direct` or `requirement`.
    var via: IndexFamilyReference.Via

    /// The reference this row holds.
    var reference: IndexFamilyReference {
        IndexFamilyReference(fromFamily: fromFamily, toFamily: toFamily, via: via)
    }

    /// The row for `reference` in snapshot `snapshotId`.
    init(_ reference: IndexFamilyReference, snapshotId: Int64) {
        self.snapshotId = snapshotId
        fromFamily = reference.fromFamily
        toFamily = reference.toFamily
        via = reference.via
    }
}
