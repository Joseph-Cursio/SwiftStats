//
//  SnapshotStore+Index.swift
//  SwiftStatsCore
//
//  The T1 group's rows (store v6, M7, design §9.1): a snapshot's index,
//  build and dead-code results are written with it, each block as its
//  rows (`IndexRows`, `BuildRows`, `DeadCodeRows`) and each record's
//  columns with its function row, all three dated when the T1 build ran;
//  and whether a snapshot holds T1 results is read without reading them,
//  so results too damaged to read can still be dropped. A snapshot holds
//  T1 results when its `build` collector ran and it has a `buildScan` row:
//  a build that ran always replaces held T1 results, even when the index
//  or outskirts then failed. A rescan that may carry them reads them back
//  with what the carry is checked against (`HeldIndex`): the blocks from
//  their rows, and the records, types, files, `swiftc` findings and
//  warnings from the stored report, decoded only as far as they go.
//

import Foundation
import GRDB

extension SnapshotStore {
    /// The parts of a stored report a T1 carry reads.
    private struct StoredScanParts: Decodable {
        /// The report's records.
        let records: [FunctionRecord]
        /// The report's type records.
        let types: [TypeRecord]
        /// The report's files.
        let files: [FileRecord]
        /// The report's findings.
        let findings: [Finding]
        /// The report's warnings.
        let warnings: [ScanWarning]
    }

    /// The parts of snapshot `id`'s report a T1 carry reads, read in
    /// `database`; a report that doesn't read throws a damaged store.
    private static func scanParts(id: Int64, in database: Database) throws -> StoredScanParts {
        guard let row = try ReportRow.filter(Column("snapshotId") == id).fetchOne(database) else {
            throw StoreError.noSnapshot("id \(id)")
        }
        guard row.encoding == ReportCompression.encoding else {
            throw StoreError.corruptReport("unknown encoding \(row.encoding)")
        }
        do {
            let json = try ReportCompression.inflate(row.data, length: row.uncompressedLength)
            return try JSONDecoder().decode(StoredScanParts.self, from: json)
        } catch {
            throw StoreError.corruptReport("the report of snapshot \(id)")
        }
    }

    /// The T1 results snapshot `id` holds, with its git state, its three
    /// runs and what carrying them is checked against, read in `database`,
    /// for a rescan that may carry them; nil when it holds none. Rows or a
    /// report too damaged to read, a T1 run missing, or a reader that ran
    /// without its rows (a fresh scan always writes them) throw
    /// `StoreError.corruptReport`.
    static func heldIndex(id: Int64, in database: Database) throws -> HeldIndex? {
        guard try holdsIndex(id: id, in: database), let build = try BuildRows(id: id, in: database) else {
            return nil
        }
        let snapshot = try info(id: id, in: database)
        let run = { (name: String) in snapshot.collectors.first { $0.name == name } }
        guard let buildRun = run(BuildAdapter.name), let indexRun = run(IndexAdapter.name),
              let peripheryRun = run(PeripheryAdapter.name)
        else {
            throw StoreError.corruptReport("the T1 runs of snapshot \(id)")
        }
        let index = try IndexRows(id: id, in: database)?.stored.report
        if indexRun.state == .ran, index == nil {
            throw StoreError.corruptReport("the index rows of snapshot \(id)")
        }
        let deadCode = try DeadCodeRows(id: id, in: database)?.stored.report
        if peripheryRun.state == .ran, deadCode == nil {
            throw StoreError.corruptReport("the dead-code rows of snapshot \(id)")
        }
        let parts = try scanParts(id: id, in: database)
        let hashes = index?.files.map { ($0.path, $0.sha256) } ?? parts.files.map { ($0.path, Optional($0.sha256)) }
        return HeldIndex(
            git: snapshot.git,
            build: buildRun,
            readers: [indexRun, peripheryRun],
            collectedAt: build.scan.collectedAt,
            buildReport: build.stored.report,
            index: index,
            deadCode: deadCode,
            findings: parts.findings.filter { $0.tool == WarningReader.tool },
            warnings: parts.warnings.filter(IndexCarry.describesResults),
            records: HeldIndex.places(of: parts.records),
            types: parts.types.map(HeldIndex.TypeSpan.init),
            files: Dictionary(hashes) { first, _ in first }
        )
    }

    /// Inserts the T1 blocks of `report`, collected at `collectedAt`, as
    /// rows of snapshot `snapshotId` in `database`: each block that is
    /// there, but for the records' columns, which go with the function
    /// rows.
    static func insertIndexRows(
        of report: ScanReport,
        collectedAt: String,
        snapshotId: Int64,
        in database: Database
    ) throws {
        if let index = report.index {
            try IndexRows(index, collectedAt: collectedAt, snapshotId: snapshotId).insert(database)
        }
        if let build = report.build {
            try BuildRows(build, collectedAt: collectedAt, snapshotId: snapshotId).insert(database)
        }
        if let deadCode = report.deadCode {
            try DeadCodeRows(deadCode, collectedAt: collectedAt, snapshotId: snapshotId).insert(database)
        }
    }

    /// Whether snapshot `id` holds T1 results, read in `database`: a
    /// `buildScan` row beside a `build` collector that ran. Nothing of the
    /// results themselves is read.
    static func holdsIndex(id: Int64, in database: Database) throws -> Bool {
        try Bool.fetchOne(
            database,
            sql: """
                SELECT EXISTS (SELECT 1 FROM buildScan WHERE snapshotId = ?)
                    AND EXISTS (SELECT 1 FROM collectorRun WHERE snapshotId = ? AND name = ? AND state = ?)
                """,
            arguments: [id, id, BuildAdapter.name, CollectorState.ran.rawValue]
        ) ?? false
    }
}
