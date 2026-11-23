//
//  MarkdownMutationTests+Incomplete.swift
//  SwiftStatsCoreTests
//
//  The report's Mutation section on incomplete results (M6, design §4,
//  §8): a carried, incomplete run with suspect tests, failed control runs
//  and more unmapped mutants than it lists, with no percent of its own or
//  of SwiftMutator's; and results left incomplete by changed files no run
//  retested, which name those files as the cause.
//

import Foundation
@testable import SwiftStatsCore
import Testing

/// The Mutation section when results are incomplete.
extension MarkdownMutationTests {
    @Test("""
        a carried, incomplete run says when it was collected, leaves its percentages and SwiftMutator's out, \
        names its suspect tests and failed control runs, and lists the first 50 unmapped mutants
        """)
    func carriedIncomplete() throws {
        let scanned = try MutationSnapshots.snapshot(commit: "c1")
        let report = try #require(scanned.report.mutation)
        let carried = try MutationSnapshots.replacing(
            scanned,
            git: scanned.info.git,
            mutation: Self.incomplete(report),
            run: CollectorRunInfo(
                name: MutationAdapter.name,
                state: .ran,
                reason: CollectorRunInfo.carriedPrefix + "2026-11-01T10:00:00Z; 2 control runs failed (flaky tests)",
                version: "0.1.0",
                identity: MutationSnapshots.identity,
                identityLabel: nil,
                options: [],
                durationMilliseconds: 0
            )
        )

        let lines = MarkdownMutation.render(carried.report)

        #expect(Array(lines.prefix(4)) == [
            "Status: 2 control runs failed (flaky tests).",
            "Carried from the scan of 2026-11-01T10:00:00Z: the tree and its functions' lines are unchanged since.",
            "Made by one full run.",
            "Incomplete: not every mutant the runs discovered has a result, so scores above functions are left out. "
                + "Code no test ran is listed (not covered)."
        ])
        // The 51 repeats of the killed, unmapped mutant count in the run's
        // mutants and among every mutant, not in the production part.
        #expect(lines.contains { $0.hasPrefix("| 0 | full | c1 | finished | 1 | 84 | 10 | 0 | 3 (2) | ") })
        #expect(lines.contains("| production | 29/31 (incomplete) | 29 | 0 | 2 | 0 | 0 | 10 | 0 | 0 |"))
        #expect(lines.contains("| every mutant (dropped and unmapped too) | 82/84 (incomplete) | 82 | 0 | 2 | 0 | 0 "
            + "| 10 | 0 | 0 |"))
        #expect(lines.contains { $0.contains("SwiftMutator: ") } == false)
        #expect(lines.contains("Suspect-only kills: 0; suspects judged for 29 of 29 kills by a failing test; run 0 "
            + "judged none (its report wasn't read)."))
        #expect(lines.contains("| 0 | flaky() | — | flaky when rerun alone |"))
        #expect(lines.contains("| 0 | wide() | Tests/ProbeTests/WideTests.swift | reach: fails in 9 of 10 files "
            + "with kills |"))
        #expect(lines.contains { $0.hasPrefix("Unresolved") } == false)
        #expect(lines.contains("Unmapped mutants: 52 (52 excluded)."))
        #expect(lines.count { $0.hasPrefix("| Sources/Probe/Excluded.swift | 3 | 5 | ReplaceReturnValue |") }
            == MarkdownMutation.listedEntries)
        #expect(lines.last == "2 more in the JSON report.")
    }

    @Test("results left incomplete by changed files no run retested name those files as the cause and list them")
    func unresolved() throws {
        let scanned = try MutationSnapshots.snapshot(commit: "c1")
        let report = try #require(scanned.report.mutation)
        let gone = ["Sources/Probe/Gone.swift", "Sources/Probe/Moved.swift"].map { path in
            MutationFile(path: path, sha256: nil, disposition: .unresolved, changedTest: false, run: nil)
        }
        let render = { (files: [MutationFile]) in
            let mutation = MutationReport(
                collectedAt: report.collectedAt,
                complete: false,
                listsNotCovered: report.listsNotCovered,
                mode: report.mode,
                base: report.base,
                files: report.files + files,
                runs: report.runs,
                suspectTests: report.suspectTests,
                mutants: report.mutants
            )
            return MarkdownMutation.render(
                MutationSnapshots.replacing(
                    scanned,
                    git: scanned.info.git,
                    mutation: mutation,
                    run: MutationSnapshots.ran(identity: MutationSnapshots.identity)
                ).report
            )
        }

        let lines = render(gone)
        let single = render(Array(gone.prefix(1)))

        #expect(lines.contains("Incomplete: 2 changed files weren't retested and have no results, so scores above "
            + "functions are left out. Code no test ran is listed (not covered)."))
        #expect(single.contains("Incomplete: 1 changed file wasn't retested and has no results, so scores above "
            + "functions are left out. Code no test ran is listed (not covered)."))
        #expect(lines.contains("Unresolved (changed since the base and not retested, so they have no results): "
            + "`Sources/Probe/Gone.swift`, `Sources/Probe/Moved.swift`."))
        #expect(lines.contains { $0.hasPrefix("Incomplete: not every mutant") } == false)
    }
}
