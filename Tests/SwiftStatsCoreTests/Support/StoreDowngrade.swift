//
//  StoreDowngrade.swift
//  SwiftStatsCoreTests
//
//  SQL that takes a store back to before migration v5 (M6) or v4 (M5), so
//  tests can check that a store written by an earlier SwiftStats migrates.
//  Each later migration has to be undone before an earlier one, or GRDB
//  would run the earlier one again with the later one still recorded.
//

/// Statements undoing store migrations.
enum StoreDowngrade {
    /// The tables v5 adds.
    static let mutationTables = ["mutationScan", "mutationRun", "mutationFile", "mutationSuspect", "mutant"]

    /// Statements dropping what v5 adds (its indexes go with their table)
    /// and forgetting it ran, leaving `user_version` for the caller to set.
    static let undoingVersion5 = mutationTables.map { "DROP TABLE \($0)" }
        + ["DELETE FROM grdb_migrations WHERE identifier = 'v5'"]

    /// The tables v4 adds.
    static let coverageTables = [
        "coverageRun", "functionCoverage", "coverageAttachment", "coverageLine", "coverageUnmapped"
    ]
    /// The columns v4 adds to `function`.
    static let functionColumns = ["access", "typePath", "typeFile"]

    /// Statements dropping what v5 and v4 add and forgetting they ran,
    /// leaving `user_version` for the caller to set.
    static let undoingVersion4 = undoingVersion5 + coverageTables.map { "DROP TABLE \($0)" }
        + functionColumns.map { "ALTER TABLE function DROP COLUMN \($0)" }
        + ["DELETE FROM grdb_migrations WHERE identifier = 'v4'"]
}
