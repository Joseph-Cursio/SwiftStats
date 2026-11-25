import Foundation
@testable import SwiftStatsCore
import Testing

/// What `scan` prints on standard error about an opt-in run it asked for
/// that collected nothing (`UnrunNotice`): the line names the collector and
/// how its run ended, in the carry's words, or is the carry's own warning
/// when the replaced snapshot's results were kept; a run that ran prints
/// nothing, and neither does a collector that wasn't asked for. With
/// `--index`, the index read and outskirts each print a line when they
/// failed or were skipped for a reason of their own, but not when the
/// build didn't run or their status was carried.
@Suite("Unrun notices")
struct UnrunNoticeTests {
    /// Counts the opens of a recorded index store across threads.
    private final class OpenCount: @unchecked Sendable { // `count` is behind `lock`
        /// Guards `count`.
        private let lock = NSLock()
        /// The opens so far.
        private var count = 0

        /// Counts one more open and returns how many there have been.
        func next() -> Int {
            lock.withLock {
                count += 1
                return count
            }
        }

        deinit {
            // Nothing to release.
        }
    }

    /// What a SwiftMutator run that fails prints.
    private static let failing = FakeMutator.Scenario(errorText: "swift-mutator: no such option\n", status: 64)

    /// The scan report of the harness's package, with no tools on PATH,
    /// asking for `tiers`.
    private static func report(_ harness: MutationRunHarness, tiers: RequestedTiers) throws -> ScanReport {
        try PackageScanner(describer: harness.package.describer, tools: SnapshotHarness.noTools)
            .scan(packageAt: harness.package.root, tiers: tiers)
    }

    @Test("""
        a requested SwiftMutator run that failed prints one line naming the collector and its reason, after the \
        coverage run's when that was asked for and didn't run either; a collector not asked for prints none
        """)
    func failedRun() throws {
        let harness = try MutationRunHarness(Self.failing)
        defer { harness.remove() }
        let mutationOnly = RequestedTiers(mutation: .full)
        let both = RequestedTiers(coverage: true, mutation: .full)

        let report = try Self.report(harness, tiers: both)

        let mutation = try #require(report.collectors.first { $0.name == MutationAdapter.name })
        let coverage = try #require(report.collectors.first { $0.name == CoverageAdapter.name })
        #expect(mutation.state == .failed && coverage.state != .ran)
        let mutationLine = "Warning: swiftmutator: this scan's mutation run failed (\(try #require(mutation.reason)))"
        let coverageWhat = try #require(CoverageCarry.ownRun(state: coverage.state, reason: coverage.reason))
        #expect(UnrunNotice.lines(for: report, requested: both) == ["Warning: coverage: \(coverageWhat)", mutationLine])
        #expect(UnrunNotice.lines(for: report, requested: mutationOnly) == [mutationLine])
        #expect(UnrunNotice.lines(for: report, requested: .syntaxOnly).isEmpty)
    }

    @Test("a requested SwiftMutator run that ran prints nothing")
    func ranRun() throws {
        let harness = try MutationRunHarness(try FakeMutator.recorded("full"))
        defer { harness.remove() }
        let tiers = RequestedTiers(mutation: .full)

        let report = try Self.report(harness, tiers: tiers)

        #expect(report.collectors.first { $0.name == MutationAdapter.name }?.state == .ran)
        #expect(UnrunNotice.lines(for: report, requested: tiers).isEmpty)
    }

    @Test("""
        a requested SwiftMutator run that failed while the replaced snapshot's results carry prints the carry's \
        warning, though the collector reads ran
        """)
    func carriedRun() throws {
        let harness = try SinceHarness()
        defer { harness.remove() }
        _ = try harness.base()

        let failed = try harness.scan(
            "main",
            acting: SinceHarness.scenario("stopped"),
            request: .full,
            in: harness.workspace
        ).snapshot

        let notice = try #require(failed.report.warnings.first { warning in
            warning.message.hasPrefix("swiftmutator: this scan's mutation run failed (")
        })
        #expect(failed.report.collectors.first { $0.name == MutationAdapter.name }?.state == .ran)
        #expect(UnrunNotice.lines(for: failed.report, requested: RequestedTiers(mutation: .full))
            == ["Warning: " + notice.message])
    }

    @Test("""
        a requested index build that failed prints one line naming the build and its reason, after the coverage \
        run's; one that was skipped says so; the readers it left skipped print none, and a collector not asked for \
        prints nothing
        """)
    func indexBuild() throws {
        var brokenBuild = try IndexGroupHarness.emptyBuild()
        brokenBuild.stderr = "error: no such module 'Missing'\n"
        brokenBuild.status = 1
        let both = RequestedTiers(coverage: true, index: true)
        let indexOnly = RequestedTiers(index: true)
        let outskirts = try IndexGroupHarness.outskirts()
        defer { try? FileManager.default.removeItem(at: outskirts.deletingLastPathComponent()) }
        let periphery = "  periphery:\n    path: \(outskirts.path)\n"

        let noTools = SnapshotHarness.noTools
        try IndexGroupHarness.scanSmall(brokenBuild, extra: periphery, tiers: both, tools: noTools) { outcome in
            let coverage = try #require(outcome.report.collectors.first { $0.name == CoverageAdapter.name })
            let coverageWhat = try #require(CoverageCarry.ownRun(state: coverage.state, reason: coverage.reason))
            let buildLine = "Warning: build: this scan's index build failed "
                + "(swift build exited 1: error: no such module 'Missing')"
            #expect(outcome.statuses[PeripheryAdapter.name]?.reason?.hasPrefix(BuildAdapter.needsBuildLead) == true)
            #expect(UnrunNotice.lines(for: outcome.report, requested: both)
                == ["Warning: coverage: \(coverageWhat)", buildLine])
            #expect(UnrunNotice.lines(for: outcome.report, requested: indexOnly) == [buildLine])
            #expect(UnrunNotice.lines(for: outcome.report, requested: .syntaxOnly).isEmpty)
        }
        try IndexGroupHarness.scanSmall(
            try IndexGroupHarness.emptyBuild(),
            extra: "  build:\n    enabled: false\n" + periphery,
            tiers: indexOnly,
            tools: SnapshotHarness.noTools
        ) { outcome in
            #expect(UnrunNotice.lines(for: outcome.report, requested: indexOnly)
                == ["Warning: build: this scan's index build was skipped (disabled by collectors.build.enabled)"])
        }
    }

    @Test("""
        after a good build, a requested outskirts run that was skipped prints one line naming periphery and its \
        reason, though the index read ran
        """)
    func skippedPeriphery() async throws {
        let scan = try IndexFixtureScan()
        try await scan.run { _, outcome in
            #expect(outcome.statuses[BuildAdapter.name]?.state == .ran)
            #expect(outcome.statuses[IndexAdapter.name]?.state == .ran)
            #expect(UnrunNotice.lines(for: outcome.report, requested: RequestedTiers(index: true)) == [
                "Warning: periphery: this scan's outskirts run was skipped "
                    + "(`outskirts` not found on PATH; set collectors.periphery.path)"
            ])
            #expect(UnrunNotice.lines(for: outcome.report, requested: .syntaxOnly).isEmpty)
        }
    }

    @Test("after a good build, a requested index read that failed prints one line naming index and its reason")
    func failedIndex() async throws {
        let fake = try FakePeriphery.make(try FakePeriphery.recorded())
        defer { fake.remove() }
        var scan = try IndexFixtureScan()
        scan.extra = fake.configuration
        let opens = OpenCount()
        scan.source = { recorded in
            // The index read opens the store first; outskirts' stale-unit
            // move, which the failed read leaves to it, opens it again.
            guard opens.next() > 1 else {
                throw IndexFixtureScanError(description: "the recorded store is unreadable")
            }
            return recorded
        }
        try await scan.run { _, outcome in
            let index = try #require(outcome.statuses[IndexAdapter.name])
            let reason = try #require(index.reason)
            #expect(outcome.statuses[BuildAdapter.name]?.state == .ran)
            #expect(outcome.statuses[PeripheryAdapter.name]?.state == .ran)
            #expect(index.state == .failed)
            #expect(UnrunNotice.lines(for: outcome.report, requested: RequestedTiers(index: true))
                == ["Warning: index: this scan's index read failed (\(reason))"])
        }
    }

    @Test("a requested T1 group whose build, index read and outskirts run all ran prints nothing")
    func ranIndexGroup() async throws {
        try await IndexHarness.scan(indexed: true) { snapshot in
            #expect(UnrunNotice.lines(for: snapshot.report, requested: RequestedTiers(index: true)).isEmpty)
        }
    }

    @Test("""
        a reader's status carried from an earlier scan prints no line of its own, failed or skipped, and neither \
        does one skipped because the build didn't run
        """)
    func carriedReaders() async throws {
        try await IndexHarness.scan(indexed: true) { snapshot in
            let carried = CollectorRunInfo.carriedPrefix + "2026-11-25T10:25:52Z; "
            let status = { (name: String, state: CollectorState, reason: String) in
                CollectorStatus(name: name, state: state, version: nil, reason: reason, options: [])
            }
            let missing = "`outskirts` not found on PATH; set collectors.periphery.path"
            let report = snapshot.report
                .with(index: nil, status: status(IndexAdapter.name, .failed, carried + "exited 1"))
                .with(deadCode: nil, status: status(PeripheryAdapter.name, .skipped, carried + missing))
            let unbuilt = snapshot.report
                .with(index: nil, status: status(IndexAdapter.name, .skipped, BuildAdapter.needsBuildLead + "failed"))
                .with(deadCode: nil, status: status(PeripheryAdapter.name, .skipped, missing))

            #expect(UnrunNotice.lines(for: report, requested: RequestedTiers(index: true)).isEmpty)
            #expect(UnrunNotice.lines(for: unbuilt, requested: RequestedTiers(index: true))
                == ["Warning: periphery: this scan's outskirts run was skipped (\(missing))"])
        }
    }
}
