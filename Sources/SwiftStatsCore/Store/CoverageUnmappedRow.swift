//
//  CoverageUnmappedRow.swift
//  SwiftStatsCore
//
//  The `coverageUnmapped` table (store v4, M5): one row per export entry
//  of a snapshot that no record, type or file took, in the report's order.
//

import GRDB

/// One unmapped entry in a snapshot.
struct CoverageUnmappedRow: Codable, FetchableRecord, PersistableRecord {
    /// The table name.
    static let databaseTableName = "coverageUnmapped"

    /// The snapshot.
    var snapshotId: Int64
    /// The entry's position in the report, from 0.
    var ordinal: Int
    /// The file.
    var file: String
    /// The line of its first region's start.
    var startLine: Int
    /// The column of its first region's start.
    var startColumn: Int
    /// The line of its first region's end.
    var endLine: Int
    /// The column of its first region's end, exclusive.
    var endColumn: Int
    /// How often it was entered; `Int64.max` when saturated.
    var count: Int64
    /// The mangled name.
    var name: String
    /// The demangled name; null when demangling failed.
    var demangled: String?
    /// Why it is unmapped.
    var reason: String

    /// The entry this row records.
    var entry: CoverageUnmapped {
        CoverageUnmapped(
            file: file,
            startLine: startLine,
            startColumn: startColumn,
            endLine: endLine,
            endColumn: endColumn,
            count: count,
            name: name,
            demangled: demangled,
            reason: reason
        )
    }

    /// The row for `entry`, the `ordinal`th of the report, in snapshot
    /// `snapshotId`.
    init(_ entry: CoverageUnmapped, ordinal: Int, snapshotId: Int64) {
        self.snapshotId = snapshotId
        self.ordinal = ordinal
        file = entry.file
        startLine = entry.startLine
        startColumn = entry.startColumn
        endLine = entry.endLine
        endColumn = entry.endColumn
        count = entry.count
        name = entry.name
        demangled = entry.demangled
        reason = entry.reason
    }
}
