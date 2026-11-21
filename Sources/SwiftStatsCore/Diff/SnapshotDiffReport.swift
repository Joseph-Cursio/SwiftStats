//
//  SnapshotDiffReport.swift
//  SwiftStatsCore
//
//  `swiftstats diff` (PRD §6.6, §10): what changed between two snapshots.
//

/// The difference between two snapshots.
public struct SnapshotDiffReport: Codable, Hashable, Sendable {
    /// The version of this document's format: 2 adds records' coverage
    /// percentages and the test bundles that changed (M5).
    public static let currentSchemaVersion = 2

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
    /// collected.
    public var isEmpty: Bool {
        families.isEmpty && functions.isEmpty && rollups.isEmpty && bundles == nil
            && collectors.allSatisfy { $0.outcome != .notComparable }
    }
}
