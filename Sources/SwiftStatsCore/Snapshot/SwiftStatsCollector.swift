//
//  SwiftStatsCollector.swift
//  SwiftStatsCore
//
//  SwiftStats as a collector in its own snapshots (PRD §6.2): its name and
//  the options that change what it measures.
//

/// SwiftStats' own collector.
public enum SwiftStatsCollector {
    /// Its name in snapshots and diffs.
    public static let name = "swiftstats"

    /// The effective `excluded` and `generated` globs, each list sorted, and
    /// whether SwiftLint-compatible complexity skips `case` statements, since
    /// each changes what SwiftStats measures.
    static func options(configuration: SwiftStatsConfiguration, metrics: MetricsInfo) -> [String] {
        configuration.excluded.sorted().map { "excluded: \($0)" }
            + configuration.generated.sorted().map { "generated: \($0)" }
            + ["swiftlint ignores case statements: \(metrics.swiftLintIgnoresCaseStatements)"]
    }
}
