//
//  CoverageBundleChange.swift
//  SwiftStatsCore
//
//  The test bundles that came or went between two snapshots holding
//  coverage (M5). Which test targets exist is tree content, not a setting
//  of the tool, so a change is shown as a fact beside the coverage deltas
//  rather than making coverage not comparable.
//

/// Test bundles added and removed.
public struct CoverageBundleChange: Codable, Hashable, Sendable {
    /// Bundles only in the newer snapshot, sorted.
    public let added: [String]
    /// Bundles only in the older snapshot, sorted.
    public let removed: [String]

    /// The change from `old`'s bundles to `new`'s; nil when either holds
    /// no coverage or the bundles are the same.
    init?(old: StoredCoverage?, new: StoredCoverage?) {
        guard let old, let new else {
            return nil
        }
        let before = Set(old.report.bundles)
        let after = Set(new.report.bundles)
        guard before != after else {
            return nil
        }
        added = after.subtracting(before).sorted()
        removed = before.subtracting(after).sorted()
    }
}
