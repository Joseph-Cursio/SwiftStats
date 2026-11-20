import Foundation
@testable import SwiftStatsCore
import Testing

/// The store's v3 rows (PRD §9, M4): function facts, scan facts, property
/// candidates, law checks and clones read back as the report holds them,
/// and a store written before v3 migrates with nulls.
@Suite("Store v3 rows")
struct StoreRowTests {
    /// A library with a function, a getter, a subscript and an initialiser,
    /// a generated file, and a test.
    private static let files = [
        "Sources/Lib/Lib.swift": """
        public struct Money {
            public var cents: Int

            public init(cents: Int) {
                self.cents = cents
            }

            public var doubled: Int {
                cents * 2
            }

            public subscript(scale: Int) -> Int {
                cents * scale
            }

            public func double(_ value: Int) -> Int {
                value * 2
            }
        }
        """,
        "Sources/Lib/Model.generated.swift": "func made() -> Int {\n    1\n}\n",
        "Tests/LibTests/LibTests.swift": "func testDouble() {\n    _ = 2\n}\n"
    ]

    /// The columns v3 adds to `function`.
    private static let functionColumns = [
        "effectTier", "effectSource", "purity", "refutation", "inference", "inferredTier", "inferredAnchor",
        "inferredDepth", "inferredVia", "valueShaped", "shape", "generated"
    ]

    /// The tables v3 adds.
    private static let tables = [
        "scanFacts", "propertyCandidate", "lawCheck", "cloneInstance", "cloneClass", "historyCommit", "familyChange"
    ]

    /// `sqlite3`'s output for `statement` on the database at `url`.
    private static func query(_ url: URL, _ statement: String) throws -> String {
        let output = try ProcessRunner.run(
            executable: "/usr/bin/sqlite3",
            arguments: [url.path, statement],
            in: url.deletingLastPathComponent()
        )
        return String(bytes: output, encoding: .utf8) ?? ""
    }

    @Test("every v3 row reads back as the report holds it")
    func roundTrip() throws {
        let directory = try SnapshotHarness.temporaryDirectory("StoreRows")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("stats.sqlite")
        let store = try SnapshotStore(at: url)
        let package = try TemporaryPackage(Self.files)
        defer { package.remove() }
        let scanned = try SnapshotHarness.scan(package, commit: "c1")
        var records = scanned.report.records
        let index = try #require(records.firstIndex { $0.name == "double" })
        records[index].effect = try StoreRowSamples.effect()
        let report = try StoreRowSamples.report(scanned.report, records: records)

        let id = try store.save(ScannedSnapshot(info: scanned.info, report: report))
        let stored = try store.load(id: id)

        #expect(try store.report(id: id) == report)
        #expect(stored.candidates == report.properties?.candidates)
        #expect(stored.lawChecks == report.laws.checks)
        #expect(stored.cloneClasses == report.clones?.classes)
        #expect(stored.scanFacts?.kitDependency == true)
        #expect(stored.scanFacts?.sipSeiRevision == "ba3624d")
        #expect(stored.historyCommits.isEmpty)
        #expect(stored.familyChanges.isEmpty)
        let generated = Set(report.files.filter(\.generated).map(\.path))
        #expect(generated == ["Sources/Lib/Model.generated.swift"])
        for record in records {
            let row = try #require(stored.functions.first { $0.key == record.key })
            let effect = record.effect.map(StoredEffect.init)
            #expect(row.facts == StoredFunctionFacts(generated: generated.contains(record.file), effect: effect))
        }
        let double = try #require(stored.functions.first { $0.key == records[index].key })
        #expect(double.facts?.effect?.refutation == "nondeterministicCall")
        #expect(double.facts?.effect?.function?.inferred?.via == ["calls `a()`", "calls `b()`"])
        let getter = try #require(stored.functions.first { $0.accessorKind == "get" }?.facts?.effect)
        #expect(getter.function == nil)
        #expect(stored.functions.first { $0.kind == .subscriptDeclaration }?.facts?.effect != nil)
        #expect(stored.functions.first { $0.kind == .initializer }?.facts?.effect == nil)
        #expect(stored.functions.first { $0.role == .test }?.facts?.effect == nil)
    }

    @Test("absent fields are null columns, not zeros or empty strings")
    func nullColumns() throws {
        let directory = try SnapshotHarness.temporaryDirectory("StoreRows")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("stats.sqlite")
        let store = try SnapshotStore(at: url)
        let package = try TemporaryPackage(Self.files)
        defer { package.remove() }
        let scanned = try SnapshotHarness.scan(package, commit: "c1")
        let report = try StoreRowSamples.report(scanned.report, records: scanned.report.records)

        try store.save(ScannedSnapshot(info: scanned.info, report: report))

        let joins = """
            SELECT ordinal, ifnull(verifyOutcome, '-'), ifnull(verifyFresh, '-'), ifnull(verified, '-'),
                ifnull(file, '-'), ifnull(attachedTo, '-'), testKeys
            FROM propertyCandidate ORDER BY ordinal
            """
        #expect(try Self.query(url, joins) == """
            0|-|-|-|-|-|
            1|measured-bothPass|1|1|Sources/Lib/Lib.swift|function|Tests::func first()
            Tests::func second()
            2|measured-defaultFails|-|-|-|-|
            3|-|0|0|Sources/Lib/Lib.swift|type|Tests::func stub()

            """)
        let unset = """
            SELECT count(*) FROM function
            WHERE generated IS NULL OR (role = 'test' AND effectSource IS NOT NULL)
            """
        #expect(try Self.query(url, unset) == "0\n")
        #expect(try Self.query(url, "SELECT ordinal, ifnull(similarity, '-') FROM cloneClass") == "1|-\n2|0.9012\n")
    }

    @Test("a v2 store migrates to v3: old rows get nulls and no v3 rows, and new scans get all of them")
    func migration() throws {
        let directory = try SnapshotHarness.temporaryDirectory("StoreRows")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("stats.sqlite")
        let old = try SnapshotHarness.stored(Self.files, commit: "c1", in: try SnapshotStore(at: url))
        let downgrade = Self.tables.map { "DROP TABLE \($0)" }
            + Self.functionColumns.map { "ALTER TABLE function DROP COLUMN \($0)" }
            + ["DELETE FROM grdb_migrations WHERE identifier = 'v3'", "PRAGMA user_version = 2"]
        try SnapshotHarness.sqlite(url, downgrade.joined(separator: "; "))
        #expect(try Self.query(url, "PRAGMA user_version") == "2\n")

        let store = try SnapshotStore(at: url)
        let migrated = try store.load(id: old.id)

        #expect(try Self.query(url, "PRAGMA user_version") == "3\n")
        #expect(migrated.functions.map(\.key) == old.functions.map(\.key))
        #expect(migrated.functions.allSatisfy { $0.facts == nil })
        #expect(migrated.scanFacts == nil)
        #expect(migrated.candidates.isEmpty && migrated.lawChecks.isEmpty && migrated.cloneClasses.isEmpty)
        #expect(migrated.historyCommits.isEmpty && migrated.familyChanges.isEmpty)
        let nulls = Self.functionColumns.map { "\($0) IS NULL" }.joined(separator: " AND ")
        let count = "SELECT count(*) = (SELECT count(*) FROM function) FROM function WHERE \(nulls)"
        #expect(try Self.query(url, count) == "1\n")

        let fresh = try SnapshotHarness.stored(Self.files, commit: "c2", in: store)
        #expect(fresh.functions.allSatisfy { $0.facts != nil })
        #expect(fresh.scanFacts?.kitDependency == false)
        #expect(try store.load(id: old.id).functions.allSatisfy { $0.facts == nil })
    }
}
