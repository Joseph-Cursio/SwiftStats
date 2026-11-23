import Foundation
@testable import SwiftStatsCore
import Testing

/// The mutation block of a scan's JSON (M6, design §3), through the fake
/// tools acting out the Coverage fixture's recorded run on a copy of the
/// fixture: a run that ran is mapped onto the scan's records and passed
/// through the store's rows, recording the commit its copy checked out,
/// and rolled up, and the collector's options end with the map rule; a
/// run that failed, or wasn't asked for, leaves no block and no roll-ups.
@Suite("Mutation scan JSON")
struct MutationScanTests {
    /// The settings pointing the collectors at `tools`.
    private static func settings(_ tools: FakeMutator) -> String {
        "collectors:\n  coverage:\n    path: \(tools.swift.path)\n  swiftmutator:\n    path: \(tools.mutator.path)\n"
    }

    @Test("""
        a scan whose SwiftMutator run ran holds its results mapped onto the scan's records, as the store's rows \
        hold them, recording the commit the copy checked out and where the results file was kept, rolled up on \
        the production modules, and the collector's options end with the map rule
        """)
    func ranScan() throws {
        let fake = try FakeMutator.make(FakeMutator.recorded("full", in: MutationFixture.coverageDirectory))
        defer { fake.remove() }
        let harness = try MappingHarness.coverage(adding: Self.settings(fake))
        defer { harness.remove() }
        let root = harness.package.root
        try SnapshotHarness.runGit(["init", "--quiet", "--initial-branch=main"], in: root)
        try SnapshotHarness.runGit(["add", "--all"], in: root)
        try SnapshotHarness.runGit(["commit", "--quiet", "--message", "Fixture"], in: root)
        let head = try SnapshotHarness.runGit(["rev-parse", "HEAD"], in: root)
        let (results, suspects) = try MappingHarness.coverageRun()
        let mapped = harness.report(results, suspects: suspects)

        let report = try PackageScanner(describer: harness.package.describer, tools: SnapshotHarness.noTools)
            .scan(packageAt: root, tiers: RequestedTiers(mutation: .full))

        let mutation = try #require(report.mutation)
        let status = try #require(report.collectors.first { $0.name == MutationAdapter.name })
        #expect(status.state == .ran)
        #expect(status.options.last == "map: " + MutationMapper.rule)
        #expect(mutation.mutants == mapped.mutants)
        #expect(mutation.records == mapped.records && mutation.attachments == mapped.attachments)
        #expect(mutation.everyMutant == mapped.everyMutant && mutation.unmapped == ["excluded": 1])
        #expect(mutation.files == mapped.files && mutation.collectedAt == MappingHarness.coverageStartedAt)
        #expect(MutationRows.normalized(mutation) == mutation)
        let run = try #require(mutation.runs.first)
        #expect(run.commit == head && run.dirty == false)
        #expect(run.resultsFile.hasPrefix(".swiftstats/mutation/runs/") && run.resultsFile.hasSuffix("/results.jsonl"))
        let kept = try Data(contentsOf: harness.package.root.appendingPathComponent(run.resultsFile))
        #expect(run.resultsSHA256 == ContentHash.sha256(kept))
        let production = try #require(report.rollups.first { $0.scope == .project && $0.name == "production" })
        #expect(production.mutation?.score == MutationScore(killed: 29, scored: 31))
        #expect(report.rollups.first { $0.name == "ProbeTests" }?.mutation == nil)
        #expect(try JSONDecoder().decode(ScanReport.self, from: ScanReportEncoder.encode(report)) == report)
    }

    @Test("a scan whose SwiftMutator run failed, or that didn't ask for one, has no mutation block or roll-ups")
    func noBlock() throws {
        let failing = try MutationRunHarness(try FakeMutator.recorded("stopped"))
        defer { failing.remove() }
        let scanner = PackageScanner(describer: failing.package.describer, tools: SnapshotHarness.noTools)

        let failed = try scanner.scan(packageAt: failing.package.root, tiers: RequestedTiers(mutation: .full))
        let plain = try scanner.scan(packageAt: failing.package.root)

        #expect(failed.collectors.first { $0.name == MutationAdapter.name }?.state == .failed)
        #expect(failed.mutation == nil)
        #expect(plain.mutation == nil)
        #expect((failed.rollups + plain.rollups).allSatisfy { $0.mutation == nil })
    }
}
