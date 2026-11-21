import Foundation
@testable import SwiftStatsCore
import Testing

/// Keeping coverage across rescans (M5, design §6) through the commands'
/// own paths, on the Coverage fixture in a git repository with the fake
/// toolchain acting out the recorded run: `scan` after `scan --coverage`,
/// a SwiftStats rebuild, `diff --rescan` of an exported commit, and a
/// working-tree rescan over other uncommitted changes.
@Suite("Coverage carry through scans")
struct CoverageCarryScanTests {
    /// Another SwiftStats build.
    private static let otherBuild = SwiftStatsBuild(identity: "inputs:rebuilt", label: nil)

    @Test("""
        a plain scan after scan --coverage of the same tree, then one by another SwiftStats build, carries the \
        coverage, and the printed scan, the stored report, its rows and its roll-up numbers agree
        """)
    func plainScans() throws {
        let toolchain = try FakeToolchain.make(try FakeToolchain.recorded())
        defer { toolchain.remove() }
        let package = try CoverageFixture.repository(toolchain: toolchain)
        defer { package.remove() }
        let workspace = try CarryHarness.workspace(package, build: SnapshotHarness.build)
        let rebuilt = try CarryHarness.workspace(package, build: Self.otherBuild)

        let first = try workspace.scanWorkingTree(history: .skipped("test"), coverage: true).snapshot
        let second = try workspace.scanWorkingTree(history: .skipped("test"))
        let third = try rebuilt.scanWorkingTree(history: .skipped("test"))

        let coverage = try #require(first.report.coverage)
        let originalRun = try #require(CarryHarness.coverageRun(first.info))
        let firstStatus = try #require(first.report.collectors.first { $0.name == CoverageAdapter.name })
        #expect(originalRun.state == .ran && first.info.git.isDirty == false)
        for carried in [second, third] {
            #expect(carried.snapshot.report.coverage == coverage)
            #expect(carried.snapshot.report.rollups == first.report.rollups)
            #expect(carried.snapshot.report.with(coverage: coverage, status: firstStatus, warnings: []) == first.report)
            #expect(CarryHarness.coverageRun(carried.snapshot.info) == CollectorRunInfo(
                name: CoverageAdapter.name,
                state: .ran,
                reason: "carried from the scan of \(first.info.date)",
                version: originalRun.version,
                identity: originalRun.identity,
                identityLabel: originalRun.identityLabel,
                options: originalRun.options,
                durationMilliseconds: originalRun.durationMilliseconds
            ))
        }
        let stored = try rebuilt.store.load(id: third.id)
        #expect(stored.coverage == StoredCoverage(collectedAt: first.info.date, report: coverage))
        #expect(stored.info == third.snapshot.info)
        #expect(stored.info.collectors.first { $0.name == SwiftStatsCollector.name }?.identity == "inputs:rebuilt")
        #expect(try ScanReportEncoder.encode(rebuilt.store.report(id: third.id))
            == ScanReportEncoder.encode(third.snapshot.report))
        let numbers = try CarryHarness.coverageNumbers(first.report.rollups)
        #expect(CarryHarness.coverageNumbers(stored.rollups) == numbers && numbers.isEmpty == false)
    }

    @Test("""
        diff --rescan by another build carries an exported commit's coverage; a working-tree rescan over other \
        uncommitted changes is refused, and --drop-coverage replaces it
        """)
    func diffRescans() throws {
        let toolchain = try FakeToolchain.make(try FakeToolchain.recorded())
        defer { toolchain.remove() }
        let package = try CoverageFixture.repository(toolchain: toolchain)
        defer { package.remove() }
        let workspace = try CarryHarness.workspace(package, build: SnapshotHarness.build)
        let rebuilt = try CarryHarness.workspace(package, build: Self.otherBuild)
        let counter = package.root.appendingPathComponent("Sources/Probe/Counter.swift")
        let source = try String(contentsOf: counter, encoding: .utf8)
        let first = try workspace.scanWorkingTree(history: .skipped("test"), coverage: true).snapshot
        let commit = try #require(first.info.git.commit)
        try (source + "// Changed.\n").write(to: counter, atomically: true, encoding: .utf8)
        try SnapshotHarness.runGit(["commit", "--quiet", "--all", "--message", "Change"], in: package.root)

        let ids = try rebuilt.diffSnapshotIDs(older: commit, newer: nil, includeDirty: false, rescan: true)

        let older = try rebuilt.store.load(id: ids.older)
        let coverage = try #require(first.report.coverage)
        #expect(older.info.git.commit == commit)
        #expect(older.coverage == StoredCoverage(collectedAt: first.info.date, report: coverage))
        #expect(older.info.collectors.first { $0.name == SwiftStatsCollector.name }?.identity == "inputs:rebuilt")
        #expect(try rebuilt.store.load(id: ids.newer).coverage == nil)

        try (source + "// Dirty.\n").write(to: counter, atomically: true, encoding: .utf8)
        let dirty = try workspace.scanWorkingTree(history: .skipped("test"), coverage: true).snapshot
        try (source + "// Dirtier.\n").write(to: counter, atomically: true, encoding: .utf8)
        let head = String(try SnapshotHarness.runGit(["rev-parse", "HEAD"], in: package.root).prefix(10))
        #expect(throws: StoreError.coverageNotKept(
            snapshot: "Probe at \(head) with uncommitted changes",
            collectedAt: dirty.info.date,
            reason: "the uncommitted changes differ"
        )) {
            try workspace.diffSnapshotIDs(older: commit, newer: nil, includeDirty: true, rescan: false)
        }
        let replaced = try workspace.diffSnapshotIDs(
            older: commit,
            newer: nil,
            includeDirty: true,
            rescan: false,
            dropCoverage: true
        )
        let newer = try workspace.store.load(id: replaced.newer)
        #expect(newer.info.git.isDirty && newer.coverage == nil)
    }
}
