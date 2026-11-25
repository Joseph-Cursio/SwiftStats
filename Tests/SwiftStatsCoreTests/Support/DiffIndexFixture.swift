//
//  DiffIndexFixture.swift
//  SwiftStatsCoreTests
//
//  The Diff fixture's two trees (Tests/Fixtures/Diff/before and after),
//  each scanned from a temporary copy with a fixed description of its three
//  targets, with index results joined to the scan's records from the tree's
//  recorded dump (`Recorded/index/<side>.json`, made by
//  Scripts/record-index-fixture.sh from a real build): `USRJoin` over
//  `IndexWalk` over `RecordedIndexSource`, as the `index` collector reads
//  a store (M7, design §3.6, §13 step 7b). Only the records' USRs are kept;
//  the rest of the index block is empty. The `build` and `index` runs are
//  marked ran with a given build identity, so `diff` compares the index
//  exactly when the identities match. Nothing is built or read for real.
//

import Foundation
@testable import SwiftStatsCore

/// The Diff fixture's trees with the USRs their recorded index gives.
enum DiffIndexFixture {
    /// The build identity both sides get unless a test says otherwise.
    static let buildIdentity = "swift-6.4.2-test"

    /// The fixture's directory.
    private static let directory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/Diff")

    /// The tree `side` (`before` or `after`): its Swift files and manifest,
    /// by path relative to the tree.
    static func files(_ side: String) throws -> [String: String] {
        let root = directory.appendingPathComponent(side)
        let paths = try FileManager.default.subpathsOfDirectory(atPath: root.path)
            .filter { $0.hasSuffix(".swift") }
            .sorted()
        var files: [String: String] = [:]
        for path in paths {
            files[path] = try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
        }
        return files
    }

    /// The description of `files`' three targets, as `Package.swift`
    /// declares them.
    static func targets(_ files: [String: String]) -> [DescribedTarget] {
        ["Glossary", "Shapes", "Spelling"].map { name in
            let prefix = "Sources/\(name)/"
            return DescribedTarget(
                name: name,
                type: "library",
                moduleType: "SwiftTarget",
                path: "Sources/\(name)",
                sources: files.keys.filter { $0.hasPrefix(prefix) }.map { String($0.dropFirst(prefix.count)) }.sorted(),
                targetDependencies: name == "Spelling" ? ["Glossary"] : []
            )
        }
    }

    /// The primary USRs the recorded index of `side` gives its records, by
    /// key.
    static func usrs(_ side: String) throws -> [String: String] {
        let package = try TemporaryPackage(try files(side), targets: targets(try files(side)))
        defer { package.remove() }
        let scanned = try SnapshotHarness.scan(package, commit: side)
        return try join(side, records: scanned.report, root: package.root).primary
    }

    /// The tree `side` scanned at `commit`, holding index results whose
    /// records carry the USRs its recorded index gives, with its `build`
    /// and `index` runs ran as `buildIdentity`.
    static func snapshot(_ side: String, commit: String) throws -> ScannedSnapshot {
        try snapshot(side, commit: commit, build: buildIdentity)
    }

    /// The tree `side` scanned at `commit`, holding index results whose
    /// records carry the USRs its recorded index gives, with its `build`
    /// and `index` runs ran as `build` (their identity).
    static func snapshot(_ side: String, commit: String, build: String) throws -> ScannedSnapshot {
        let files = try files(side)
        let package = try TemporaryPackage(files, targets: targets(files))
        defer { package.remove() }
        let scanned = try SnapshotHarness.scan(package, commit: commit)
        let join = try join(side, records: scanned.report, root: package.root)
        let index = IndexReport(
            store: IndexStoreSummary(
                layout: "swiftbuild",
                counts: IndexUnitCounts([], quarantined: 0),
                records: 0,
                occurrences: 0,
                units: []
            ),
            libraryModules: [],
            records: records(of: scanned.report, join: join),
            definitions: IndexDefinitions(
                joined: join.joinedCount,
                implicit: join.implicitCount,
                secondary: 0,
                objc: 0
            ),
            disagreements: [],
            withoutRecord: [],
            collisions: [],
            moduleEdges: [],
            types: [],
            familyReferences: [],
            familyTypeReferences: [],
            files: scanned.report.files.map(\.path).sorted().map { IndexFileHash(path: $0, sha256: nil) }
        )
        let report = scanned.report
            .with(build: nil, status: status(BuildAdapter.name))
            .with(index: IndexRows.normalized(index), status: status(IndexAdapter.name))
        let info = scanned.info
            .with(run: run(BuildAdapter.name, identity: build))
            .with(run: run(IndexAdapter.name, identity: IndexAdapter.name))
        return ScannedSnapshot(info: info, report: report)
    }

    /// `scan`'s records with the USRs `join` gives them, `unexplained`
    /// when it gives none, and no referrers.
    private static func records(of scan: ScanReport, join: USRJoin) -> [IndexRecordUSR] {
        scan.records.map { record in
            let usr = join.primary[record.key]
            return IndexRecordUSR(
                key: record.key,
                usr: usr,
                usrAccessor: join.secondary[record.key],
                reason: usr == nil ? .unexplained : nil,
                coupling: usr.map { _ in
                    IndexRecordCoupling(
                        witness: false,
                        references: IndexReferences(sameModule: 0, otherModules: 0, tests: 0, testReferrers: [])
                    )
                }
            )
        }
    }

    /// The join of the recorded index of `side`, its `@ROOT@` put back as
    /// the real path of `root`, to `scan`'s records.
    private static func join(_ side: String, records scan: ScanReport, root: URL) throws -> USRJoin {
        let realRoot = IndexStoreReader.realPath(root.path)
        let recording = try Data(contentsOf: directory.appendingPathComponent("Recorded/index/\(side).json"))
        let source = try RecordedIndexSource(recording: recording, restoring: [IndexFixture.rootToken: realRoot])
        let filter = try UnitFilter(
            root: realRoot,
            scratch: realRoot + "/.swiftstats/index-build",
            package: DescribedPackage(name: "Shapes", targets: targets(try files(side)))
        )
        let snapshot = try IndexWalk.walk(source, filter: filter)
        return USRJoin(
            snapshot: snapshot,
            records: scan.records,
            files: Set(scan.files.map(\.path)),
            changedFiles: []
        )
    }

    /// Collector `name`'s status, ran.
    private static func status(_ name: String) -> CollectorStatus {
        CollectorStatus(name: name, state: .ran, version: "test", reason: nil, options: [])
    }

    /// Collector `name`'s run, ran as `identity`.
    private static func run(_ name: String, identity: String) -> CollectorRunInfo {
        CollectorRunInfo(
            name: name,
            state: .ran,
            reason: nil,
            version: "test",
            identity: identity,
            identityLabel: nil,
            options: [],
            durationMilliseconds: 0
        )
    }
}
