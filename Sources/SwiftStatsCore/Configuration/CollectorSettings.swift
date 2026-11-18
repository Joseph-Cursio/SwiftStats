//
//  CollectorSettings.swift
//  SwiftStatsCore
//
//  One `collectors.<name>` entry of `.swiftstats.yml` (PRD §10.1).
//

/// How `.swiftstats.yml` configures one collector.
public struct CollectorSettings: Hashable, Sendable {
    /// Whether the collector runs (`enabled`, default true).
    public let enabled: Bool
    /// The tool's executable (`path`), relative to the package root or
    /// absolute; nil to look it up on PATH.
    public let path: String?

    /// Settings. Fields are documented on their properties.
    public init(enabled: Bool, path: String?) {
        self.enabled = enabled
        self.path = path
    }
}
