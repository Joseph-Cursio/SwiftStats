//
//  DependencyReport.swift
//  SwiftStatsCore
//
//  A package's dependencies (PRD §7.14): what `Package.swift` declares,
//  what `Package.resolved` pins, and the resolved graph.
//

/// Direct dependencies, pins and the resolved graph.
public struct DependencyReport: Codable, Hashable, Sendable {
    /// What `Package.swift` declares, sorted by identity.
    public let direct: [DescribedDependency]
    /// `Package.resolved`'s pins; nil when the package has none.
    public let lockfile: Lockfile?
    /// The resolved graph; nil when the `dependencies` collector didn't run
    /// (its status says why).
    public let resolved: ResolvedGraph?

    /// Creates a report. Fields are documented on their properties.
    public init(direct: [DescribedDependency], lockfile: Lockfile?, resolved: ResolvedGraph?) {
        self.direct = direct
        self.lockfile = lockfile
        self.resolved = resolved
    }
}
