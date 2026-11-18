//
//  DependencyPin.swift
//  SwiftStatsCore
//
//  One pin from `Package.resolved` (PRD §7.14): a flat list of remote
//  packages, with no edges and no direct or transitive flag.
//

/// A pinned package.
public struct DependencyPin: Codable, Hashable, Sendable {
    /// SwiftPM's identity for the package.
    public let identity: String
    /// Where it comes from.
    public let location: String
    /// The pinned version, when it is pinned to one.
    public let version: String?
    /// The pinned branch, when it is pinned to one.
    public let branch: String?
    /// The pinned revision.
    public let revision: String?

    /// Creates a pin. Fields are documented on their properties.
    public init(identity: String, location: String, version: String?, branch: String?, revision: String?) {
        self.identity = identity
        self.location = location
        self.version = version
        self.branch = branch
        self.revision = revision
    }
}
