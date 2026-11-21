//
//  CoverageRows.swift
//  SwiftStatsCore
//
//  A coverage report as the store's v4 rows (M5): the run, each record,
//  attachment, kept file and unmapped entry. The rows hold the report
//  whole, and the report is put back together in the scan JSON's order, so
//  a scan builds its coverage through them too: a fresh scan and one that
//  carries stored coverage can't give different JSON.
//

import GRDB

/// A coverage report's rows.
struct CoverageRows {
    /// The run.
    let run: CoverageRunRow
    /// Each record's coverage.
    let records: [FunctionCoverageRow]
    /// Each attachment.
    let attachments: [CoverageAttachmentRow]
    /// Each kept file's line data.
    let lines: [CoverageLineRow]
    /// Each unmapped entry.
    let unmapped: [CoverageUnmappedRow]

    /// The stored coverage these rows hold; it throws when a file's line
    /// data is damaged.
    var stored: StoredCoverage {
        get throws {
            StoredCoverage(collectedAt: run.collectedAt, report: try report())
        }
    }

    /// The rows of `report`, collected at `collectedAt`, in snapshot
    /// `snapshotId`.
    init(_ report: CoverageReport, collectedAt: String, snapshotId: Int64) {
        run = CoverageRunRow(report, collectedAt: collectedAt, snapshotId: snapshotId)
        records = report.records.map { FunctionCoverageRow($0, snapshotId: snapshotId) }
        attachments = report.attachments.map { CoverageAttachmentRow($0, snapshotId: snapshotId) }
        lines = report.files.map { CoverageLineRow($0, snapshotId: snapshotId) }
        unmapped = report.unmapped.enumerated().map { ordinal, entry in
            CoverageUnmappedRow(entry, ordinal: ordinal, snapshotId: snapshotId)
        }
    }

    /// Snapshot `id`'s rows, read in `database`; nil when it holds no
    /// coverage.
    init?(id: Int64, in database: Database) throws {
        let mine = Column("snapshotId") == id
        guard let runRow = try CoverageRunRow.filter(mine).fetchOne(database) else {
            return nil
        }
        run = runRow
        records = try FunctionCoverageRow.filter(mine).fetchAll(database)
        attachments = try CoverageAttachmentRow.filter(mine).fetchAll(database)
        lines = try CoverageLineRow.filter(mine).fetchAll(database)
        unmapped = try CoverageUnmappedRow.filter(mine).order(Column("ordinal")).fetchAll(database)
    }

    /// `report` as its rows read it back. The rows always hold it whole;
    /// should they somehow not read back, `report` stands.
    static func normalized(_ report: CoverageReport) -> CoverageReport {
        (try? Self(report, collectedAt: "", snapshotId: 0).report()) ?? report
    }

    /// The report these rows hold, in the scan JSON's order: records by
    /// key, attachments by what they attach to then owner, unmapped
    /// entries as stored, files by path. It throws when a file's line data
    /// is damaged.
    func report() throws -> CoverageReport {
        CoverageReport(
            records: records.map(\.record).sorted { $0.key < $1.key },
            attachments: attachments.map(\.attachment)
                .sorted { ($0.attachedTo.rawValue, $0.owner) < ($1.attachedTo.rawValue, $1.owner) },
            unmapped: unmapped.sorted { $0.ordinal < $1.ordinal }.map(\.entry),
            dropped: run.dropped,
            bundles: run.bundleNames,
            tests: run.tests,
            saturated: run.saturated,
            files: try lines.map { try $0.fileLines() }.sorted { $0.file < $1.file }
        )
    }

    /// Inserts the rows in `database`.
    func insert(_ database: Database) throws {
        try run.insert(database)
        for row in records {
            try row.insert(database)
        }
        for row in attachments {
            try row.insert(database)
        }
        for row in lines {
            try row.insert(database)
        }
        for row in unmapped {
            try row.insert(database)
        }
    }
}
