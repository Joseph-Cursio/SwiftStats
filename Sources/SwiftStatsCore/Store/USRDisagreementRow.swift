//
//  USRDisagreementRow.swift
//  SwiftStatsCore
//
//  The `usrDisagreement` table (store v6, M7, design §3.5, §9.1): the
//  index block's three listings in one table, numbered in the scan JSON's
//  order: the disagreements (`severalUSRs`, `sharedUSR`), then the
//  definitions with no record (`noRecord`), then the collisions the USR
//  tells apart (`collision`). The kind and sub-reason are held by name.
//

import GRDB

/// A listed USR, as one row.
struct USRDisagreementRow: Codable, Equatable, FetchableRecord, PersistableRecord {
    /// The table name.
    static let databaseTableName = "usrDisagreement"

    /// The snapshot.
    var snapshotId: Int64
    /// Its position across the three listings.
    var ordinal: Int
    /// What is listed, by name.
    var kind: String
    /// Why a definition has no record, by name.
    var subreason: String?
    /// The USR.
    var usr: String?
    /// The record's key.
    var key: String?
    /// The definition's symbol kind.
    var symbolKind: Int?
    /// The definition's name.
    var name: String?
    /// The file.
    var file: String
    /// The line.
    var line: Int
    /// The UTF-8 column.
    var column: Int

    /// The listing this row holds; it throws when the kind or sub-reason
    /// names none.
    var listing: USRListing {
        get throws {
            USRListing(
                kind: try RowJSON.named(USRListing.Kind.self, from: kind),
                subreason: try subreason.map { try RowJSON.named(USRListing.Subreason.self, from: $0) },
                usr: usr,
                key: key,
                symbolKind: symbolKind,
                name: name,
                file: file,
                line: line,
                column: column
            )
        }
    }

    /// The row for `listing`, at `ordinal`, in snapshot `snapshotId`.
    init(_ listing: USRListing, ordinal: Int, snapshotId: Int64) {
        self.snapshotId = snapshotId
        self.ordinal = ordinal
        kind = listing.kind.rawValue
        subreason = listing.subreason?.rawValue
        usr = listing.usr
        key = listing.key
        symbolKind = listing.symbolKind
        name = listing.name
        file = listing.file
        line = listing.line
        column = listing.column
    }
}
