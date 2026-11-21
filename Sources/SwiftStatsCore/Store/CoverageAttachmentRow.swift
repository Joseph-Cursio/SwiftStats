//
//  CoverageAttachmentRow.swift
//  SwiftStatsCore
//
//  The `coverageAttachment` table (store v4, M5): one row per type or file
//  of a snapshot with coverage outside every function record.
//

import GRDB

/// Coverage attached to one type or file in a snapshot.
struct CoverageAttachmentRow: Codable, FetchableRecord, PersistableRecord {
    /// The table name.
    static let databaseTableName = "coverageAttachment"

    /// The snapshot.
    var snapshotId: Int64
    /// The type as `TypeOwner` names it, or the file's path.
    var owner: String
    /// `type` or `file`.
    var attachedTo: FindingTarget
    /// Lines that ran.
    var lineCovered: Int
    /// Lines.
    var lineTotal: Int
    /// Regions that ran.
    var regionCovered: Int
    /// Regions.
    var regionTotal: Int

    /// The attachment this row records.
    var attachment: CoverageAttachment {
        CoverageAttachment(
            owner: owner,
            attachedTo: attachedTo,
            lines: CoverageTally(covered: lineCovered, total: lineTotal),
            regions: CoverageTally(covered: regionCovered, total: regionTotal)
        )
    }

    /// The row for `attachment` in snapshot `snapshotId`.
    init(_ attachment: CoverageAttachment, snapshotId: Int64) {
        self.snapshotId = snapshotId
        owner = attachment.owner
        attachedTo = attachment.attachedTo
        lineCovered = attachment.lines.covered
        lineTotal = attachment.lines.total
        regionCovered = attachment.regions.covered
        regionTotal = attachment.regions.total
    }
}
