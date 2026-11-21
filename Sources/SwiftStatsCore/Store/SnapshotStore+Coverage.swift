//
//  SnapshotStore+Coverage.swift
//  SwiftStatsCore
//
//  Reading the coverage a snapshot holds for a rescan that may carry it
//  (M5, design §6). Only the snapshot's metadata, its coverage rows and its
//  production records' keys and lines are read, and the report blob only
//  for the warnings mapping the coverage gave, when there is coverage, so a
//  plain scan stays fast.
//

import Foundation
import GRDB

extension SnapshotStore {
    /// The part of a stored report a carry reads: its warnings.
    private struct StoredWarnings: Decodable {
        /// The report's warnings.
        let warnings: [ScanWarning]
    }

    /// The warnings mapping coverage gave among snapshot `id`'s report's
    /// warnings, read in `database`, in the report's order.
    private static func coverageWarnings(id: Int64, in database: Database) throws -> [ScanWarning] {
        guard let row = try ReportRow.filter(Column("snapshotId") == id).fetchOne(database) else {
            throw StoreError.noSnapshot("id \(id)")
        }
        guard row.encoding == ReportCompression.encoding else {
            throw StoreError.corruptReport("unknown encoding \(row.encoding)")
        }
        let json = try ReportCompression.inflate(row.data, length: row.uncompressedLength)
        return try JSONDecoder().decode(StoredWarnings.self, from: json).warnings
            .filter(PackageScanner.coverageMappingWarnings.contains)
    }

    /// The coverage snapshot `id` holds, with its git state, coverage run
    /// and production records' spans, read in `database`; nil when it
    /// holds none: no coverage rows, or a coverage run that didn't run.
    static func heldCoverage(id: Int64, in database: Database) throws -> HeldCoverage? {
        guard let rows = try CoverageRows(id: id, in: database) else {
            return nil
        }
        let snapshot = try info(id: id, in: database)
        guard let run = snapshot.collectors.first(where: { $0.name == CoverageAdapter.name }), run.state == .ran else {
            return nil
        }
        let spans = try Row.fetchAll(
            database,
            sql: "SELECT key, file, startLine, endLine FROM function WHERE snapshotId = ? AND role = ?",
            arguments: [id, CodeRole.production.rawValue]
        )
        .map { row in
            (
                row["key"] as String,
                HeldCoverage.Span(file: row["file"], startLine: row["startLine"], endLine: row["endLine"])
            )
        }
        return HeldCoverage(
            git: snapshot.git,
            run: run,
            coverage: try rows.stored,
            warnings: try coverageWarnings(id: id, in: database),
            spans: Dictionary(spans) { first, _ in first }
        )
    }
}
