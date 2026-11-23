//
//  CountedMetrics.swift
//  SwiftStatsCore
//
//  Metrics that are counts keyed by name (findings by rule, functions by
//  kind, side-effect records by tier, law pairs by state, …), where a name
//  missing from one snapshot means zero rather than not collected (PRD
//  §6.5, §6.6). Suggestion counts are absent from a scope holding none, so
//  they read as zero too; clone counts are listed with them, though every
//  production scope has them once SwiftCloneDetector ran. A count's
//  collector must have run in both snapshots for the diff to read it at all.
//  Coverage and mutation numbers are left out on purpose: a missing one
//  was not collected (a record with no coverage data, or no mutant),
//  never zero.
//

/// Which missing metrics read as zero.
enum CountedMetrics {
    /// Path prefixes of counts keyed by name.
    private static let prefixes = [
        "findings.", "findingKinds.", "functions.", "types.", "tests.tests.",
        "api.accessLevels.", "tests.lineRatio.testLinesByKind.", "effects.tier.", "effects.purity.",
        "laws.state.", "properties.", "clones."
    ]

    /// `value`, or zero when it is missing and `metric` is a keyed count.
    static func value(_ value: Double?, metric: String) -> Double? {
        value ?? (prefixes.contains { metric.hasPrefix($0) } ? 0 : nil)
    }
}
