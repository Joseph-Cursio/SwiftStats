//
//  IndexReferences.swift
//  SwiftStatsCore
//
//  A record's referrers in the T1 build's index (M7, design §4.1): the
//  distinct containers of the references that count for it, split by the
//  container's target (the record's own production target, another
//  production target, a test target), and the names of the first five test
//  containers. Only a record with a primary USR has referrers; the scan's
//  `index` block writes them as the record's `references`.
//

/// One record's referrers, by the container's target.
public struct IndexReferences: Codable, Hashable, Sendable {
    /// Distinct containers in the record's own target (a production one).
    public let sameModule: Int
    /// Distinct containers in other production targets: cross-module
    /// fan-in.
    public let otherModules: Int
    /// Distinct containers in test targets.
    public let tests: Int
    /// The first five test containers' names (record keys, or symbol
    /// names for containers that aren't records), sorted in code point
    /// order.
    public let testReferrers: [String]

    /// Creates the referrers. Fields are documented on their properties.
    public init(sameModule: Int, otherModules: Int, tests: Int, testReferrers: [String]) {
        self.sameModule = sameModule
        self.otherModules = otherModules
        self.tests = tests
        self.testReferrers = testReferrers
    }
}
