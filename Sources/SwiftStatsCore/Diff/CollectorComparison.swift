//
//  CollectorComparison.swift
//  SwiftStatsCore
//
//  One collector's comparability in a diff (PRD §6.6).
//

/// Whether one collector's results were compared, and why not.
public struct CollectorComparison: Codable, Hashable, Sendable {
    /// The collector.
    public let name: String
    /// Compared, not comparable or not collected.
    public let outcome: ComparisonOutcome
    /// Why it wasn't compared; nil when it was.
    public let reason: String?
}
