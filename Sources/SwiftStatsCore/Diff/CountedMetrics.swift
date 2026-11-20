//
//  CountedMetrics.swift
//  SwiftStatsCore
//
//  Metrics that are counts keyed by name (findings by rule, functions by
//  kind, side-effect records by tier, law pairs by state, …), where a name
//  missing from one snapshot means zero rather than not collected (PRD
//  §6.5, §6.6). Suggestion counts are absent from a scope holding none, so
//  they read as zero too. A count's collector must have run in both
//  snapshots for the diff to read it at all.
//

/// Which missing metrics read as zero.
enum CountedMetrics {
    /// Path prefixes of counts keyed by name.
    private static let prefixes = [
        "findings.", "findingKinds.", "functions.", "types.", "tests.tests.",
        "api.accessLevels.", "tests.lineRatio.testLinesByKind.", "effects.tier.", "effects.purity.",
        "laws.state.", "properties."
    ]

    /// `value`, or zero when it is missing and `metric` is a keyed count.
    static func value(_ value: Double?, metric: String) -> Double? {
        value ?? (prefixes.contains { metric.hasPrefix($0) } ? 0 : nil)
    }
}
