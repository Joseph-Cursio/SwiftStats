//
//  CoverageLineRow.swift
//  SwiftStatsCore
//
//  The `coverageLine` table (store v4, M5): one row per kept file of a
//  snapshot holding coverage, with its line data as text. `lines` holds
//  runs `start-end:count`, a `*` after the count marking partly run lines,
//  and `skipped` ranges `start-end`, each comma-separated, in order.
//  Counts are the 64-bit counts the export gives, saturated ones included.
//

import GRDB

/// One kept file's line data in a snapshot.
struct CoverageLineRow: Codable, FetchableRecord, PersistableRecord {
    /// The table name.
    static let databaseTableName = "coverageLine"
    /// Separates runs, and ranges.
    private static let separator: Character = ","
    /// Separates a range's ends.
    private static let rangeSeparator: Character = "-"
    /// Separates a run's range from its count.
    private static let countSeparator: Character = ":"
    /// Marks a partly run run.
    private static let partlyRunMark: Character = "*"
    /// The parts of a range (its ends) and of a run (range and count).
    private static let pairCount = 2

    /// The snapshot.
    var snapshotId: Int64
    /// The file, relative to the package root.
    var file: String
    /// Its runs.
    var lines: String
    /// Its skipped ranges.
    var skipped: String

    /// The row for `file` in snapshot `snapshotId`.
    init(_ file: CoverageFileLines, snapshotId: Int64) {
        self.snapshotId = snapshotId
        self.file = file.file
        lines = file.lines.map { run in
            "\(run.start)\(Self.rangeSeparator)\(run.end)\(Self.countSeparator)\(run.count)"
                + (run.partlyRun ? String(Self.partlyRunMark) : "")
        }
        .joined(separator: String(Self.separator))
        skipped = file.skipped.map { "\($0.start)\(Self.rangeSeparator)\($0.end)" }
            .joined(separator: String(Self.separator))
    }

    /// The range `text` writes as `start-end`; nil when it doesn't.
    private static func range(_ text: Substring) -> CoverageLineRange? {
        let ends = text.split(separator: rangeSeparator, omittingEmptySubsequences: false)
        guard ends.count == pairCount, let start = Int(ends[0]), let end = Int(ends[1]) else {
            return nil
        }
        return CoverageLineRange(start: start, end: end)
    }

    /// The run `text` writes as `start-end:count`, with `*` when partly
    /// run; nil when it doesn't.
    private static func run(_ text: Substring) -> CoverageLineRun? {
        let partlyRun = text.last == partlyRunMark
        let parts = text.dropLast(partlyRun ? 1 : 0).split(separator: countSeparator, omittingEmptySubsequences: false)
        guard parts.count == pairCount, let range = range(parts[0]), let count = Int64(parts[1]) else {
            return nil
        }
        return CoverageLineRun(start: range.start, end: range.end, count: count, partlyRun: partlyRun)
    }

    /// The file's line data this row records; it throws when the text is
    /// damaged.
    func fileLines() throws -> CoverageFileLines {
        let runs = lines.split(separator: Self.separator).map(Self.run)
        let ranges = skipped.split(separator: Self.separator).map(Self.range)
        guard runs.allSatisfy({ $0 != nil }), ranges.allSatisfy({ $0 != nil }) else {
            throw StoreError.corruptReport("the coverage line data of \(file)")
        }
        return CoverageFileLines(file: file, lines: runs.compactMap(\.self), skipped: ranges.compactMap(\.self))
    }
}
