import Foundation
@testable import SwiftStatsCore
import Testing

/// The snapshot store (PRD §6.2, §9, D9).
@Suite("Snapshot store")
struct SnapshotStoreTests {
    /// A small package to store.
    private static let files = [
        "Sources/Lib/Lib.swift": """
        /// Doubles `value`.
        public func double(_ value: Int) -> Int {
            let result = value * 2
            return result
        }

        func risky(_ value: Int?) -> Int {
            precondition(value != nil)
            return value ?? 0
        }
        """
    ]

    @Test("a stored snapshot reads back: its report equal, its rows matching it")
    func roundTrip() throws {
        let directory = try SnapshotHarness.temporaryDirectory("Store")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SnapshotStore(at: directory.appendingPathComponent("stats.sqlite"))
        let package = try TemporaryPackage(Self.files)
        defer { package.remove() }
        let snapshot = try SnapshotHarness.scan(
            package,
            commit: "c1",
            build: SnapshotHarness.build,
            tools: SnapshotHarness.noTools
        )

        let id = try store.save(snapshot)
        let loaded = try store.load(id: id)

        #expect(try store.report(id: id) == snapshot.report)
        #expect(try store.info(id: id) == snapshot.info)
        #expect(loaded.functions.map(\.key) == snapshot.report.records.map(\.key).sorted())
        #expect(loaded.findings.count == snapshot.report.findings.flatMap(\.locations).count)
        #expect(loaded.findings.map(\.rule) == ["precondition"])
        let production = loaded.rollups.filter { $0.scope == .project && $0.name == "production" }
        #expect(production.first { $0.metric == "functions.func" }?.value == 2)
        #expect(production.first { $0.metric == "findings.swiftstats.precondition" }?.collector == "swiftstats")
        #expect(production.first { $0.metric == "effects.purity.pure" }?.collector == "swifteffectinference")
        let collectorNames = [
            "dependencies", "history", "swifteffectinference", "swiftlint", "swiftprojectlint", "swiftstats"
        ]
        #expect(snapshot.info.collectors.map(\.name) == collectorNames)
    }

    @Test("a rescan replaces its commit's snapshot; clean and dirty, and other commits, are kept apart")
    func replacement() throws {
        let directory = try SnapshotHarness.temporaryDirectory("Store")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SnapshotStore(at: directory.appendingPathComponent("stats.sqlite"))
        let package = try TemporaryPackage(Self.files)
        defer { package.remove() }
        let clean = try SnapshotHarness.scan(package, commit: "c1")
        let dirtyState = GitState(commit: "c1", branch: nil, isDirty: true, dirtyHash: "h", packagePath: "")
        let dirty = ScannedSnapshot(
            info: SnapshotInfo(
                package: clean.info.package,
                git: dirtyState,
                date: clean.info.date,
                toolchain: clean.info.toolchain,
                collectors: clean.info.collectors
            ),
            report: clean.report
        )

        let first = try store.save(clean)
        let second = try store.save(clean)
        let dirtyID = try store.save(dirty)
        let other = try store.save(try SnapshotHarness.scan(
            package,
            commit: "c2",
            build: SnapshotHarness.build,
            tools: SnapshotHarness.noTools
        ))

        #expect(first != second)
        #expect(try store.snapshotID(package: "Probe", packagePath: "", commit: "c1", isDirty: false) == second)
        #expect(try store.snapshotID(package: "Probe", packagePath: "", commit: "c1", isDirty: true) == dirtyID)
        #expect(try store.snapshotID(package: "Probe", packagePath: "", commit: "c2", isDirty: false) == other)
        #expect(throws: StoreError.noSnapshot("id \(first)")) {
            try store.load(id: first)
        }
    }

    @Test("a package outside git keeps one snapshot, replaced by each scan")
    func outsideGit() throws {
        let directory = try SnapshotHarness.temporaryDirectory("Store")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SnapshotStore(at: directory.appendingPathComponent("stats.sqlite"))
        let package = try TemporaryPackage(Self.files)
        defer { package.remove() }
        let snapshot = try SnapshotHarness.scan(package, commit: nil)

        let replaced = try store.save(snapshot)
        let latest = try store.save(snapshot)

        #expect(try store.snapshotID(package: "Probe", packagePath: "", commit: nil, isDirty: false) == latest)
        #expect(try store.latestSnapshotID(package: "Probe", packagePath: "") == latest)
        #expect(throws: StoreError.noSnapshot("id \(replaced)")) {
            try store.load(id: replaced)
        }
    }

    @Test("a store with a migration this build doesn't know is refused; user_version mirrors the migrations")
    func newerStore() throws {
        let directory = try SnapshotHarness.temporaryDirectory("Store")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("stats.sqlite")
        _ = try SnapshotStore(at: url)
        let version = try ProcessRunner.run(
            executable: "/usr/bin/sqlite3",
            arguments: [url.path, "PRAGMA user_version"],
            in: directory
        )
        #expect(String(bytes: version, encoding: .utf8) == "2\n")

        try SnapshotHarness.sqlite(url, "INSERT INTO grdb_migrations VALUES ('v99')")

        #expect(throws: StoreError.newerStore(url.path)) {
            try SnapshotStore(at: url)
        }
    }

    @Test("a report stored with another schema says to rescan rather than failing to decode")
    func otherSchema() throws {
        let directory = try SnapshotHarness.temporaryDirectory("Store")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("stats.sqlite")
        let store = try SnapshotStore(at: url)
        let id = try SnapshotHarness.stored(Self.files, commit: "c1", in: store).id

        try SnapshotHarness.sqlite(url, "UPDATE report SET schemaVersion = 2")

        #expect(throws: StoreError.reportSchema(stored: 2, current: ScanReport.currentSchemaVersion)) {
            try store.report(id: id)
        }
        #expect(try store.load(id: id).functions.isEmpty == false)
    }

    @Test("the default store ignores itself in git; store: and --store move it")
    func location() throws {
        let root = try SnapshotHarness.temporaryDirectory("Location")
        defer { try? FileManager.default.removeItem(at: root) }
        let configured = try SwiftStatsConfiguration.parse("store: ../shared/stats.sqlite\n", path: "c.yml")

        let standard = StoreLocation.resolve(packageRoot: root, configuration: SwiftStatsConfiguration(), override: nil)
        try StoreLocation.prepare(standard, packageRoot: root)
        let moved = StoreLocation.resolve(packageRoot: root, configuration: configured, override: nil)
        let overridden = StoreLocation.resolve(packageRoot: root, configuration: configured, override: "/tmp/x.sqlite")

        #expect(standard.path == root.standardizedFileURL.path + "/.swiftstats/stats.sqlite")
        let ignore = root.appendingPathComponent(".swiftstats/.gitignore")
        #expect(try String(contentsOf: ignore, encoding: .utf8) == "*\n")
        #expect(moved.path == root.deletingLastPathComponent().standardizedFileURL.path + "/shared/stats.sqlite")
        #expect(overridden.path == "/tmp/x.sqlite")
    }
}
