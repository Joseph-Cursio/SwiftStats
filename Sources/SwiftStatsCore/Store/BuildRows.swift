//
//  BuildRows.swift
//  SwiftStatsCore
//
//  A build report as the store's v6 rows (M7, design §6.4, §9.1, §9.2):
//  the scan row, each type or file attachment, and each timed record's
//  milliseconds and slowest expression, which are `function` columns
//  (`FunctionRow+Index`). The warnings are `finding` rows of tool `swiftc`
//  and aren't part of the block. The rows hold the report whole, and it is
//  put back together in the scan JSON's order, so a scan builds its build
//  results through them (`normalized(_:)`): a fresh scan and a carried one
//  can't give different JSON. The store writes them with the snapshot and
//  reads them back (`SnapshotStore+Index`).
//

import GRDB

/// A build report's rows.
struct BuildRows: Equatable {
    /// The timed records' `function` columns.
    private static let recordColumns = """
        SELECT key, typeCheckMilliseconds, slowestExpressionMilliseconds FROM function
        WHERE snapshotId = ? AND (typeCheckMilliseconds IS NOT NULL OR slowestExpressionMilliseconds IS NOT NULL)
        """

    /// The scan row.
    let scan: BuildScanRow
    /// Each timed record: the `function` columns.
    let records: [BuildRecordTiming]
    /// Each type or file attachment.
    let attachments: [TimingAttachmentRow]

    /// The stored build results these rows hold.
    var stored: StoredBuild {
        StoredBuild(collectedAt: scan.collectedAt, report: report())
    }

    /// The rows of `report`, collected at `collectedAt`, in snapshot
    /// `snapshotId`. A record holding neither figure isn't timed, so it
    /// has no columns to keep.
    init(_ report: BuildReport, collectedAt: String, snapshotId: Int64) {
        scan = BuildScanRow(report, collectedAt: collectedAt, snapshotId: snapshotId)
        records = report.records.filter { $0.milliseconds != nil || $0.slowestExpression != nil }
        attachments = report.attachments.map { TimingAttachmentRow($0, snapshotId: snapshotId) }
    }

    /// Snapshot `id`'s rows, read in `database`; nil when it holds no
    /// build results. A column that doesn't decode as its row's type
    /// throws a damaged store.
    init?(id: Int64, in database: Database) throws {
        let mine = Column("snapshotId") == id
        do {
            guard let scanRow = try BuildScanRow.filter(mine).fetchOne(database) else {
                return nil
            }
            scan = scanRow
            records = try Row.fetchAll(database, sql: Self.recordColumns, arguments: [id]).map { row in
                BuildRecordTiming(
                    key: row["key"],
                    milliseconds: row["typeCheckMilliseconds"],
                    slowestExpression: row["slowestExpressionMilliseconds"]
                )
            }
            attachments = try TimingAttachmentRow.filter(mine).fetchAll(database)
        } catch is RowDecodingError {
            throw StoreError.corruptReport("the build rows of snapshot \(id)")
        } catch is DecodingError {
            throw StoreError.corruptReport("the build rows of snapshot \(id)")
        }
    }

    /// `report` as its rows read it back.
    static func normalized(_ report: BuildReport) -> BuildReport {
        Self(report, collectedAt: "", snapshotId: 0).report()
    }

    /// `report`'s timed records by key, as the snapshot's function rows
    /// take them.
    static func byKey(_ report: BuildReport) -> [String: BuildRecordTiming] {
        Dictionary(report.records.map { ($0.key, $0) }) { first, _ in first }
    }

    /// The report these rows hold, in the scan JSON's order: records by
    /// key, attachments by what they attach to, then owner, as
    /// `TimingMapper` sorts them.
    func report() -> BuildReport {
        scan.report(
            records: records.sorted { $0.key < $1.key },
            attachments: attachments.map(\.attachment)
                .sorted { ($0.attachedTo.rawValue, $0.owner) < ($1.attachedTo.rawValue, $1.owner) }
        )
    }

    /// Inserts the rows in `database`, all but the records' columns,
    /// which go with the snapshot's function rows.
    func insert(_ database: Database) throws {
        try scan.insert(database)
        for row in attachments {
            try row.insert(database)
        }
    }
}
