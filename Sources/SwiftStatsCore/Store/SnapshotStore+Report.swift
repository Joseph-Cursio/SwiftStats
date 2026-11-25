//
//  SnapshotStore+Report.swift
//  SwiftStatsCore
//
//  Reading a snapshot's stored scan report (PRD §9): its compressed JSON,
//  refused when another report schema or encoding wrote it, with its
//  history's change-coupling pairs read from the `couplingPair` table,
//  which every scan reading history writes from M7 (design §8.1, §10.1:
//  the pairs are a table, and the report keeps them too).
//

import Foundation
import GRDB

extension SnapshotStore {
    /// Snapshot `id`'s scan report in `database`, its history's pairs
    /// those of the `couplingPair` table.
    static func report(id: Int64, in database: Database) throws -> ScanReport {
        guard let row = try ReportRow.filter(Column("snapshotId") == id).fetchOne(database) else {
            throw StoreError.noSnapshot("id \(id)")
        }
        guard row.schemaVersion == ScanReport.currentSchemaVersion else {
            throw StoreError.reportSchema(stored: row.schemaVersion, current: ScanReport.currentSchemaVersion)
        }
        guard row.encoding == ReportCompression.encoding else {
            throw StoreError.corruptReport("unknown encoding \(row.encoding)")
        }
        let json = try ReportCompression.inflate(row.data, length: row.uncompressedLength)
        var report = try JSONDecoder().decode(ScanReport.self, from: json)
        report.history?.coupling = try CouplingPairRow.filter(Column("snapshotId") == id)
            .order(Column("ordinal"))
            .fetchAll(database)
            .map(\.pair)
        return report
    }
}
