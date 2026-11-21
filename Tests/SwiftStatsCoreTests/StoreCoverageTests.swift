import Foundation
@testable import SwiftStatsCore
import Testing

/// The store's v4 rows (M5, design §5): a snapshot's coverage reads back
/// from its rows exactly as the scan JSON holds it, with when it was
/// collected; function rows keep their access level and owning type; null
/// stays null; and a store written before v4 migrates with nulls and no
/// coverage.
@Suite("Store v4 rows")
struct StoreCoverageTests {
    /// A small library to scan when the coverage is made by hand, with a
    /// file-scoped type.
    private static let files = [
        "Sources/Lib/Lib.swift": """
        public func one() -> Int {
            1
        }

        private struct Hidden {
            func peek() -> Int {
                2
            }
        }
        """,
        "Tests/LibTests/LibTests.swift": "func testOne() {\n    _ = 1\n}\n"
    ]

    /// The condition picking the library file's line row.
    private static let libFile = "file = 'Sources/Lib/Lib.swift'"

    /// `sqlite3`'s output for `statement` on the database at `url`.
    private static func query(_ url: URL, _ statement: String) throws -> String {
        let output = try ProcessRunner.run(
            executable: "/usr/bin/sqlite3",
            arguments: [url.path, statement],
            in: url.deletingLastPathComponent()
        )
        return String(bytes: output, encoding: .utf8) ?? ""
    }

    /// A snapshot of `files` at `commit` holding `coverage`.
    private static func snapshot(commit: String, coverage: CoverageReport) throws -> ScannedSnapshot {
        let package = try TemporaryPackage(files)
        defer { package.remove() }
        return CoverageSnapshots.replacing(
            try SnapshotHarness.scan(package, commit: commit),
            git: SnapshotHarness.git(commit: commit),
            coverage: coverage,
            run: CoverageSnapshots.ran(options: ["tests: failing"])
        )
    }

    @Test("""
        a scan's coverage reads back from its rows as the scan JSON holds it, dated by the scan or by the scan it \
        was carried from, beside function rows with their access and owning type and roll-up numbers from coverage
        """)
    func roundTrip() throws {
        let directory = try SnapshotHarness.temporaryDirectory("StoreCoverage")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("stats.sqlite")
        let store = try SnapshotStore(at: url)
        let snapshot = try CoverageFixture.snapshot(commit: "c1")
        let coverage = try #require(snapshot.report.coverage)

        let id = try store.save(snapshot)
        let stored = try store.load(id: id)

        #expect(stored.coverage == StoredCoverage(collectedAt: snapshot.info.date, report: coverage))
        #expect(try store.report(id: id) == snapshot.report)
        #expect(try CoverageRows(coverage, collectedAt: "", snapshotId: 0).report() == coverage)
        for record in snapshot.report.records {
            let row = try #require(stored.functions.first { $0.key == record.key })
            #expect(row.access == record.access && row.typePath == record.typePath && row.typeFile == record.typeFile)
        }
        #expect(stored.functions.contains { $0.typePath == "Counter" })
        #expect(stored.functions.contains { $0.access == .private })
        let numbers = stored.rollups.filter { $0.metric.hasPrefix("coverage.") }
        #expect(numbers.allSatisfy { $0.collector == CoverageAdapter.name })
        #expect(numbers.contains { number in
            number.name == "production" && number.metric == "coverage.lines.percent" && number.value == 79.31
        })
        #expect(numbers.contains { $0.name == "Probe" && $0.metric == "coverage.regions.total" && $0.value == 53 })
        let unmeasured = numbers.filter { $0.name == "Unlinked" }.map(\.metric)
        #expect(unmeasured.contains { $0.hasPrefix("coverage.lines.") || $0.hasPrefix("coverage.regions.") } == false)
        #expect(numbers.contains { $0.name == "Unlinked" && $0.metric == "coverage.functions.noData" && $0.value == 1 })
        let counts = try Self.query(url, """
            SELECT (SELECT count(*) FROM functionCoverage), (SELECT count(*) FROM coverageAttachment),
                (SELECT count(*) FROM coverageLine), (SELECT count(*) FROM coverageUnmapped),
                (SELECT count(*) FROM coverageRun)
            """)
        #expect(counts == "\(coverage.records.count)|\(coverage.attachments.count)|\(coverage.files.count)|"
            + "\(coverage.unmapped.count)|1\n")

        let carried = try store.save(snapshot, coverageCollectedAt: "2026-12-01T09:30:00Z")

        #expect(try store.load(id: carried).coverage?.collectedAt == "2026-12-01T09:30:00Z")
        #expect(try store.load(id: carried).coverage?.report == coverage)
    }

    @Test("""
        hand-made coverage reads back exactly, saturated counts and unsorted unmapped entries included, \
        with absent values as null columns and line data as runs and ranges
        """)
    func columns() throws {
        let directory = try SnapshotHarness.temporaryDirectory("StoreCoverage")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("stats.sqlite")
        let store = try SnapshotStore(at: url)
        let sample = try CoverageSamples.stored()
        let snapshot = try Self.snapshot(commit: "c1", coverage: sample)

        let stored = try store.load(id: try store.save(snapshot))

        #expect(stored.coverage?.report == sample)
        #expect(CoverageRows.normalized(sample) == sample)
        let records = """
            SELECT key, ifnull(lineCovered, '-'), ifnull(lineTotal, '-'), ifnull(regionCovered, '-'),
                ifnull(regionTotal, '-'), replace(testTargets, char(10), ','), ifnull(reason, '-'), ifnull(link, '-'),
                ifnull(linkedTests, '-')
            FROM functionCoverage ORDER BY key
            """
        #expect(try Self.query(url, records) == """
            Lib::Grid::subscript(_: Int) -> Int|-|-|-|-||-|-|-
            Lib::Ring::func makeIterator() -> Ring.Iterator|0|1|0|1||-|witness|-
            Lib::func one() -> Int|2|3|1|2|ATests,BTests|-|function|4
            Lib::func two()|-|-|-|-||no coverage data|-|-
            Lib::func é()|1|1|1|1|ATests|-|-|-

            """)
        #expect(try Self.query(url, "SELECT file, lines, skipped FROM coverageLine ORDER BY file") == """
            Sources/Lib/Empty.swift||
            Sources/Lib/Lib.swift|1-3:5*,4-4:0,5-6:9223372036854775807|9-9,11-12

            """)
        let unmapped = "SELECT ordinal, file, count, ifnull(demangled, '-') FROM coverageUnmapped ORDER BY ordinal"
        #expect(try Self.query(url, unmapped) == """
            0|Sources/Lib/Z.swift|9223372036854775807|-
            1|Sources/Lib/A.swift|0|Lib.a() -> ()

            """)
        let run = """
            SELECT collectedAt, replace(bundles, char(10), ','), tests, droppedBuild, droppedOutsideRoot,
                droppedTestFiles, droppedOtherPackage, droppedOtherLanguage, saturated
            FROM coverageRun
            """
        #expect(try Self.query(url, run) == """
            \(snapshot.info.date)|ATests,BTests|failing|10|1|28|2|3|[{"file":"Sources/Lib/Lib.swift","line":5}]

            """)
    }

    @Test("damaged line data is reported as a damaged store, never read as no lines")
    func damagedLines() throws {
        let directory = try SnapshotHarness.temporaryDirectory("StoreCoverage")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("stats.sqlite")
        let store = try SnapshotStore(at: url)
        let id = try store.save(try Self.snapshot(commit: "c1", coverage: try CoverageSamples.stored()))

        for damaged in ["1-3:5*,4-x:0", "1:5", "1-3:", "1-3:5**"] {
            try SnapshotHarness.sqlite(url, "UPDATE coverageLine SET lines = '\(damaged)' WHERE \(Self.libFile)")

            #expect(throws: StoreError.corruptReport("the coverage line data of Sources/Lib/Lib.swift"), "\(damaged)") {
                try store.load(id: id)
            }
        }
        try SnapshotHarness.sqlite(url, "UPDATE coverageLine SET lines = '', skipped = '9' WHERE \(Self.libFile)")

        #expect(throws: StoreError.corruptReport("the coverage line data of Sources/Lib/Lib.swift")) {
            try store.load(id: id)
        }
    }

    @Test("a v3 store migrates to v4: old rows get no access, owning type or coverage, and new scans get them")
    func migration() throws {
        let directory = try SnapshotHarness.temporaryDirectory("StoreCoverage")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("stats.sqlite")
        let old = try SnapshotHarness.stored(Self.files, commit: "c1", in: try SnapshotStore(at: url))
        let downgrade = StoreDowngrade.undoingVersion4 + ["PRAGMA user_version = 3"]
        try SnapshotHarness.sqlite(url, downgrade.joined(separator: "; "))
        #expect(try Self.query(url, "PRAGMA user_version") == "3\n")
        #expect(try Self.query(url, "SELECT count(*) FROM sqlite_master WHERE name = 'functionCoverage'") == "0\n")

        let store = try SnapshotStore(at: url)
        let migrated = try store.load(id: old.id)

        #expect(try Self.query(url, "PRAGMA user_version") == "4\n")
        #expect(migrated.functions.map(\.key) == old.functions.map(\.key))
        #expect(migrated.functions.allSatisfy { $0.access == nil && $0.typePath == nil && $0.typeFile == nil })
        #expect(migrated.functions.allSatisfy { $0.facts != nil })
        #expect(migrated.coverage == nil)

        let sample = try CoverageSamples.stored()
        let fresh = try store.load(id: try store.save(try Self.snapshot(commit: "c2", coverage: sample)))
        #expect(fresh.functions.allSatisfy { $0.access != nil })
        let peek = try #require(fresh.functions.first { $0.name == "peek" })
        #expect(peek.access == .fileprivate && peek.typePath == "Hidden" && peek.typeFile == "Sources/Lib/Lib.swift")
        #expect(fresh.coverage?.report == sample)
        #expect(try store.load(id: old.id).coverage == nil)
    }
}
