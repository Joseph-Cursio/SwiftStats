//
//  TrendReport.swift
//  SwiftStatsCore
//
//  `swiftstats trend <metric>` (PRD §10): one roll-up number over the clean
//  snapshots of HEAD's first-parent commits, oldest first. A point where
//  the number's collector, or SwiftStats itself, ran a different build or
//  options from the point before is marked as a break (PRD §13). A keyed
//  count (findings by rule, side-effect records by tier, law pairs by state,
//  …) reads 0 where its collector ran and the roll-up is there, once some
//  point stores it there, as `diff` reads it, so a count falling to zero
//  isn't shown as not collected, and one never collected there isn't 0.
//

/// A metric over time.
public struct TrendReport: Codable, Hashable, Sendable {
    /// The version of this document's format.
    public static let currentSchemaVersion = 1

    /// The document's format version.
    public let schemaVersion: Int
    /// The package.
    public let package: String
    /// The roll-up number's path, such as `cognitive.median`.
    public let metric: String
    /// Whether the roll-up is a module's or a project part's.
    public let scope: RollupScope
    /// The module or project part (`production` or `tests`).
    public let name: String
    /// The points, oldest first.
    public let points: [TrendPoint]
    /// Clean snapshots of commits off HEAD's first-parent line, not shown.
    public let offLine: Int
}
