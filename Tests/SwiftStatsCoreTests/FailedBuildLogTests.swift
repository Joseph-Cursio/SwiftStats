import Foundation
@testable import SwiftStatsCore
import Testing

/// Which T1 build output `scan --index` names (M7, design §1.5,
/// `FailedBuildLog`): the standard error, which holds the errors, then the
/// task log, and only those of a build this scan's own build command ran
/// that failed, whether or not the scan then returned, and never a log
/// another scan holding `index.lock` is writing, or one a scan left before
/// a failure that stopped this one before its build command.
@Suite("Failed build log")
struct FailedBuildLogTests {
    /// What a scan of the small package gave.
    private struct Scanned {
        /// The scan's record of the failed build's log.
        let record: FailedBuildLog
        /// The build collector's status.
        let build: CollectorStatus?
        /// The package's build log, as its real path.
        let log: String
        /// What the recorded standard error file held after the scan; nil
        /// when none was recorded or it couldn't be read.
        let errors: String?
        /// What the recorded task log held after the scan; nil when none
        /// was recorded or it couldn't be read.
        let taskLog: String?
    }

    /// A build that runs and exits 1, its error on standard error after
    /// `-v`'s target graph, its task log holding no error, as Swift Build
    /// prints them.
    private static func brokenBuild() throws -> FakeToolchain.BuildScenario {
        var scenario = try IndexGroupHarness.emptyBuild()
        scenario.stdout = "SwiftDriver IndexCore normal arm64 com.apple.xcode.tools.swift.compiler\n"
        scenario.stderr = "info: Target dependency graph (1 targets)\n"
            + "info: Target 'IndexCore' in project 'IndexFixture' (no dependencies)\n"
            + "error: no such module 'Missing'\n"
        scenario.status = 1
        return scenario
    }

    /// The real path of the build log of the package at `root`.
    private static func logPath(of root: URL) -> String {
        BuildFixture.realPath(root) + "/.swiftstats/index-build/swiftstats-build.log"
    }

    /// Scans the small package as a snapshot asking for `tiers`, with a
    /// fake toolchain acting out `scenario` and further collector keys
    /// `extra`, after `prepare` has had the package root.
    private static func scan(
        _ scenario: FakeToolchain.BuildScenario,
        extra: String,
        tiers: RequestedTiers,
        prepare: (URL) throws -> Void
    ) throws -> Scanned {
        let toolchain = try FakeToolchain.make(build: scenario)
        defer { toolchain.remove() }
        let package = try TemporaryPackage(
            IndexGroupHarness.files.merging([
                ".swiftstats.yml": IndexGroupHarness.configuration(toolchain, extra: extra)
            ]) { $1 }
        )
        defer { package.remove() }
        try prepare(package.root)
        let record = FailedBuildLog()
        let snapshot = try IndexGroupHarness.scan(
            root: package.root,
            describer: package.describer,
            tiers: tiers,
            tools: SnapshotHarness.noTools,
            failedBuild: record
        )
        return Scanned(
            record: record,
            build: snapshot.report.collectors.first { $0.name == BuildAdapter.name },
            log: logPath(of: package.root),
            errors: record.stderr.flatMap { try? String(contentsOf: $0, encoding: .utf8) },
            taskLog: record.url.flatMap { try? String(contentsOf: $0, encoding: .utf8) }
        )
    }

    /// Writes a build log into the package at `root` now, as another scan
    /// building there would.
    private static func writeFreshLog(in root: URL) throws {
        let directory = try StoreLocation.ignoreDirectory(packageRoot: root)
            .appendingPathComponent("index-build")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let log = directory.appendingPathComponent("swiftstats-build.log")
        try Data("another scan's build output\n".utf8).write(to: log)
    }

    @Test("""
        a build whose command ran and failed records its task log, named in the line scan prints; one that ran, \
        was skipped or wasn't asked for records none
        """)
    func recordedOnlyWhenTheBuildFailed() throws {
        let failed = try Self.scan(try Self.brokenBuild(), extra: "", tiers: RequestedTiers(index: true)) { _ in
            // Nothing to prepare.
        }
        let emptyBuild = try IndexGroupHarness.emptyBuild()
        let ran = try Self.scan(emptyBuild, extra: "", tiers: RequestedTiers(index: true)) { _ in
            // Nothing to prepare.
        }
        let skipped = try Self.scan(
            try Self.brokenBuild(),
            extra: "  build:\n    enabled: false\n",
            tiers: RequestedTiers(index: true)
        ) { _ in
            // Nothing to prepare.
        }
        let unasked = try Self.scan(try Self.brokenBuild(), extra: "", tiers: .syntaxOnly) { _ in
            // Nothing to prepare.
        }

        #expect(failed.build?.state == .failed)
        #expect(failed.build?.reason == "swift build exited 1: error: no such module 'Missing'")
        let log = try #require(failed.record.url)
        #expect(BuildFixture.realPath(log) == failed.log)
        let errors = try #require(failed.record.stderr)
        #expect(errors.deletingLastPathComponent() == log.deletingLastPathComponent())
        #expect(errors.lastPathComponent == "swiftstats-build.stderr")
        // The line names the file holding the error first, then the task
        // log, which holds none.
        #expect(failed.record.line
            == "The index build's errors are in \(errors.path); its task log is in \(log.path)")
        #expect(failed.errors?.contains("error: no such module 'Missing'") == true)
        #expect(failed.taskLog?.isEmpty == false && failed.taskLog?.contains("error") == false)
        #expect(ran.build?.state == .ran)
        #expect(ran.record.url == nil && ran.record.line == nil && ran.record.stderr == nil)
        #expect(skipped.build?.state == .skipped)
        #expect(skipped.record.url == nil)
        #expect(unasked.build?.state == .skipped)
        #expect(unasked.record.url == nil)
    }

    @Test("""
        a build refused because another scan holds index.lock, or that failed describing the package, records \
        no log, though a log written during the scan is there
        """)
    func noLogWhenTheCommandDidNotRun() throws {
        var otherLock: IndexLock?
        defer { otherLock?.release() }
        let held = try Self.scan(try Self.brokenBuild(), extra: "", tiers: RequestedTiers(index: true)) { root in
            try Self.writeFreshLog(in: root)
            otherLock = try IndexLock(
                file: try StoreLocation.ignoreDirectory(packageRoot: root).appendingPathComponent("index.lock")
            )
        }
        otherLock?.release()
        otherLock = nil
        var undescribed = try Self.brokenBuild()
        undescribed.failing = ["describe"]
        let failedDescribe = try Self.scan(undescribed, extra: "", tiers: RequestedTiers(index: true)) { root in
            try Self.writeFreshLog(in: root)
        }

        #expect(held.build?.state == .failed)
        #expect(held.build?.reason == "another scan --index is running in this package")
        #expect(held.record.url == nil)
        #expect(failedDescribe.build?.state == .failed)
        #expect(failedDescribe.build?.reason?.contains("error: unable to describe") == true)
        #expect(failedDescribe.record.url == nil)
    }

    @Test("""
        a failed build's log is recorded though the scan then throws, as when its save refuses held T1 results \
        that don't describe the files, naming the failed build
        """)
    func recordedThoughTheScanThrows() throws {
        let harness = try HeldResultsHarness()
        defer { harness.remove() }
        let toolchain = try FakeToolchain.make(build: try Self.brokenBuild())
        defer { toolchain.remove() }
        try harness.storeIndex()
        let expected = try #require(try harness.plainRefusal())
        guard case let .indexNotKept(snapshot, collectedAt, reason) = expected else {
            Issue.record("expected the index refusal, got \(expected)")
            return
        }
        let configuration = harness.since.folder.appendingPathComponent("index.yml")
        try IndexGroupHarness.configuration(toolchain, extra: "")
            .write(to: configuration, atomically: true, encoding: .utf8)
        let workspace = try SnapshotWorkspace(
            packageRoot: harness.since.root,
            configurationFile: configuration,
            storeOverride: harness.since.folder.appendingPathComponent("stats.sqlite").path,
            build: SnapshotHarness.build,
            describer: TreeDescriber(name: "Mutation", targets: MappingHarness.mutationTargets),
            tools: SnapshotHarness.noTools
        )
        let record = FailedBuildLog()

        let refused = try harness.storeError {
            _ = try workspace.scanWorkingTree(
                history: .skipped("test"),
                tiers: RequestedTiers(index: true),
                failedBuild: record
            )
        }

        guard case let .indexNotKept(refusedSnapshot, refusedAt, refusedReason) = refused else {
            Issue.record("expected the index refusal, got \(String(describing: refused))")
            return
        }
        #expect(refusedSnapshot == snapshot && refusedAt == collectedAt)
        #expect(refusedReason.hasPrefix(reason + "; this scan's index build failed ("))
        #expect(toolchain.calls(of: "swift").contains { $0.hasPrefix("build\t") })
        let log = try #require(record.url)
        #expect(BuildFixture.realPath(log) == Self.logPath(of: harness.since.root))
    }
}
