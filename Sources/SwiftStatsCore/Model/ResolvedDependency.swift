//
//  ResolvedDependency.swift
//  SwiftStatsCore
//
//  One package in the resolved graph from `swift package show-dependencies`
//  (PRD §7.14).
//

/// A package in the resolved dependency graph.
public struct ResolvedDependency: Codable, Hashable, Sendable {
    /// SwiftPM's identity for the package.
    public let identity: String
    /// Where it comes from.
    public let location: String
    /// The resolved version (`unspecified` for a local path).
    public let version: String
    /// Whether the root package depends on it directly.
    public let direct: Bool
    /// The identities it depends on, sorted.
    public let dependencies: [String]

    /// Creates a package. Fields are documented on their properties.
    public init(identity: String, location: String, version: String, direct: Bool, dependencies: [String]) {
        self.identity = identity
        self.location = location
        self.version = version
        self.direct = direct
        self.dependencies = dependencies
    }
}
