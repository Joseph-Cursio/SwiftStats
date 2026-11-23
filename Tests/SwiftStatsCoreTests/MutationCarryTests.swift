import Foundation
@testable import SwiftStatsCore
import Testing

/// Keeping mutation results across rescans that don't run the SwiftMutator
/// collector (M6, design §6.4), on hand-made snapshots of the Coverage
/// fixture holding its recorded run: a rescan of the same tree carries the
/// results, clean or with the same uncommitted changes, with the original
/// run and the date they were collected, however often; a rescan the
/// results don't describe is refused before anything is written, naming
/// the first of its reasons (`MutationCarryReplacementTests` covers
/// `--drop-mutation`, failed runs and runs that replace them).
@Suite("Mutation carry")
struct MutationCarryTests {
    @Test("""
        carried twice, mutation results keep the run that collected them, name their date and the run's reason \
        once, and give the roll-ups the first scan gave; a later refusal names that date too
        """)
    func repeatedCarry() throws {
        let (package, workspace) = try CarrySamples.store()
        defer { package.remove() }
        let first = try MutationCarrySamples.held(try MutationCarrySamples.scan(git: MutationCarrySamples.clean))
        let results = try #require(first.report.mutation)
        let carriedReason = MutationCarrySamples.carriedReason

        let original = try workspace.save(first, drop: [])
        let second = try workspace.save(
            try MutationCarrySamples.scan(git: MutationCarrySamples.clean, date: MutationCarrySamples.later(1)),
            drop: []
        )
        let third = try workspace.save(
            try MutationCarrySamples.scan(git: MutationCarrySamples.clean, date: MutationCarrySamples.later(2)),
            drop: []
        )

        #expect(second.snapshot.report.mutation == results)
        #expect(second.snapshot.report.rollups == first.report.rollups)
        for carried in [second.snapshot, third.snapshot] {
            #expect(MutationCarrySamples.mutationRun(carried.info) == MutationCarrySamples.carriedRun)
            #expect(carried.report.collectors.first { $0.name == MutationAdapter.name }?.reason == carriedReason)
        }
        let stored = try workspace.store.load(id: third.id)
        #expect(stored.mutation == StoredMutation(report: results))
        #expect(stored.info == third.snapshot.info)
        #expect(try workspace.store.report(id: third.id) == third.snapshot.report)
        let numbers = try MutationCarrySamples.mutationNumbers(first.report.rollups)
        #expect(MutationCarrySamples.mutationNumbers(stored.rollups) == numbers && numbers.isEmpty == false)
        #expect(original.id != third.id)

        let moved = try MutationCarrySamples.scan(
            git: MutationCarrySamples.clean,
            files: MutationCarrySamples.movedCounter,
            date: MutationCarrySamples.later(3)
        )
        let refusal = MutationCarrySamples.refused(
            "`\(try MutationCarrySamples.firstCounterRecord(in: first))` spans other lines now"
        )
        #expect(throws: refusal) {
            try workspace.save(moved, drop: [])
        }
        #expect(try workspace.store.snapshotID(package: "Probe", packagePath: "", commit: "c1", isDirty: false)
            == third.id)
    }

    @Test("""
        a rescan over the same uncommitted changes carries the mutation results, with the run that collected them \
        and their date
        """)
    func dirtyCarry() throws {
        let (package, workspace) = try CarrySamples.store()
        defer { package.remove() }
        let dirty = MutationCarrySamples.dirty("aaa")
        let first = try MutationCarrySamples.held(try MutationCarrySamples.scan(git: dirty))
        let results = try #require(first.report.mutation)

        let original = try workspace.save(first, drop: [])
        let rescan = try workspace.save(
            try MutationCarrySamples.scan(git: dirty, date: MutationCarrySamples.later(1)),
            drop: []
        )

        #expect(rescan.snapshot.report.mutation == results)
        #expect(rescan.snapshot.info.git == dirty)
        #expect(MutationCarrySamples.mutationRun(rescan.snapshot.info) == MutationCarrySamples.carriedRun)
        #expect(try workspace.store.load(id: rescan.id).mutation == StoredMutation(report: results))
        #expect(try workspace.store.snapshotID(package: "Probe", packagePath: "", commit: "c1", isDirty: true)
            == rescan.id)
        #expect(original.id != rescan.id)
    }

    @Test("""
        when several conditions fail, the refusal names the first of commit, tree, mapping rule, records and \
        file bytes
        """)
    func refusalOrder() throws {
        let (package, workspace) = try CarrySamples.store()
        defer { package.remove() }
        let moved = MutationCarrySamples.movedCounter
        let otherRule = MutationCarrySamples.otherRule
        let held = { (git: GitState, run: CollectorRunInfo) in
            try MutationCarrySamples.held(try MutationCarrySamples.scan(git: git), run: run)
        }

        let outside = try MutationCarrySamples.refusal(
            in: workspace,
            held: try held(.outsideGit, otherRule),
            rescan: try MutationCarrySamples.scan(git: .outsideGit, files: moved)
        )
        let changed = try MutationCarrySamples.refusal(
            in: workspace,
            held: try held(MutationCarrySamples.dirty("aaa"), otherRule),
            rescan: try MutationCarrySamples.scan(git: MutationCarrySamples.dirty("bbb"), files: moved)
        )
        let rule = try MutationCarrySamples.refusal(
            in: workspace,
            held: try held(MutationCarrySamples.clean, otherRule),
            rescan: try MutationCarrySamples.scan(git: MutationCarrySamples.clean, files: moved)
        )
        let lines = try MutationCarrySamples.refusal(
            in: workspace,
            held: try held(MutationCarrySamples.clean, MutationCarrySamples.run),
            rescan: try MutationCarrySamples.scan(git: MutationCarrySamples.clean, files: moved)
        )

        let date = MutationCarrySamples.collectedAt
        let first = try MutationCarrySamples.firstCounterRecord(
            in: try held(MutationCarrySamples.clean, MutationCarrySamples.run)
        )
        #expect(outside.error == .mutationNotKept(
            snapshot: "Probe (no git commit)",
            collectedAt: date,
            reason: "no git commit to compare against"
        ))
        #expect(changed.error == .mutationNotKept(
            snapshot: "Probe at c1 with uncommitted changes",
            collectedAt: date,
            reason: "the uncommitted changes differ"
        ))
        #expect(rule.error == MutationCarrySamples.refused("it was mapped by another rule"))
        #expect(lines.error == MutationCarrySamples.refused("`\(first)` spans other lines now"))
        #expect(outside.kept && changed.kept && rule.kept && lines.kept)
    }

    @Test("""
        a rescan of the same tree is refused, writing nothing, when a record a mutant names is gone or moved, or \
        a file holding mapped mutants holds other bytes
        """)
    func otherRecords() throws {
        let (package, workspace) = try CarrySamples.store()
        defer { package.remove() }
        let plain = try MutationCarrySamples.scan(git: MutationCarrySamples.clean)
        let held = try MutationCarrySamples.held(plain)
        let neverCalled = try MutationCarrySamples.key("neverCalled", in: plain)
        let firstCounter = try MutationCarrySamples.firstCounterRecord(in: held)
        #expect(try #require(held.report.mutation).records.contains { $0.key == neverCalled })

        let results = [
            try MutationCarrySamples.refusal(
                in: workspace,
                held: held,
                rescan: try MutationCarrySamples.scan(
                    git: MutationCarrySamples.clean,
                    files: MutationCarrySamples.withoutNeverCalled
                )
            ),
            try MutationCarrySamples.refusal(
                in: workspace,
                held: held,
                rescan: try MutationCarrySamples.scan(
                    git: MutationCarrySamples.clean,
                    files: MutationCarrySamples.movedCounter
                )
            ),
            try MutationCarrySamples.refusal(
                in: workspace,
                held: held,
                rescan: try MutationCarrySamples.scan(
                    git: MutationCarrySamples.clean,
                    files: MutationCarrySamples.editedCounter
                )
            )
        ]

        let expected: [StoreError?] = [
            MutationCarrySamples.refused("`\(neverCalled)` names no record now"),
            MutationCarrySamples.refused("`\(firstCounter)` spans other lines now"),
            MutationCarrySamples.refused("`\(MutationCarrySamples.counterPath)` holds other bytes now")
        ]
        #expect(results.map(\.error) == expected)
        let allKept = results.allSatisfy(\.kept)
        #expect(allKept)
    }

    @Test("""
        a file holding only attached mutants that the rescan no longer scans is refused by name, and the same \
        files carry
        """)
    func unscannedFile() throws {
        let plain = try MutationCarrySamples.scan(git: MutationCarrySamples.clean)
        let results = try MutationCarrySamples.results()
        let attached = MutationSnapshots.changing(results, mode: results.mode, base: results.base) { mutant in
            [.type, .file].contains(mutant.place) ? mutant : nil
        }
        let path = try #require(attached.mutants.first).path
        let held = HeldMutation(
            git: MutationCarrySamples.clean,
            run: MutationCarrySamples.run,
            results: StoredMutation(report: attached),
            warnings: [],
            spans: MutationCarrySamples.spans(of: plain)
        )

        #expect(attached.mutants.isEmpty == false && attached.records.isEmpty)
        #expect(MutationCarry.refusal(of: held, onto: plain) == nil)
        #expect(MutationCarry.filesRefusal(of: attached.mutants, onto: plain.report.files.filter { $0.path != path })
            == "`\(path)` isn't scanned now")
    }
}
