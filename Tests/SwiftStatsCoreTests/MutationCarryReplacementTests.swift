import Foundation
@testable import SwiftStatsCore
import Testing

/// What a rescan does to mutation results it could carry or can't (M6,
/// design §6.4), on hand-made snapshots of the Coverage fixture:
/// `--drop-mutation` drops only results that don't carry, or that are too
/// damaged to read, carried results keep the warnings describing them,
/// and a rescan whose SwiftMutator run was asked for and failed or was
/// skipped carries what it can, saying so, or is refused naming the run's
/// reason, while a run that ran replaces the results as any scan does.
@Suite("Mutation carry replacements")
struct MutationCarryReplacementTests {
    /// A SwiftMutator run whose tool exited 7.
    private static let failedRun = MutationCarrySamples.ended(.failed, reason: "swift-mutator exited 7")
    /// A SwiftMutator run turned off in the configuration.
    private static let disabledRun = MutationCarrySamples.ended(
        .skipped,
        reason: "disabled by collectors.swiftmutator.enabled"
    )

    @Test("--drop-mutation never drops mutation results a rescan carries")
    func dropKeepsCarried() throws {
        let (package, workspace) = try CarrySamples.store()
        defer { package.remove() }
        let first = try MutationCarrySamples.held(try MutationCarrySamples.scan(git: MutationCarrySamples.clean))
        let results = try #require(first.report.mutation)

        _ = try workspace.save(first, drop: [])
        let rescan = try workspace.save(
            try MutationCarrySamples.scan(git: MutationCarrySamples.clean, date: MutationCarrySamples.later(1)),
            drop: .mutation
        )

        #expect(rescan.snapshot.report.mutation == results)
        #expect(MutationCarrySamples.mutationRun(rescan.snapshot.info) == MutationCarrySamples.carriedRun)
        #expect(try workspace.store.load(id: rescan.id).mutation == StoredMutation(report: results))
    }

    @Test("""
        carried mutation results keep the warnings describing them, the mapping's, the results lines that didn't \
        read and why kills weren't judged, once, however often they are carried, and no other warning of the scan \
        that collected them
        """)
    func carriedWarnings() throws {
        let (package, workspace) = try CarrySamples.store()
        defer { package.remove() }
        let plain = try MutationCarrySamples.scan(git: MutationCarrySamples.clean)
        let held = try MutationCarrySamples.held(plain)
        let describing = [
            MutationSession.warning(
                "Sources/Probe/Case.swift, Sources/Probe/case.swift differ only in case, which a case-insensitive "
                    + "volume can't tell apart, so their mutants may be mapped to the wrong one"
            ),
            MutationSession.warning("skipped 2 lines of the results file that didn't read (4, 9)"),
            MutationSession.warning("swift-mutator report exited 1; kills only suspect tests made aren't judged"),
            MutationSession.warning("3 keys of swift-mutator report's JSON don't read, so their kills aren't judged")
        ]
        let unrelated = MutationSession.warning("discarding the interrupted run of 2026-11-20T09:00:00Z")
        let first = ScannedSnapshot(
            info: held.info,
            report: held.report.with(
                mutation: try #require(held.report.mutation),
                status: MutationCarrySamples.run.status,
                warnings: describing + [unrelated]
            )
        )
        let expected = (plain.report.warnings + describing).sorted(by: PackageScanner.warningOrder)

        _ = try workspace.save(first, drop: [])
        let second = try workspace.save(
            try MutationCarrySamples.scan(git: MutationCarrySamples.clean, date: MutationCarrySamples.later(1)),
            drop: []
        )
        let third = try workspace.save(
            try MutationCarrySamples.scan(git: MutationCarrySamples.clean, date: MutationCarrySamples.later(2)),
            drop: []
        )

        #expect(describing.allSatisfy(MutationSession.describesResults))
        #expect(MutationSession.describesResults(unrelated) == false)
        #expect(second.snapshot.report.warnings == expected)
        #expect(third.snapshot.report.warnings == expected)
        #expect(try workspace.store.report(id: third.id) == third.snapshot.report)
    }

    @Test("""
        a rescan whose SwiftMutator run failed carries the results, with a warning saying the run failed that a \
        later carry doesn't repeat
        """)
    func failedRunCarries() throws {
        let (package, workspace) = try CarrySamples.store()
        defer { package.remove() }
        let held = try MutationCarrySamples.held(try MutationCarrySamples.scan(git: MutationCarrySamples.clean))
        let failedSame = MutationCarrySamples.without(
            try MutationCarrySamples.scan(git: MutationCarrySamples.clean, date: MutationCarrySamples.later(1)),
            run: Self.failedRun
        )
        let failure = MutationSession.warning(
            "this scan's mutation run failed (swift-mutator exited 7), so it keeps the results collected "
                + MutationCarrySamples.collectedAt
        )

        _ = try workspace.save(held, drop: [])
        let carried = try workspace.save(failedSame, drop: [])
        let storedCarried = try workspace.store.report(id: carried.id)
        let later = try workspace.save(
            try MutationCarrySamples.scan(git: MutationCarrySamples.clean, date: MutationCarrySamples.later(2)),
            drop: []
        )

        #expect(carried.snapshot.report.mutation == held.report.mutation)
        #expect(MutationCarrySamples.mutationRun(carried.snapshot.info) == MutationCarrySamples.carriedRun)
        #expect(carried.snapshot.report.warnings.contains(failure))
        #expect(storedCarried == carried.snapshot.report)
        #expect(later.snapshot.report.warnings.contains(failure) == false)
        #expect(later.snapshot.report.mutation == held.report.mutation)
    }

    @Test("""
        a rescan whose SwiftMutator run failed is refused, writing nothing, when the results can't carry, and \
        --drop-mutation replaces them, as it does for a plain rescan
        """)
    func failedRunRefused() throws {
        let (package, workspace) = try CarrySamples.store()
        defer { package.remove() }
        let plain = try MutationCarrySamples.scan(git: MutationCarrySamples.clean)
        let held = try MutationCarrySamples.held(plain)
        let gone = try MutationCarrySamples.scan(
            git: MutationCarrySamples.clean,
            files: MutationCarrySamples.withoutNeverCalled
        )
        let failedGone = MutationCarrySamples.without(gone, run: Self.failedRun)

        let refusal = try MutationCarrySamples.refusal(in: workspace, held: held, rescan: failedGone)
        let dropped = try workspace.save(failedGone, drop: .mutation)
        let droppedResults = try workspace.store.load(id: dropped.id).mutation
        _ = try workspace.save(held, drop: [])
        let droppedPlain = try workspace.save(gone, drop: .mutation)
        let droppedPlainResults = try workspace.store.load(id: droppedPlain.id).mutation

        let neverCalled = try MutationCarrySamples.key("neverCalled", in: plain)
        #expect(refusal.error == MutationCarrySamples.refused(
            "`\(neverCalled)` names no record now; this scan's mutation run failed (swift-mutator exited 7)"
        ))
        #expect(refusal.kept)
        #expect(dropped.snapshot == failedGone && droppedResults == nil)
        #expect(droppedPlain.snapshot == gone && droppedPlainResults == nil)
    }

    @Test("""
        a rescan whose SwiftMutator run was asked for and skipped carries the results, with a warning naming the \
        skip that a later carry doesn't repeat, while a backfill's skip gives none; when they can't carry, the \
        refusal names the skip
        """)
    func skippedRun() throws {
        let (package, workspace) = try CarrySamples.store()
        defer { package.remove() }
        let held = try MutationCarrySamples.held(try MutationCarrySamples.scan(git: MutationCarrySamples.clean))
        let skipped = MutationCarrySamples.without(
            try MutationCarrySamples.scan(git: MutationCarrySamples.clean, date: MutationCarrySamples.later(1)),
            run: Self.disabledRun
        )
        let backfilled = MutationCarrySamples.without(
            try MutationCarrySamples.scan(git: MutationCarrySamples.clean, date: MutationCarrySamples.later(2)),
            run: MutationCarrySamples.ended(.skipped, reason: SnapshotWorkspace.backfillToolSkipReason)
        )
        let skippedGone = MutationCarrySamples.without(
            try MutationCarrySamples.scan(
                git: MutationCarrySamples.clean,
                files: MutationCarrySamples.withoutNeverCalled
            ),
            run: Self.disabledRun
        )
        let skip = "this scan's mutation run was skipped (disabled by collectors.swiftmutator.enabled)"
        let notice = MutationSession.warning(
            "\(skip), so it keeps the results collected \(MutationCarrySamples.collectedAt)"
        )

        _ = try workspace.save(held, drop: [])
        let carried = try workspace.save(skipped, drop: [])
        let storedCarried = try workspace.store.report(id: carried.id)
        let afterBackfill = try workspace.save(backfilled, drop: [])
        let refusal = try MutationCarrySamples.refusal(in: workspace, held: held, rescan: skippedGone)

        #expect(carried.snapshot.report.mutation == held.report.mutation)
        #expect(MutationCarrySamples.mutationRun(carried.snapshot.info) == MutationCarrySamples.carriedRun)
        let expected = (held.report.warnings + [notice]).sorted(by: PackageScanner.warningOrder)
        #expect(carried.snapshot.report.warnings == expected)
        #expect(storedCarried == carried.snapshot.report)
        #expect(afterBackfill.snapshot.report.warnings == held.report.warnings)
        #expect(afterBackfill.snapshot.report.mutation == held.report.mutation)
        let neverCalled = try MutationCarrySamples.key("neverCalled", in: held)
        #expect(refusal.error == MutationCarrySamples.refused("`\(neverCalled)` names no record now; \(skip)"))
        #expect(refusal.kept)
    }

    @Test("""
        held mutation results too damaged to read stop a rescan, naming --drop-mutation, which replaces them \
        without mutation results
        """)
    func damagedHeldResults() throws {
        let (package, workspace) = try CarrySamples.store()
        defer { package.remove() }
        let first = try MutationCarrySamples.held(try MutationCarrySamples.scan(git: MutationCarrySamples.clean))
        let held = try workspace.save(first, drop: [])
        try SnapshotHarness.sqlite(
            workspace.store.url,
            "UPDATE mutant SET verdict = 'gone' WHERE snapshotId = \(held.id) AND ordinal = 0"
        )
        let rescan = try MutationCarrySamples.scan(
            git: MutationCarrySamples.clean,
            date: MutationCarrySamples.later(1)
        )

        let damaged = StoreError.damagedMutation(
            snapshot: "Probe at c1",
            reason: "the mutation rows of snapshot \(held.id)"
        )
        #expect(throws: damaged) {
            try workspace.save(rescan, drop: [])
        }
        #expect(throws: damaged) {
            try workspace.save(rescan, drop: .coverage)
        }
        #expect(damaged.description == "the snapshot of Probe at c1 holds mutation results too damaged to read "
            + "(the mutation rows of snapshot \(held.id)); run scan --mutation to collect them again, "
            + "or --drop-mutation to replace it without them")
        #expect(try workspace.store.snapshotID(package: "Probe", packagePath: "", commit: "c1", isDirty: false)
            == held.id)
        let dropped = try workspace.save(rescan, drop: .mutation)

        #expect(dropped.snapshot == rescan)
        #expect(try workspace.store.load(id: dropped.id).mutation == nil)
        #expect(try workspace.store.snapshotID(package: "Probe", packagePath: "", commit: "c1", isDirty: false)
            == dropped.id)
    }

    @Test("a scan whose SwiftMutator run ran replaces held results without carrying them, as the refusal says")
    func ranReplaces() throws {
        let (package, workspace) = try CarrySamples.store()
        defer { package.remove() }
        let results = try MutationCarrySamples.results()
        let rerunResults = MutationSnapshots.changing(results, mode: .full, base: nil) { mutant in
            mutant.verdict == .notCovered ? nil : mutant
        }
        let rerun = MutationSnapshots.replacing(
            try MutationCarrySamples.scan(git: MutationCarrySamples.clean, files: MutationCarrySamples.movedCounter),
            git: MutationCarrySamples.clean,
            mutation: rerunResults,
            run: MutationSnapshots.ran(identity: MutationSnapshots.identity)
        )

        let held = try MutationCarrySamples.held(try MutationCarrySamples.scan(git: MutationCarrySamples.clean))
        _ = try workspace.save(held, drop: [])
        let replaced = try workspace.save(rerun, drop: [])

        #expect(replaced.snapshot == rerun)
        #expect(try workspace.store.load(id: replaced.id).mutation == StoredMutation(report: rerunResults))
        #expect(StoreError.mutationNotKept(snapshot: "Probe at c1", collectedAt: "a date", reason: "a reason")
            .description == "the snapshot of Probe at c1 holds mutation results from a date that this scan can't "
            + "keep (a reason); run scan --mutation to collect them again, or --drop-mutation to replace them")
    }
}
