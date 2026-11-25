//
//  StoredIndexUnitRow.swift
//  SwiftStatsCore
//
//  The `indexUnit` table (store v6, M7, design §9.1): one row per unit of
//  a listed class (kept, variant, duplicate, stale, other module) of a
//  snapshot holding index results. The class is held by name.
//

import GRDB

/// A listed index unit, as one row.
struct StoredIndexUnitRow: Codable, Equatable, FetchableRecord, PersistableRecord {
    /// The table's columns.
    private enum CodingKeys: String, CodingKey {
        case snapshotId
        case name
        case target
        case mainFile
        case triple
        case unitClass = "class"
    }

    /// The table name.
    static let databaseTableName = "indexUnit"

    /// The snapshot.
    var snapshotId: Int64
    /// The unit's name.
    var name: String
    /// Its target.
    var target: String
    /// Its main file.
    var mainFile: String
    /// Its target triple.
    var triple: String
    /// Its class, by name.
    var unitClass: String

    /// The unit this row holds; it throws when the class names none.
    var unit: IndexUnitRow {
        get throws {
            IndexUnitRow(
                name: name,
                target: target,
                mainFile: mainFile,
                triple: triple,
                unitClass: try RowJSON.named(IndexUnitClass.self, from: unitClass)
            )
        }
    }

    /// The row for `unit` in snapshot `snapshotId`.
    init(_ unit: IndexUnitRow, snapshotId: Int64) {
        self.snapshotId = snapshotId
        name = unit.name
        target = unit.target
        mainFile = unit.mainFile
        triple = unit.triple
        unitClass = unit.unitClass.rawValue
    }
}
