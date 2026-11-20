//
//  CloneInstanceRow.swift
//  SwiftStatsCore
//
//  The `cloneInstance` table (store v3, PRD §7.12): one row per copy in a
//  clone class, with both ends inclusive; `wholes` is newline-joined.
//

import GRDB

/// One copy in a clone class of a snapshot.
struct CloneInstanceRow: Codable, FetchableRecord, PersistableRecord {
    /// The table name.
    static let databaseTableName = "cloneInstance"

    /// The snapshot.
    var snapshotId: Int64
    /// The class's number.
    var classOrdinal: Int
    /// The copy's position in its class, from 1.
    var ordinal: Int
    /// The file.
    var file: String
    /// The first line.
    var startLine: Int
    /// The first column.
    var startColumn: Int
    /// The last line.
    var endLine: Int
    /// The last column.
    var endColumn: Int
    /// Lines in the copy that hold a token.
    var strippedLines: Int
    /// Key of the innermost function record holding the copy.
    var containing: String?
    /// Keys of the records the copy covers whole, one per line.
    var wholes: String

    /// The copy this row records.
    var instance: CloneInstance {
        CloneInstance(
            file: file,
            range: SourceSpan(
                start: SourcePosition(line: startLine, column: startColumn),
                end: SourcePosition(line: endLine, column: endColumn)
            ),
            strippedLines: strippedLines,
            containing: containing,
            wholes: wholes.split(separator: "\n").map(String.init)
        )
    }

    /// The row for `instance`, the `ordinal`th copy of class
    /// `classOrdinal`, in snapshot `snapshotId`.
    init(_ instance: CloneInstance, classOrdinal: Int, ordinal: Int, snapshotId: Int64) {
        self.snapshotId = snapshotId
        self.classOrdinal = classOrdinal
        self.ordinal = ordinal
        file = instance.file
        startLine = instance.range.start.line
        startColumn = instance.range.start.column
        endLine = instance.range.end.line
        endColumn = instance.range.end.column
        strippedLines = instance.strippedLines
        containing = instance.containing
        wholes = instance.wholes.joined(separator: "\n")
    }
}
