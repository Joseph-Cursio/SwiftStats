import Foundation
@testable import SwiftStatsCore
import Testing

/// A `--since` merge whose base is itself a merged snapshot (M6, design
/// §6.1, review finding 14): the base holds two runs, the full run its own
/// base carried (run 0) and its own `--since` run (run 1). When nothing
/// of run 0 is kept, the merge copies run 1 alone, renumbered 0 and
/// carried from the merged base while keeping the commit it tested; its
/// rows, its files and its suspect tests point at the new number, run 0's
/// suspect tests go, and a new run takes the next ordinal.
@Suite("Mutation merge onto a merged base")
struct MutationMergeChainTests {
    /// The fixture's `main`, the first base's commit.
    private static let firstCommit = "37124375f4e9e6e1429daf2651e47fc91132142f"
    /// The merged base's commit.
    private static let mergedCommit = "c2c2c2c2c2c2c2c2c2c2c2c2c2c2c2c2c2c2c2c2"
    /// The file the merged base's own run retested.
    private static let retested = "Sources/Core/Bounds.swift"

    /// Results of a run over `tree` with one killed mutant at line 3 of
    /// each of `paths`.
    private static func results(tree: [String: String], paths: [String]) throws -> MutationResults {
        let mutants = paths.map { path in
            ResultsLines.mutant(ResultsLines.Mutant(path: path, line: 3, column: 9, fileSHA256: tree[path]))
        }
        return try ResultsLines.results(
            [ResultsLines.header(ResultsLines.Header(discovered: paths.count, tree: tree))]
                + mutants + [ResultsLines.end(ResultsLines.End())]
        )
    }

    /// The record of a run of `results` at `commit`.
    private static func run(_ results: MutationResults, commit: String) -> MutationRunRecord {
        MutationMapper.run(
            results,
            ordinal: 0,
            resultsFile: ".swiftstats/mutation/runs/\(commit)/results.jsonl",
            git: SnapshotHarness.git(commit: commit),
            suspects: .unjudged
        )
    }

    /// A suspect test of run `run` named `name`.
    private static func suspect(_ name: String, run: Int) -> MutationSuspectTest {
        MutationSuspectTest(name: name, file: nil, run: run, why: .flaky, files: nil, filesWithKills: nil)
    }

    /// The mapped package, and the merged base: the recorded full run at
    /// `main` merged with a run at `c2` that retested `Bounds.swift`, with
    /// a suspect test on each of its two runs.
    private static func mergedBase() throws -> (MappingHarness, MutationBase) {
        let harness = try MappingHarness.mutation()
        let (full, suspects) = try MappingHarness.fullRun(of: MutationFixture.directory)
        let first = MutationBase(
            revision: "main",
            commit: firstCommit,
            report: MutationRows.normalized(harness.report(full, suspects: suspects)),
            options: []
        )
        let tree = Dictionary(uniqueKeysWithValues: first.report.files.compactMap { file in
            file.sha256.map { (file.path, $0) }
        })
        let since = try results(tree: tree, paths: [retested])
        let noChanges = MutationChanges(selection: [], tree: [:])
        let merged = MutationMerge(base: first, mapper: harness.mapper, changes: noChanges)
            .merged(results: since, run: run(since, commit: "c2"), suspects: .unjudged)
            .report
        let report = MutationReport(
            collectedAt: merged.collectedAt,
            complete: merged.complete,
            listsNotCovered: merged.listsNotCovered,
            mode: merged.mode,
            base: merged.base,
            files: merged.files,
            runs: merged.runs,
            suspectTests: [suspect("dropped()", run: 0), suspect("kept()", run: 1)],
            mutants: merged.mutants
        )
        return (harness, MutationBase(revision: "c2", commit: mergedCommit, report: report, options: []))
    }

    /// The production paths of `report` whose rows run `run` tested.
    private static func paths(testedBy run: Int, in report: MutationReport) -> [String] {
        report.files.filter { $0.run == run && $0.disposition != .untested }.map(\.path).sorted()
    }

    @Test("the merged base holds the first base's run, carried, and its own run, which retested one file")
    func mergedBaseShape() throws {
        let (harness, base) = try Self.mergedBase()
        defer { harness.remove() }

        let report = base.report
        #expect(report.runs.map(\.ordinal) == [0, 1])
        #expect(report.runs.map(\.commit) == ["c1", "c2"])
        #expect(report.runs[0].carriedFrom?.commit == Self.firstCommit && report.runs[1].carriedFrom == nil)
        #expect(Self.paths(testedBy: 1, in: report) == [Self.retested])
        #expect(Self.paths(testedBy: 0, in: report).count == 6)
        #expect(report.mutants.filter { $0.run == 1 }.map(\.path) == [Self.retested])
    }

    @Test("""
        when every file the merged base carried from its first run changed, the merge keeps only the base's own \
        run, renumbered 0 and carried from the merged base, its rows, files and suspect tests renumbered with it
        """)
    func laterRunKept() throws {
        let (harness, base) = try Self.mergedBase()
        defer { harness.remove() }
        let tree = Dictionary(uniqueKeysWithValues: base.report.files.compactMap { file in
            file.sha256.map { (file.path, $0) }
        })
        let selection = Self.paths(testedBy: 0, in: base.report)

        let merged = MutationMerge(
            base: base,
            mapper: harness.mapper,
            changes: MutationChanges(selection: selection, tree: tree)
        )
        .merged(results: nil, run: nil, suspects: .unjudged)
        .report

        let source = MutationSource(commit: Self.mergedCommit, collectedAt: base.report.collectedAt)
        #expect(merged.runs.map(\.ordinal) == [0])
        #expect(merged.runs.first?.commit == "c2")
        #expect(merged.runs.first?.carriedFrom == source)
        #expect(merged.mutants.isEmpty == false)
        #expect(merged.mutants.allSatisfy { $0.run == 0 && $0.carried && $0.path == Self.retested })
        #expect(Self.paths(testedBy: 0, in: merged) == [Self.retested])
        #expect(merged.files.first { $0.path == Self.retested }?.disposition == .carried)
        #expect(selection.allSatisfy { path in merged.files.first { $0.path == path }?.disposition == .unlisted })
        #expect(merged.suspectTests == [Self.suspect("kept()", run: 0)])
    }

    @Test("""
        a new run retesting every file the merged base carried from its first run takes ordinal 1 beside the \
        base's own run, renumbered 0
        """)
    func newRunAfterKeptRun() throws {
        let (harness, base) = try Self.mergedBase()
        defer { harness.remove() }
        let tree = Dictionary(uniqueKeysWithValues: base.report.files.compactMap { file in
            file.sha256.map { (file.path, $0) }
        })
        let retesting = Self.paths(testedBy: 0, in: base.report)
        let results = try Self.results(tree: tree, paths: retesting)

        let noChanges = MutationChanges(selection: [], tree: [:])
        let merged = MutationMerge(base: base, mapper: harness.mapper, changes: noChanges)
            .merged(results: results, run: Self.run(results, commit: "c3"), suspects: .unjudged)
            .report

        let source = MutationSource(commit: Self.mergedCommit, collectedAt: base.report.collectedAt)
        #expect(merged.runs.map(\.ordinal) == [0, 1])
        #expect(merged.runs.map(\.commit) == ["c2", "c3"])
        #expect(merged.runs.map(\.carriedFrom) == [source, nil])
        #expect(merged.mutants.filter { $0.run == 0 }.allSatisfy { $0.carried && $0.path == Self.retested })
        #expect(merged.mutants.filter { $0.run == 1 }.map(\.path).sorted() == retesting)
        #expect(merged.mutants.allSatisfy { $0.run == 0 || ($0.run == 1 && $0.carried == false) })
        #expect(Self.paths(testedBy: 0, in: merged) == [Self.retested])
        #expect(Self.paths(testedBy: 1, in: merged) == retesting)
        #expect(merged.suspectTests == [Self.suspect("kept()", run: 0)])
    }
}
