import Foundation
@testable import SwiftStatsCore
import Testing

/// When M6's per-function signals are left out (PRD §6.5, design §7): in
/// order, a snapshot stored before M6 or without a SwiftMutator run
/// predates M6; a SwiftMutator, then a coverage run that didn't run is
/// named with its reason; genuinely under-tested then needs results that
/// list code no test ran; and a computation finding no mutation rows, then
/// no coverage rows, says so.
@Suite("Mutation signal requirements")
struct MutationSignalRequirementTests {
    /// The harness's shorthand.
    private typealias Harness = MutationSignalHarness
    /// The signals the requirements are checked on.
    private static let names: [SignalName] = [.weakTests, .genuinelyUnderTested]
    /// A function the tests run and barely check.
    private static let weak = [Harness.covered(Harness.planted(1, .killed) + Harness.planted(3, .survived))]

    /// Why each of weak tests and genuinely under-tested is left out of
    /// `snapshot`, nil for one computed.
    private static func reasons(_ snapshot: StoredSnapshot) throws -> [String?] {
        try names.map { try Harness.signal($0, of: snapshot).leftOut }
    }

    @Test("""
        the left-out reasons come in order: predates M6 (schema 7, or no SwiftMutator run), needs swiftmutator, \
        needs coverage, then no mutation rows and no coverage rows
        """)
    func order() throws {
        let directory = try SnapshotHarness.temporaryDirectory("MutationRequirements")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("stats.sqlite")
        let store = try SnapshotStore(at: url)
        let full = try Harness.stored(Self.weak, Harness.Setup(store: store))
        let reload = { try store.load(id: full.id) }

        #expect(try Self.reasons(full) == [nil, nil])
        try SnapshotHarness.sqlite(url, "UPDATE snapshot SET reportSchemaVersion = 7")
        #expect(try Self.reasons(reload()) == ["the snapshot predates M6", "the snapshot predates M6"])
        try SnapshotHarness.sqlite(url, "UPDATE snapshot SET reportSchemaVersion = 8")
        try SnapshotHarness.sqlite(url, "DELETE FROM coverageRun")
        let noCoverageRows = "the snapshot holds no coverage rows"
        #expect(try Self.reasons(reload()) == [noCoverageRows, noCoverageRows])
        try SnapshotHarness.sqlite(url, "DELETE FROM mutationScan")
        let noMutationRows = "the snapshot holds no mutation rows"
        #expect(try Self.reasons(reload()) == [noMutationRows, noMutationRows])
        try SnapshotHarness.sqlite(url, "UPDATE collectorRun SET state = 'skipped', reason = 'not requested; "
            + "scan --coverage runs it' WHERE name = 'coverage'")
        let needsCoverage = "needs coverage: skipped, not requested; scan --coverage runs it"
        #expect(try Self.reasons(reload()) == [needsCoverage, needsCoverage])
        try SnapshotHarness.sqlite(url, "UPDATE collectorRun SET state = 'failed', reason = 'the tests failed' "
            + "WHERE name = 'swiftmutator'")
        let failed = "needs swiftmutator: failed, the tests failed"
        #expect(try Self.reasons(reload()) == [failed, failed])
        try SnapshotHarness.sqlite(url, "DELETE FROM collectorRun WHERE name = 'swiftmutator'")
        #expect(try Self.reasons(reload()) == ["the snapshot predates M6", "the snapshot predates M6"])

        let files = ["Sources/Lib/Lib.swift": "func one() -> Int {\n    1\n}\n"]
        let plain = try SnapshotHarness.stored(files, commit: "c2", in: store)
        let skipped = "needs swiftmutator: skipped, not requested; scan --mutation runs it"
        #expect(try Self.reasons(plain) == [skipped, skipped])
        #expect(SignalEngine.leftOut([.m6Snapshot], in: plain) == nil)
    }

    @Test("without coverage both are left out needing it, before genuinely under-tested's need for listed code")
    func needsCoverage() throws {
        let setup = Harness.Setup(listsNotCovered: false, withCoverage: false)
        let snapshot = try Harness.stored(Self.weak, setup)
        let needsCoverage = "needs coverage: skipped, not requested; scan --coverage runs it"

        #expect(try Self.reasons(snapshot) == [needsCoverage, needsCoverage])
        #expect(try Harness.signal(.weakTests, of: snapshot).rule == WeakTests.rule(thresholds: SignalThresholds()))
    }

    @Test("a --since scan without --coverage stores no coverage, so both say they need it")
    func sinceWithoutCoverage() throws {
        let harness = try SinceHarness()
        defer { harness.remove() }
        _ = try harness.base()
        let merged = try harness.since("since", acting: "since")
        let store = try SnapshotStore(at: harness.folder.appendingPathComponent("stats.sqlite"))
        let snapshot = try store.load(id: merged.id)
        let needsCoverage = "needs coverage: skipped, not requested; scan --coverage runs it"

        #expect(snapshot.mutation?.report.mode == .since)
        #expect(try Self.reasons(snapshot) == [needsCoverage, needsCoverage])
    }
}
