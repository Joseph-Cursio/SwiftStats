//
//  FileMeasure.swift
//  SwiftStatsCore
//
//  A file's length (PRD §7.2): physical lines, and lines holding a token.
//

import SwiftSyntax

/// Measures one parsed file.
enum FileMeasure {
    /// The file's record.
    static func record(of file: ParsedFile, module: String) -> FileRecord {
        let converter = SourceLocationConverter(fileName: file.path, tree: file.tree)
        var stripped = Set<Int>()
        for token in file.tree.tokens(viewMode: .sourceAccurate)
        where token.presence == .present && token.tokenKind != .endOfFile {
            let first = converter.location(for: token.positionAfterSkippingLeadingTrivia).line
            let last = converter.location(for: token.endPositionBeforeTrailingTrivia).line
            stripped.formUnion(first...max(first, last))
        }
        return FileRecord(
            path: file.path,
            module: module,
            lines: physicalLines(in: file.source),
            strippedLines: stripped.count
        )
    }

    /// Lines in `source`: one per newline, plus an unterminated last line.
    static func physicalLines(in source: String) -> Int {
        let newlines = source.utf8.reduce(into: 0) { count, byte in
            if byte == UInt8(ascii: "\n") {
                count += 1
            }
        }
        let hasUnterminatedLine = source.isEmpty == false && source.utf8.last != UInt8(ascii: "\n")
        return newlines + (hasUnterminatedLine ? 1 : 0)
    }
}
