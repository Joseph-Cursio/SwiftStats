//
//  TimingAttachmentRow.swift
//  SwiftStatsCore
//
//  The `timingAttachment` table (store v6, M7, design §6.2, §9.1): one row
//  per type or file of a snapshot holding build results with type-check
//  time outside every function record. Milliseconds are null when only
//  expression entries landed there, the slowest expression when none did.
//

import GRDB

/// Type-check time attached to a type or file, as one row.
struct TimingAttachmentRow: Codable, Equatable, FetchableRecord, PersistableRecord {
    /// The table name.
    static let databaseTableName = "timingAttachment"

    /// The snapshot.
    var snapshotId: Int64
    /// The type or file.
    var owner: String
    /// `type` or `file`.
    var attachedTo: FindingTarget
    /// Its function-body milliseconds.
    var milliseconds: Int?
    /// Its slowest expression's milliseconds.
    var slowestExpressionMilliseconds: Int?

    /// The attachment this row holds.
    var attachment: BuildAttachment {
        BuildAttachment(
            owner: owner,
            attachedTo: attachedTo,
            milliseconds: milliseconds,
            slowestExpression: slowestExpressionMilliseconds
        )
    }

    /// The row for `attachment` in snapshot `snapshotId`.
    init(_ attachment: BuildAttachment, snapshotId: Int64) {
        self.snapshotId = snapshotId
        owner = attachment.owner
        attachedTo = attachment.attachedTo
        milliseconds = attachment.milliseconds
        slowestExpressionMilliseconds = attachment.slowestExpression
    }
}
