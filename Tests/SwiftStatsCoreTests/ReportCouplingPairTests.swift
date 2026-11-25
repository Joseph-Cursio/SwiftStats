//
//  ReportCouplingPairTests.swift
//  SwiftStatsCoreTests
//
//  The report's change-coupling pairs come from the store's `couplingPair`
//  table (M7, design §8.1, §10.1; PRD §9): on the Index fixture with its
//  deterministic history, the stored report's pairs equal the scan's, and
//  a row changed in the table changes the pair `report` reads, in its
//  JSON and in the History section's table.
//

import Foundation
@testable import SwiftStatsCore
import Testing

@Suite("Report change-coupling pairs")
struct ReportCouplingPairTests {
    @Test("the stored report's history pairs are the couplingPair rows, in the JSON and the History table")
    func pairsFromTable() async throws {
        try await IndexHarness.scanWithHistory { snapshot in
            let made = try IndexReportHarness.made(snapshot)
            defer { made.store.remove() }
            let pairs = try #require(snapshot.report.history?.coupling)
            let first = try #require(pairs.first)

            #expect(made.report.scan.history?.coupling == pairs)
            try SnapshotHarness.sqlite(made.store.url, "UPDATE couplingPair SET support = 99, changesA = 98 "
                + "WHERE snapshotId = \(made.id) AND ordinal = 0")
            let changed = try IndexReportHarness.report(id: made.id, in: made.store.store)
            let read = try #require(changed.scan.history?.coupling.first)
            let history = IndexReportHarness.section("History", of: MarkdownReport.render(changed))

            #expect(read.familyA == first.familyA)
            #expect(read.support == 99)
            #expect(read.changesA == 98)
            #expect(changed.scan.history?.coupling.dropFirst() == pairs.dropFirst())
            #expect(history.contains { $0.hasSuffix("| 99 | 98 / \(first.changesB) |") })
        }
    }
}
