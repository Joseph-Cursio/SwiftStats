//
//  FunctionCoverageRow.swift
//  SwiftStatsCore
//
//  The `functionCoverage` table (store v4, M5): one row per production
//  record of a snapshot holding coverage. Lines and regions are null for a
//  record with no coverage data, which carries its reason instead, and for
//  a subscript whose accessors carry the coverage; `link` and
//  `linkedTests` are null for what isn't a public function, and
//  `linkedTests` also for a witness. `testTargets` is newline-joined.
//

import GRDB

/// One record's coverage in a snapshot.
struct FunctionCoverageRow: Codable, FetchableRecord, PersistableRecord {
    /// The table name.
    static let databaseTableName = "functionCoverage"

    /// The snapshot.
    var snapshotId: Int64
    /// The record's key.
    var key: String
    /// Lines that ran; null without data.
    var lineCovered: Int?
    /// Lines; null without data.
    var lineTotal: Int?
    /// Regions that ran; null without data.
    var regionCovered: Int?
    /// Regions; null without data.
    var regionTotal: Int?
    /// The test targets that ran it, one per line.
    var testTargets: String
    /// Why it has no data.
    var reason: String?
    /// A public function's link rule.
    var link: CoverageLink?
    /// A public function's linked tests.
    var linkedTests: Int?

    /// The record's coverage this row records.
    var record: CoverageRecord {
        CoverageRecord(
            key: key,
            lines: Self.tally(covered: lineCovered, total: lineTotal),
            regions: Self.tally(covered: regionCovered, total: regionTotal),
            testTargets: testTargets.split(separator: "\n").map(String.init),
            reason: reason,
            link: link,
            linkedTests: linkedTests
        )
    }

    /// The row for `record` in snapshot `snapshotId`.
    init(_ record: CoverageRecord, snapshotId: Int64) {
        self.snapshotId = snapshotId
        key = record.key
        lineCovered = record.lines?.covered
        lineTotal = record.lines?.total
        regionCovered = record.regions?.covered
        regionTotal = record.regions?.total
        testTargets = record.testTargets.joined(separator: "\n")
        reason = record.reason
        link = record.link
        linkedTests = record.linkedTests
    }

    /// The tally of `covered` of `total`; nil when either is null.
    private static func tally(covered: Int?, total: Int?) -> CoverageTally? {
        guard let covered, let total else {
            return nil
        }
        return CoverageTally(covered: covered, total: total)
    }
}
