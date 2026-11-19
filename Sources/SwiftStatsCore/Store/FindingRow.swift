//
//  FindingRow.swift
//  SwiftStatsCore
//
//  The `finding` table (PRD §9): one row per finding location.
//

import GRDB

/// One location of one finding in a snapshot.
public struct FindingRow: Codable, Hashable, Sendable, FetchableRecord, PersistableRecord {
    /// The table name.
    public static let databaseTableName = "finding"

    /// The snapshot.
    var snapshotId: Int64
    /// The tool.
    public var tool: String
    /// The rule.
    public var rule: String
    /// Census or defect.
    public var kind: FindingKind
    /// The tool's severity.
    public var severity: String
    /// The message.
    public var message: String
    /// The file.
    public var file: String
    /// The line, when given.
    public var line: Int?
    /// The column, when given.
    public var column: Int?
    /// What the location attaches to.
    public var attachedTo: FindingTarget
    /// The function's key or the type's name, when attached to one.
    public var owner: String?

    /// The rows for each location of `finding` in snapshot `snapshotId`.
    static func rows(for finding: Finding, snapshotId: Int64) -> [Self] {
        finding.locations.map { location in
            Self(
                snapshotId: snapshotId,
                tool: finding.tool,
                rule: finding.rule,
                kind: finding.kind,
                severity: finding.severity,
                message: finding.message,
                file: location.file,
                line: location.line,
                column: location.column,
                attachedTo: location.attachedTo,
                owner: location.owner
            )
        }
    }
}
