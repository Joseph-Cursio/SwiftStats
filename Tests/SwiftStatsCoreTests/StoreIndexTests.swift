import Foundation
@testable import SwiftStatsCore
import Testing

/// The store's v6 rows (M7, design §9.1): a scan's index, build and
/// dead-code results read back from their rows exactly as its JSON holds
/// them, dated when the T1 build ran; they go with the snapshot when a
/// rescan replaces it; a store written before v6 migrates with no T1 rows;
/// and a scan whose build didn't run is refused rather than replace held
/// T1 results that don't describe its files (`IndexCarryTests` covers the
/// carry). Serialized: the fixture scan runs on a
/// thread of its own, as the index collector's tests do.
@Suite("Store v6 rows", .serialized)
struct StoreIndexTests {
    /// The statement counting the T1 tables' rows left by snapshots no
    /// longer stored.
    private static let leftBehind = "SELECT " + StoreDowngrade.indexTables.map { table in
        "(SELECT count(*) FROM \(table) WHERE snapshotId NOT IN (SELECT id FROM snapshot))"
    }
    .joined(separator: " + ")

    /// `value` as compact JSON with sorted keys, as a block is compared.
    private static func json(_ value: some Encodable) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    /// Checks that `snapshot`, holding all three T1 blocks, reads back
    /// from `made` as it was stored, dated by the scan.
    private static func expectStored(_ snapshot: ScannedSnapshot, in made: TemporaryStore) throws {
        let index = try #require(snapshot.report.index)
        let build = try #require(snapshot.report.build)
        let deadCode = try #require(snapshot.report.deadCode)

        let id = try made.store.save(snapshot)
        let stored = try made.store.load(id: id)

        #expect(stored.index == StoredIndex(collectedAt: snapshot.info.date, report: index))
        #expect(stored.build == StoredBuild(collectedAt: snapshot.info.date, report: build))
        #expect(stored.deadCode == StoredDeadCode(collectedAt: snapshot.info.date, report: deadCode))
        #expect(try json(try #require(stored.index).report) == json(index))
        #expect(try json(try #require(stored.build).report) == json(build))
        #expect(try json(try #require(stored.deadCode).report) == json(deadCode))
        #expect(IndexRows.normalized(index) == index && BuildRows.normalized(build) == build)
        #expect(DeadCodeRows.normalized(deadCode) == deadCode)
        #expect(try made.store.report(id: id) == snapshot.report)
        #expect(try made.store.holdsIndex(id: id))
        #expect(index.store.units.isEmpty == false && index.types.isEmpty == false)
        #expect(try made.query("SELECT count(*) FROM indexUnit") == "\(index.store.units.count)\n")
        let withUSR = index.records.count { $0.usr != nil }
        #expect(try made.query("SELECT count(*) FROM function WHERE usr IS NOT NULL") == "\(withUSR)\n")
        let timed = "SELECT count(*) FROM function WHERE typeCheckMilliseconds IS NOT NULL "
            + "OR slowestExpressionMilliseconds IS NOT NULL"
        #expect(try made.query(timed) == "\(build.records.count)\n")
    }

    @Test("""
        a fixture scan's index, build and dead-code blocks read back from their rows as its JSON holds them, \
        dated when the build ran or as the save says, and a replaced snapshot leaves no T1 rows behind
        """)
    func fixtureRoundTrip() async throws {
        let fake = try FakePeriphery.make(try FakePeriphery.recorded())
        defer { fake.remove() }
        var scan = try IndexFixtureScan()
        scan.extra = fake.configuration
        try await scan.run { _, outcome in
            let made = try TemporaryStore("StoreIndex")
            defer { made.remove() }
            let snapshot = outcome.snapshot
            try Self.expectStored(snapshot, in: made)
            let date = "2026-11-24T10:00:00.000Z"

            let replaced = try made.store.save(snapshot, indexCollectedAt: date)

            let again = try made.store.load(id: replaced)
            #expect(again.index?.collectedAt == date && again.build?.collectedAt == date)
            #expect(again.deadCode?.collectedAt == date && again.index?.report == snapshot.report.index)
            #expect(try made.query("SELECT count(*) FROM snapshot") == "1\n")
            #expect(try made.query(Self.leftBehind) == "0\n")
        }
    }

    @Test("""
        dead lines go in runs first, then modules in code point order, whatever order the report's dictionaries \
        give them in, so identical scans write identical rows
        """)
    func deadLinesOrder() throws {
        let made = try TemporaryStore("StoreIndex")
        defer { made.remove() }
        let full = try IndexStoreSamples.snapshot(commit: "c1")
        let sample = try IndexStoreSamples.deadCode()
        let modules = ["Zeta", "alpha", "Beta", "\u{C9}mile", "Lib", "Other", "_Under", "beta", "Mid", "Alpha2"]
        let counts = Dictionary(uniqueKeysWithValues: modules.enumerated().map { ($1, $0) })
        let report = DeadCodeReport(
            version: sample.version,
            runs: sample.runs,
            declarations: sample.declarations,
            records: sample.records,
            dropped: sample.dropped,
            deadLines: ["production": counts, "roots": counts]
        )
        let status = try #require(full.report.collectors.first { $0.name == PeripheryAdapter.name })
        let snapshot = ScannedSnapshot(info: full.info, report: full.report.with(deadCode: report, status: status))
        let ordered = ["Alpha2", "Beta", "Lib", "Mid", "Other", "Zeta", "_Under", "alpha", "beta", "\u{C9}mile"]
        let expected = ["roots", "production"].flatMap { run in ordered.map { "\(run) \($0)\n" } }.joined()

        _ = try made.store.save(snapshot)

        #expect(try made.query("SELECT run || ' ' || module FROM deadLines ORDER BY rowid") == expected)
    }

    @Test("a v5 store migrates to v6: old snapshots hold no T1 results or coupling pairs, and new scans store theirs")
    func migration() throws {
        let made = try TemporaryStore("StoreIndex")
        defer { made.remove() }
        let old = try SnapshotHarness.stored(IndexStoreSamples.files, commit: "c1", in: made.store)
        try SnapshotHarness.sqlite(made.url, (StoreDowngrade.undoingVersion6 + ["PRAGMA user_version = 5"])
            .joined(separator: "; "))
        let names = StoreDowngrade.indexTables.map { "'\($0)'" }.joined(separator: ", ")
        let tables = "SELECT count(*) FROM sqlite_master WHERE name IN (\(names))"
        #expect(try made.query("PRAGMA user_version") == "5\n")
        #expect(try made.query(tables) == "0\n")
        #expect(try made.query("SELECT count(*) FROM pragma_table_info('function') WHERE name = 'usr'") == "0\n")

        let store = try SnapshotStore(at: made.url)
        let migrated = try store.load(id: old.id)

        #expect(try made.query("PRAGMA user_version") == "6\n")
        #expect(try made.query(tables) == "\(StoreDowngrade.indexTables.count)\n")
        let indexes = "SELECT name FROM sqlite_master WHERE name IN ('deadRecordKey', 'familyReferenceTarget')"
        #expect(try made.query(indexes + " ORDER BY name") == "deadRecordKey\nfamilyReferenceTarget\n")
        let nulls = StoreDowngrade.indexFunctionColumns.map { "\($0) IS NULL" }.joined(separator: " AND ")
        #expect(try made.query("SELECT count(*) = (SELECT count(*) FROM function) FROM function WHERE \(nulls)")
            == "1\n")
        #expect(migrated.functions == old.functions)
        #expect(migrated.index == nil && migrated.build == nil && migrated.deadCode == nil)
        #expect(migrated.couplingPairs.isEmpty)
        #expect(try store.holdsIndex(id: old.id) == false)
        let snapshot = try IndexStoreSamples.snapshot(commit: "c2")
        let fresh = try store.load(id: try store.save(snapshot))
        #expect(fresh.index?.report == snapshot.report.index && fresh.deadCode?.report == snapshot.report.deadCode)
        #expect(fresh.couplingPairs == snapshot.report.history?.coupling)
        #expect(try store.load(id: old.id).index == nil)
    }

    @Test("""
        a scan whose build didn't run is refused, before anything is written, rather than replace held T1 \
        results whose files hold other bytes; --drop-index replaces them, and a scan whose build ran always does
        """)
    func otherBytesRefusal() throws {
        let made = try TemporaryStore("StoreIndex")
        defer { made.remove() }
        let package = try TemporaryPackage(IndexStoreSamples.files)
        defer { package.remove() }
        let workspace = try SnapshotWorkspace(
            packageRoot: package.root,
            configurationFile: nil,
            storeOverride: made.url.path,
            build: SnapshotHarness.build,
            describer: package.describer,
            tools: SnapshotHarness.noTools
        )
        let full = try IndexStoreSamples.snapshot(commit: "c1")
        let plain = IndexStoreSamples.plain(full)
        let held = try workspace.save(full, drop: []).id
        let refusal = StoreError.indexNotKept(
            snapshot: "\(full.info.package) at c1",
            collectedAt: full.info.date,
            reason: "`Sources/Lib/Lib.swift` holds other bytes now"
        )

        #expect(throws: refusal) {
            try workspace.save(plain, drop: [.coverage, .mutation])
        }
        #expect(refusal.description == """
            the snapshot of \(full.info.package) at c1 holds index results from \(full.info.date) that this scan \
            can't keep (`Sources/Lib/Lib.swift` holds other bytes now); run scan --index to collect them again, \
            or --drop-index to replace them
            """)
        #expect(try workspace.store.load(id: held).index != nil)

        let dropped = try workspace.save(plain, drop: [.index]).id

        let replaced = try workspace.store.load(id: dropped)
        #expect(replaced.index == nil && replaced.build == nil && replaced.deadCode == nil)
        #expect(try workspace.store.holdsIndex(id: dropped) == false)
        let rebuilt = try workspace.save(full, drop: []).id
        #expect(try workspace.store.holdsIndex(id: rebuilt))
        let again = try workspace.save(full, drop: []).id
        #expect(try workspace.store.load(id: again).build?.report == full.report.build)
        #expect(try made.query(Self.leftBehind) == "0\n")
    }
}
