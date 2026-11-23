import Foundation
@testable import SwiftStatsCore
import Testing

/// A SwiftMutator run's results kept until its snapshot is stored (M6,
/// design §6.4, as built; review findings 4 and 16): a save still refused
/// after a run that ran keeps `pending.json` naming the results, says so,
/// and `scan --mutation --resume`, once the scan lets the snapshot be
/// stored, stores them without running SwiftMutator again; a stored
/// snapshot, a new run or `scan --no-store` leave nothing pending.
@Suite("Mutation results kept until stored")
struct HeldResultsKeptTests {
    /// The SwiftMutator run in `snapshot`, without its duration.
    private static func run(_ snapshot: ScannedSnapshot) -> [String?] {
        guard let run = snapshot.info.collectors.first(where: { $0.name == MutationAdapter.name }) else {
            return []
        }
        return [run.state.rawValue, run.reason, run.identity, run.version] + run.options
    }

    @Test("""
        a save refused after a full run that ran keeps its results and says so; scan --mutation --resume is \
        refused up front until --drop-coverage, then stores the same results without running SwiftMutator and \
        forgets them
        """)
    func fullRunKept() throws {
        let harness = try HeldResultsHarness()
        defer { harness.remove() }
        try harness.edit("Edit A.")
        try harness.storeCoverage()
        try harness.edit("Edit B.")
        let plain = try #require(try harness.plainRefusal())
        let scanned = try harness.unchecked(RequestedTiers(mutation: .full), base: nil, acting: "full")
        let file = try #require(scanned.report.mutation?.runs.first?.resultsFile)

        let refused = try harness.storeError { _ = try harness.workspace.storing(scanned, drop: []) }

        #expect(refused == .mutationResultsKept(refusal: plain.description, advised: true))
        #expect(refused?.description.hasSuffix(
            "; this scan's SwiftMutator results are kept: add --mutation --resume to either scan to store them "
                + "without running SwiftMutator again"
        ) == true)
        #expect(try harness.pending()?.kept?.resultsFile == file)
        #expect(harness.since.runs() == 1)

        let again = try harness.storeError { _ = try harness.scan(RequestedTiers(mutation: .resume), drop: []) }
        #expect(again == plain)
        #expect(try harness.pending()?.kept?.resultsFile == file)

        let stored = try harness.scan(RequestedTiers(mutation: .resume), drop: .coverage)

        #expect(harness.since.runs() == 1)
        #expect(stored.snapshot.report.mutation == scanned.report.mutation)
        #expect(Self.run(stored.snapshot) == Self.run(scanned))
        #expect(try harness.workspace.store.holdsMutation(id: stored.id))
        #expect(try harness.pending() == nil)
    }

    @Test("""
        the kept results of a --since run resume as its merge with the base, keeping SwiftMutator's selection, \
        without running it again
        """)
    func sinceRunKept() throws {
        let harness = try HeldResultsHarness()
        defer { harness.remove() }
        _ = try harness.since.base()
        try harness.since.repository.checkOut("since")
        try harness.storeCoverage()
        let lookup = MutationBase.Lookup(
            store: harness.workspace.store,
            package: "Mutation",
            root: harness.since.root,
            git: GitReader.read(packageRoot: harness.since.root, ignoring: [])
        )
        let base = try MutationBase.select(revision: "main", lookup: lookup)
        let scanned = try harness.unchecked(RequestedTiers(mutation: .since("main")), base: base, acting: "since")
        let merged = try #require(scanned.report.mutation)
        let refused = try harness.storeError { _ = try harness.workspace.storing(scanned, drop: []) }
        #expect(merged.mode == .since)
        #expect(try harness.pending()?.kept?.selection.isEmpty == false)

        try harness.since.fake.act(SinceHarness.scenario("since"))
        let stored = try harness.workspace.scanWorkingTree(
            history: .skipped("test"),
            tiers: RequestedTiers(mutation: .resume),
            drop: .coverage
        )

        #expect(refused.map { if case .mutationResultsKept = $0 { true } else { false } } == true)
        #expect(harness.since.runs() == 2)
        #expect(stored.snapshot.report.mutation == merged)
        #expect(Self.run(stored.snapshot) == Self.run(scanned))
        #expect(try harness.pending() == nil)
    }

    @Test("""
        a new run discards kept results, saying whose they were, and neither a stored scan nor scan --no-store \
        leaves its run's results pending
        """)
    func keptDiscarded() throws {
        let harness = try HeldResultsHarness()
        defer { harness.remove() }
        try harness.edit("Edit A.")
        try harness.storeCoverage()
        try harness.edit("Edit B.")
        let scanned = try harness.unchecked(RequestedTiers(mutation: .full), base: nil, acting: "full")
        _ = try harness.storeError { _ = try harness.workspace.storing(scanned, drop: []) }
        let started = try #require(try harness.pending()?.startedAt)

        let stored = try harness.scan(RequestedTiers(mutation: .full), drop: .coverage)
        let discarding = "swiftmutator: discarding the results of the run of \(started), whose snapshot wasn't stored"

        #expect(stored.snapshot.report.warnings.contains { $0.message == discarding })
        #expect(try harness.pending() == nil)
        try harness.since.fake.act(SinceHarness.scenario("full"))
        let report = try harness.workspace.scanner.scanner.scan(
            packageAt: harness.since.root,
            configurationFile: harness.workspace.configurationFile,
            tiers: RequestedTiers(mutation: .full)
        )
        #expect(report.mutation != nil)
        #expect(try harness.pending() == nil)
        #expect(harness.since.runs() == 3)
    }
}
