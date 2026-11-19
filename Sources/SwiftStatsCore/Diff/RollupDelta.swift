//
//  RollupDelta.swift
//  SwiftStatsCore
//
//  A roll-up number that changed between two snapshots (PRD §6.6).
//

/// One changed number in a module's or the project's roll-up.
public struct RollupDelta: Codable, Hashable, Sendable {
    /// Module or project.
    public let scope: RollupScope
    /// The module, or the project part (`production`, `tests`).
    public let name: String
    /// The collector the number comes from.
    public let collector: String
    /// The change.
    public let delta: MetricDelta
}
