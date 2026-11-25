//
//  FamilyTypeReferenceRow.swift
//  SwiftStatsCore
//
//  The `familyTypeReference` table (store v6, M7, design §4.4, §9.1): one
//  row per production family referencing a package type, in a snapshot
//  holding index results. `typeFile` is '' when the type isn't
//  file-scoped.
//

import GRDB

/// A family's reference to a package type, as one row.
struct FamilyTypeReferenceRow: Codable, Equatable, FetchableRecord, PersistableRecord {
    /// The table name.
    static let databaseTableName = "familyTypeReference"

    /// The snapshot.
    var snapshotId: Int64
    /// The referencing family.
    var family: String
    /// The type's target.
    var module: String
    /// Its type path.
    var typePath: String
    /// Its file when file-scoped; '' otherwise.
    var typeFile: String

    /// The reference this row holds.
    var reference: IndexFamilyTypeReference {
        IndexFamilyTypeReference(
            family: family,
            module: module,
            typePath: typePath,
            typeFile: typeFile.isEmpty ? nil : typeFile
        )
    }

    /// The row for `reference` in snapshot `snapshotId`.
    init(_ reference: IndexFamilyTypeReference, snapshotId: Int64) {
        self.snapshotId = snapshotId
        family = reference.family
        module = reference.module
        typePath = reference.typePath
        typeFile = reference.typeFile ?? ""
    }
}
