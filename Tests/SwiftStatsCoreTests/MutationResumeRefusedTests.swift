import Foundation
@testable import SwiftStatsCore
import Testing

/// When `scan --mutation --resume` of a full run is refused (M6, design
/// §1.7), through the fake tools acting out the Mutation fixture's
/// interrupted run: by `scan` before anything is scanned, run or stored
/// when no run is pending, when a setting, the tree or the files left out
/// of it changed since the run started, or when nothing is left to
/// continue; and by the mutation step, before it runs anything or touches
/// the copy or the record, when a file its scan parsed changed, which the
/// git state can't see outside git.
@Suite("Mutation resume refused")
struct MutationResumeRefusedTests {
    /// The refusal of a scan for `reason`.
    static func refused(_ reason: String) -> ScanError {
        ScanError.mutationRefused(reason)
    }

    @Test("""
        a resume of a package whose scanned file was edited since the run started is refused outside git, where \
        the git state can't see it: by scan before anything is scanned, and by the mutation step before it runs \
        anything or touches the copy or the record, so the copy keeps the run's bytes and the run stays resumable
        """)
    func refusedForAnEditedFile() throws {
        let harness = try MutationResumeTests.interrupted(then: try FakeMutator.resuming())
        defer { harness.remove() }
        let pending = try #require(harness.pending)
        let edited = "public func one() -> Int { 2 }\n"
        let path = MutationRunHarness.sourcePath
        try edited.write(to: harness.package.root.appendingPathComponent(path), atomically: true, encoding: .utf8)

        #expect(throws: Self.refused(PendingMutationRun.treeChangedReason)) {
            try MutationResumeTests.resume(harness)
        }
        let run = harness.run(.resume, scanned: [path: ContentHash.sha256(Data(edited.utf8))])

        let copied = try String(contentsOf: harness.project.appendingPathComponent(path), encoding: .utf8)
        #expect(run.status.state == .failed)
        #expect(run.status.reason == PendingMutationRun.treeChangedReason)
        #expect(harness.fake.calls(of: "swift-mutator").count == 1)
        #expect(harness.pending == pending)
        #expect(copied == MutationRunHarness.source)
    }

    @Test("""
        scan --mutation --resume is refused, saying why, when the pending run left other files out of the tree, \
        as scan --mutation --no-store does with a store kept in the package
        """)
    func refusedAfterNoStore() throws {
        let harness = try MutationRunHarness(try FakeMutator.recorded("interrupted"))
        defer { harness.remove() }
        _ = try harness.scan(.full)
        try harness.fake.act(try FakeMutator.resuming())
        let workspace = try SnapshotWorkspace(
            packageRoot: harness.package.root,
            configurationFile: nil,
            storeOverride: harness.package.root.appendingPathComponent("stats.sqlite").path,
            build: SnapshotHarness.build,
            describer: harness.package.describer,
            tools: SnapshotHarness.noTools
        )

        #expect(harness.pending?.ignoring.isEmpty == true)
        #expect(throws: Self.refused(PendingMutationRun.ignoringChangedReason)) {
            try workspace.scanWorkingTree(history: .skipped("test"), tiers: RequestedTiers(mutation: .resume))
        }
        #expect(harness.fake.calls(of: "swift-mutator").count == 1)
    }

    @Test("""
        scan --mutation --resume is refused before anything is scanned, run or stored when no run is pending, \
        and when a setting or the tree has changed since it started
        """)
    func refusedForChanges() throws {
        let harness = try MutationRunHarness(try FakeMutator.recorded("interrupted"))
        defer { harness.remove() }

        #expect(throws: Self.refused("no interrupted or failed SwiftMutator run to resume")) {
            try MutationResumeTests.resume(harness)
        }
        _ = harness.run()
        let pending = try #require(harness.pending)
        let yaml = harness.package.root.appendingPathComponent(".swiftstats.yml")
        let configuration = try String(contentsOf: yaml, encoding: .utf8)
        try (configuration + "    options:\n      workers: 3\n").write(to: yaml, atomically: true, encoding: .utf8)
        #expect(throws: Self.refused(
            "the settings have changed since that run started (collectors.swiftmutator.options.workers); "
                + "run scan --mutation"
        )) {
            try MutationResumeTests.resume(harness)
        }
        try configuration.write(to: yaml, atomically: true, encoding: .utf8)
        try PendingMutationRun(
            startedAt: pending.startedAt,
            commit: "0123456789abcdef0123456789abcdef01234567",
            dirtyHash: nil,
            packagePath: "",
            mode: .full,
            base: nil,
            resultsFile: pending.resultsFile,
            project: pending.project,
            command: pending.command,
            settings: pending.settings,
            copyFixed: 0,
            ignoring: pending.ignoring,
            scanned: pending.scanned
        )
        .write(in: MutationDirectory(lookingIn: harness.package.root))
        #expect(throws: Self.refused("the tree has changed since that run started; run scan --mutation")) {
            try MutationResumeTests.resume(harness)
        }

        #expect(harness.fake.calls(of: "swift-mutator").count == 1)
        let store = try MutationResumeTests.workspace(harness).store
        #expect(try store.latestSnapshotID(package: "Probe", packagePath: "") == nil)
    }

    @Test("""
        scan --mutation --resume is refused before anything is scanned, run or stored when the pending run left \
        only a stopped line, which a resume can't continue, and when its copy is gone
        """)
    func refusedForWhatIsLeft() throws {
        let harness = try MutationRunHarness(try FakeMutator.recorded("interrupted"))
        defer { harness.remove() }
        _ = harness.run()
        try MutationResumeTests.forgetResultsFile(harness)
        let file = MutationResumeTests.resultsFile(harness)
        let stopped = try #require(try FakeMutator.recorded("stopped").results)
        try FileClone.write(Data(stopped.utf8), to: file)

        #expect(throws: Self.refused("that run left no results a resume can continue; run scan --mutation")) {
            try MutationResumeTests.resume(harness)
        }
        try FileClone.remove(harness.directory.appendingPathComponent("work"))
        #expect(throws: Self.refused("the copy of that run is gone; run scan --mutation")) {
            try MutationResumeTests.resume(harness)
        }

        #expect(harness.fake.calls(of: "swift-mutator").count == 1)
        let store = try MutationResumeTests.workspace(harness).store
        #expect(try store.latestSnapshotID(package: "Probe", packagePath: "") == nil)
    }
}
