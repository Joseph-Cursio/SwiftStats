//
//  StoredIndex.swift
//  SwiftStatsCore
//
//  A snapshot's index results read back from the store's v6 rows (M7,
//  design §9.1): the report as the scan JSON holds it, and when the build
//  it was read from ran, which a scan carrying it keeps.
//

/// A snapshot's index results and when they were collected.
public struct StoredIndex: Hashable, Sendable {
    /// When the T1 build ran.
    public let collectedAt: String
    /// The index results.
    public let report: IndexReport

    /// Creates stored index results. Fields are documented on their
    /// properties.
    public init(collectedAt: String, report: IndexReport) {
        self.collectedAt = collectedAt
        self.report = report
    }
}
