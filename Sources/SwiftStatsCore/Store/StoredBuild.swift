//
//  StoredBuild.swift
//  SwiftStatsCore
//
//  A snapshot's T1 build results read back from the store's v6 rows (M7,
//  design §9.1): the report as the scan JSON holds it, and when the build
//  ran, which a scan carrying it keeps. Its warnings are the snapshot's
//  `swiftc` findings.
//

/// A snapshot's build results and when they were collected.
public struct StoredBuild: Hashable, Sendable {
    /// When the T1 build ran.
    public let collectedAt: String
    /// The build results.
    public let report: BuildReport

    /// Creates stored build results. Fields are documented on their
    /// properties.
    public init(collectedAt: String, report: BuildReport) {
        self.collectedAt = collectedAt
        self.report = report
    }
}
