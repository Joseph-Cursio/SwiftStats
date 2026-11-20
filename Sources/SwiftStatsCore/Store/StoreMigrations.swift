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
        steps.registerMigration("v3", migrate: version3)
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

    /// M4: function rows' generated flag and side effects, scan-wide facts,
    /// property candidates, law checks, clones and history's commit lists.
    /// Rows written before it get nulls in the new columns and no rows in
    /// the new tables.
    private static func version3(_ database: Database) throws {
        try database.alter(table: FunctionRow.databaseTableName) { table in
            for name in ["effectTier", "effectSource", "purity", "refutation", "inference", "inferredTier"] {
                table.add(column: name, .text)
            }
            table.add(column: "inferredAnchor", .text)
            table.add(column: "inferredDepth", .integer)
            table.add(column: "inferredVia", .text)
            table.add(column: "valueShaped", .boolean)
            table.add(column: "shape", .text)
            table.add(column: "generated", .boolean)
        }
        try database.create(table: ScanFactsRow.databaseTableName) { table in
            snapshotColumn(table).primaryKey()
            table.column("kitDependency", .boolean).notNull()
            table.column("sipSeiRevision", .text)
        }
        try createCandidateTable(database)
        try database.create(table: LawCheckRow.databaseTableName) { table in
            snapshotColumn(table)
            table.column("ordinal", .integer).notNull()
            table.column("type", .text).notNull()
            table.column("protocol", .text).notNull()
            table.column("provenance", .text).notNull()
            table.column("implementation", .text).notNull()
            table.column("state", .text).notNull()
            table.column("evidence", .text)
            table.column("file", .text).notNull()
            table.column("line", .integer).notNull()
            table.column("generated", .boolean).notNull()
            table.primaryKey(["snapshotId", "ordinal"])
        }
        try createCloneTables(database)
        try database.create(table: HistoryCommitRow.databaseTableName) { table in
            snapshotColumn(table)
            table.column("ordinal", .integer).notNull()
            table.column("hash", .text).notNull()
            table.column("date", .text).notNull()
            table.column("sweep", .boolean).notNull()
            table.column("fix", .boolean).notNull()
            table.primaryKey(["snapshotId", "ordinal"])
        }
        try database.create(table: FamilyChangeRow.databaseTableName) { table in
            snapshotColumn(table).indexed()
            table.column("family", .text).notNull()
            table.column("file", .text).notNull()
            table.column("commitOrdinal", .integer).notNull()
        }
        try database.execute(sql: "PRAGMA user_version = 3")
    }

    /// The `propertyCandidate` table.
    private static func createCandidateTable(_ database: Database) throws {
        try database.create(table: PropertyCandidateRow.databaseTableName) { table in
            snapshotColumn(table)
            table.column("ordinal", .integer).notNull()
            for name in ["identity", "population", "template", "tier"] {
                table.column(name, .text).notNull()
            }
            table.column("score", .integer).notNull()
            table.column("scoreBand", .text).notNull()
            table.column("blocked", .boolean).notNull()
            table.column("function", .text).notNull()
            table.column("typeName", .text)
            table.column("file", .text)
            table.column("line", .integer)
            for name in ["attachedTo", "owner", "site", "unmapped"] {
                table.column(name, .text)
            }
            table.column("generated", .boolean).notNull()
            table.column("identityCollision", .boolean).notNull()
            for name in ["partner", "partnerKey", "decision", "verifyOutcome"] {
                table.column(name, .text)
            }
            for name in ["verifyFresh", "verified", "disproven"] {
                table.column(name, .boolean)
            }
            table.column("testedBy", .text)
            table.column("testKeys", .text).notNull()
            table.primaryKey(["snapshotId", "ordinal"])
        }
    }

    /// The `cloneClass` and `cloneInstance` tables.
    private static func createCloneTables(_ database: Database) throws {
        try database.create(table: CloneClassRow.databaseTableName) { table in
            snapshotColumn(table)
            table.column("ordinal", .integer).notNull()
            table.column("pass", .text).notNull()
            table.column("exact", .boolean).notNull()
            table.column("mass", .integer).notNull()
            table.column("similarity", .double)
            table.column("lineSpan", .integer).notNull()
            table.column("fingerprint", .text).notNull()
            table.primaryKey(["snapshotId", "ordinal"])
        }
        try database.create(table: CloneInstanceRow.databaseTableName) { table in
            snapshotColumn(table)
            table.column("classOrdinal", .integer).notNull()
            table.column("ordinal", .integer).notNull()
            table.column("file", .text).notNull()
            for name in ["startLine", "startColumn", "endLine", "endColumn", "strippedLines"] {
                table.column(name, .integer).notNull()
            }
            table.column("containing", .text)
            table.column("wholes", .text).notNull()
            table.primaryKey(["snapshotId", "classOrdinal", "ordinal"])
        }
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
