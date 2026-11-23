//
//  StoredMutation.swift
//  SwiftStatsCore
//
//  A snapshot's mutation results read back from the store's v5 tables
//  (M6, design §5), as the scan JSON holds them. Unlike coverage, the
//  results carry their own collection date (when the newest run's first
//  session started), so a scan that carries them keeps it with them.
//

/// A snapshot's mutation results.
public struct StoredMutation: Hashable, Sendable {
    /// The results.
    public let report: MutationReport

    /// When the results were collected, as the report records it.
    public var collectedAt: String {
        report.collectedAt
    }

    /// Creates stored mutation results. Fields are documented on their
    /// properties.
    public init(report: MutationReport) {
        self.report = report
    }
}
