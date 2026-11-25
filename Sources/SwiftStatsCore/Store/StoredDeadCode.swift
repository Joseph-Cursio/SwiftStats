//
//  StoredDeadCode.swift
//  SwiftStatsCore
//
//  A snapshot's dead-code results read back from the store's v6 rows (M7,
//  design §9.1): the report as the scan JSON holds it, and when outskirts
//  ran over the T1 build's store, which a scan carrying it keeps.
//

/// A snapshot's dead-code results and when they were collected.
public struct StoredDeadCode: Hashable, Sendable {
    /// When outskirts ran.
    public let collectedAt: String
    /// The dead-code results.
    public let report: DeadCodeReport

    /// Creates stored dead-code results. Fields are documented on their
    /// properties.
    public init(collectedAt: String, report: DeadCodeReport) {
        self.collectedAt = collectedAt
        self.report = report
    }
}
