import Foundation
@testable import SwiftStatsCore
import Testing

/// What `scan` prints on standard error about an opt-in run it asked for
/// that collected nothing (`UnrunNotice`): the line names the collector and
/// how its run ended, in the carry's words, or is the carry's own warning
/// when the replaced snapshot's results were kept; a run that ran prints
/// nothing, and neither does a collector that wasn't asked for.
@Suite("Unrun notices")
struct UnrunNoticeTests {
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
        run's; one that was skipped says so; one that ran, or wasn't asked for, prints nothing
        """)
    func indexBuild() throws {
        var brokenBuild = try IndexGroupHarness.emptyBuild()
        brokenBuild.stderr = "error: no such module 'Missing'\n"
        brokenBuild.status = 1
        let both = RequestedTiers(coverage: true, index: true)
        let indexOnly = RequestedTiers(index: true)

        let noTools = SnapshotHarness.noTools
        try IndexGroupHarness.scanSmall(brokenBuild, extra: "", tiers: both, tools: noTools) { outcome in
            let coverage = try #require(outcome.report.collectors.first { $0.name == CoverageAdapter.name })
            let coverageWhat = try #require(CoverageCarry.ownRun(state: coverage.state, reason: coverage.reason))
            let buildLine = "Warning: build: this scan's index build failed "
                + "(swift build exited 1: error: no such module 'Missing')"
            #expect(UnrunNotice.lines(for: outcome.report, requested: both)
                == ["Warning: coverage: \(coverageWhat)", buildLine])
            #expect(UnrunNotice.lines(for: outcome.report, requested: indexOnly) == [buildLine])
            #expect(UnrunNotice.lines(for: outcome.report, requested: .syntaxOnly).isEmpty)
        }
        try IndexGroupHarness.scanSmall(
            try IndexGroupHarness.emptyBuild(),
            extra: "  build:\n    enabled: false\n",
            tiers: indexOnly,
            tools: SnapshotHarness.noTools
        ) { outcome in
            #expect(UnrunNotice.lines(for: outcome.report, requested: indexOnly)
                == ["Warning: build: this scan's index build was skipped (disabled by collectors.build.enabled)"])
        }
        try IndexGroupHarness.scanSmall(
            try IndexGroupHarness.emptyBuild(),
            extra: "",
            tiers: indexOnly,
            tools: SnapshotHarness.noTools
        ) { outcome in
            #expect(outcome.report.collectors.first { $0.name == BuildAdapter.name }?.state == .ran)
            #expect(UnrunNotice.lines(for: outcome.report, requested: indexOnly).isEmpty)
        }
    }
}
