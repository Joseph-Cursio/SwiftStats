//
//  SnapshotDiffReport.swift
//  SwiftStatsCore
//
//  `swiftstats diff` (PRD §6.6, §10): what changed between two snapshots.
//

/// The difference between two snapshots.
public struct SnapshotDiffReport: Codable, Hashable, Sendable {
    /// The version of this document's format: 1 is M2's; 2 adds records'
    /// coverage percentages and the test bundles that changed (M5); 3
    /// adds records' mutation figures, the mutation roll-ups and where
    /// each side's mutation results came from (M6); 4 adds the `usr`
    /// match method, the `usr-changed` status with each family's
    /// `usrChanges`, and the index, compiler-warning and dead-code
    /// roll-ups among the deltas (M7).
    public static let currentSchemaVersion = 4

    /// The document's format version.
    public let schemaVersion: Int
    /// The older snapshot.
    public let older: DiffSide
    /// The newer snapshot.
    public let newer: DiffSide
    /// Each collector's comparability, sorted by name.
    public let collectors: [CollectorComparison]
    /// Function families that changed, sorted by key.
    public let families: [FamilyChange]
    /// Matched function records whose metrics changed, sorted by key.
    public let functions: [FunctionDelta]
    /// Roll-up numbers that changed, sorted by scope, name and metric.
    public let rollups: [RollupDelta]
    /// The test bundles added and removed, when both snapshots hold
    /// coverage; nil when neither does, one doesn't, or none changed.
    public let bundles: CoverageBundleChange?
    /// Problems worth knowing about, sorted.
    public let warnings: [String]

    /// Whether nothing changed: no families, no deltas, no test bundles
    /// added or removed, and every collector either compared or not
    /// collected. Where the sides' mutation results came from is a fact,
    /// not a change.
    public var isEmpty: Bool {
        families.isEmpty && functions.isEmpty && rollups.isEmpty && bundles == nil
            && collectors.allSatisfy { $0.outcome != .notComparable }
    }
}
