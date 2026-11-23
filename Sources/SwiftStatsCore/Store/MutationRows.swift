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
//  can't give different JSON. This is the rows' pure part; the store
//  reads and writes them (M6 step 5).
//

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
}
