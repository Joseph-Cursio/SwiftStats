//
//  CoverageSignalRequirementTests.swift
//  SwiftStatsCoreTests
//
//  When M5's signals are left out (PRD §6.5, §8): a snapshot stored before
//  M5, or without a coverage run, predates M5, even when it holds M4's
//  rows; a coverage run that didn't run is named with its reason.
//

import Foundation
@testable import SwiftStatsCore
import Testing

@Suite("Coverage signal requirements")
struct CoverageSignalRequirementTests {
    @Test("M5's signals say a snapshot before M5 or without a coverage run predates M5, and name a skipped run")
    func leftOutReasons() throws {
        let directory = try SnapshotHarness.temporaryDirectory("Requirements")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("stats.sqlite")
        let store = try SnapshotStore(at: url)
        let files = ["Sources/Lib/Lib.swift": "func one() -> Int {\n    1\n}\n"]
        let snapshot = try SnapshotHarness.stored(files, commit: "c1", in: store)
        let reason = { (requirements: [SignalRequirement], snapshot: StoredSnapshot) in
            SignalEngine.leftOut(requirements, in: snapshot)
        }
        let skipped = "needs coverage: skipped, not requested; scan --coverage runs it"
        try SnapshotHarness.sqlite(url, "UPDATE snapshot SET reportSchemaVersion = 6")
        let fromM4 = try store.load(id: snapshot.id)
        try SnapshotHarness.sqlite(url, "DELETE FROM collectorRun WHERE name = 'coverage'")
        try SnapshotHarness.sqlite(url, "UPDATE snapshot SET reportSchemaVersion = 7")
        let noCoverageRun = try store.load(id: snapshot.id)

        // A scan without --coverage has a coverage run, skipped: an M5 snapshot.
        #expect(reason([.m5Snapshot], snapshot) == nil)
        #expect(reason(SignalName.riskyUntested.requirements, snapshot) == skipped)
        #expect(reason(SignalName.unevenCloneTesting.requirements, snapshot)
            == "needs swiftclonedetector: skipped, `swift-clone-detector` not found on PATH; "
            + "set collectors.swiftclonedetector.path")
        // The M5 snapshot is listed first, so an M4 snapshot predates M5, not M4.
        #expect(reason([.m4Snapshot], fromM4) == nil)
        #expect(reason(SignalName.riskyUntested.requirements, fromM4) == "the snapshot predates M5")
        #expect(reason(SignalName.unevenCloneTesting.requirements, fromM4) == "the snapshot predates M5")
        #expect(reason([.m5Snapshot], noCoverageRun) == "the snapshot predates M5")
    }
}
