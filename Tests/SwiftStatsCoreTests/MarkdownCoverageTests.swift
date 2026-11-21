//
//  MarkdownCoverageTests.swift
//  SwiftStatsCoreTests
//
//  The report's Coverage section (PRD §7.8, M5): the Coverage fixture's
//  recorded run as the section shows it, and a carried run of failing
//  tests with saturated counts and more unmapped entries than it lists.
//

import Foundation
@testable import SwiftStatsCore
import Testing

@Suite("Markdown coverage")
struct MarkdownCoverageTests {
    @Test("the section shows status, bundles, scopes, functions without data, public functions and unmapped entries")
    func fixture() throws {
        let scanned = try CoverageFixture.snapshot(commit: "c1")

        let lines = MarkdownCoverage.render(scanned.report)

        #expect(lines == [
            "Status: tests passed.",
            "Test bundles: `ProbeTests`, `SwiftTestKitTests`.",
            "",
            "|  | Lines | Regions | Functions with data | Executed | No data |",
            "| --- | --- | --- | --- | --- | --- |",
            "| production | 69/87 (79.31%) | 42/59 (71.19%) | 37 | 28 | 2 |",
            "| Exe | 3/7 (42.86%) | 1/6 (16.67%) | 2 | 1 | 0 |",
            "| Probe | 66/80 (82.50%) | 41/53 (77.36%) | 35 | 27 | 1 |",
            "| Unlinked | no data | no data | 0 | 0 | 1 |",
            "",
            "Per-function coverage is a separate, partial view: functions need not add up to the totals above, "
                + "which also count code outside functions.",
            "",
            "Functions with no coverage data: 2 (1 no coverage data; 1 not linked into any test bundle).",
            "",
            "Public functions (heuristic: the test's target ran it and the test names it):",
            "",
            "|  | Public | With coverage | Linked | Unlinked | Reached generically | Extension members | "
                + "Linked tests (median / p90 / max) |",
            "| --- | --- | --- | --- | --- | --- | --- | --- |",
            "| production | 33 | 31 | 23 | 8 | 0 | 0 | 1 / 1 / 2 |",
            "| Exe | 0 | 0 | 0 | 0 | 0 | 0 | — / — / — |",
            "| Probe | 32 | 31 | 23 | 8 | 0 | 0 | 1 / 1 / 2 |",
            "| Unlinked | 1 | 0 | 0 | 0 | 0 | 0 | — / — / — |",
            "",
            "No saturated counts.",
            "",
            "Files left out by design: 2 build products and dependencies, 0 outside the package, 4 test files, "
                + "1 in other packages, 0 not Swift.",
            "",
            "Unmapped entries: 1.",
            "",
            "| File | Lines | Count | Function | Reason |",
            "| --- | --- | --- | --- | --- |",
            "| Sources/Probe/Excluded.swift | 2–4 | 1 | `Probe.excludedHelper() -> Swift.Int` | excluded |"
        ])
    }

    @Test("a carried run of failing tests says so, counts saturated lines, and lists the first 50 unmapped entries")
    func carriedFailing() throws {
        let scanned = try CoverageFixture.snapshot(commit: "c1")
        let report = try #require(scanned.report.coverage)
        let entry = try #require(report.unmapped.first)
        let failing = CoverageReport(
            records: report.records,
            attachments: report.attachments,
            unmapped: Array(repeating: entry, count: MarkdownCoverage.listedUnmapped + 1),
            dropped: report.dropped,
            bundles: report.bundles,
            tests: "failing",
            saturated: [
                CoverageSaturation(file: "Sources/Probe/Counter.swift", line: 11),
                CoverageSaturation(file: "Sources/Probe/Counter.swift", line: 16)
            ],
            files: report.files
        )
        let reason = "tests failing (swift test exited 1); coverage merged from the test processes' profiles"
        let run = CollectorRunInfo(
            name: CoverageAdapter.name,
            state: .ran,
            reason: CoverageCarry.carriedPrefix + "2026-11-01T10:00:00Z; " + reason,
            version: "LLVM version 21.0.0",
            identity: "swift:test swift",
            identityLabel: nil,
            options: [],
            durationMilliseconds: 0
        )
        let carried = CoverageSnapshots.replacing(scanned, git: scanned.info.git, coverage: failing, run: run)

        let lines = MarkdownCoverage.render(carried.report)

        #expect(Array(lines.prefix(3)) == [
            "Status: \(reason).",
            "Carried from the scan of 2026-11-01T10:00:00Z: the tree and its functions' lines are unchanged since.",
            "Test bundles: `ProbeTests`, `SwiftTestKitTests`."
        ])
        #expect(lines.contains("Saturated counts: 2 lines in 1 files, read as covered (parallel tests lose counter "
            + "updates, so counts can vary between runs)."))
        #expect(lines.contains("Unmapped entries: 51."))
        let listed = lines.filter { $0.hasPrefix("| Sources/Probe/Excluded.swift |") }
        #expect(listed.count == MarkdownCoverage.listedUnmapped)
        #expect(lines.last == "1 more in the JSON report.")
    }
}
