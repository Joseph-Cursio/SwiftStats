//
//  StoreMigrations+Index.swift
//  SwiftStatsCore
//
//  Store v6 (M7, design §9.1): the T1 group's rows and history's coupling
//  pairs. `function` gains each record's USRs or the reason it has none,
//  its witness flag and referrers, and its type-check timings; the new
//  tables hold the rest of the `index` block (`indexScan`, `indexUnit`,
//  `indexFile`, `usrDisagreement`, `moduleEdge`, `typeIndex`,
//  `familyReference`, `familyTypeReference`), of the `build` block
//  (`buildScan`, `timingAttachment`) and of the `deadCode` block
//  (`deadScan`, `deadDeclaration`, `deadRecord`, `deadLines`), and every
//  scan's change-coupling pairs (`couplingPair`). Snapshots stored before
//  it get nulls in the new columns and no rows in the new tables: never
//  zero for what wasn't collected.
//

import GRDB

extension StoreMigrations {
    /// The columns v6 adds to `function`, with their types.
    static let indexFunctionColumns: [(name: String, type: Database.ColumnType)] = [
        ("usr", .text), ("usrAccessor", .text), ("usrReason", .text), ("witness", .boolean),
        ("referrersSameModule", .integer), ("referrersOtherModules", .integer), ("referrersTests", .integer),
        ("testReferrers", .text), ("typeCheckMilliseconds", .integer), ("slowestExpressionMilliseconds", .integer)
    ]

    /// M7: the T1 group's results and the coupling pairs.
    static func version6(_ database: Database) throws {
        try database.alter(table: FunctionRow.databaseTableName) { table in
            for column in indexFunctionColumns {
                table.add(column: column.name, column.type)
            }
        }
        try createIndexTables(database)
        try createCouplingTables(database)
        try createBuildTables(database)
        try createDeadCodeTables(database)
        try database.execute(sql: "PRAGMA user_version = 6")
    }

    /// The `indexScan`, `indexUnit`, `indexFile` and `usrDisagreement`
    /// tables.
    private static func createIndexTables(_ database: Database) throws {
        try database.create(table: IndexScanRow.databaseTableName) { table in
            snapshotColumn(table).primaryKey()
            for name in ["collectedAt", "layout", "libraryModules"] {
                table.column(name, .text).notNull()
            }
            let counts = [
                "unitsKept", "unitsVariant", "unitsSystem", "unitsOtherPackage", "unitsOtherModule", "unitsStale",
                "unitsDuplicate", "unitsQuarantined", "records", "occurrences", "definitionsJoined",
                "definitionsImplicit", "secondaryUSRs", "objcUSRs"
            ]
            for name in counts {
                table.column(name, .integer).notNull()
            }
        }
        try database.create(table: StoredIndexUnitRow.databaseTableName) { table in
            snapshotColumn(table)
            for name in ["name", "target", "mainFile", "triple", "class"] {
                table.column(name, .text).notNull()
            }
            table.primaryKey(["snapshotId", "name"])
        }
        try database.create(table: IndexFileRow.databaseTableName) { table in
            snapshotColumn(table)
            table.column("path", .text).notNull()
            table.column("sha256", .text)
            table.primaryKey(["snapshotId", "path"])
        }
        try database.create(table: USRDisagreementRow.databaseTableName) { table in
            snapshotColumn(table)
            table.column("ordinal", .integer).notNull()
            table.column("kind", .text).notNull()
            for name in ["subreason", "usr", "key"] {
                table.column(name, .text)
            }
            table.column("symbolKind", .integer)
            table.column("name", .text)
            table.column("file", .text).notNull()
            table.column("line", .integer).notNull()
            table.column("column", .integer).notNull()
            table.primaryKey(["snapshotId", "ordinal"])
        }
    }

    /// The coupling tables: `moduleEdge`, `typeIndex`, `familyReference`,
    /// `familyTypeReference` and history's `couplingPair`. A type is keyed
    /// on its USR too: two local types of one name in one target share
    /// their target, type path and (empty) file.
    private static func createCouplingTables(_ database: Database) throws {
        try database.create(table: ModuleEdgeRow.databaseTableName) { table in
            snapshotColumn(table)
            for name in ["fromModule", "toModule", "kind"] {
                table.column(name, .text).notNull()
            }
            table.column("references", .integer)
            table.column("files", .integer).notNull()
            table.primaryKey(["snapshotId", "fromModule", "toModule"])
        }
        try database.create(table: TypeIndexRow.databaseTableName) { table in
            snapshotColumn(table)
            for name in ["module", "typePath", "typeFile", "usr"] {
                table.column(name, .text).notNull()
            }
            for name in ["referrersSameModule", "referrersOtherModules", "referrersTests"] {
                table.column(name, .integer).notNull()
            }
            table.column("cycle", .integer)
            table.primaryKey(["snapshotId", "module", "typePath", "typeFile", "usr"])
        }
        try database.create(table: FamilyReferenceRow.databaseTableName) { table in
            snapshotColumn(table)
            for name in ["fromFamily", "toFamily", "via"] {
                table.column(name, .text).notNull()
            }
            table.primaryKey(["snapshotId", "fromFamily", "toFamily", "via"])
        }
        try database.create(
            index: "familyReferenceTarget",
            on: FamilyReferenceRow.databaseTableName,
            columns: ["snapshotId", "toFamily"]
        )
        try database.create(table: FamilyTypeReferenceRow.databaseTableName) { table in
            snapshotColumn(table)
            for name in ["family", "module", "typePath", "typeFile"] {
                table.column(name, .text).notNull()
            }
            table.primaryKey(["snapshotId", "family", "module", "typePath", "typeFile"])
        }
        try database.create(table: CouplingPairRow.databaseTableName) { table in
            snapshotColumn(table)
            table.column("ordinal", .integer).notNull()
            for name in ["familyA", "fileA", "familyB", "fileB"] {
                table.column(name, .text).notNull()
            }
            for name in ["support", "changesA", "changesB"] {
                table.column(name, .integer).notNull()
            }
            table.primaryKey(["snapshotId", "ordinal"])
        }
    }

    /// The `buildScan` and `timingAttachment` tables. Each class of
    /// entries the timings leave out keeps its entries and milliseconds.
    private static func createBuildTables(_ database: Database) throws {
        try database.create(table: BuildScanRow.databaseTableName) { table in
            snapshotColumn(table).primaryKey()
            table.column("collectedAt", .text).notNull()
            table.column("complete", .boolean).notNull()
            let counts = [
                "functionEntries", "expressionEntries", "totalMilliseconds", "synthesizedEntries",
                "synthesizedMilliseconds", "macroEntries", "macroMilliseconds", "buildEntries", "buildMilliseconds",
                "outsideRootEntries", "outsideRootMilliseconds", "fileChangedEntries", "fileChangedMilliseconds",
                "unscannedEntries", "unscannedMilliseconds", "changedFiles", "unparsedTimingLines", "escapedLines",
                "otherWarningLines", "warningsDropped", "warningsUnmapped", "pluginWarnings"
            ]
            for name in counts {
                table.column(name, .integer).notNull()
            }
        }
        try database.create(table: TimingAttachmentRow.databaseTableName) { table in
            snapshotColumn(table)
            table.column("owner", .text).notNull()
            table.column("attachedTo", .text).notNull()
            table.column("milliseconds", .integer)
            table.column("slowestExpressionMilliseconds", .integer)
            table.primaryKey(["snapshotId", "owner", "attachedTo"])
        }
    }

    /// The `deadScan`, `deadDeclaration`, `deadRecord` and `deadLines`
    /// tables.
    private static func createDeadCodeTables(_ database: Database) throws {
        try database.create(table: DeadScanRow.databaseTableName) { table in
            snapshotColumn(table).primaryKey()
            table.column("collectedAt", .text).notNull()
            table.column("version", .text).notNull()
            table.column("rootsResults", .integer).notNull()
            table.column("productionResults", .integer).notNull()
        }
        try database.create(table: DeadDeclarationRow.databaseTableName) { table in
            snapshotColumn(table)
            table.column("run", .text).notNull()
            table.column("ordinal", .integer).notNull()
            table.column("hint", .text).notNull()
            table.column("hintText", .text)
            let texts = ["kind", "name", "accessibility", "attributes", "modifiers", "ids", "modules", "class"]
            for name in texts {
                table.column(name, .text).notNull()
            }
            table.column("file", .text)
            table.column("line", .integer).notNull()
            table.column("column", .integer).notNull()
            table.column("place", .text).notNull()
            table.column("owner", .text)
            table.column("module", .text)
            table.column("strippedLines", .integer)
            table.primaryKey(["snapshotId", "run", "ordinal"])
        }
        try database.create(table: DeadRecordRow.databaseTableName) { table in
            snapshotColumn(table)
            for name in ["run", "key"] {
                table.column(name, .text).notNull()
            }
            table.column("declaration", .integer).notNull()
            table.column("via", .text).notNull()
            table.primaryKey(["snapshotId", "run", "key"])
        }
        try database.create(index: "deadRecordKey", on: DeadRecordRow.databaseTableName, columns: ["snapshotId", "key"])
        try database.create(table: DeadLinesRow.databaseTableName) { table in
            snapshotColumn(table)
            for name in ["run", "module"] {
                table.column(name, .text).notNull()
            }
            table.column("lines", .integer).notNull()
            table.primaryKey(["snapshotId", "run", "module"])
        }
    }
}
