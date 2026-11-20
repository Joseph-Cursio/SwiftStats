//
//  CloneClassRow.swift
//  SwiftStatsCore
//
//  The `cloneClass` table (store v3, PRD §7.12): one row per merged clone
//  class; its copies are `cloneInstance` rows.
//

import GRDB

/// One clone class in a snapshot.
struct CloneClassRow: Codable, FetchableRecord, PersistableRecord {
    /// The table name.
    static let databaseTableName = "cloneClass"

    /// The snapshot.
    var snapshotId: Int64
    /// The class's number, from 1.
    var ordinal: Int
    /// The pass that reported it.
    var pass: CloneClass.Pass
    /// Whether a subtree class's copies are token-identical.
    var exact: Bool
    /// The tool's mass.
    var mass: Int
    /// For near-miss, the least similarity between two copies.
    var similarity: Double?
    /// The tool's line span.
    var lineSpan: Int
    /// The tool's fingerprint.
    var fingerprint: String

    /// The row for `clone` in snapshot `snapshotId`.
    init(_ clone: CloneClass, snapshotId: Int64) {
        self.snapshotId = snapshotId
        ordinal = clone.ordinal
        pass = clone.pass
        exact = clone.exact
        mass = clone.mass
        similarity = clone.similarity
        lineSpan = clone.lineSpan
        fingerprint = clone.fingerprint
    }

    /// The class this row records, with `instances` as its copies.
    func clone(instances: [CloneInstance]) -> CloneClass {
        CloneClass(
            ordinal: ordinal,
            pass: pass,
            exact: exact,
            mass: mass,
            similarity: similarity,
            lineSpan: lineSpan,
            fingerprint: fingerprint,
            instances: instances
        )
    }
}
