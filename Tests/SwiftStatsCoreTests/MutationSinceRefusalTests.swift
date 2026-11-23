import Foundation
@testable import SwiftStatsCore
import Testing

/// When `scan --mutation --since main` is refused before anything runs
/// (M6, design §6.1), first reason that applies: no clean snapshot of the
/// base's commit; one holding no mutation results (naming the nearest
/// first-parent ancestor of HEAD whose snapshot holds some); incomplete
/// results; a base that isn't an ancestor of HEAD; and results made with
/// another SwiftMutator build or other settings. Each leaves SwiftMutator
/// unrun and the store as it was. After the run, a header that no longer
/// matches the base (another merge base, other operators) fails the
/// collector, merges and keeps nothing, and leaves no pending run.
@Suite("Mutation since refusals")
struct MutationSinceRefusalTests {
    /// A header changed after the run: the text replaced, its
    /// replacement and the reason the collector fails with.
    struct HeaderChange: CustomTestStringConvertible, Sendable {
        /// What changes.
        let name: String
        /// The recorded text.
        let recorded: String
        /// What replaces it.
        let changed: String
        /// The reason expected.
        let reason: String

        /// The row's name in the test's report.
        var testDescription: String {
            name
        }
    }

    /// The recorded runs' operators, sorted.
    private static let operators = [
        "ChangeArithmeticOperator", "ChangeLogicalConnector", "FlipBooleanLiteral", "NegateConditional",
        "RelationalBoundary", "RelationalOperatorReplacement", "RemoveSideEffects", "ReplaceBooleanValue",
        "ReplaceReturnValue", "SwapTernary"
    ]

    /// The header changes the post-run guard catches.
    static let headerChanges: [HeaderChange] = [
        HeaderChange(
            name: "another merge base",
            recorded: #""mergeBase":"37124375f4e9e6e1429daf2651e47fc91132142f""#,
            changed: #""mergeBase":"0000000000000000000000000000000000000000""#,
            reason: "the run compared the tree with 0000000000 rather than 37124375f4, the commit of the results of "
                + "main"
        ),
        HeaderChange(
            name: "other operators",
            recorded: #""operators":["ChangeArithmeticOperator","#,
            changed: #""operators":["#,
            reason: "the run's operators (\(operators.dropFirst().joined(separator: ", "))) differ from those of the "
                + "results of main (\(operators.joined(separator: ", ")))"
        )
    ]

    /// `main`'s commit, shortened as reasons show it.
    private static let main10 = "37124375f4"

    /// The refusal saying `reason`.
    private static func refused(_ reason: String) -> StoreError {
        StoreError.noMutationBase(reason)
    }

    /// Whether scanning `branch` of `harness` with `--since <revision>`
    /// in `workspace` throws `refusal` without running SwiftMutator or
    /// storing anything.
    private static func refuses(
        _ harness: SinceHarness,
        branch: String,
        revision: String,
        in workspace: SnapshotWorkspace,
        with refusal: StoreError
    ) throws -> Bool {
        let runs = harness.runs()
        let latest = try workspace.store.latestSnapshotID(package: "Mutation", packagePath: "")
        var thrown: (any Error)?
        do {
            _ = try harness.scan(
                branch,
                acting: SinceHarness.scenario("since"),
                request: .since(revision),
                in: workspace
            )
        } catch {
            thrown = error
        }
        let stored = try workspace.store.latestSnapshotID(package: "Mutation", packagePath: "")
        return thrown as? StoreError == refusal && harness.runs() == runs && stored == latest
    }

    /// The refusal of a scan of the working tree asking for `--since
    /// <since>`, a full commit; nil when there is none.
    private static func thrown(_ harness: SinceHarness, since: String) throws -> StoreError? {
        try harness.fake.act(SinceHarness.scenario("since"))
        do {
            _ = try harness.workspace.scanWorkingTree(
                history: .skipped("test"),
                tiers: RequestedTiers(mutation: .since(since))
            )
        } catch let error as StoreError {
            return error
        }
        return nil
    }

    @Test("""
        with no clean snapshot of the base's commit, or one that holds no mutation results, --since is refused \
        before anything runs, naming the nearest first-parent ancestor of HEAD whose snapshot holds complete ones
        """)
    func noBase() throws {
        let harness = try SinceHarness()
        defer { harness.remove() }
        #expect(try Self.refuses(
            harness,
            branch: "since",
            revision: "main",
            in: harness.workspace,
            with: Self.refused("no snapshot of main (\(Self.main10)); run scan --mutation at main first")
        ))
        _ = try harness.scan("main", acting: SinceHarness.scenario("full"), request: nil, in: harness.workspace)
        #expect(try Self.refuses(
            harness,
            branch: "since",
            revision: "main",
            in: harness.workspace,
            with: Self.refused(
                "the snapshot of main (\(Self.main10)) holds no mutation results; run scan --mutation at main "
                    + "first, which can then be the base"
            )
        ))
        let base = try harness.base()
        _ = try harness.scan("since", acting: SinceHarness.scenario("full"), request: nil, in: harness.workspace)
        try MutationFixture.git(["commit", "--quiet", "--allow-empty", "--message", "next"], in: harness.root, day: 2)
        let since = harness.repository.commits["since", default: ""]
        let since10 = since.prefix(MutationBase.shortCommitLength)

        let nearest = try Self.thrown(harness, since: since)
        try SnapshotHarness.sqlite(
            harness.folder.appendingPathComponent("stats.sqlite"),
            "UPDATE mutationScan SET complete = 0 WHERE snapshotId = \(base.id)"
        )
        let incomplete = try Self.thrown(harness, since: since)

        #expect(nearest == Self.refused(
            "the snapshot of \(since10) holds no mutation results; "
                + "--since \(Self.main10), the nearest ancestor of HEAD whose snapshot holds them, can be the base"
        ))
        #expect(incomplete == Self.refused(
            "the snapshot of \(since10) holds no mutation results; run scan --mutation at \(since10) first, which "
                + "can then be the base"
        ))
    }

    @Test("""
        a base whose results are incomplete, or whose commit isn't an ancestor of HEAD, is refused before \
        anything runs
        """)
    func incompleteOrNotAnAncestor() throws {
        let harness = try SinceHarness()
        defer { harness.remove() }
        let base = try harness.base()
        try SnapshotHarness.sqlite(
            harness.folder.appendingPathComponent("stats.sqlite"),
            "UPDATE mutationScan SET complete = 0 WHERE snapshotId = \(base.id)"
        )
        #expect(try Self.refuses(
            harness,
            branch: "since",
            revision: "main",
            in: harness.workspace,
            with: Self.refused("the results of main (\(Self.main10)) are incomplete; run a full scan --mutation")
        ))
        _ = try harness.scan("tests-only", acting: SinceHarness.scenario("full"), request: .full, in: harness.workspace)

        #expect(try Self.refuses(
            harness,
            branch: "since",
            revision: "tests-only",
            in: harness.workspace,
            with: Self.refused(
                "tests-only isn't an ancestor of HEAD, so files changed on both sides would have no results"
            )
        ))
    }

    @Test("""
        results made with another SwiftMutator build, or with other arguments or another toolchain, are refused \
        before anything runs, naming the first setting that differs
        """)
    func otherBuildOrSettings() throws {
        let harness = try SinceHarness()
        defer { harness.remove() }
        var recordedBuild = try FakeMutator.recorded("full")
        recordedBuild.ownIdentity = false
        _ = try harness.scan("main", acting: recordedBuild, request: .full, in: harness.workspace)
        #expect(try Self.refuses(
            harness,
            branch: "since",
            revision: "main",
            in: harness.workspace,
            with: Self.refused(
                "the results of main were made with another SwiftMutator build; run a full scan --mutation"
            )
        ))
        _ = try harness.base()
        let skipping = try harness.workspace(adding: "    arguments: [\"--skip\", \"slow\"]\n")
        #expect(try Self.refuses(
            harness,
            branch: "since",
            revision: "main",
            in: skipping,
            with: Self.refused(
                "the results of main were made with other settings (arguments); run a full scan --mutation"
            )
        ))
        var otherToolchain = try SinceHarness.scenario("since")
        otherToolchain.swiftVersion = "Apple Swift version 6.5\n"
        try harness.repository.checkOut("since")
        try harness.fake.act(otherToolchain)

        #expect(throws: Self.refused(
            "the results of main were made with other settings (toolchain); run a full scan --mutation"
        )) {
            try harness.workspace.scanWorkingTree(
                history: .skipped("test"),
                tiers: RequestedTiers(mutation: .since("main"))
            )
        }
    }

    @Test(
        """
        a run whose header compared the tree with another merge base, or asked for other operators, fails the \
        collector naming both values, merging and keeping nothing and leaving no pending run
        """,
        arguments: headerChanges
    )
    func headerChanged(row: HeaderChange) throws {
        let harness = try SinceHarness()
        defer { harness.remove() }
        _ = try harness.base()
        var scenario = try SinceHarness.scenario("since")
        scenario.results = scenario.results?.replacingOccurrences(of: row.recorded, with: row.changed)

        let since = try harness.scan("since", acting: scenario, request: .since("main"), in: harness.workspace)

        let status = since.snapshot.info.collectors.first { $0.name == MutationAdapter.name }
        #expect(status?.state == .failed)
        #expect(status?.reason == row.reason)
        #expect(since.snapshot.report.mutation == nil)
        let directory = harness.root.appendingPathComponent(".swiftstats/mutation")
        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("pending.json").path) == false)
        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("work").path) == false)
        let kept = (try? FileManager.default.contentsOfDirectory(atPath: directory.appendingPathComponent("runs").path))
        #expect(kept?.count == 1)
    }
}
