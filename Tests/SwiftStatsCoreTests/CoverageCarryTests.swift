import Foundation
@testable import SwiftStatsCore
import Testing

/// Keeping coverage across rescans that don't run the coverage collector
/// (M5, design §6), on hand-made snapshots: a rescan of the same tree
/// carries the coverage, clean or with the same uncommitted changes, with
/// the original run and the date it was collected, however often; a rescan
/// the coverage doesn't describe is refused before anything is written,
/// naming the first of its reasons (`CoverageCarryReplacementTests`
/// covers `--drop-coverage`, failed runs and runs that replace it).
@Suite("Coverage carry")
struct CoverageCarryTests {
    @Test("""
        carried twice, coverage keeps the run that collected it, names that scan's date and its failing tests once, \
        and gives the roll-ups the first scan gave; a later refusal names that date too
        """)
    func repeatedCarry() throws {
        let (package, workspace) = try CarrySamples.store()
        defer { package.remove() }
        let first = try CarrySamples.covered(try CarrySamples.scan(git: CarrySamples.clean))
        let coverage = try #require(first.report.coverage)
        let carriedReason = "carried from the scan of \(first.info.date); \(CarrySamples.failing)"

        let original = try workspace.save(first, dropCoverage: false)
        let second = try workspace.save(
            try CarrySamples.scan(git: CarrySamples.clean, date: SnapshotHarness.date + CarrySamples.day),
            dropCoverage: false
        )
        let third = try workspace.save(
            try CarrySamples.scan(git: CarrySamples.clean, date: SnapshotHarness.date + 2 * CarrySamples.day),
            dropCoverage: false
        )

        #expect(second.snapshot.report.coverage == coverage)
        #expect(second.snapshot.report.rollups == first.report.rollups)
        for carried in [second.snapshot, third.snapshot] {
            #expect(CarryHarness.coverageRun(carried.info) == CollectorRunInfo(
                name: CoverageAdapter.name,
                state: .ran,
                reason: carriedReason,
                version: CarrySamples.run.version,
                identity: CarrySamples.run.identity,
                identityLabel: nil,
                options: CarrySamples.run.options,
                durationMilliseconds: CarrySamples.run.durationMilliseconds
            ))
            #expect(carried.report.collectors.first { $0.name == CoverageAdapter.name }?.reason == carriedReason)
        }
        let stored = try workspace.store.load(id: third.id)
        #expect(stored.coverage == StoredCoverage(collectedAt: first.info.date, report: coverage))
        #expect(stored.info == third.snapshot.info)
        #expect(try workspace.store.report(id: third.id) == third.snapshot.report)
        let numbers = try CarryHarness.coverageNumbers(first.report.rollups)
        #expect(CarryHarness.coverageNumbers(stored.rollups) == numbers && numbers.isEmpty == false)
        #expect(original.id != third.id)

        let moved = try CarrySamples.scan(
            git: CarrySamples.clean,
            files: ["Sources/Kit/Kit.swift": "\n" + CarrySamples.kit],
            date: SnapshotHarness.date + 3 * CarrySamples.day
        )
        let refusal = CarrySamples.refused("`\(try CarrySamples.key("kit", in: moved))` spans other lines now")
        #expect(throws: refusal) {
            try workspace.save(moved, dropCoverage: false)
        }
        #expect(try workspace.store.snapshotID(package: "Probe", packagePath: "", commit: "c1", isDirty: false)
            == third.id)
    }

    @Test("""
        a rescan over the same uncommitted changes carries the coverage, with the run that collected it and that \
        scan's date
        """)
    func dirtyCarry() throws {
        let (package, workspace) = try CarrySamples.store()
        defer { package.remove() }
        let first = try CarrySamples.covered(try CarrySamples.scan(git: CarrySamples.dirty("aaa")))
        let coverage = try #require(first.report.coverage)

        let original = try workspace.save(first, dropCoverage: false)
        let rescan = try workspace.save(
            try CarrySamples.scan(git: CarrySamples.dirty("aaa"), date: SnapshotHarness.date + CarrySamples.day),
            dropCoverage: false
        )

        #expect(rescan.snapshot.report.coverage == coverage)
        #expect(rescan.snapshot.info.git == CarrySamples.dirty("aaa"))
        #expect(CarryHarness.coverageRun(rescan.snapshot.info)?.reason
            == "carried from the scan of \(first.info.date); \(CarrySamples.failing)")
        #expect(try workspace.store.load(id: rescan.id).coverage
            == StoredCoverage(collectedAt: first.info.date, report: coverage))
        #expect(try workspace.store.snapshotID(package: "Probe", packagePath: "", commit: "c1", isDirty: true)
            == rescan.id)
        #expect(original.id != rescan.id)
    }

    @Test("""
        when several conditions fail, the refusal names the first of commit, tree, mapping rule and records
        """)
    func refusalOrder() throws {
        let (package, workspace) = try CarrySamples.store()
        defer { package.remove() }
        let moved = ["Sources/Kit/Kit.swift": "\n" + CarrySamples.kit]
        let otherRule = CollectorRunInfo(
            name: CoverageAdapter.name,
            state: .ran,
            reason: nil,
            version: CarrySamples.run.version,
            identity: CarrySamples.run.identity,
            identityLabel: nil,
            options: ["map: an older rule"],
            durationMilliseconds: 0
        )

        let outsideMoved = try CarryHarness.refusal(
            in: workspace,
            held: try CarrySamples.covered(try CarrySamples.scan(git: .outsideGit), run: otherRule),
            rescan: try CarrySamples.scan(git: .outsideGit, files: moved)
        )
        let changedRuleMoved = try CarryHarness.refusal(
            in: workspace,
            held: try CarrySamples.covered(try CarrySamples.scan(git: CarrySamples.dirty("aaa")), run: otherRule),
            rescan: try CarrySamples.scan(git: CarrySamples.dirty("bbb"), files: moved)
        )
        let ruleMoved = try CarryHarness.refusal(
            in: workspace,
            held: try CarrySamples.covered(try CarrySamples.scan(git: CarrySamples.clean), run: otherRule),
            rescan: try CarrySamples.scan(git: CarrySamples.clean, files: moved)
        )

        let date = SnapshotScanner.format(SnapshotHarness.date)
        #expect(outsideMoved.error == .coverageNotKept(
            snapshot: "Probe (no git commit)",
            collectedAt: date,
            reason: "no git commit to compare against"
        ))
        #expect(changedRuleMoved.error == .coverageNotKept(
            snapshot: "Probe at c1 with uncommitted changes",
            collectedAt: date,
            reason: "the uncommitted changes differ"
        ))
        #expect(ruleMoved.error == CarrySamples.refused("it was mapped by another rule"))
        #expect(outsideMoved.kept && changedRuleMoved.kept && ruleMoved.kept)
    }

    @Test("a rescan with no commit to compare, or over other uncommitted changes, is refused, writing nothing")
    func otherTrees() throws {
        let (package, workspace) = try CarrySamples.store()
        defer { package.remove() }

        let outside = try CarryHarness.refusal(
            in: workspace,
            held: try CarrySamples.covered(try CarrySamples.scan(git: .outsideGit)),
            rescan: try CarrySamples.scan(git: .outsideGit)
        )
        let changed = try CarryHarness.refusal(
            in: workspace,
            held: try CarrySamples.covered(try CarrySamples.scan(git: CarrySamples.dirty("aaa"))),
            rescan: try CarrySamples.scan(git: CarrySamples.dirty("bbb"))
        )

        let date = SnapshotScanner.format(SnapshotHarness.date)
        #expect(outside.error == .coverageNotKept(
            snapshot: "Probe (no git commit)",
            collectedAt: date,
            reason: "no git commit to compare against"
        ))
        #expect(changed.error == .coverageNotKept(
            snapshot: "Probe at c1 with uncommitted changes",
            collectedAt: date,
            reason: "the uncommitted changes differ"
        ))
        #expect(outside.kept && changed.kept)
    }

    @Test("""
        a rescan of the same tree is refused, writing nothing, when the coverage was mapped by another rule or a \
        record is gone, moved or new
        """)
    func otherRecords() throws {
        let (package, workspace) = try CarrySamples.store()
        defer { package.remove() }
        let plain = try CarrySamples.scan(git: CarrySamples.clean)
        let otherRule = CollectorRunInfo(
            name: CoverageAdapter.name,
            state: .ran,
            reason: nil,
            version: CarrySamples.run.version,
            identity: CarrySamples.run.identity,
            identityLabel: nil,
            options: ["map: an older rule"],
            durationMilliseconds: 0
        )
        let added = try CarrySamples.scan(
            git: CarrySamples.clean,
            files: ["Sources/Kit/Kit.swift": CarrySamples.kit + "\nfunc extra() -> Int {\n    3\n}\n"]
        )
        let gone = try CarrySamples.scan(git: CarrySamples.clean, files: CarrySamples.withoutHelper)
        let moved = try CarrySamples.scan(
            git: CarrySamples.clean,
            files: ["Sources/Kit/Kit.swift": "\n" + CarrySamples.kit]
        )

        let results = [
            try CarryHarness.refusal(
                in: workspace,
                held: try CarrySamples.covered(plain, run: otherRule),
                rescan: plain
            ),
            try CarryHarness.refusal(in: workspace, held: try CarrySamples.covered(plain), rescan: gone),
            try CarryHarness.refusal(in: workspace, held: try CarrySamples.covered(plain), rescan: moved),
            try CarryHarness.refusal(in: workspace, held: try CarrySamples.covered(plain), rescan: added)
        ]

        let expected: [StoreError?] = [
            CarrySamples.refused("it was mapped by another rule"),
            CarrySamples.refused("`\(try CarrySamples.key("helper", in: plain))` names no record now"),
            CarrySamples.refused("`\(try CarrySamples.key("kit", in: plain))` spans other lines now"),
            CarrySamples.refused("`\(try CarrySamples.key("extra", in: added))` has no coverage")
        ]
        #expect(results.map(\.error) == expected)
        let allKept = results.allSatisfy(\.kept)
        #expect(allKept)
    }
}
