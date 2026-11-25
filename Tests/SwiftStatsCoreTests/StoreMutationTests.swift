import Foundation
@testable import SwiftStatsCore
import Testing

/// The store's v5 rows (M6, design §5): a snapshot's mutation results read
/// back from their rows exactly as the scan JSON holds them, every column
/// of every table included; they go with the snapshot when a rescan
/// replaces it; columns that don't read are a damaged store, never no
/// results; and a store written before v5 migrates with no mutation rows.
@Suite("Store v5 rows")
struct StoreMutationTests {
    /// A small library to attach hand-made results to.
    private static let files = [
        "Sources/Lib/Lib.swift": "public func one() -> Int {\n    1\n}\n",
        "Tests/LibTests/LibTests.swift": "func testOne() {\n    _ = 1\n}\n"
    ]

    /// The statement counting the rows of each mutation table.
    private static let rowCounts = """
        SELECT (SELECT count(*) FROM mutationScan), (SELECT count(*) FROM mutationRun),
            (SELECT count(*) FROM mutationFile), (SELECT count(*) FROM mutationSuspect), (SELECT count(*) FROM mutant)
        """

    /// `sqlite3`'s output for `statement` on the database at `url`.
    private static func query(_ url: URL, _ statement: String) throws -> String {
        let output = try ProcessRunner.run(
            executable: "/usr/bin/sqlite3",
            arguments: [url.path, statement],
            in: url.deletingLastPathComponent()
        )
        return String(bytes: output, encoding: .utf8) ?? ""
    }

    /// A snapshot of `files` at `commit` holding `mutation`.
    private static func snapshot(commit: String, mutation: MutationReport) throws -> ScannedSnapshot {
        let package = try TemporaryPackage(files)
        defer { package.remove() }
        return MutationSnapshots.replacing(
            try SnapshotHarness.scan(package, commit: commit),
            git: SnapshotHarness.git(commit: commit),
            mutation: mutation,
            run: MutationSnapshots.ran(identity: MutationSnapshots.identity)
        )
    }

    @Test("""
        a scan's mutation results read back from their rows as the scan JSON holds them, beside roll-up numbers \
        from SwiftMutator, and a replaced snapshot leaves no mutation rows behind
        """)
    func roundTrip() throws {
        let directory = try SnapshotHarness.temporaryDirectory("StoreMutation")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("stats.sqlite")
        let store = try SnapshotStore(at: url)
        let snapshot = try MutationSnapshots.snapshot(commit: "c1")
        let mutation = try #require(snapshot.report.mutation)

        let id = try store.save(snapshot)
        let stored = try store.load(id: id)

        #expect(stored.mutation == StoredMutation(report: mutation))
        #expect(stored.mutation?.collectedAt == MappingHarness.coverageStartedAt)
        #expect(try store.report(id: id) == snapshot.report)
        #expect(try ScanReportEncoder.encode(store.report(id: id)) == ScanReportEncoder.encode(snapshot.report))
        let numbers = stored.rollups.filter { $0.metric.hasPrefix("mutation.") }
        #expect(numbers.isEmpty == false && numbers.allSatisfy { $0.collector == MutationAdapter.name })
        #expect(numbers.contains { number in
            number.name == "production" && number.metric == "mutation.score.percent" && number.value == 93.55
        })
        #expect(numbers.contains { $0.name == "Probe" && $0.metric == "mutation.notCovered" && $0.value == 10 })
        #expect(numbers.contains { $0.name == "ProbeTests" } == false)
        let counts = try Self.query(url, Self.rowCounts)
        #expect(counts == "1|1|\(mutation.files.count)|\(mutation.suspectTests.count)|\(mutation.mutants.count)\n")
        #expect(mutation.mutants.count == 43 && mutation.files.count == 20)
        let verdicts = "SELECT verdict, count(*) FROM mutant GROUP BY verdict ORDER BY verdict"
        #expect(try Self.query(url, verdicts) == "killed|31\nnotCovered|10\nsurvived|2\n")

        let replaced = try store.save(snapshot)

        #expect(replaced != id)
        #expect(try store.load(id: replaced).mutation?.report == mutation)
        let tables = ["mutationScan", "mutationRun", "mutationFile", "mutationSuspect", "mutant"]
        let leftBehind = tables.map { table in
            "(SELECT count(*) FROM \(table) WHERE snapshotId NOT IN (SELECT id FROM snapshot))"
        }
        #expect(try Self.query(url, "SELECT " + leftBehind.joined(separator: ", ")) == "0|0|0|0|0\n")
        #expect(try Self.query(url, Self.rowCounts) == counts)
    }

    @Test("""
        hand-made merged results read back exactly: the scan row with its base, each run with absent facts as \
        null columns and lists as JSON arrays, the tree with a deleted path, and suspect tests with no file
        """)
    func columns() throws {
        let directory = try SnapshotHarness.temporaryDirectory("StoreMutation")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("stats.sqlite")
        let store = try SnapshotStore(at: url)
        let merged = MutationRowsTests.merged()

        let stored = try store.load(id: try store.save(try Self.snapshot(commit: "c1", mutation: merged)))

        #expect(stored.mutation?.report == merged)
        let scan = "SELECT collectedAt, complete, listsNotCovered, mode, baseCommit, baseCollectedAt FROM mutationScan"
        #expect(try Self.query(url, scan) == "2026-11-21T09:00:00.000Z|0|0|since|b1|2026-11-20T09:00:00.000Z\n")
        let runs = """
            SELECT ordinal, ifnull(identity, '-'), "commit", dirty, mode, ifnull(sinceRef, '-'), ifnull(mergeBase, '-'),
                ifnull(carriedFrom, '-'), formatVersions, operators, ifnull(suspectsJudged, '-'),
                ifnull(timeoutSeconds, '-'), ifnull(endedAt, '-')
            FROM mutationRun ORDER BY ordinal
            """
        #expect(try Self.query(url, runs) == """
            0|-|b1|0|full|-|-|b1|[1,4]|["RelationalBoundary","SwapTernary"]|-|-|-
            1|sha256:abc|c1|1|since|main|b1|-|[1,4]|["RelationalBoundary","SwapTernary"]|0|2.5|2026-11-21T10:00:00.000Z

            """)
        let paths = "SELECT path, ifnull(sha256, '-'), disposition, changedTest, ifnull(run, '-') FROM mutationFile"
        #expect(try Self.query(url, paths + " ORDER BY path") == """
            Lib.swift|abc|tested|0|1
            Old.swift|-|deleted|0|-
            Tests/T.swift|t|untested|1|-

            """)
        let suspects = """
            SELECT run, name, ifnull(file, '-'), why, ifnull(files, '-'), ifnull(filesWithKills, '-')
            FROM mutationSuspect ORDER BY run, name, file
            """
        #expect(try Self.query(url, suspects) == """
            1|flaky()|-|flaky|-|-
            1|reaches()|ATests.swift|reach|3|4
            1|reaches()|BTests.swift|controlRun|-|-

            """)
    }

    @Test("""
        hand-made mutants read back with tri-states as 1, 0 or null, no anchor or hash as null, and killing tests' \
        names holding line breaks, commas and quotes as a JSON array
        """)
    func mutantColumns() throws {
        let directory = try SnapshotHarness.temporaryDirectory("StoreMutation")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("stats.sqlite")
        let store = try SnapshotStore(at: url)
        let snapshot = try Self.snapshot(commit: "c1", mutation: MutationRowsTests.merged())

        let stored = try store.load(id: try store.save(snapshot))

        let mutants = """
            SELECT ordinal, line, verdict, ifnull(activated, '-'), ifnull(killedByComplete, '-'),
                ifnull(suspectOnly, '-'), carried, place, ifnull(owner, '-'), ifnull(anchorLine, '-'),
                ifnull(fileSHA256, '-'), killedBy
            FROM mutant ORDER BY ordinal
            """
        #expect(try Self.query(url, mutants) == """
            0|1|survived|0|-|0|0|unmapped|-|-|-|[]
            1|2|notCovered|-|-|-|1|record|Lib::func one() -> Int|2|abc|[]
            2|3|killed|1|0|1|0|record|Lib::func one() -> Int|3|abc|\(RowJSON.text([MutationRowsTests.oddName, "b()"]))

            """)
        let killing = try #require(stored.mutation?.report.mutants.last?.killedBy)
        #expect(killing == [MutationRowsTests.oddName, "b()"])
    }

    @Test("""
        mutation rows whose verdict, reason, mode, place, disposition or JSON columns don't read are a damaged \
        store, never no results
        """)
    func damagedRows() throws {
        let directory = try SnapshotHarness.temporaryDirectory("StoreMutation")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("stats.sqlite")
        let store = try SnapshotStore(at: url)
        let snapshot = try Self.snapshot(commit: "c1", mutation: MutationRowsTests.merged())
        let damages = [
            "UPDATE mutant SET verdict = 'gone' WHERE ordinal = 0",
            "UPDATE mutant SET killedBy = 'kills()' WHERE ordinal = 2",
            "UPDATE mutationRun SET operators = '{' WHERE ordinal = 1",
            "UPDATE mutationRun SET formatVersions = '[\"4\"]' WHERE ordinal = 0",
            "UPDATE mutationSuspect SET why = 'unknown' WHERE name = 'flaky()'",
            "UPDATE mutant SET place = 'gone' WHERE ordinal = 0",
            "UPDATE mutationScan SET mode = 'x'",
            "UPDATE mutationRun SET mode = 'x' WHERE ordinal = 0",
            "UPDATE mutationFile SET disposition = 'x'"
        ]

        for damage in damages {
            let id = try store.save(snapshot)
            try SnapshotHarness.sqlite(url, damage)

            #expect(throws: StoreError.corruptReport("the mutation rows of snapshot \(id)"), "\(damage)") {
                try store.load(id: id)
            }
        }
    }

    @Test("a v4 store migrates to v6: old snapshots hold no mutation results, and new scans store theirs")
    func migration() throws {
        let directory = try SnapshotHarness.temporaryDirectory("StoreMutation")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("stats.sqlite")
        let old = try SnapshotHarness.stored(Self.files, commit: "c1", in: try SnapshotStore(at: url))
        let downgrade = StoreDowngrade.undoingVersion5 + ["PRAGMA user_version = 4"]
        try SnapshotHarness.sqlite(url, downgrade.joined(separator: "; "))
        #expect(try Self.query(url, "PRAGMA user_version") == "4\n")
        #expect(try Self.query(url, "SELECT count(*) FROM sqlite_master WHERE name LIKE 'mutant%'") == "0\n")

        let store = try SnapshotStore(at: url)
        let migrated = try store.load(id: old.id)

        #expect(try Self.query(url, "PRAGMA user_version") == "6\n")
        #expect(try Self.query(url, "SELECT name FROM sqlite_master WHERE name LIKE 'mutant%' ORDER BY name") == """
            mutant
            mutantOwner
            mutantPath

            """)
        #expect(migrated.functions == old.functions)
        #expect(migrated.mutation == nil)
        let merged = MutationRowsTests.merged()
        let fresh = try store.load(id: try store.save(try Self.snapshot(commit: "c2", mutation: merged)))
        #expect(fresh.mutation?.report == merged)
        #expect(try store.load(id: old.id).mutation == nil)
    }
}
