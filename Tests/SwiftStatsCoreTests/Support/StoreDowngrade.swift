//
//  StoreDowngrade.swift
//  SwiftStatsCoreTests
//
//  SQL that takes a store back to before migration v4 (M5), so tests can
//  check that a store written by an earlier SwiftStats migrates. Each
//  later migration has to be undone before an earlier one, or GRDB would
//  run the earlier one again with the later one still recorded.
//

/// Statements undoing store migrations.
enum StoreDowngrade {
    /// The tables v4 adds.
    static let coverageTables = [
        "coverageRun", "functionCoverage", "coverageAttachment", "coverageLine", "coverageUnmapped"
    ]
    /// The columns v4 adds to `function`.
    static let functionColumns = ["access", "typePath", "typeFile"]

    /// Statements dropping what v4 adds and forgetting it ran, leaving
    /// `user_version` for the caller to set.
    static let undoingVersion4 = coverageTables.map { "DROP TABLE \($0)" }
        + functionColumns.map { "ALTER TABLE function DROP COLUMN \($0)" }
        + ["DELETE FROM grdb_migrations WHERE identifier = 'v4'"]
}
