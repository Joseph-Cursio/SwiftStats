//
//  MarkdownTrendTests.swift
//  SwiftStatsCoreTests
//
//  `trend`'s Markdown (design §10.4): a type-check time's trend
//  (`typecheck.milliseconds.*`, `typecheck.slowestExpression.*`) ends with
//  the footnote that it depends on the machine and its load; any other
//  metric's doesn't, the count of records timed included.
//

@testable import SwiftStatsCore
import Testing

@Suite("Markdown trend")
struct MarkdownTrendTests {
    /// A trend of `metric` with one point.
    private static func trend(_ metric: String) -> TrendReport {
        TrendReport(
            schemaVersion: TrendReport.currentSchemaVersion,
            package: "Probe",
            metric: metric,
            scope: .project,
            name: "production",
            points: [TrendPoint(commit: "c1", date: "2026-11-24", value: 12, breakReason: nil)],
            offLine: 0
        )
    }

    @Test("""
        a type-check time's trend has the machine-and-load footnote; another metric's has none, nor has the count \
        of records timed
        """)
    func typeCheckFootnote() {
        let timed = ["typecheck.milliseconds.total", "typecheck.milliseconds.max", "typecheck.slowestExpression.max"]
            .map { MarkdownTrend.render(Self.trend($0)) }
        let counted = ["index.withUSR", "typecheck.functions.timed"].map { MarkdownTrend.render(Self.trend($0)) }

        #expect(timed.allSatisfy { $0.hasSuffix("\n\n" + MarkdownTrend.typeCheckNote + "\n") })
        #expect(timed.allSatisfy { $0.contains("which no build identity names") })
        #expect(counted.allSatisfy { $0.contains(MarkdownTrend.typeCheckNote) == false })
    }
}
