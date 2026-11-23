import Foundation
@testable import SwiftStatsCore
import Testing

/// Keeping mutation results across rescans (M6, design §6.4) through the
/// commands' own paths, on the Mutation fixture's repository with a
/// `FakeMutator` acting out its recorded runs: `scan` after
/// `scan --mutation`, on a clean tree and on one with uncommitted changes,
/// a SwiftStats rebuild, `scan --mutation` whose run fails or is turned
/// off, `diff --rescan` of an exported commit, and a working-tree rescan
/// over other uncommitted changes, which `--drop-mutation` replaces.
@Suite("Mutation carry through scans")
struct MutationCarryScanTests {
    /// Another SwiftStats build.
    private static let otherBuild = SwiftStatsBuild(identity: "inputs:rebuilt", label: nil)
    /// The test file the uncommitted changes edit, which holds no mutant.
    private static let testFile = "Tests/CoreTests/SignTests.swift"

    /// The reason a run carried from `run`, whose results were collected
    /// at `collectedAt`, gives.
    private static func carriedReason(of run: CollectorRunInfo, collectedAt: String) -> String {
        (["carried from the scan of \(collectedAt)"] + [run.reason].compactMap(\.self)).joined(separator: "; ")
    }

    /// Appends `text` to the test file in `harness`'s repository.
    private static func edit(_ harness: SinceHarness, appending text: String) throws {
        let url = harness.root.appendingPathComponent(testFile)
        let source = try String(contentsOf: url, encoding: .utf8)
        try (source + text).write(to: url, atomically: true, encoding: .utf8)
    }

    @Test("""
        a plain scan after scan --mutation of the same tree, then one by another SwiftStats build, carries the \
        results without running SwiftMutator, and the printed scan, the stored report, its rows and its roll-up \
        numbers agree
        """)
    func plainScans() throws {
        let harness = try SinceHarness()
        defer { harness.remove() }
        let rebuilt = try harness.workspace(build: Self.otherBuild)

        let first = try harness.base().snapshot
        let second = try harness.workspace.scanWorkingTree(history: .skipped("test"))
        let third = try rebuilt.scanWorkingTree(history: .skipped("test"))

        let results = try #require(first.report.mutation)
        let originalRun = try #require(MutationCarrySamples.mutationRun(first.info))
        #expect(originalRun.state == .ran && first.info.git.isDirty == false)
        #expect(harness.runs() == 1)
        for carried in [second, third] {
            #expect(carried.snapshot.report.mutation == results)
            #expect(carried.snapshot.report.rollups == first.report.rollups)
            #expect(MutationCarrySamples.mutationRun(carried.snapshot.info) == CollectorRunInfo(
                name: MutationAdapter.name,
                state: .ran,
                reason: Self.carriedReason(of: originalRun, collectedAt: results.collectedAt),
                version: originalRun.version,
                identity: originalRun.identity,
                identityLabel: originalRun.identityLabel,
                options: originalRun.options,
                durationMilliseconds: originalRun.durationMilliseconds
            ))
        }
        let stored = try rebuilt.store.load(id: third.id)
        #expect(stored.mutation == StoredMutation(report: results))
        #expect(stored.info == third.snapshot.info)
        #expect(stored.info.collectors.first { $0.name == SwiftStatsCollector.name }?.identity == "inputs:rebuilt")
        #expect(try ScanReportEncoder.encode(rebuilt.store.report(id: third.id))
            == ScanReportEncoder.encode(third.snapshot.report))
        let numbers = try MutationCarrySamples.mutationNumbers(first.report.rollups)
        #expect(MutationCarrySamples.mutationNumbers(stored.rollups) == numbers && numbers.isEmpty == false)
    }

    @Test("""
        a plain scan after scan --mutation of a tree with uncommitted changes carries the results onto the dirty \
        snapshot; after another edit it is refused, writing nothing, and --drop-mutation replaces them
        """)
    func dirtyScans() throws {
        let harness = try SinceHarness()
        defer { harness.remove() }
        try Self.edit(harness, appending: "// Dirty.\n")

        let first = try harness.base()
        let second = try harness.workspace.scanWorkingTree(history: .skipped("test"))
        let storedSecond = try harness.workspace.store.load(id: second.id).mutation
        try Self.edit(harness, appending: "// Dirtier.\n")
        let head = String(harness.mainCommit.prefix(10))
        let results = try #require(first.snapshot.report.mutation)
        #expect(throws: StoreError.mutationNotKept(
            snapshot: "Mutation at \(head) with uncommitted changes",
            collectedAt: results.collectedAt,
            reason: "the uncommitted changes differ"
        )) {
            try harness.workspace.scanWorkingTree(history: .skipped("test"))
        }
        let kept = try harness.workspace.store.snapshotID(
            package: "Mutation",
            packagePath: "",
            commit: harness.mainCommit,
            isDirty: true
        )
        let dropped = try harness.workspace.scanWorkingTree(history: .skipped("test"), drop: .mutation)

        #expect(first.snapshot.info.git.isDirty && second.snapshot.info.git == first.snapshot.info.git)
        #expect(second.snapshot.report.mutation == results)
        #expect(storedSecond == StoredMutation(report: results))
        #expect(first.id != second.id && kept == second.id)
        #expect(dropped.snapshot.report.mutation == nil)
        #expect(try harness.workspace.store.load(id: dropped.id).mutation == nil)
        #expect(harness.runs() == 1)
    }

    @Test("""
        scan --mutation whose run fails, or whose collector is turned off, carries the results with a warning \
        naming what became of its run
        """)
    func unrunScans() throws {
        let harness = try SinceHarness()
        defer { harness.remove() }
        let disabled = try harness.workspace(adding: "    enabled: false\n")

        let first = try harness.base().snapshot
        let failed = try harness.scan(
            "main",
            acting: SinceHarness.scenario("stopped"),
            request: .full,
            in: harness.workspace
        ).snapshot
        let skipped = try disabled.scanWorkingTree(
            history: .skipped("test"),
            tiers: RequestedTiers(mutation: .full)
        ).snapshot

        let results = try #require(first.report.mutation)
        let kept = ", so it keeps the results collected \(results.collectedAt)"
        let failure = failed.report.warnings.filter { warning in
            warning.message.hasPrefix("swiftmutator: this scan's mutation run failed (")
                && warning.message.hasSuffix(kept)
        }
        #expect(harness.runs() == 2)
        #expect(failed.report.mutation == results && skipped.report.mutation == results)
        #expect(failure.count == 1)
        #expect(skipped.report.warnings.contains(MutationSession.warning(
            "this scan's mutation run was skipped (disabled by collectors.swiftmutator.enabled)" + kept
        )))
        #expect(MutationCarrySamples.mutationRun(skipped.info)?.state == .ran)
    }

    @Test("diff --rescan by another build carries an exported commit's mutation results")
    func diffRescans() throws {
        let harness = try SinceHarness()
        defer { harness.remove() }
        let rebuilt = try harness.workspace(build: Self.otherBuild)
        let first = try harness.base().snapshot
        try harness.repository.checkOut("since")

        let ids = try rebuilt.diffSnapshotIDs(older: "main", newer: nil, includeDirty: false, rescan: true)

        let older = try rebuilt.store.load(id: ids.older)
        let results = try #require(first.report.mutation)
        #expect(older.info.git.commit == harness.mainCommit)
        #expect(older.mutation == StoredMutation(report: results))
        #expect(older.info.collectors.first { $0.name == SwiftStatsCollector.name }?.identity == "inputs:rebuilt")
        #expect(try rebuilt.store.load(id: ids.newer).mutation == nil)
        #expect(harness.runs() == 1)
    }
}
