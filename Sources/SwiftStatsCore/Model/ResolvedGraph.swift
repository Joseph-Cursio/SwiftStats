//
//  ResolvedGraph.swift
//  SwiftStatsCore
//
//  The resolved dependency graph (PRD §7.14).
//

/// Every package in the resolved graph.
public struct ResolvedGraph: Codable, Hashable, Sendable {
    /// The packages, each once, sorted by identity.
    public let packages: [ResolvedDependency]

    /// Creates a graph. Fields are documented on their properties.
    public init(packages: [ResolvedDependency]) {
        self.packages = packages
    }
}
