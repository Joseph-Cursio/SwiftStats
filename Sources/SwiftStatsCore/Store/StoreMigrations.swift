//
//  StoreMigrations.swift
//  SwiftStatsCore
//
//  The store's schema, forward only (PRD §9). GRDB's table of applied
//  migrations is the source of truth; `PRAGMA user_version` mirrors their
//  count for other readers and is never lowered.
//

import GRDB

/// The store's migrations.
enum StoreMigrations {
    /// Every migration, in order.
    static var migrator: DatabaseMigrator {
        var steps = DatabaseMigrator()
        steps.registerMigration("v1", migrate: version1)
        steps.registerMigration("v2", migrate: version2)
        return steps
    }

    /// The M2 schema.
    private static func version1(_ database: Database) throws {
        try database.create(table: SnapshotRow.databaseTableName) { table in
            table.autoIncrementedPrimaryKey("id")
            table.column("package", .text).notNull()
            table.column("packagePath", .text).notNull()
            table.column("commitHash", .text)
            table.column("branch", .text)
            table.column("date", .text).notNull()
            table.column("isDirty", .boolean).notNull()
            table.column("dirtyHash", .text)
            table.column("swiftVersion", .text)
            table.column("swiftlySelection", .text)
            table.column("sdkVersion", .text)
            table.column("reportSchemaVersion", .integer).notNull()
        }
        // One clean and one dirty snapshot per package and commit; SQLite
        // treats NULLs as distinct, so a package outside git is keyed by ''.
        try database.execute(sql: """
            CREATE UNIQUE INDEX snapshotState
            ON snapshot(package, packagePath, ifnull(commitHash, ''), isDirty)
            """)
        try database.create(table: CollectorRunRow.databaseTableName) { table in
            snapshotColumn(table)
            table.column("name", .text).notNull()
            table.column("state", .text).notNull()
            table.column("reason", .text)
            table.column("version", .text)
            table.column("identity", .text)
            table.column("identityLabel", .text)
            table.column("options", .text).notNull()
            table.column("durationMilliseconds", .integer).notNull()
            table.primaryKey(["snapshotId", "name"])
        }
        try createFunctionTable(database)
        try createFindingTable(database)
        try database.create(table: RollupMetricRow.databaseTableName) { table in
            snapshotColumn(table)
            table.column("scope", .text).notNull()
            table.column("name", .text).notNull()
            table.column("metric", .text).notNull()
            table.column("collector", .text).notNull()
            table.column("value", .double).notNull()
            table.primaryKey(["snapshotId", "scope", "name", "metric"])
        }
        try database.create(table: ReportRow.databaseTableName) { table in
            snapshotColumn(table).primaryKey()
            table.column("schemaVersion", .integer).notNull()
            table.column("encoding", .text).notNull()
            table.column("uncompressedLength", .integer).notNull()
            table.column("data", .blob).notNull()
        }
        try database.execute(sql: "PRAGMA user_version = 1")
    }

    /// M3: each snapshot's history run and its families' history.
    private static func version2(_ database: Database) throws {
        try database.create(table: HistoryRunRow.databaseTableName) { table in
            snapshotColumn(table).primaryKey()
            table.column("commitHash", .text).notNull()
            table.column("date", .text).notNull()
            table.column("windowDays", .integer).notNull()
            table.column("windowStart", .text).notNull()
            table.column("mergeStyle", .text).notNull()
            table.column("commits", .integer).notNull()
            table.column("windowCommits", .integer).notNull()
        }
        try database.create(table: FamilyHistoryRow.databaseTableName) { table in
            snapshotColumn(table).indexed()
            table.column("family", .text).notNull()
            table.column("file", .text).notNull()
            table.column("line", .integer).notNull()
            table.column("generated", .boolean).notNull()
            let counts = [
                "changes", "sweepChanges", "allChanges", "fixes", "allFixes", "reverts", "repeatedFixes", "testChanges"
            ]
            for name in counts {
                table.column(name, .integer)
            }
            table.column("fixScore", .double)
            table.column("fixRate", .double)
            table.column("hasTests", .boolean).notNull()
            table.column("firstSeen", .text)
            table.column("lastChanged", .text)
            table.column("tracedBy", .text).notNull()
        }
        try database.execute(sql: "PRAGMA user_version = 2")
    }

    /// The `function` table.
    private static func createFunctionTable(_ database: Database) throws {
        try database.create(table: FunctionRow.databaseTableName) { table in
            snapshotColumn(table).indexed()
            table.column("key", .text).notNull()
            table.column("module", .text).notNull()
            table.column("kind", .text).notNull()
            table.column("name", .text).notNull()
            table.column("accessorKind", .text)
            table.column("file", .text).notNull()
            table.column("startLine", .integer).notNull()
            table.column("endLine", .integer).notNull()
            table.column("bodyHash", .text).notNull()
            table.column("parentKey", .text)
            table.column("ifConfig", .text)
            table.column("role", .text).notNull()
            table.column("strippedLines", .integer).notNull()
            table.column("bodyLines", .integer).notNull()
            table.column("parameterCount", .integer)
            table.column("isDocumented", .boolean).notNull()
            table.column("isAsync", .boolean).notNull()
            table.column("cognitive", .integer)
            table.column("decisionCount", .integer)
            table.column("swiftLintCompatible", .integer)
            table.column("maxNesting", .integer)
        }
    }

    /// The `finding` table.
    private static func createFindingTable(_ database: Database) throws {
        try database.create(table: FindingRow.databaseTableName) { table in
            snapshotColumn(table).indexed()
            table.column("tool", .text).notNull()
            table.column("rule", .text).notNull()
            table.column("kind", .text).notNull()
            table.column("severity", .text).notNull()
            table.column("message", .text).notNull()
            table.column("file", .text).notNull()
            table.column("line", .integer)
            table.column("column", .integer)
            table.column("attachedTo", .text).notNull()
            table.column("owner", .text)
        }
    }

    /// A `snapshotId` column whose rows go when their snapshot does.
    @discardableResult
    private static func snapshotColumn(_ table: TableDefinition) -> ColumnDefinition {
        table.column("snapshotId", .integer)
            .notNull()
            .references(SnapshotRow.databaseTableName, onDelete: .cascade)
    }
}
