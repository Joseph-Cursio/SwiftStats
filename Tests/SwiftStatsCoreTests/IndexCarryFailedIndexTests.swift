import Foundation
@testable import SwiftStatsCore
import Testing

/// Keeping T1 results whose readers failed after a build that ran (M7,
/// design §9.4, step 8's deviation 2): with no index rows, the files a
/// rescan is checked against are the stored scan's own, with their hashes,
/// so the carry still decides on the bytes.
@Suite("Index carry without index rows")
struct IndexCarryFailedIndexTests {
    @Test("""
        T1 results whose readers failed after a build that ran (no index rows) are checked against the stored \
        scan's file hashes: a rescan of other bytes is refused, and one of the same bytes carries them, both \
        readers failed
        """)
    func failedIndexCarries() throws {
        let (package, workspace) = try CarrySamples.store()
        defer { package.remove() }
        let plain = try IndexCarrySamples.scan(git: IndexCarrySamples.clean, date: SnapshotHarness.date)
        let full = try IndexCarrySamples.held(plain)
        let noStore = "the build wrote no index store"
        let failed = [IndexAdapter.name, PeripheryAdapter.name].map { name in
            IndexCarrySamples.ended(name, .failed, reason: noStore, options: [], milliseconds: 0)
        }
        let first = ScannedSnapshot(
            info: failed.reduce(full.info) { $0.with(run: $1) },
            report: full.report.with(index: nil, status: failed[0].status).with(deadCode: nil, status: failed[1].status)
        )
        let date = first.info.date
        let held = try workspace.save(first, drop: [])
        let edited = try IndexCarrySamples.scan(
            git: IndexCarrySamples.clean,
            files: [IndexCarrySamples.libPath: (IndexCarrySamples.files[IndexCarrySamples.libPath] ?? "") + "\n"],
            date: IndexCarrySamples.later(1)
        )

        let stored = try workspace.store.load(id: held.id)
        #expect(try workspace.store.holdsIndex(id: held.id))
        #expect(stored.index == nil && stored.build != nil)
        #expect(throws: IndexCarrySamples.refused(
            "`\(IndexCarrySamples.libPath)` holds other bytes now",
            package: first.info.package
        )) {
            try workspace.save(edited, drop: [])
        }
        let carried = try workspace.save(
            try IndexCarrySamples.scan(git: IndexCarrySamples.clean, date: IndexCarrySamples.later(1)),
            drop: []
        ).snapshot

        #expect(carried.report.build == stored.build?.report)
        #expect(carried.report.index == nil && carried.report.deadCode == nil)
        #expect(carried.report.findings == [IndexCarrySamples.warning])
        for name in [IndexAdapter.name, PeripheryAdapter.name] {
            let run = try #require(carried.info.collectors.first { $0.name == name })
            #expect(run.state == .failed && run.reason == "carried from the scan of \(date); \(noStore)")
        }
    }
}
