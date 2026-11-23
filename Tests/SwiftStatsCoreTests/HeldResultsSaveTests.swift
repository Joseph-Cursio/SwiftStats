import Foundation
@testable import SwiftStatsCore
import Testing

/// A rescan of a snapshot holding both coverage and mutation results (M6,
/// design §6.4), on the Coverage fixture scanned with its recorded coverage
/// run and given its recorded SwiftMutator run: both are decided before
/// anything is written, coverage first, so a coverage refusal is the one a
/// rescan that keeps neither gets, a mutation refusal after coverage
/// carries still writes nothing, and when both carry they are stored in
/// one save; each `--drop-` option lets only its own results go.
@Suite("Coverage and mutation held together")
struct HeldResultsSaveTests {
    /// The Coverage fixture at `c1` with its recorded coverage and
    /// mutation results.
    private static func heldBoth() throws -> ScannedSnapshot {
        try MutationCarrySamples.held(try CoverageFixture.snapshot(commit: "c1"))
    }

    /// Whether `workspace`'s snapshot of `c1` is still `id`, holding
    /// coverage and mutation results.
    private static func untouched(_ workspace: SnapshotWorkspace, id: Int64) throws -> Bool {
        let current = try workspace.store.snapshotID(package: "Probe", packagePath: "", commit: "c1", isDirty: false)
        return try current == id && workspace.store.holdsCoverage(id: id) && workspace.store.holdsMutation(id: id)
    }

    @Test("""
        a plain rescan carries the coverage and the mutation results in one save, each run with its own date, \
        and the roll-ups, the stored report and its rows agree with the scan that collected them
        """)
    func bothCarried() throws {
        let (package, workspace) = try CarrySamples.store()
        defer { package.remove() }
        let held = try Self.heldBoth()
        let coverage = try #require(held.report.coverage)
        let mutation = try #require(held.report.mutation)

        _ = try workspace.save(held, drop: [])
        let rescan = try workspace.save(
            try MutationCarrySamples.scan(git: MutationCarrySamples.clean, date: MutationCarrySamples.later(1)),
            drop: []
        )

        #expect(rescan.snapshot.report.coverage == coverage)
        #expect(rescan.snapshot.report.mutation == mutation)
        #expect(rescan.snapshot.report.rollups == held.report.rollups)
        #expect(CarryHarness.coverageRun(rescan.snapshot.info)?.reason?.hasPrefix(
            "carried from the scan of \(held.info.date)"
        ) == true)
        #expect(MutationCarrySamples.mutationRun(rescan.snapshot.info) == MutationCarrySamples.carriedRun)
        let stored = try workspace.store.load(id: rescan.id)
        #expect(stored.coverage == StoredCoverage(collectedAt: held.info.date, report: coverage))
        #expect(stored.mutation == StoredMutation(report: mutation))
        #expect(stored.info == rescan.snapshot.info)
        #expect(try workspace.store.report(id: rescan.id) == rescan.snapshot.report)
        let numbers = try CarryHarness.coverageNumbers(held.report.rollups)
            + MutationCarrySamples.mutationNumbers(held.report.rollups)
        #expect(CarryHarness.coverageNumbers(stored.rollups) + MutationCarrySamples.mutationNumbers(stored.rollups)
            == numbers)
    }

    @Test("""
        when neither carries, the coverage refusal comes first; --drop-coverage then meets the mutation refusal, \
        and dropping both replaces the snapshot without either
        """)
    func coverageRefusesFirst() throws {
        let (package, workspace) = try CarrySamples.store()
        defer { package.remove() }
        let held = try Self.heldBoth()
        let id = try workspace.save(held, drop: []).id
        let moved = try MutationCarrySamples.scan(
            git: MutationCarrySamples.clean,
            files: MutationCarrySamples.movedCounter,
            date: MutationCarrySamples.later(1)
        )

        var first: StoreError?
        do {
            try workspace.save(moved, drop: [])
        } catch let error as StoreError {
            first = error
        }
        let keptAfterFirst = try Self.untouched(workspace, id: id)
        let record = try MutationCarrySamples.firstCounterRecord(in: held)
        #expect(throws: MutationCarrySamples.refused("`\(record)` spans other lines now")) {
            try workspace.save(moved, drop: .coverage)
        }
        let keptAfterSecond = try Self.untouched(workspace, id: id)
        let dropped = try workspace.save(moved, drop: [.coverage, .mutation])
        let stored = try workspace.store.load(id: dropped.id)

        guard case let .coverageNotKept(snapshot, collectedAt, reason) = first else {
            Issue.record("expected the coverage refusal, got \(String(describing: first))")
            return
        }
        #expect(snapshot == "Probe at c1" && collectedAt == held.info.date && reason.hasSuffix("spans other lines now"))
        #expect(keptAfterFirst && keptAfterSecond)
        #expect(dropped.snapshot == moved && stored.coverage == nil && stored.mutation == nil)
    }

    @Test("""
        when the coverage carries and the mutation results don't, nothing is written, and --drop-mutation keeps \
        the coverage while it drops them
        """)
    func mutationRefusedAfterCoverage() throws {
        let (package, workspace) = try CarrySamples.store()
        defer { package.remove() }
        let held = try Self.heldBoth()
        let id = try workspace.save(held, drop: []).id
        let edited = try MutationCarrySamples.scan(
            git: MutationCarrySamples.clean,
            files: MutationCarrySamples.editedCounter,
            date: MutationCarrySamples.later(1)
        )

        #expect(throws: MutationCarrySamples.refused("`\(MutationCarrySamples.counterPath)` holds other bytes now")) {
            try workspace.save(edited, drop: [])
        }
        let kept = try Self.untouched(workspace, id: id)
        let dropped = try workspace.save(edited, drop: .mutation)
        let stored = try workspace.store.load(id: dropped.id)

        #expect(kept)
        let coverage = try #require(held.report.coverage)
        #expect(stored.coverage == StoredCoverage(collectedAt: held.info.date, report: coverage))
        #expect(stored.mutation == nil && dropped.snapshot.report.mutation == nil)
        #expect(MutationCarrySamples.mutationRun(dropped.snapshot.info) == MutationSnapshots.skipped)
    }
}
