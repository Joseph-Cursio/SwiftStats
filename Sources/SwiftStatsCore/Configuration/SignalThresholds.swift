//
//  SignalThresholds.swift
//  SwiftStatsCore
//
//  `signals:` in `.swiftstats.yml` (PRD §8, §10.1): the share of candidates
//  a ranked signal keeps. Read when a report is made, so they can be tuned
//  without rescanning; reports print the thresholds they used.
//

/// The membership thresholds of the ranked signals.
public struct SignalThresholds: Hashable, Sendable {
    /// The signals that take a threshold.
    static let rankedSignals: Set<String> = ["hotspot", "bug-prone"]
    /// The default percent of candidates a ranked signal keeps.
    public static let defaultPercent = 10.0

    /// Percent of candidates kept, by signal name; absent means the default.
    public let percents: [String: Double]

    /// Thresholds. `percents` is documented on its property.
    public init(percents: [String: Double] = [:]) {
        self.percents = percents
    }

    /// The percent of candidates `signal` keeps.
    public func percent(for signal: String) -> Double {
        percents[signal] ?? Self.defaultPercent
    }
}
