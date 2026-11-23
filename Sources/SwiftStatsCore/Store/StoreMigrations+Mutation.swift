//
//  StoreMigrations+Mutation.swift
//  SwiftStatsCore
//
//  Store v5 (M6, design §5): the mutation tables. A snapshot holding
//  mutation results has one `mutationScan` row, a row per run its mutants
//  refer to, a row per Swift path of the tree they describe, a row per
//  suspect test and a row per mutant, dropped and unmapped ones included.
//  Snapshots stored before it have no mutation rows.
//

import GRDB

extension StoreMigrations {
    /// M6: mutation results.
    static func version5(_ database: Database) throws {
        try database.create(table: MutationScanRow.databaseTableName) { table in
            snapshotColumn(table).primaryKey()
            table.column("collectedAt", .text).notNull()
            table.column("complete", .boolean).notNull()
            table.column("listsNotCovered", .boolean).notNull()
            table.column("mode", .text).notNull()
            table.column("baseCommit", .text)
            table.column("baseCollectedAt", .text)
        }
        try createMutationRunTable(database)
        try database.create(table: MutationFileRow.databaseTableName) { table in
            snapshotColumn(table)
            table.column("path", .text).notNull()
            table.column("sha256", .text)
            table.column("disposition", .text).notNull()
            table.column("changedTest", .boolean).notNull()
            table.column("run", .integer)
            table.primaryKey(["snapshotId", "path"])
        }
        // A test is its name and file, as SwiftMutator tells tests apart;
        // an XCTest test has no file, which SQLite allows in this key.
        try database.create(table: MutationSuspectRow.databaseTableName) { table in
            snapshotColumn(table)
            table.column("run", .integer).notNull()
            table.column("name", .text).notNull()
            table.column("file", .text)
            table.column("why", .text).notNull()
            table.column("files", .integer)
            table.column("filesWithKills", .integer)
            table.primaryKey(["snapshotId", "run", "name", "file"])
        }
        try createMutantTable(database)
        try database.execute(sql: "PRAGMA user_version = 5")
    }

    /// The `mutationRun` table, its columns grouped by type.
    private static func createMutationRunTable(_ database: Database) throws {
        try database.create(table: MutationRunRow.databaseTableName) { table in
            snapshotColumn(table)
            for name in ["ordinal", "sessions", "workers", "mutantsDiscovered", "controlRuns", "controlFailures"] {
                table.column(name, .integer).notNull()
            }
            for name in ["suspectsJudged", "mutantsDropped"] {
                table.column(name, .integer)
            }
            let texts = ["version", "startedAt", "mode", "resultsFile", "resultsSHA256", "formatVersions", "operators"]
            for name in texts {
                table.column(name, .text).notNull()
            }
            let optionalTexts = [
                "identity", "endedAt", "endReason", "commit", "sinceRef", "sinceCommit", "mergeBase", "toolchain",
                "testExecutableSHA256", "sdkEnvironment", "carriedFrom", "carriedFromCollectedAt"
            ]
            for name in optionalTexts {
                table.column(name, .text)
            }
            for name in ["dirty", "skipCoverage", "listsNotCovered", "stopsAtFirstFailure"] {
                table.column(name, .boolean).notNull()
            }
            table.column("timeoutSeconds", .double)
            table.primaryKey(["snapshotId", "ordinal"])
        }
    }

    /// The `mutant` table, its columns grouped by type, indexed by owner
    /// and by path.
    private static func createMutantTable(_ database: Database) throws {
        try database.create(table: MutantRow.databaseTableName) { table in
            snapshotColumn(table)
            for name in ["ordinal", "line", "column", "occurrence", "run"] {
                table.column(name, .integer).notNull()
            }
            let optionalIntegers = [
                "anchorLine", "anchorColumn", "activated", "exitStatus", "killedByComplete", "failedTestCount",
                "suspectOnly", "session"
            ]
            for name in optionalIntegers {
                table.column(name, .integer)
            }
            for name in ["path", "operator", "verdict", "killedBy", "before", "after", "description", "place"] {
                table.column(name, .text).notNull()
            }
            for name in ["outcome", "endedBy", "fileSHA256", "rerunBecause", "owner", "reason"] {
                table.column(name, .text)
            }
            table.column("durationSeconds", .double)
            table.column("carried", .boolean).notNull()
            table.column("reused", .boolean).notNull()
            table.primaryKey(["snapshotId", "ordinal"])
        }
        try database.create(index: "mutantOwner", on: MutantRow.databaseTableName, columns: ["snapshotId", "owner"])
        try database.create(index: "mutantPath", on: MutantRow.databaseTableName, columns: ["snapshotId", "path"])
    }
}
