import Foundation
@testable import SwiftStatsCore
import Testing

/// Keeping T1 results across rescans through the scans' own paths (M7,
/// design §9.4): a plain scan, and a `scan --index` whose build fails,
/// after `scan --index` of the Index fixture with its recorded build,
/// index and outskirts runs; coverage, mutation and T1 results carried in
/// one save of the Coverage fixture's repository, coverage refused first;
/// and `diff`'s rescans with `--drop-index` (`IndexGateTests` covers the
/// checks before the slow runs). Serialized: the fixture scans run on threads of
/// their own, as the index collector's tests do.
@Suite("Index carry through scans", .serialized)
struct IndexCarryScanTests {
    /// The T1 statuses of `report`.
    private static func statuses(_ report: ScanReport) -> [CollectorStatus] {
        report.collectors.filter { IndexCarry.names.contains($0.name) }
    }

    /// `report` with `statuses` as its T1 collectors' statuses, its blocks
    /// attached again.
    private static func with(_ statuses: [CollectorStatus], in report: ScanReport) throws -> ScanReport {
        let status = { (name: String) in try #require(statuses.first { $0.name == name }) }
        return report.with(
            build: report.build,
            totals: TypeCheckTotals(rollups: report.rollups),
            status: try status(BuildAdapter.name)
        )
            .with(index: report.index, status: try status(IndexAdapter.name))
            .with(deadCode: report.deadCode, status: try status(PeripheryAdapter.name))
    }

    /// `snapshot`'s `swiftc` finding rows, one line each, in their order.
    private static func compilerRows(_ snapshot: StoredSnapshot) -> [String] {
        snapshot.findings.filter { $0.tool == WarningReader.tool }.map { row in
            let place = "\(row.file):\(row.line ?? 0):\(row.column ?? 0)"
            return "\(row.rule) \(row.message) \(place) \(row.attachedTo) \(row.owner ?? "")"
        }
    }

    /// The error `body` throws as a store error; nil when it throws none.
    private static func storeError(_ body: () throws -> Void) throws -> StoreError? {
        do {
            try body()
            return nil
        } catch let error as StoreError {
            return error
        }
    }

    /// Which held results `error` refuses over.
    private static func kind(_ error: StoreError) -> String {
        switch error {
        case .coverageNotKept:
            "coverage"

        case .mutationNotKept:
            "mutation"

        case .indexNotKept:
            "index"

        default:
            "other"
        }
    }

    /// A workspace on `fixture` storing in `made`.
    private static func workspace(_ fixture: BuildFixture, store made: TemporaryStore) throws -> SnapshotWorkspace {
        try SnapshotWorkspace(
            packageRoot: fixture.package.root,
            configurationFile: nil,
            storeOverride: made.url.path,
            build: SnapshotHarness.build,
            describer: fixture.package.describer,
            tools: SnapshotHarness.noTools
        )
    }

    /// `fixture` scanned again, as the test build at `c1` on `date`, with
    /// its `.swiftstats.yml`, asking for `tiers`.
    private static func rescan(_ fixture: BuildFixture, date: Date, tiers: RequestedTiers) throws -> ScannedSnapshot {
        let root = fixture.package.root
        return try SnapshotScanner(
            scanner: PackageScanner(describer: fixture.package.describer, tools: SnapshotHarness.noTools),
            build: SnapshotHarness.build
        )
        .scan(
            packageAt: root,
            configurationFile: StoreLocation.localConfiguration(packageRoot: root),
            git: SnapshotHarness.git(commit: "c1"),
            toolchain: SnapshotHarness.toolchain,
            date: date,
            history: .skipped("test"),
            tiers: tiers
        )
    }

    @Test("""
        a plain scan after scan --index of the Index fixture carries the build, index and dead-code results with \
        the compiler warnings, their groups included, giving the report the scan --index gave but for the three \
        runs, and the store reads back the same rows
        """)
    func fixtureCarry() async throws {
        let fake = try FakePeriphery.make(try FakePeriphery.recorded())
        defer { fake.remove() }
        var scan = try IndexFixtureScan()
        scan.extra = fake.configuration
        try await scan.run { fixture, outcome in
            let made = try TemporaryStore("IndexCarryScan")
            defer { made.remove() }
            let workspace = try Self.workspace(fixture, store: made)
            let held = outcome.snapshot
            let stored = try workspace.store.load(id: try workspace.save(held, drop: []).id)

            let carried = try workspace.save(
                try Self.rescan(fixture, date: IndexCarrySamples.later(1), tiers: .syntaxOnly),
                drop: []
            )

            let swiftc = held.report.findings.filter { $0.tool == WarningReader.tool }
            #expect(swiftc.isEmpty == false && held.report.deadCode != nil && held.report.index != nil)
            #expect(swiftc.contains { $0.category != nil })
            #expect(carried.snapshot.report.findings == held.report.findings)
            #expect(try Self.with(Self.statuses(held.report), in: carried.snapshot.report) == held.report)
            let runs = IndexCarry.names.compactMap { name in held.info.collectors.first { $0.name == name } }
            #expect(Self.statuses(carried.snapshot.report)
                == runs.map { $0.carried(collectedAt: held.info.date).status })
            let again = try workspace.store.load(id: carried.id)
            #expect(again.index == stored.index && again.build == stored.build && again.deadCode == stored.deadCode)
            #expect(Self.compilerRows(again) == Self.compilerRows(stored))
            #expect(Self.compilerRows(stored).isEmpty == false)
            #expect(try workspace.store.report(id: carried.id) == carried.snapshot.report)
        }
    }

    @Test("""
        a scan --index of the Index fixture whose build fails keeps the results of the scan --index before it, \
        and says so in the warning scan prints
        """)
    func failedBuildCarry() async throws {
        let fake = try FakePeriphery.make(try FakePeriphery.recorded())
        defer { fake.remove() }
        var scan = try IndexFixtureScan()
        scan.extra = fake.configuration
        try await scan.run { fixture, outcome in
            let made = try TemporaryStore("IndexCarryScan")
            defer { made.remove() }
            let workspace = try Self.workspace(fixture, store: made)
            let held = outcome.snapshot
            _ = try workspace.save(held, drop: [])
            var failing = try FakeToolchain.recordedBuild()
            failing.status = 1
            let toolchain = try FakeToolchain.make(build: failing)
            defer { toolchain.remove() }
            try IndexGroupHarness.configuration(toolchain, extra: fake.configuration).write(
                to: fixture.package.root.appendingPathComponent(".swiftstats.yml"),
                atomically: true,
                encoding: .utf8
            )
            let failed = try Self.rescan(fixture, date: IndexCarrySamples.later(1), tiers: RequestedTiers(index: true))
            let ownBuild = try #require(failed.report.collectors.first { $0.name == BuildAdapter.name })

            let kept = try workspace.save(failed, drop: []).snapshot

            let notice = "build: this scan's index build failed (\(ownBuild.reason ?? "")), so it keeps the results "
                + "collected \(held.info.date)"
            #expect(ownBuild.state == .failed)
            #expect(kept.report.index == held.report.index && kept.report.findings == held.report.findings)
            #expect(UnrunNotice.lines(for: kept.report, requested: RequestedTiers(index: true))
                == ["Warning: " + notice])
        }
    }

    @Test("""
        a plain scan carries coverage, mutation results and T1 results in one save, each with its own date; when \
        none carries, coverage is refused first, then mutation, then the T1 results, and dropping all three \
        replaces the snapshot
        """)
    func threeKinds() throws {
        let toolchain = try FakeToolchain.make(try FakeToolchain.recorded())
        defer { toolchain.remove() }
        let package = try CoverageFixture.repository(toolchain: toolchain)
        defer { package.remove() }
        let workspace = try CarryHarness.workspace(package, build: SnapshotHarness.build)
        let covered = try workspace.scanWorkingTree(history: .skipped("test"), tiers: .coverage).snapshot
        let mutated = MutationSnapshots.replacing(
            covered,
            git: covered.info.git,
            mutation: try MutationCarrySamples.results(),
            run: MutationCarrySamples.run
        )
        let held = try IndexCarrySamples.held(mutated)
        let heldID = try workspace.save(held, drop: []).id
        let stored = try workspace.store.load(id: heldID)

        let carried = try workspace.scanWorkingTree(history: .skipped("test"))

        let report = carried.snapshot.report
        #expect(report.coverage == covered.report.coverage && report.mutation == mutated.report.mutation)
        #expect(report.index == stored.index?.report && report.build == stored.build?.report)
        let again = try workspace.store.load(id: carried.id)
        #expect(again.coverage?.collectedAt == covered.info.date)
        #expect(again.mutation == stored.mutation && again.index == stored.index)
        #expect(again.index?.collectedAt == held.info.date)

        _ = try workspace.save(held, drop: [])
        let counter = package.root.appendingPathComponent(MutationCarrySamples.counterPath)
        try ("\n" + MutationCarrySamples.counter).write(to: counter, atomically: true, encoding: .utf8)
        let moved = try workspace.scanner.scan(
            packageAt: package.root,
            configurationFile: workspace.configurationFile,
            git: held.info.git,
            toolchain: SnapshotHarness.toolchain,
            date: IndexCarrySamples.later(1),
            history: .skipped("test")
        )
        let refusals = try [[], DropOptions.coverage, [.coverage, .mutation]].map { drop in
            try #require(try Self.storeError { _ = try workspace.save(moved, drop: drop) })
        }

        #expect(refusals.map(Self.kind) == ["coverage", "mutation", "index"])
        if case let .indexNotKept(_, _, reason) = refusals[2] {
            #expect(reason.hasSuffix("spans other lines or columns now"))
        }
        let replaced = try workspace.save(moved, drop: [.coverage, .mutation, .index])
        #expect(replaced.snapshot == moved)
        #expect(try workspace.store.holdsIndex(id: replaced.id) == false)
    }

    @Test("""
        diff's rescan of a commit carries its T1 results; over held T1 results of other uncommitted changes it \
        stops, and --drop-index replaces the snapshot without them
        """)
    func diffRescans() throws {
        let toolchain = try FakeToolchain.make(try FakeToolchain.recorded())
        defer { toolchain.remove() }
        let package = try CoverageFixture.repository(toolchain: toolchain)
        defer { package.remove() }
        let workspace = try CarryHarness.workspace(package, build: SnapshotHarness.build)
        let other = SwiftStatsBuild(identity: "inputs:rebuilt", label: nil)
        let rebuilt = try CarryHarness.workspace(package, build: other)
        let counter = package.root.appendingPathComponent(MutationCarrySamples.counterPath)
        let plain = try workspace.scanWorkingTree(history: .skipped("test")).snapshot
        let first = try IndexCarrySamples.held(plain)
        _ = try workspace.save(first, drop: [])
        let commit = try #require(first.info.git.commit)
        try (MutationCarrySamples.counter + "// Changed.\n").write(to: counter, atomically: true, encoding: .utf8)
        try SnapshotHarness.runGit(["commit", "--quiet", "--all", "--message", "Change"], in: package.root)

        let ids = try rebuilt.diffSnapshotIDs(older: commit, newer: nil, includeDirty: false, rescan: true)

        let older = try rebuilt.store.load(id: ids.older)
        #expect(older.index?.collectedAt == first.info.date)
        #expect(older.index?.report.files == first.report.index?.files)
        #expect(try rebuilt.store.holdsIndex(id: ids.newer) == false)

        try (MutationCarrySamples.counter + "// Dirty.\n").write(to: counter, atomically: true, encoding: .utf8)
        let dirty = try IndexCarrySamples.held(try workspace.scanWorkingTree(history: .skipped("test")).snapshot)
        _ = try workspace.save(dirty, drop: [])
        try (MutationCarrySamples.counter + "// Dirtier.\n").write(to: counter, atomically: true, encoding: .utf8)
        let head = String(try SnapshotHarness.runGit(["rev-parse", "HEAD"], in: package.root).prefix(10))
        #expect(throws: StoreError.indexNotKept(
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
            drop: .index
        )
        #expect(try workspace.store.load(id: replaced.newer).info.git.isDirty)
        #expect(try workspace.store.holdsIndex(id: replaced.newer) == false)
    }
}
