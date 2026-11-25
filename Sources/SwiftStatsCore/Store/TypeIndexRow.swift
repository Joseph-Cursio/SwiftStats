//
//  TypeIndexRow.swift
//  SwiftStatsCore
//
//  The `typeIndex` table (store v6, M7, design §4.3, §9.1): one row per
//  production type of a snapshot holding index results, with its fan-in
//  and USR cycle number. `typeFile` is '' when the type isn't file-scoped,
//  and the USR is part of the key: two local types of one name in one
//  target share their target, type path and file.
//

import GRDB

/// A production type, as one row.
struct TypeIndexRow: Codable, Equatable, FetchableRecord, PersistableRecord {
    /// The table name.
    static let databaseTableName = "typeIndex"

    /// The snapshot.
    var snapshotId: Int64
    /// The type's target.
    var module: String
    /// Its type path.
    var typePath: String
    /// Its file when file-scoped; '' otherwise.
    var typeFile: String
    /// Its USR.
    var usr: String
    /// Distinct referrers in its own target.
    var referrersSameModule: Int
    /// Distinct referrers in other production targets.
    var referrersOtherModules: Int
    /// Distinct referrers in test targets.
    var referrersTests: Int
    /// The number of its USR cycle; null outside every cycle.
    var cycle: Int?

    /// The type this row holds.
    var type: IndexTypeRow {
        IndexTypeRow(
            module: module,
            typePath: typePath,
            typeFile: typeFile.isEmpty ? nil : typeFile,
            usr: usr,
            referrersSameModule: referrersSameModule,
            referrersOtherModules: referrersOtherModules,
            referrersTests: referrersTests,
            cycle: cycle
        )
    }

    /// The row for `type` in snapshot `snapshotId`.
    init(_ type: IndexTypeRow, snapshotId: Int64) {
        self.snapshotId = snapshotId
        module = type.module
        typePath = type.typePath
        typeFile = type.typeFile ?? ""
        usr = type.usr
        referrersSameModule = type.referrersSameModule
        referrersOtherModules = type.referrersOtherModules
        referrersTests = type.referrersTests
        cycle = type.cycle
    }
}
