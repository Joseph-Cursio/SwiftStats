//
//  MarkdownMutationTests.swift
//  SwiftStatsCoreTests
//
//  The report's Mutation section (M6, design §8): the Coverage fixture's
//  recorded full run as the section shows it, with SwiftMutator's own
//  whole percent beside every mutant's score and no run times; the
//  Mutation fixture's `--since` merges, labelled as merged results with no
//  percent of SwiftMutator's, their runs, carried rows, deleted, unlisted
//  and changed test files; and a run that didn't happen. Incomplete
//  results are in `MarkdownMutationTests+Incomplete.swift`.
//

import Foundation
@testable import SwiftStatsCore
import Testing

@Suite("Markdown mutation")
struct MarkdownMutationTests {
    /// The Coverage fixture's recorded full run as the section shows it.
    private static let fixtureLines = [
        "Status: ran.",
        "Made by one full run.",
        "Complete: every mutant the runs discovered has a result. Code no test ran is listed (not covered).",
        "",
        "| Run | Mode | Commit | Ended | Sessions | Mutants tested | Not covered | Carried | Control runs "
            + "(failed) | Workers | Time limit | SwiftMutator build | Toolchain |",
        "| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |",
        "| 0 | full | c1 | finished | 1 | 33 | 10 | 0 | 0 (0) | 1 | 20 s | sha256:5138cbf1b8 | Apple Swift "
            + "version 6.4.2 (swiftlang-6.4.2.1.9 clang-2100.4.1.1) |",
        "",
        "Settings: operators ChangeArithmeticOperator, ChangeLogicalConnector, FlipBooleanLiteral, "
            + "NegateConditional, RelationalBoundary, RelationalOperatorReplacement, RemoveSideEffects, "
            + "ReplaceBooleanValue, ReplaceReturnValue, SwapTernary; coverage on.",
        "",
        "Mutation score (SwiftMutator's formula: killed ÷ (killed + survived + no coverage + timed out)) and "
            + "mutants by verdict:",
        "",
        "|  | Score | Killed | Crash kills | Survived | No coverage | Timed out | Not covered | Build errors "
            + "| Suspect-only |",
        "| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |",
        "| production | 29/31 (93.55%) | 29 | 0 | 2 | 0 | 0 | 10 | 0 | 0 |",
        "| Exe | 2/2 (100%) | 2 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |",
        "| Probe | 27/29 (93.10%) | 27 | 0 | 2 | 0 | 0 | 10 | 0 | 0 |",
        "| Unlinked | — | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |",
        "| every mutant (dropped and unmapped too) | 31/33 (93.94%; SwiftMutator: 93%) | 31 | 0 | 2 | 0 | 0 | "
            + "10 | 0 | 0 |",
        "",
        "Production functions by mutation state:",
        "",
        "|  | Scored | Only not covered | Only build errors | No mutant | No results | Not listed |",
        "| --- | --- | --- | --- | --- | --- | --- |",
        "| production | 22 | 6 | 0 | 11 | 0 | 0 |",
        "| Exe | 1 | 0 | 0 | 1 | 0 | 0 |",
        "| Probe | 21 | 6 | 0 | 9 | 0 | 0 |",
        "| Unlinked | 0 | 0 | 0 | 1 | 0 | 0 |",
        "",
        "Mapped mutants by operator:",
        "",
        "| Operator | Scored | Killed | Survived | Timed out | No coverage | Not covered | Build errors |",
        "| --- | --- | --- | --- | --- | --- | --- | --- |",
        "| ChangeArithmeticOperator | 10 | 8 | 0 | 0 | 0 | 2 | 0 |",
        "| ChangeLogicalConnector | 1 | 1 | 0 | 0 | 0 | 0 | 0 |",
        "| NegateConditional | 1 | 1 | 0 | 0 | 0 | 0 | 0 |",
        "| RelationalBoundary | 1 | 0 | 0 | 0 | 0 | 1 | 0 |",
        "| RelationalOperatorReplacement | 1 | 0 | 0 | 0 | 0 | 1 | 0 |",
        "| ReplaceBooleanValue | 2 | 1 | 1 | 0 | 0 | 0 | 0 |",
        "| ReplaceReturnValue | 25 | 18 | 1 | 0 | 0 | 6 | 0 |",
        "",
        "Killing tests: 0 of 29 kills name no test (0%), 0 of them crash kills, which usually name none; "
            + "every run stops a mutant's tests at the first failure, so a kill names at most the first "
            + "failing test; a kill names at most 20 tests. Killing tests are a lower bound.",
        "",
        "Suspect-only kills: 0; suspects judged for 29 of 29 kills by a failing test; run 0 judged "
            + "control-run, flaky and reach suspects.",
        "",
        "No suspect tests.",
        "",
        "Files: 13 tested, 0 carried, 7 not mutated (tests, excluded files, other packages), 0 deleted since "
            + "the base, 0 unresolved, 0 unlisted.",
        "",
        "Mutants left out by design: 0 in build products and dependencies, 0 outside the package, 0 in test "
            + "files, 1 in other packages, 0 not Swift.",
        "",
        "Unmapped mutants: 1 (1 excluded).",
        "",
        "| File | Line | Column | Operator | Reason |",
        "| --- | --- | --- | --- | --- |",
        "| Sources/Probe/Excluded.swift | 3 | 5 | ReplaceReturnValue | excluded |"
    ]

    /// `report` made incomplete, its run's report unread with three control
    /// runs, two failed; two suspect tests; and 51 more unmapped mutants,
    /// repeats of its unmapped one (the incomplete scenarios use it).
    static func incomplete(_ report: MutationReport) throws -> MutationReport {
        let unmapped = try #require(report.mutants.first { $0.place == .unmapped })
        var repeats: [Mutant] = []
        for occurrence in 1...(MarkdownMutation.listedEntries + 1) {
            var row = MutantRow(unmapped, ordinal: 0, snapshotId: 0)
            row.occurrence = occurrence
            repeats.append(try row.mutant)
        }
        let run = try edited(try #require(report.runs.first)) { fields in
            fields["controlRuns"] = 3
            fields["controlFailures"] = 2
            fields["suspectsJudged"] = nil
        }
        return MutationReport(
            collectedAt: report.collectedAt,
            complete: false,
            listsNotCovered: report.listsNotCovered,
            mode: report.mode,
            base: report.base,
            files: report.files,
            runs: [run],
            suspectTests: [
                MutationSuspectTest(
                    name: "wide()",
                    file: "Tests/ProbeTests/WideTests.swift",
                    run: 0,
                    why: .reach,
                    files: 9,
                    filesWithKills: 10
                ),
                MutationSuspectTest(name: "flaky()", file: nil, run: 0, why: .flaky, files: nil, filesWithKills: nil)
            ],
            mutants: report.mutants + repeats
        )
    }

    /// `value` with the JSON fields `change` edits.
    static func edited<Value: Codable>(
        _ value: Value,
        _ change: (inout [String: Any]) -> Void
    ) throws -> Value {
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(value))
        var fields = try #require(object as? [String: Any])
        change(&fields)
        return try JSONDecoder().decode(Value.self, from: JSONSerialization.data(withJSONObject: fields))
    }

    @Test("""
        a full run shows its status, run, settings, scores with SwiftMutator's percent beside every mutant's, \
        functions, operators, killing tests, suspects, files, dropped and unmapped mutants, and no run times
        """)
    func fixture() throws {
        let scanned = try MutationSnapshots.snapshot(commit: "c1")
        let run = try #require(scanned.report.mutation?.runs.first)

        let lines = MarkdownMutation.render(scanned.report)

        #expect(lines == Self.fixtureLines)
        let text = lines.joined(separator: "\n")
        #expect(text.contains(run.startedAt) == false)
        #expect(run.endedAt.map(text.contains) == false)
    }

    @Test("""
        a --since merge labels its score as merged results, without SwiftMutator's percent, lists both runs with \
        the carried rows, and counts the deleted file and the changed test file
        """)
    func merged() throws {
        let harness = try SinceHarness()
        defer { harness.remove() }
        _ = try harness.base()
        let since = try harness.since("since", acting: "since").snapshot
        let base = String(harness.mainCommit.prefix(MarkdownSignals.shortLength))
        let collected = try #require(since.report.mutation?.base?.collectedAt)

        let lines = MarkdownMutation.render(since.report)

        #expect(Array(lines.prefix(2)) == [
            "Status: merged: 2 files retested since \(base), 5 carried; 1 test file changed since \(base), so carried "
                + "verdicts weren't retested against them.",
            "Merged: a --since run retested the files changed since \(base); the other files' results are carried "
                + "from its scan of \(collected)."
        ])
        let runs = lines.filter { $0.hasPrefix("| 0 | full | ") || $0.hasPrefix("| 1 | since ") }
        #expect(runs.count == 2)
        #expect(runs.first?.contains(" | 9 | 21 | 30 from \(base) | ") == true)
        #expect(runs.last?.contains("| 1 | since \(base) | ") == true)
        #expect(runs.last?.contains(" | 29 | 0 | 0 | ") == true)
        #expect(lines.contains("Score over merged results (SwiftMutator's formula: killed ÷ (killed + survived + no "
            + "coverage + timed out); 50.85% of mutants carried from \(base)) and mutants by verdict:"))
        #expect(lines.contains("| every mutant (dropped and unmapped too) | 27/38 (71.05%) | 27 | 3 | 11 | 0 | 0 | 21 "
            + "| 0 | 0 |"))
        #expect(lines.contains { $0.contains("SwiftMutator: ") } == false)
        #expect(lines.contains("Files: 2 tested, 5 carried, 5 not mutated (tests, excluded files, other packages), 1 "
            + "deleted since the base, 0 unresolved, 0 unlisted."))
        #expect(lines.contains("Test files changed since the base (carried verdicts weren't retested against them): "
            + "`Tests/CoreTests/SignTests.swift`."))
    }

    @Test("a --since run that tested no mutant in a changed file lists it as unlisted")
    func unlisted() throws {
        let harness = try SinceHarness()
        defer { harness.remove() }
        _ = try harness.base()
        let since = try harness.since("since-unlisted", acting: "since-unlisted").snapshot

        let lines = MarkdownMutation.render(since.report)

        #expect(lines.contains("Files: 0 tested, 6 carried, 5 not mutated (tests, excluded files, other packages), 0 "
            + "deleted since the base, 0 unresolved, 1 unlisted."))
        #expect(lines.contains("Unlisted (changed since the base, but SwiftMutator tested no mutant in them, so "
            + "their code no test ran isn't listed): `Sources/Core/Dormant.swift`."))
    }

    @Test("a run that didn't happen says why")
    func notCollected() throws {
        let scanned = try MutationSnapshots.snapshot(commit: "c1")
        let failed = MutationSnapshots.replacing(
            scanned,
            git: scanned.info.git,
            mutation: nil,
            run: CollectorRunInfo(
                name: MutationAdapter.name,
                state: .failed,
                reason: "swift-mutator exited 3",
                version: nil,
                identity: nil,
                identityLabel: nil,
                options: [],
                durationMilliseconds: 0
            )
        )

        #expect(MarkdownMutation.render(failed.report) == ["Not collected: failed, swift-mutator exited 3."])
    }
}
