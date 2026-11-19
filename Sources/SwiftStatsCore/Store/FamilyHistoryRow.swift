//
//  FamilyHistoryRow.swift
//  SwiftStatsCore
//
//  The `familyHistory` table (PRD §9, M3): one row per function family of a
//  snapshot whose history was read. Signals are computed from these rows
//  and the `function` rows. A null number means the family has no history
//  (it exists only in uncommitted changes), never zero.
//

import GRDB

/// One family's history in a snapshot.
public struct FamilyHistoryRow: Codable, Hashable, Sendable, FetchableRecord, PersistableRecord {
    /// The table name.
    public static let databaseTableName = "familyHistory"

    /// The snapshot.
    var snapshotId: Int64
    /// The family's id: its root's key, or a computed property's key.
    public var family: String
    /// The family's file.
    public var file: String
    /// Where it starts.
    public var line: Int
    /// Whether its file is generated.
    public var generated: Bool
    /// Commits in the window that changed it, sweeps aside.
    public var changes: Int?
    /// Sweeps in the window that changed it.
    public var sweepChanges: Int?
    /// Commits that ever changed it.
    public var allChanges: Int?
    /// Fix commits in the window that changed it.
    public var fixes: Int?
    /// Fix commits that ever changed it.
    public var allFixes: Int?
    /// Fix commits weighted by age.
    public var fixScore: Double?
    /// Fixes per change in the window.
    public var fixRate: Double?
    /// Revert commits in the window that touched it.
    public var reverts: Int?
    /// Repeated fixes in the window.
    public var repeatedFixes: Int?
    /// Changes in the window that also changed a matching test file.
    public var testChanges: Int?
    /// Whether a test file matching it by name exists.
    public var hasTests: Bool
    /// When it first appeared.
    public var firstSeen: String?
    /// When it last changed.
    public var lastChanged: String?
    /// How surely its history was traced.
    public var tracedBy: TracedBy

    /// The row for `history` in snapshot `snapshotId`.
    init(_ history: FamilyHistory, snapshotId: Int64) {
        self.snapshotId = snapshotId
        family = history.family
        file = history.file
        line = history.line
        generated = history.generated
        changes = history.changes
        sweepChanges = history.sweepChanges
        allChanges = history.allChanges
        fixes = history.fixes
        allFixes = history.allFixes
        fixScore = history.fixScore
        fixRate = history.fixRate
        reverts = history.reverts
        repeatedFixes = history.repeatedFixes
        testChanges = history.testChanges
        hasTests = history.hasTests
        firstSeen = history.firstSeen
        lastChanged = history.lastChanged
        tracedBy = history.tracedBy
    }
}
