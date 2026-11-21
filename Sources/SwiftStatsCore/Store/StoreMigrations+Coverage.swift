//
//  StoreMigrations+Coverage.swift
//  SwiftStatsCore
//
//  Store v4 (M5): each function row's access level and owning type, and
//  the coverage tables. Rows written before it get nulls in the new
//  columns and no coverage rows.
//

import GRDB

extension StoreMigrations {
    /// M5: function rows' access and owning type, and coverage.
    static func version4(_ database: Database) throws {
        try database.alter(table: FunctionRow.databaseTableName) { table in
            for name in ["access", "typePath", "typeFile"] {
                table.add(column: name, .text)
            }
        }
        try createCoverageRunTable(database)
        try database.create(table: FunctionCoverageRow.databaseTableName) { table in
            snapshotColumn(table)
            table.column("key", .text).notNull()
            for name in ["lineCovered", "lineTotal", "regionCovered", "regionTotal"] {
                table.column(name, .integer)
            }
            table.column("testTargets", .text).notNull()
            table.column("reason", .text)
            table.column("link", .text)
            table.column("linkedTests", .integer)
            table.primaryKey(["snapshotId", "key"])
        }
        try database.create(table: CoverageAttachmentRow.databaseTableName) { table in
            snapshotColumn(table)
            table.column("owner", .text).notNull()
            table.column("attachedTo", .text).notNull()
            for name in ["lineCovered", "lineTotal", "regionCovered", "regionTotal"] {
                table.column(name, .integer).notNull()
            }
            table.primaryKey(["snapshotId", "attachedTo", "owner"])
        }
        try database.create(table: CoverageLineRow.databaseTableName) { table in
            snapshotColumn(table)
            table.column("file", .text).notNull()
            table.column("lines", .text).notNull()
            table.column("skipped", .text).notNull()
            table.primaryKey(["snapshotId", "file"])
        }
        try createCoverageUnmappedTable(database)
        try database.execute(sql: "PRAGMA user_version = 4")
    }

    /// The `coverageRun` table.
    private static func createCoverageRunTable(_ database: Database) throws {
        try database.create(table: CoverageRunRow.databaseTableName) { table in
            snapshotColumn(table).primaryKey()
            table.column("collectedAt", .text).notNull()
            table.column("bundles", .text).notNull()
            table.column("tests", .text).notNull()
            for name in [
                "droppedBuild", "droppedOutsideRoot", "droppedTestFiles", "droppedOtherPackage", "droppedOtherLanguage"
            ] {
                table.column(name, .integer).notNull()
            }
            table.column("saturated", .text).notNull()
        }
    }

    /// The `coverageUnmapped` table.
    private static func createCoverageUnmappedTable(_ database: Database) throws {
        try database.create(table: CoverageUnmappedRow.databaseTableName) { table in
            snapshotColumn(table)
            table.column("ordinal", .integer).notNull()
            table.column("file", .text).notNull()
            for name in ["startLine", "startColumn", "endLine", "endColumn", "count"] {
                table.column(name, .integer).notNull()
            }
            table.column("name", .text).notNull()
            table.column("demangled", .text)
            table.column("reason", .text).notNull()
            table.primaryKey(["snapshotId", "ordinal"])
        }
    }
}
