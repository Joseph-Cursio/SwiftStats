//
//  DeadCodeRows.swift
//  SwiftStatsCore
//
//  A dead-code report as the store's v6 rows (M7, design §5, §9.1, §9.2):
//  the scan row, every entry of both outskirts runs (dropped classes
//  included), each covered record and each module's dead lines per run.
//  The dropped counts follow from the entries' classes, so they aren't
//  stored. The rows hold the report whole, and it is put back together in
//  the scan JSON's order, so a scan builds its dead-code results through
//  them (`normalized(_:)`): a fresh scan and a carried one can't give
//  different JSON. The store writes them with the snapshot and reads them
//  back (`SnapshotStore+Index`).
//

import GRDB

/// A dead-code report's rows.
struct DeadCodeRows: Equatable {
    /// The scan row.
    let scan: DeadScanRow
    /// Every entry of both runs.
    let declarations: [DeadDeclarationRow]
    /// Each covered record, per run.
    let records: [DeadRecordRow]
    /// Each module's dead lines, per run.
    let lines: [DeadLinesRow]

    /// The stored dead-code results these rows hold; it throws a damaged
    /// store when a column doesn't read, never reading it as nothing.
    var stored: StoredDeadCode {
        get throws {
            do {
                return StoredDeadCode(collectedAt: scan.collectedAt, report: try report())
            } catch {
                throw StoreError.corruptReport("the dead-code rows of snapshot \(scan.snapshotId)")
            }
        }
    }

    /// The rows of `report`, collected at `collectedAt`, in snapshot
    /// `snapshotId`.
    init(_ report: DeadCodeReport, collectedAt: String, snapshotId: Int64) {
        scan = DeadScanRow(report, collectedAt: collectedAt, snapshotId: snapshotId)
        declarations = report.declarations.map { DeadDeclarationRow($0, snapshotId: snapshotId) }
        records = report.records.map { DeadRecordRow($0, snapshotId: snapshotId) }
        lines = Self.lines(of: report, snapshotId: snapshotId)
    }

    /// Snapshot `id`'s rows, read in `database`; nil when it holds no
    /// dead-code results. A column that doesn't decode as its row's type
    /// throws a damaged store, as `stored` does.
    init?(id: Int64, in database: Database) throws {
        let mine = Column("snapshotId") == id
        do {
            guard let scanRow = try DeadScanRow.filter(mine).fetchOne(database) else {
                return nil
            }
            scan = scanRow
            declarations = try DeadDeclarationRow.filter(mine).fetchAll(database)
            records = try DeadRecordRow.filter(mine).fetchAll(database)
            lines = try DeadLinesRow.filter(mine).fetchAll(database)
        } catch is RowDecodingError {
            throw StoreError.corruptReport("the dead-code rows of snapshot \(id)")
        } catch is DecodingError {
            throw StoreError.corruptReport("the dead-code rows of snapshot \(id)")
        }
    }

    /// `report` as its rows read it back. The rows always hold it whole;
    /// should they somehow not read back, `report` stands.
    static func normalized(_ report: DeadCodeReport) -> DeadCodeReport {
        (try? Self(report, collectedAt: "", snapshotId: 0).report()) ?? report
    }

    /// The dead-lines rows of `report` in snapshot `snapshotId`, in the
    /// order they are inserted: runs as `DeadCodeRun.ordered` gives them
    /// (roots first), then any other run name in code point order, each
    /// run's modules in code point order. A dictionary's own order changes
    /// from one process to the next, so identical scans would write rows
    /// in different orders.
    private static func lines(of report: DeadCodeReport, snapshotId: Int64) -> [DeadLinesRow] {
        let known = DeadCodeRun.ordered.map(\.rawValue)
        let others = report.deadLines.keys.filter { !known.contains($0) }.sorted(by: CodePointOrder.precedes)
        return (known + others).flatMap { run in
            (report.deadLines[run] ?? [:])
                .sorted { CodePointOrder.precedes($0.key, $1.key) }
                .map { module, count in
                    DeadLinesRow(run: run, module: module, lines: count, snapshotId: snapshotId)
                }
        }
    }

    /// The position of `run` in the report's order: roots first.
    private static func position(of run: DeadCodeRun) -> Int {
        DeadCodeRun.ordered.firstIndex(of: run) ?? DeadCodeRun.ordered.count
    }

    /// The report these rows hold, in the scan JSON's order, as
    /// `DeadCodeMapper` writes it: entries by run, roots first, then
    /// ordinal; covered records by run, then key in code point order; the
    /// dropped counts of each run's entries and each run's dead lines, for
    /// both runs. It throws when a column doesn't read.
    func report() throws -> DeadCodeReport {
        let entries = try declarations.map { try $0.declaration }.sorted { lhs, rhs in
            (Self.position(of: lhs.run), lhs.ordinal) < (Self.position(of: rhs.run), rhs.ordinal)
        }
        let covered = try records.map { try $0.record }.sorted { lhs, rhs in
            let (left, right) = (Self.position(of: lhs.run), Self.position(of: rhs.run))
            return left == right ? CodePointOrder.precedes(lhs.key, rhs.key) : left < right
        }
        let counted = try lines.map { row in
            (run: try RowJSON.named(DeadCodeRun.self, from: row.run), module: row.module, lines: row.lines)
        }
        var dropped: [String: DeadCodeDropped] = [:]
        var deadLines: [String: [String: Int]] = [:]
        for run in DeadCodeRun.ordered {
            dropped[run.rawValue] = DeadCodeDropped(entries.filter { $0.run == run }.map(\.entryClass))
            deadLines[run.rawValue] = Dictionary(
                counted.filter { $0.run == run }.map { ($0.module, $0.lines) }
            ) { first, _ in first }
        }
        return DeadCodeReport(
            version: scan.version,
            runs: scan.runs,
            declarations: entries,
            records: covered,
            dropped: dropped,
            deadLines: deadLines
        )
    }

    /// Inserts the rows in `database`.
    func insert(_ database: Database) throws {
        try scan.insert(database)
        for row in declarations {
            try row.insert(database)
        }
        for row in records {
            try row.insert(database)
        }
        for row in lines {
            try row.insert(database)
        }
    }
}
