import Foundation
@testable import SwiftStatsCore
import Testing

/// A full run that finds no code SwiftMutator could test (M6, design §1.5:
/// exit 255 with its nothing-to-test line): the collector ran, and its
/// results are empty but there, complete, listing no code no test ran,
/// with no run and no mutant, over the scan's files, each production file
/// unlisted; they are stored, carried by a rescan of the same tree and
/// reported as any others, and the mutation signals give their funnels.
@Suite("Mutation nothing tested")
struct MutationNothingTestedTests {
    private typealias Harness = MutationSignalHarness

    /// SwiftMutator's exit for a package with nothing to test.
    private static let nothingToTest = FakeMutator.Scenario(
        errorText: MutationExit.nothingToTestLine + "\n\nThis is likely caused by misconfiguring SwiftMutator.\n",
        status: 255
    )

    @Test("""
        a full run with nothing to test stores empty, complete results over the scan's files, which the report \
        shows as such and a plain rescan of the same tree carries
        """)
    func storedAndCarried() throws {
        let harness = try SinceHarness()
        defer { harness.remove() }

        let first = try harness.scan("main", acting: Self.nothingToTest, request: .full, in: harness.workspace)
        let stored = try harness.workspace.store.load(id: first.id)
        let second = try harness.workspace.scanWorkingTree(history: .skipped("test"))

        let run = first.snapshot.info.collectors.first { $0.name == MutationAdapter.name }
        #expect(run?.state == .ran)
        #expect(run?.reason == MutationExit.nothingToTestReason)
        let report = try #require(first.snapshot.report.mutation)
        #expect(report.mode == .full && report.complete && report.listsNotCovered == false)
        #expect(report.runs.isEmpty && report.mutants.isEmpty && report.suspectTests.isEmpty)
        let scanned = Set(first.snapshot.report.files.map(\.path).filter { $0.hasSuffix(".swift") })
        #expect(Set(report.files.map(\.path)) == scanned)
        #expect(report.files.contains { $0.disposition == .unlisted })
        #expect(report.files.allSatisfy { [.unlisted, .untested].contains($0.disposition) && $0.run == nil })
        #expect(stored.mutation?.report == report)
        let lines = MarkdownMutation.render(first.snapshot.report)
        #expect(Array(lines.prefix(2)) == [
            "Status: \(MutationExit.nothingToTestReason).",
            "Made by one full run, which found no code SwiftMutator could test: no mutants."
        ])
        #expect(lines.contains { $0.hasPrefix("Not collected") || $0.hasPrefix("| Run ") } == false)
        // No base, no runs and no mutants: none of the details that speak of them.
        #expect(lines.contains { $0.contains("since the base") || $0.contains("; .") } == false)
        #expect(lines.contains { $0.hasPrefix("Killing tests:") || $0.hasPrefix("Suspect-only kills:") } == false)
        let unlisted = report.files.filter { $0.disposition == .unlisted }.map { "`\($0.path)`" }
        let untested = report.files.count { $0.disposition == .untested }
        #expect(Array(lines.suffix(3)) == [
            "Files: \(unlisted.count) unlisted, \(untested) not mutated (tests, excluded files, other packages).",
            "",
            "Unlisted (the run found no code SwiftMutator could test, so their code no test ran isn't listed): "
                + unlisted.joined(separator: ", ") + "."
        ])
        let carried = second.snapshot.info.collectors.first { $0.name == MutationAdapter.name }
        #expect(carried?.state == .ran)
        #expect(carried?.reason?.hasSuffix("; " + MutationExit.nothingToTestReason) == true)
        #expect(second.snapshot.report.mutation == report)
    }

    @Test("results no run made are refused as a --since base, saying so, before anything runs")
    func noSinceBase() throws {
        let harness = try SinceHarness()
        defer { harness.remove() }
        _ = try harness.scan("main", acting: Self.nothingToTest, request: .full, in: harness.workspace)
        let runs = harness.runs()

        let since = try SinceHarness.scenario("since")
        #expect(throws: StoreError.noMutationBase(
            "the results of main come from a run that found no code SwiftMutator could test; "
                + "run a full scan --mutation"
        )) {
            try harness.scan("since", acting: since, request: .since("main"), in: harness.workspace)
        }
        #expect(harness.runs() == runs)
    }

    @Test("""
        over results no run made, weak tests gives its funnel and says why code no test ran isn't listed, and \
        genuinely under-tested is left out for that reason
        """)
    func signals() throws {
        let snapshot = try Harness.stored(
            [Harness.covered(Harness.planted(2, .survived))],
            Harness.Setup(nothingTested: true)
        )
        let weak = try Harness.signal(.weakTests, of: snapshot)
        let under = try Harness.signal(.genuinelyUnderTested, of: snapshot)

        let cause = "the run found no code SwiftMutator could test"
        #expect(weak.leftOut == nil && weak.items.isEmpty)
        #expect(Harness.unbalanced(weak.rule).isEmpty)
        #expect(weak.rule.hasSuffix(
            "; the mutation results don't list code no test ran (\(cause)), so functions no test ran aren't judged"
        ))
        #expect(under.leftOut == "the mutation results don't list code no test ran (\(cause)), so low scores can't "
            + "be told from missing ones")
    }
}
