import Foundation
@testable import SwiftStatsCore
import Testing

/// Keeping T1 results across rescans whose build didn't run (M7, design
/// §9.4), on hand-made snapshots of a small package holding the build's,
/// the index's and outskirts' results: a rescan of the same tree carries
/// all three with the `swiftc` findings and the warnings describing them,
/// each run keeping its state and naming the date, however often; a rescan
/// they don't describe is refused before anything is written, naming the
/// first of its reasons (`IndexCarryRefusalTests` covers the reasons in
/// order, `IndexCarryScanTests` the carry through scans).
@Suite("Index carry")
struct IndexCarryTests {
    @Test("""
        carried twice, T1 results keep their runs, name their date once, and give the blocks, findings, warnings and \
        roll-ups the held scan stored; the store reads them back with that date
        """)
    func repeatedCarry() throws {
        let (package, workspace) = try CarrySamples.store()
        defer { package.remove() }
        let first = try IndexCarrySamples.held(
            try IndexCarrySamples.scan(git: IndexCarrySamples.clean, date: SnapshotHarness.date)
        )
        let date = first.info.date

        let original = try workspace.save(first, drop: [])
        let stored = try workspace.store.load(id: original.id)
        let held = try workspace.store.report(id: original.id)
        let second = try workspace.save(
            try IndexCarrySamples.scan(git: IndexCarrySamples.clean, date: IndexCarrySamples.later(1)),
            drop: []
        )
        let third = try workspace.save(
            try IndexCarrySamples.scan(git: IndexCarrySamples.clean, date: IndexCarrySamples.later(2)),
            drop: []
        )

        for carried in [second.snapshot, third.snapshot] {
            #expect(carried.report.build == stored.build?.report)
            #expect(carried.report.index == stored.index?.report)
            #expect(carried.report.deadCode == stored.deadCode?.report)
            #expect(carried.report.findings == held.findings && held.findings == [IndexCarrySamples.warning])
            #expect(carried.report.warnings == held.warnings)
            #expect(carried.report.rollups == held.rollups)
            for name in IndexCarry.names {
                let run = try #require(carried.info.collectors.first { $0.name == name })
                let was = try #require(first.info.collectors.first { $0.name == name })
                #expect(run == was.carried(collectedAt: date))
                #expect(run.reason == "carried from the scan of \(date)")
                #expect(carried.report.collectors.contains(run.status))
            }
        }
        let last = try workspace.store.load(id: third.id)
        #expect(last.build == stored.build && last.index == stored.index && last.deadCode == stored.deadCode)
        #expect(last.build?.collectedAt == date)
        #expect(try workspace.store.report(id: third.id) == third.snapshot.report)
        let swiftc = third.snapshot.report.rollups.compactMap { $0.findings[WarningReader.tool] }
        #expect(swiftc.count == third.snapshot.report.rollups.count && swiftc.contains(["unused_result": 1]))
        let rows = last.rollups.filter { $0.metric.hasPrefix("findings.swiftc.") }.map { "\($0.name) \($0.metric)" }
        #expect(rows.isEmpty == false)
        #expect(try workspace.store.holdsIndex(id: third.id))
        #expect(UnrunNotice.lines(for: third.snapshot.report, requested: .syntaxOnly).isEmpty)
    }

    @Test("""
        a reader that failed has no rule to compare and carries as it was, failed, its reason after the date; a \
        rescan's own failed build adds a warning, which a later carry doesn't repeat
        """)
    func failedReaderCarries() throws {
        let (package, workspace) = try CarrySamples.store()
        defer { package.remove() }
        let plain = try IndexCarrySamples.scan(git: IndexCarrySamples.clean, date: SnapshotHarness.date)
        let full = try IndexCarrySamples.held(plain)
        let failed = IndexCarrySamples.ended(
            PeripheryAdapter.name,
            .failed,
            reason: "outskirts exited 1",
            options: ["an older option"],
            milliseconds: 7
        )
        let first = ScannedSnapshot(
            info: full.info.with(run: failed),
            report: full.report.with(deadCode: nil, status: failed.status)
        )
        let date = first.info.date
        let own = IndexCarrySamples.withBuild(
            IndexCarrySamples.ended(
                BuildAdapter.name,
                .failed,
                reason: "swift build exited 1",
                options: [],
                milliseconds: 0
            ),
            in: try IndexCarrySamples.scan(git: IndexCarrySamples.clean, date: IndexCarrySamples.later(1))
        )
        let notice = "build: this scan's index build failed (swift build exited 1), so it keeps the results "
            + "collected \(date)"
        _ = try workspace.save(first, drop: [])

        let carried = try workspace.save(own, drop: []).snapshot
        let again = try workspace.save(
            try IndexCarrySamples.scan(git: IndexCarrySamples.clean, date: IndexCarrySamples.later(2)),
            drop: []
        ).snapshot

        let periphery = try #require(carried.info.collectors.first { $0.name == PeripheryAdapter.name })
        #expect(periphery.state == .failed)
        #expect(periphery.reason == "carried from the scan of \(date); outskirts exited 1")
        #expect(periphery.options == failed.options && periphery.durationMilliseconds == 7)
        #expect(carried.report.deadCode == nil && carried.report.index != nil)
        #expect(carried.info.collectors.first { $0.name == BuildAdapter.name }?.state == .ran)
        #expect(carried.report.warnings.map(\.message).contains(notice))
        #expect(UnrunNotice.lines(for: carried.report, requested: RequestedTiers(index: true))
            == ["Warning: " + notice])
        #expect(again.report.warnings.map(\.message).contains(notice) == false)
        #expect(again.report.warnings.contains(IndexCarrySamples.buildWarning))
    }

    @Test("""
        a rescan the held T1 results don't describe is refused with the save's words, writing nothing, and names \
        its own failed build; --drop-index replaces them, and a scan whose build ran always does
        """)
    func refusedSave() throws {
        let (package, workspace) = try CarrySamples.store()
        defer { package.remove() }
        let plain = try IndexCarrySamples.scan(git: IndexCarrySamples.clean, date: SnapshotHarness.date)
        let first = try IndexCarrySamples.held(plain)
        let held = try workspace.save(first, drop: []).id
        let edited = try IndexCarrySamples.scan(
            git: IndexCarrySamples.clean,
            files: [IndexCarrySamples.libPath: (IndexCarrySamples.files[IndexCarrySamples.libPath] ?? "") + "\n"],
            date: IndexCarrySamples.later(1)
        )
        let ownSkipped = IndexCarrySamples.withBuild(
            IndexCarrySamples.ended(
                BuildAdapter.name,
                .skipped,
                reason: "no swift found",
                options: [],
                milliseconds: 0
            ),
            in: edited
        )
        let reason = "`\(IndexCarrySamples.libPath)` holds other bytes now"
        let name = first.info.package

        #expect(throws: IndexCarrySamples.refused(reason, package: name)) {
            try workspace.save(edited, drop: [.coverage, .mutation])
        }
        #expect(throws: IndexCarrySamples.refused(
            reason + "; this scan's index build was skipped (no swift found)",
            package: name
        )) {
            try workspace.save(ownSkipped, drop: [])
        }
        #expect(try workspace.store.snapshotID(package: name, packagePath: "", commit: "c1", isDirty: false) == held)

        let dropped = try workspace.save(edited, drop: .index)

        #expect(dropped.snapshot == edited)
        #expect(try workspace.store.holdsIndex(id: dropped.id) == false)
        let rebuilt = try workspace.save(try IndexCarrySamples.held(edited), drop: [])
        #expect(try workspace.store.holdsIndex(id: rebuilt.id))
        let replaced = try workspace.save(try IndexCarrySamples.held(plain), drop: [])
        #expect(try workspace.store.load(id: replaced.id).index?.report.files == first.report.index?.files)
    }

    @Test("""
        held T1 results too damaged to read stop a rescan, naming --drop-index, which replaces them without T1 \
        results
        """)
    func damagedHeldResults() throws {
        let (package, workspace) = try CarrySamples.store()
        defer { package.remove() }
        let first = try IndexCarrySamples.held(
            try IndexCarrySamples.scan(git: IndexCarrySamples.clean, date: SnapshotHarness.date)
        )
        let held = try workspace.save(first, drop: [])
        try SnapshotHarness.sqlite(
            workspace.store.url,
            "UPDATE indexUnit SET class = 'gone' WHERE snapshotId = \(held.id)"
        )
        let rescan = try IndexCarrySamples.scan(git: IndexCarrySamples.clean, date: IndexCarrySamples.later(1))
        let damaged = StoreError.damagedIndex(
            snapshot: "\(first.info.package) at c1",
            reason: "the index rows of snapshot \(held.id)"
        )

        #expect(throws: damaged) {
            try workspace.save(rescan, drop: [])
        }
        let dropped = try workspace.save(rescan, drop: .index)

        #expect(dropped.snapshot == rescan)
        #expect(try workspace.store.holdsIndex(id: dropped.id) == false)
    }

    @Test(
        """
        held T1 results whose reader ran but whose rows are gone stop a rescan as damaged, naming --drop-index, \
        rather than being carried without them
        """,
        arguments: [("indexScan", "index"), ("deadScan", "dead-code")]
    )
    func missingReaderRows(table: String, rows: String) throws {
        let (package, workspace) = try CarrySamples.store()
        defer { package.remove() }
        let first = try IndexCarrySamples.held(
            try IndexCarrySamples.scan(git: IndexCarrySamples.clean, date: SnapshotHarness.date)
        )
        let held = try workspace.save(first, drop: [])
        try SnapshotHarness.sqlite(workspace.store.url, "DELETE FROM \(table) WHERE snapshotId = \(held.id)")
        let rescan = try IndexCarrySamples.scan(git: IndexCarrySamples.clean, date: IndexCarrySamples.later(1))
        let damaged = StoreError.damagedIndex(
            snapshot: "\(first.info.package) at c1",
            reason: "the \(rows) rows of snapshot \(held.id)"
        )

        #expect(throws: damaged) {
            try workspace.save(rescan, drop: [])
        }
        let dropped = try workspace.save(rescan, drop: .index)

        #expect(dropped.snapshot == rescan)
        #expect(try workspace.store.holdsIndex(id: dropped.id) == false)
    }

    @Test("only warnings on no file led by a T1 collector's name describe the results, not the carry's notice")
    func describedWarnings() {
        let kept = ["build: a", "index: b", "periphery: c"].map { ScanWarning(file: nil, message: $0) }
        let dropped = [
            ScanWarning(file: "Sources/A.swift", message: "build: on a file"),
            ScanWarning(file: nil, message: "builder: d"),
            ScanWarning(file: nil, message: "coverage: e"),
            ScanWarning(file: nil, message: "build: this scan's index build failed (x), so it keeps the results")
        ]

        #expect(kept.allSatisfy(IndexCarry.describesResults))
        #expect(dropped.contains(where: IndexCarry.describesResults) == false)
    }
}
