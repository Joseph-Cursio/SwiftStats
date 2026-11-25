//
//  ReportThresholds.swift
//  SwiftStatsCore
//
//  The thresholds a report was made with (report schema 5, M6 design §8):
//  the share of candidates each ranked signal keeps, and every limit of
//  the mutation signals and, from M7, of hidden coupling in effect,
//  configured or default. Genuinely
//  under-tested's ratio is listed only when the configuration sets it,
//  since it has no default. The signals' rule texts state the same
//  numbers; these let a reader or a checker see them without parsing.
//

/// The thresholds a report used.
public struct ReportThresholds: Codable, Hashable, Sendable {
    /// The percent of candidates each ranked signal keeps, by signal name.
    public let percents: [String: Double]
    /// Each limit-taking signal's limits in effect, by signal name, then
    /// limit.
    public let limits: [String: [String: Double]]

    /// The thresholds `thresholds` puts in effect.
    init(_ thresholds: SignalThresholds) {
        var ranked: [String: Double] = [:]
        for signal in SignalThresholds.rankedSignals {
            ranked[signal] = thresholds.percent(for: signal)
        }
        var effective: [String: [String: Double]] = [:]
        for (signal, kinds) in SignalThresholds.limitKinds {
            for name in kinds.keys {
                if let value = thresholds.limit(name, of: signal) {
                    effective[signal, default: [:]][name] = value
                }
            }
        }
        percents = ranked
        limits = effective
    }
}
