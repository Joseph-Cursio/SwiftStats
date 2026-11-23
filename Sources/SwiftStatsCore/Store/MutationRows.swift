//
//  MutationRows.swift
//  SwiftStatsCore
//
//  A mutation report as the store's v5 rows (M6, design §3, §5): its scan
//  row, each run, each path of its tree, each suspect test, and each
//  mutant, dropped and unmapped ones included. The rows hold the report
//  whole: its records, attachments and counts follow from the mutants, so
//  they aren't stored. The report is put back together in the scan JSON's
//  order, and a scan builds its mutation results through the rows
//  (`normalized(_:)`), so a fresh scan, a carried result and a merged one
//  can't give different JSON. The store writes them with the snapshot
//  and reads them back (`SnapshotStore+Rows`).
//

import GRDB

/// A mutation report's rows.
struct MutationRows: Equatable {
    /// The scan row.
    let scan: MutationScanRow
    /// Each run.
    let runs: [MutationRunRow]
    /// Each path of the tree.
    let files: [MutationFileRow]
    /// Each suspect test.
    let suspects: [MutationSuspectRow]
    /// Each mutant, in the report's order.
    let mutants: [MutantRow]

    /// The stored mutation results these rows hold; it throws a damaged
    /// store when a column doesn't read, never reading it as nothing.
    var stored: StoredMutation {
        get throws {
            do {
                return StoredMutation(report: try report())
            } catch {
                throw StoreError.corruptReport("the mutation rows of snapshot \(scan.snapshotId)")
            }
        }
    }

    /// The rows of `report`, in snapshot `snapshotId`.
    init(_ report: MutationReport, snapshotId: Int64) {
        scan = MutationScanRow(report, snapshotId: snapshotId)
        runs = report.runs.map { MutationRunRow($0, snapshotId: snapshotId) }
        files = report.files.map { MutationFileRow($0, snapshotId: snapshotId) }
        suspects = report.suspectTests.map { MutationSuspectRow($0, snapshotId: snapshotId) }
        mutants = report.mutants.enumerated().map { ordinal, mutant in
            MutantRow(mutant, ordinal: ordinal, snapshotId: snapshotId)
        }
    }

    /// The rows given, as the store reads them back.
    init(
        scan: MutationScanRow,
        runs: [MutationRunRow],
        files: [MutationFileRow],
        suspects: [MutationSuspectRow],
        mutants: [MutantRow]
    ) {
        self.scan = scan
        self.runs = runs
        self.files = files
        self.suspects = suspects
        self.mutants = mutants
    }

    /// Snapshot `id`'s rows, read in `database` in the report's order;
    /// nil when it holds no mutation results. A column that doesn't decode
    /// as its row's type (a mode, place or disposition no value is named)
    /// throws a damaged store, as `stored` does.
    init?(id: Int64, in database: Database) throws {
        let mine = Column("snapshotId") == id
        do {
            guard let scanRow = try MutationScanRow.filter(mine).fetchOne(database) else {
                return nil
            }
            scan = scanRow
            runs = try MutationRunRow.filter(mine).order(Column("ordinal")).fetchAll(database)
            files = try MutationFileRow.filter(mine).order(Column("path")).fetchAll(database)
            suspects = try MutationSuspectRow.filter(mine)
                .order(Column("run"), Column("name"), Column("file"))
                .fetchAll(database)
            mutants = try MutantRow.filter(mine).order(Column("ordinal")).fetchAll(database)
        } catch is RowDecodingError {
            throw StoreError.corruptReport("the mutation rows of snapshot \(id)")
        } catch is DecodingError {
            throw StoreError.corruptReport("the mutation rows of snapshot \(id)")
        }
    }

    /// `report` as its rows read it back. The rows always hold it whole;
    /// should they somehow not read back, `report` stands.
    static func normalized(_ report: MutationReport) -> MutationReport {
        (try? Self(report, snapshotId: 0).report()) ?? report
    }

    /// The report these rows hold, in the scan JSON's order: runs by
    /// ordinal, files by path, suspect tests by run, name and file, mutants by
    /// ordinal, and the records, attachments and counts worked out from
    /// the mutants. It throws when a JSON column doesn't read.
    func report() throws -> MutationReport {
        MutationReport(
            collectedAt: scan.collectedAt,
            complete: scan.complete,
            listsNotCovered: scan.listsNotCovered,
            mode: scan.mode,
            base: scan.base,
            files: files.map(\.file),
            runs: try runs.map { try $0.run },
            suspectTests: try suspects.map { try $0.test },
            mutants: try mutants.sorted { $0.ordinal < $1.ordinal }.map { try $0.mutant }
        )
    }

    /// Inserts the rows in `database`.
    func insert(_ database: Database) throws {
        try scan.insert(database)
        for row in runs {
            try row.insert(database)
        }
        for row in files {
            try row.insert(database)
        }
        for row in suspects {
            try row.insert(database)
        }
        for row in mutants {
            try row.insert(database)
        }
    }
}
