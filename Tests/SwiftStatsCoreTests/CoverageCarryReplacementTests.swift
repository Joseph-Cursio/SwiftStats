import Foundation
@testable import SwiftStatsCore
import Testing

/// What a rescan does to coverage it could carry or can't (M5, design §6),
/// on hand-made snapshots: `--drop-coverage` drops only coverage that
/// doesn't carry, or that is too damaged to read, carried coverage keeps
/// the warnings mapping it gave, and a rescan whose coverage run was asked
/// for and failed or was skipped carries what it can, saying so, or is
/// refused naming the run's reason, while a run that ran replaces the
/// coverage as any scan does.
@Suite("Coverage carry replacements")
struct CoverageCarryReplacementTests {
    /// A coverage run whose build failed.
    private static let failedRun = CollectorRunInfo(
        name: CoverageAdapter.name,
        state: .failed,
        reason: "the build failed",
        version: nil,
        identity: nil,
        identityLabel: nil,
        options: [],
        durationMilliseconds: 0
    )

    @Test("--drop-coverage never drops coverage a rescan carries")
    func dropKeepsCarried() throws {
        let (package, workspace) = try CarrySamples.store()
        defer { package.remove() }
        let first = try CarrySamples.covered(try CarrySamples.scan(git: CarrySamples.clean))
        let coverage = try #require(first.report.coverage)

        _ = try workspace.save(first, dropCoverage: false)
        let rescan = try workspace.save(
            try CarrySamples.scan(git: CarrySamples.clean, date: SnapshotHarness.date + CarrySamples.day),
            dropCoverage: true
        )

        #expect(rescan.snapshot.report.coverage == coverage)
        #expect(CarryHarness.coverageRun(rescan.snapshot.info)?.reason
            == "carried from the scan of \(first.info.date); \(CarrySamples.failing)")
        #expect(try workspace.store.load(id: rescan.id).coverage
            == StoredCoverage(collectedAt: first.info.date, report: coverage))
    }

    @Test("""
        carried coverage keeps the warnings mapping it gave, once, however often it is carried, and no other \
        warning of the scan that collected it
        """)
    func carriedWarnings() throws {
        let (package, workspace) = try CarrySamples.store()
        defer { package.remove() }
        let plain = try CarrySamples.scan(git: CarrySamples.clean)
        let unrelated = ScanWarning(file: "Sources/Kit/Kit.swift", message: "an unrelated problem")
        let first = CoverageSnapshots.replacing(
            plain,
            git: CarrySamples.clean,
            coverage: CoverageRows.normalized(try CoverageSamples.shapes(records: plain.report.records)),
            run: CarrySamples.run,
            warnings: [PackageScanner.undemangledWarning, unrelated]
        )
        let expected = (plain.report.warnings + [PackageScanner.undemangledWarning])
            .sorted(by: PackageScanner.warningOrder)

        _ = try workspace.save(first, dropCoverage: false)
        let second = try workspace.save(
            try CarrySamples.scan(git: CarrySamples.clean, date: SnapshotHarness.date + CarrySamples.day),
            dropCoverage: false
        )
        let third = try workspace.save(
            try CarrySamples.scan(git: CarrySamples.clean, date: SnapshotHarness.date + 2 * CarrySamples.day),
            dropCoverage: false
        )

        #expect(second.snapshot.report.warnings == expected)
        #expect(third.snapshot.report.warnings == expected)
        #expect(try workspace.store.report(id: third.id) == third.snapshot.report)
    }

    @Test("""
        a rescan whose coverage run failed carries the coverage, with a warning saying the run failed that a \
        later carry doesn't repeat
        """)
    func failedRunCarries() throws {
        let (package, workspace) = try CarrySamples.store()
        defer { package.remove() }
        let held = try CarrySamples.covered(try CarrySamples.scan(git: CarrySamples.clean))
        let failedSame = CoverageSnapshots.replacing(
            try CarrySamples.scan(git: CarrySamples.clean, date: SnapshotHarness.date + CarrySamples.day),
            git: CarrySamples.clean,
            coverage: nil,
            run: Self.failedRun
        )
        let collected = SnapshotScanner.format(SnapshotHarness.date)
        let failure = ScanWarning(
            file: nil,
            message: "coverage: this scan's coverage run failed (the build failed), "
                + "so it keeps the coverage collected \(collected)"
        )

        _ = try workspace.save(held, dropCoverage: false)
        let carried = try workspace.save(failedSame, dropCoverage: false)
        let storedCarried = try workspace.store.report(id: carried.id)
        let later = try workspace.save(
            try CarrySamples.scan(git: CarrySamples.clean, date: SnapshotHarness.date + 2 * CarrySamples.day),
            dropCoverage: false
        )

        #expect(carried.snapshot.report.coverage == held.report.coverage)
        #expect(CarryHarness.coverageRun(carried.snapshot.info)?.reason
            == "carried from the scan of \(collected); \(CarrySamples.failing)")
        #expect(carried.snapshot.report.warnings.contains(failure))
        #expect(storedCarried == carried.snapshot.report)
        #expect(later.snapshot.report.warnings.contains(failure) == false)
        #expect(later.snapshot.report.coverage == held.report.coverage)
    }

    @Test("""
        a rescan whose coverage run failed is refused, writing nothing, when the coverage can't carry, and \
        --drop-coverage replaces it, as it does for a plain rescan
        """)
    func failedRunRefused() throws {
        let (package, workspace) = try CarrySamples.store()
        defer { package.remove() }
        let plain = try CarrySamples.scan(git: CarrySamples.clean)
        let held = try CarrySamples.covered(plain)
        let gone = try CarrySamples.scan(git: CarrySamples.clean, files: CarrySamples.withoutHelper)
        let failedGone = CoverageSnapshots.replacing(gone, git: CarrySamples.clean, coverage: nil, run: Self.failedRun)

        let refusal = try CarryHarness.refusal(in: workspace, held: held, rescan: failedGone)
        let dropped = try workspace.save(failedGone, dropCoverage: true)
        let droppedCoverage = try workspace.store.load(id: dropped.id).coverage
        _ = try workspace.save(held, dropCoverage: false)
        let droppedPlain = try workspace.save(gone, dropCoverage: true)
        let droppedPlainCoverage = try workspace.store.load(id: droppedPlain.id).coverage

        let helper = try CarrySamples.key("helper", in: plain)
        #expect(refusal.error == CarrySamples.refused(
            "`\(helper)` names no record now; this scan's coverage run failed (the build failed)"
        ))
        #expect(refusal.kept)
        #expect(dropped.snapshot == failedGone && droppedCoverage == nil)
        #expect(droppedPlain.snapshot == gone && droppedPlainCoverage == nil)
    }

    @Test("""
        a rescan whose coverage run was asked for and skipped carries the coverage, with a warning naming the skip \
        that a later carry doesn't repeat, while a backfill's skip gives none
        """)
    func skippedRunCarries() throws {
        let (package, workspace) = try CarrySamples.store()
        defer { package.remove() }
        let held = try CarrySamples.covered(try CarrySamples.scan(git: CarrySamples.clean))
        let skipped = CoverageSnapshots.replacing(
            try CarrySamples.scan(git: CarrySamples.clean, date: SnapshotHarness.date + CarrySamples.day),
            git: CarrySamples.clean,
            coverage: nil,
            run: CarrySamples.notFound
        )
        let backfillRun = CollectorRunInfo(
            name: CoverageAdapter.name,
            state: .skipped,
            reason: SnapshotWorkspace.backfillToolSkipReason,
            version: nil,
            identity: nil,
            identityLabel: nil,
            options: [],
            durationMilliseconds: 0
        )
        let backfilled = CoverageSnapshots.replacing(
            try CarrySamples.scan(git: CarrySamples.clean, date: SnapshotHarness.date + 3 * CarrySamples.day),
            git: CarrySamples.clean,
            coverage: nil,
            run: backfillRun
        )
        let collected = SnapshotScanner.format(SnapshotHarness.date)
        let notice = ScanWarning(
            file: nil,
            message: "coverage: this scan's coverage run was skipped (`swift` not found on PATH; "
                + "set collectors.coverage.path), so it keeps the coverage collected \(collected)"
        )

        _ = try workspace.save(held, dropCoverage: false)
        let carried = try workspace.save(skipped, dropCoverage: false)
        let storedCarried = try workspace.store.report(id: carried.id)
        let later = try workspace.save(
            try CarrySamples.scan(git: CarrySamples.clean, date: SnapshotHarness.date + 2 * CarrySamples.day),
            dropCoverage: false
        )
        let afterBackfill = try workspace.save(backfilled, dropCoverage: false)

        #expect(carried.snapshot.report.coverage == held.report.coverage)
        #expect(CarryHarness.coverageRun(carried.snapshot.info)?.reason
            == "carried from the scan of \(collected); \(CarrySamples.failing)")
        let expected = (held.report.warnings + [notice]).sorted(by: PackageScanner.warningOrder)
        #expect(carried.snapshot.report.warnings == expected)
        #expect(storedCarried == carried.snapshot.report)
        #expect(later.snapshot.report.warnings == held.report.warnings)
        #expect(afterBackfill.snapshot.report.warnings == held.report.warnings)
        #expect(afterBackfill.snapshot.report.coverage == held.report.coverage)
    }

    @Test("""
        a rescan whose coverage run was asked for and skipped is refused, naming the skip, when the coverage \
        can't carry
        """)
    func skippedRunRefused() throws {
        let (package, workspace) = try CarrySamples.store()
        defer { package.remove() }
        let plain = try CarrySamples.scan(git: CarrySamples.clean)
        let gone = try CarrySamples.scan(git: CarrySamples.clean, files: CarrySamples.withoutHelper)
        let skippedGone = CoverageSnapshots.replacing(
            gone,
            git: CarrySamples.clean,
            coverage: nil,
            run: CarrySamples.notFound
        )

        let held = try CarrySamples.covered(plain)
        let refusal = try CarryHarness.refusal(in: workspace, held: held, rescan: skippedGone)
        let plainRefusal = try CarryHarness.refusal(in: workspace, held: held, rescan: gone)

        let helper = try CarrySamples.key("helper", in: plain)
        #expect(refusal.error == CarrySamples.refused(
            "`\(helper)` names no record now; this scan's coverage run was skipped "
                + "(`swift` not found on PATH; set collectors.coverage.path)"
        ))
        #expect(plainRefusal.error == CarrySamples.refused("`\(helper)` names no record now"))
        #expect(refusal.kept && plainRefusal.kept)
    }

    @Test("""
        held coverage too damaged to read stops a rescan, naming --drop-coverage, which replaces it \
        without coverage
        """)
    func damagedHeldCoverage() throws {
        let (package, workspace) = try CarrySamples.store()
        defer { package.remove() }
        let covered = try CarrySamples.covered(try CarrySamples.scan(git: CarrySamples.clean))
        let held = try workspace.save(covered, dropCoverage: false)
        try SnapshotHarness.sqlite(
            workspace.store.url,
            "UPDATE coverageLine SET lines = '1:5' WHERE snapshotId = \(held.id) AND file = 'Sources/Kit/Kit.swift'"
        )
        let rescan = try CarrySamples.scan(git: CarrySamples.clean, date: SnapshotHarness.date + CarrySamples.day)

        let damaged = StoreError.damagedCoverage(
            snapshot: "Probe at c1",
            reason: "the coverage line data of Sources/Kit/Kit.swift"
        )
        #expect(throws: damaged) {
            try workspace.save(rescan, dropCoverage: false)
        }
        #expect(damaged.description == "the snapshot of Probe at c1 holds coverage too damaged to read "
            + "(the coverage line data of Sources/Kit/Kit.swift); run scan --coverage to collect it again, "
            + "or --drop-coverage to replace it without its coverage")
        #expect(try workspace.store.snapshotID(package: "Probe", packagePath: "", commit: "c1", isDirty: false)
            == held.id)
        let dropped = try workspace.save(rescan, dropCoverage: true)

        #expect(dropped.snapshot == rescan)
        #expect(try workspace.store.load(id: dropped.id).coverage == nil)
        #expect(try workspace.store.snapshotID(package: "Probe", packagePath: "", commit: "c1", isDirty: false)
            == dropped.id)
    }

    @Test("a scan whose coverage run ran replaces held coverage without carrying it")
    func ranReplaces() throws {
        let (package, workspace) = try CarrySamples.store()
        defer { package.remove() }
        let rerun = try CarrySamples.covered(
            try CarrySamples.scan(git: CarrySamples.clean, date: SnapshotHarness.date + CarrySamples.day),
            run: CoverageSnapshots.ran(options: ["map: " + CoverageMapper.rule, "links: " + CoverageTestLinks.rule])
        )

        let held = try CarrySamples.covered(try CarrySamples.scan(git: CarrySamples.clean))
        _ = try workspace.save(held, dropCoverage: false)
        let replaced = try workspace.save(rerun, dropCoverage: false)

        #expect(replaced.snapshot == rerun)
        #expect(try workspace.store.load(id: replaced.id).coverage?.collectedAt == rerun.info.date)
    }
}
