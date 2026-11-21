//
//  StoredCoverage.swift
//  SwiftStatsCore
//
//  A snapshot's coverage read back from the store's v4 tables (M5): the
//  report as the scan JSON holds it, and when the tests ran.
//

/// A snapshot's coverage and when it was collected.
public struct StoredCoverage: Hashable, Sendable {
    /// When the coverage was collected: the date of the scan that ran the
    /// tests, which a scan carrying the coverage keeps.
    public let collectedAt: String
    /// The coverage.
    public let report: CoverageReport

    /// Creates stored coverage. Fields are documented on their properties.
    public init(collectedAt: String, report: CoverageReport) {
        self.collectedAt = collectedAt
        self.report = report
    }
}
