import Foundation
@testable import SwiftStatsCore
import Testing

/// `scan --mutation --resume` of a `--since` run (M6, design §1.7, §6.2):
/// the pending run records its mode and base, the resume runs its own
/// command again (with `--since`) and `--resume`, and merges with the base
/// it recorded, chosen again; it is refused, before anything runs, when
/// that base's results changed since the run started or are gone, and a
/// resume whose header no longer matches the base fails and keeps nothing
/// for a further resume.
@Suite("Mutation since resume")
struct MutationSinceResumeTests {
    /// How many of the recorded `since` run's mutant lines the aborted run
    /// leaves to its resume.
    private static let left = 4

    /// The recorded `since` run, aborted before its last mutants: its
    /// results file with those lines left out and an `aborted` end, and
    /// SwiftMutator's exit for an abort.
    private static func aborted() throws -> FakeMutator.Scenario {
        var scenario = try SinceHarness.scenario("since")
        let lines = (scenario.results ?? "").split(separator: "\n").map(String.init)
        let end = (lines.last ?? "").replacingOccurrences(
            of: #""reason":"finished""#,
            with: #""detail":"testFailure","reason":"aborted""#
        )
        scenario.results = (lines.dropLast(Self.left + 1) + [end]).map { $0 + "\n" }.joined()
        scenario.status = MutationExit.abortedStatus
        return scenario
    }

    /// The resume of `aborted()`: a second session (the first one's
    /// header again), the mutant lines the abort left, and a finished end.
    private static func resuming() throws -> FakeMutator.Scenario {
        let recorded = try SinceHarness.scenario("since")
        let lines = (recorded.results ?? "").split(separator: "\n").map(String.init)
        let second = { (line: String) in line.replacingOccurrences(of: #""session":1"#, with: #""session":2"#) }
        var scenario = FakeMutator.Scenario()
        scenario.appended = ([lines[0]] + lines.suffix(Self.left + 1)).map(second).map { $0 + "\n" }.joined()
        scenario.report = recorded.report
        scenario.ownIdentity = true
        return scenario
    }

    @Test("""
        a --since run that aborted leaves a pending run recording its mode and base; its resume runs its \
        command again with --resume and merges with that base as the run would have
        """)
    func resumed() throws {
        let harness = try SinceHarness()
        defer { harness.remove() }
        let base = try harness.base()
        let failed = try harness.scan("since", acting: Self.aborted(), request: .since("main"), in: harness.workspace)
        let directory = MutationDirectory(lookingIn: harness.root)
        let pending = try #require(try PendingMutationRun.read(in: directory))

        let resumed = try harness.scan("since", acting: Self.resuming(), request: .resume, in: harness.workspace)

        #expect(failed.snapshot.info.collectors.first { $0.name == MutationAdapter.name }?.state == .failed)
        #expect(pending.mode == .since)
        #expect(pending.base?.commit == harness.mainCommit)
        #expect(pending.base?.collectedAt == base.snapshot.report.mutation?.collectedAt)
        let call = try #require(harness.fake.calls(of: "swift-mutator").last { $0.first == "run" })
        #expect(Array(call.suffix(4).prefix(2)) == ["--since", harness.mainCommit])
        #expect(call.suffix(2).first == "--resume")
        let mutation = try #require(resumed.snapshot.report.mutation)
        #expect(mutation.mode == .since && mutation.complete)
        #expect(mutation.base?.commit == harness.mainCommit)
        #expect(mutation.files.filter { $0.disposition == .tested }.map(\.path)
            == ["Sources/Core/Bounds.swift", "Sources/Core/Signum.swift"])
        #expect(mutation.mutants.count { $0.carried == false } == 29)
        #expect(mutation.runs.last?.sessions == 2)
        let status = resumed.snapshot.info.collectors.first { $0.name == MutationAdapter.name }
        #expect(status?.state == .ran)
        #expect(status?.reason?.hasPrefix("merged: 2 files retested since 37124375f4, 5 carried") == true)
        #expect(try PendingMutationRun.read(in: directory) == nil)
    }

    @Test(
        """
        a resumed --since run whose header compared the tree with another merge base, or asked for other \
        operators, fails the collector naming both values and keeps neither its copy nor its pending run, since a \
        further resume would fail the same way
        """,
        arguments: MutationSinceRefusalTests.headerChanges
    )
    func headerChanged(row: MutationSinceRefusalTests.HeaderChange) throws {
        let harness = try SinceHarness()
        defer { harness.remove() }
        _ = try harness.base()
        var aborted = try Self.aborted()
        aborted.results = aborted.results?.replacingOccurrences(of: row.recorded, with: row.changed)
        _ = try harness.scan("since", acting: aborted, request: .since("main"), in: harness.workspace)
        let directory = MutationDirectory(lookingIn: harness.root)
        let pending = try PendingMutationRun.read(in: directory)
        var resuming = try Self.resuming()
        resuming.appended = resuming.appended?.replacingOccurrences(of: row.recorded, with: row.changed)

        let resumed = try harness.scan("since", acting: resuming, request: .resume, in: harness.workspace)

        #expect(pending != nil)
        let status = resumed.snapshot.info.collectors.first { $0.name == MutationAdapter.name }
        #expect(status?.state == .failed)
        // A resume names its base by the commit its record holds.
        #expect(status?.reason == row.reason.replacingOccurrences(of: "of main", with: "of 37124375f4"))
        #expect(resumed.snapshot.report.mutation == nil)
        #expect(try PendingMutationRun.read(in: directory) == nil)
        let work = harness.root.appendingPathComponent(".swiftstats/mutation/work")
        #expect(FileManager.default.fileExists(atPath: work.path) == false)
    }

    @Test("the resume of a --since run is refused before anything runs when its base's results changed since")
    func baseChanged() throws {
        let harness = try SinceHarness()
        defer { harness.remove() }
        let base = try harness.base()
        _ = try harness.scan("since", acting: Self.aborted(), request: .since("main"), in: harness.workspace)
        try SnapshotHarness.sqlite(
            harness.folder.appendingPathComponent("stats.sqlite"),
            "UPDATE mutationScan SET collectedAt = '2026-11-22T00:00:00.000Z' WHERE snapshotId = \(base.id)"
        )
        let runs = harness.runs()

        #expect(throws: StoreError.noMutationBase(
            "the results of the base of that run, 37124375f4, have changed since it started; "
                + "run scan --mutation --since 37124375f4"
        )) {
            try harness.scan("since", acting: Self.resuming(), request: .resume, in: harness.workspace)
        }
        #expect(harness.runs() == runs)
        #expect(try PendingMutationRun.read(in: MutationDirectory(lookingIn: harness.root)) != nil)
    }

    @Test("""
        the resume of a --since run is refused before anything runs when its base no longer holds results, \
        giving the base's own reason once, its commit shortened
        """)
    func baseGone() throws {
        let harness = try SinceHarness()
        defer { harness.remove() }
        let base = try harness.base()
        _ = try harness.scan("since", acting: Self.aborted(), request: .since("main"), in: harness.workspace)
        try SnapshotHarness.sqlite(
            harness.folder.appendingPathComponent("stats.sqlite"),
            "DELETE FROM mutationScan WHERE snapshotId = \(base.id)"
        )
        let runs = harness.runs()

        #expect(throws: StoreError.noMutationBase(
            "the base of that run, 37124375f4, no longer has the results it started from (the snapshot of "
                + "37124375f4 holds no mutation results; run scan --mutation at 37124375f4 first, which can then be "
                + "the base); run scan --mutation --since 37124375f4"
        )) {
            try harness.scan("since", acting: Self.resuming(), request: .resume, in: harness.workspace)
        }
        #expect(harness.runs() == runs)
        #expect(try PendingMutationRun.read(in: MutationDirectory(lookingIn: harness.root)) != nil)
    }
}
