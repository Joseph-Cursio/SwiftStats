//
//  FunctionRow.swift
//  SwiftStatsCore
//
//  The `function` table (PRD §9): one row per function record, with the
//  columns `diff` and trends read.
//

import GRDB

/// One function record in a snapshot.
public struct FunctionRow: Codable, Hashable, Sendable, FetchableRecord, PersistableRecord {
    /// The table name.
    public static let databaseTableName = "function"

    /// The snapshot.
    var snapshotId: Int64
    /// The syntactic key (PRD §6.1).
    public var key: String
    /// The module.
    public var module: String
    /// The declaration kind.
    public var kind: FunctionKind
    /// The declared name.
    public var name: String
    /// For an accessor, its keyword.
    public var accessorKind: String?
    /// The file, relative to the package root.
    public var file: String
    /// The first line.
    public var startLine: Int
    /// The last line.
    public var endLine: Int
    /// The body hash.
    public var bodyHash: String
    /// The enclosing record's key.
    public var parentKey: String?
    /// The `#if` condition.
    public var ifConfig: String?
    /// Production, test or helper.
    public var role: CodeRole
    /// Stripped lines.
    public var strippedLines: Int
    /// Stripped lines of the body alone.
    public var bodyLines: Int
    /// Parameters, for kinds with a parameter list.
    public var parameterCount: Int?
    /// Whether it has a doc comment.
    public var isDocumented: Bool
    /// Whether it is `async`.
    public var isAsync: Bool
    /// Cognitive complexity; nil when unscored.
    public var cognitive: Int?
    /// Decision count; nil when unscored.
    public var decisionCount: Int?
    /// SwiftLint-compatible complexity; nil when SwiftLint doesn't score the kind.
    public var swiftLintCompatible: Int?
    /// Maximum nesting depth; nil when unscored.
    public var maxNesting: Int?

    /// The row for `record` in snapshot `snapshotId`.
    init(_ record: FunctionRecord, snapshotId: Int64) {
        self.snapshotId = snapshotId
        key = record.key
        module = record.module
        kind = record.kind
        name = record.name
        accessorKind = record.accessorKind
        file = record.file
        startLine = record.range.start.line
        endLine = record.range.end.line
        bodyHash = record.bodyHash
        parentKey = record.parentKey
        ifConfig = record.ifConfig
        role = record.role
        strippedLines = record.strippedLines
        bodyLines = record.bodyLines
        parameterCount = record.parameterCount
        isDocumented = record.isDocumented
        isAsync = record.isAsync
        cognitive = record.complexity?.cognitive
        decisionCount = record.complexity?.decisionCount
        swiftLintCompatible = record.complexity.flatMap { $0.swiftLintScored ? $0.swiftLintCompatible : nil }
        maxNesting = record.complexity?.maxNesting
    }
}
