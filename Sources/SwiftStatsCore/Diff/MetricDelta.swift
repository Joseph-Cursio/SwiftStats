//
//  MetricDelta.swift
//  SwiftStatsCore
//
//  One metric's change between two snapshots (PRD §6.6).
//

/// A metric's value before and after, and which way is better.
public struct MetricDelta: Codable, Hashable, Sendable {
    /// The metric's name or roll-up path.
    public let metric: String
    /// The older value; nil when it wasn't there.
    public let before: Double?
    /// The newer value; nil when it isn't there.
    public let after: Double?
    /// Which way is better.
    public let direction: MetricDirection

    /// Whether the change made things better, worse, or neither.
    public var verdict: DeltaVerdict {
        guard let before, let after, direction != .neutral else {
            return .neutral
        }
        return (after < before) == (direction == .lowerIsBetter) ? .better : .worse
    }

    /// The delta of `metric` from `before` to `after`.
    public init(metric: String, before: Double?, after: Double?) {
        self.metric = metric
        self.before = before
        self.after = after
        direction = MetricDirection.of(metric)
    }
}
