//
//  ReportRow.swift
//  SwiftStatsCore
//
//  The `report` table (PRD §9): the whole scan report, deflated, read only
//  by a build with the same report `schemaVersion`.
//

import Foundation
import GRDB

/// One snapshot's scan report.
struct ReportRow: Codable, FetchableRecord, PersistableRecord {
    /// The table name.
    static let databaseTableName = "report"

    /// The snapshot.
    var snapshotId: Int64
    /// The report's `schemaVersion`.
    var schemaVersion: Int
    /// How `data` is compressed.
    var encoding: String
    /// The report's length uncompressed.
    var uncompressedLength: Int
    /// The compact JSON, compressed.
    var data: Data
}
