import Foundation
@testable import SwiftStatsCore
import Testing

/// The record of a SwiftMutator run a resume can continue (M6, design
/// §1.5 and §1.7), `pending.json`: written before SwiftMutator starts, so
/// an interrupted scan leaves it; naming the results file of a run that
/// failed with a readable header; removed after any other run; discarded,
/// with a warning, by a run that isn't its resume.
@Suite("Mutation pending run")
struct PendingMutationRunTests {
    /// The scenario of a run that failed leaving no results file: another
    /// SwiftMutator run held its lock.
    static func locked() throws -> FakeMutator.Scenario {
        var scenario = try FakeMutator.recorded("full")
        scenario.results = nil
        scenario.report = nil
        scenario.status = MutationExit.lockedStatus
        return scenario
    }

    @Test("""
        pending.json is written before SwiftMutator starts, without its results file, which an interrupted scan \
        never learns; once an interrupted run is judged, the record names the file, relative to work/
        """)
    func writtenBeforeTheRun() throws {
        let harness = try MutationRunHarness(try FakeMutator.recorded("interrupted"))
        defer { harness.remove() }

        let run = harness.run()

        let text = try #require(harness.fake.pendingAtRun)
        let atRun = try JSONDecoder().decode(PendingMutationRun.self, from: Data(text.utf8))
        let name = harness.package.root.lastPathComponent
        let configuration = harness.directory.appendingPathComponent("muter.conf.yml")
        #expect(run.status.reason == "interrupted by SIGTERM; scan --mutation --resume continues it")
        #expect(text.contains("resultsFile") == false)
        #expect(atRun.resultsFile == nil)
        #expect(atRun.mode == .full)
        #expect(atRun.base == nil)
        #expect(atRun.commit == nil && atRun.dirtyHash == nil && atRun.packagePath.isEmpty)
        #expect(atRun.project == name)
        #expect(atRun.copyFixed == 0)
        #expect(atRun.command == ["run", "-c", configuration.standardizedFileURL.path, "--skip-update-check"])
        #expect(atRun.settings == PendingMutationRun.Settings(
            mutator: harness.fake.mutator,
            swift: harness.fake.swift,
            settings: CollectorSettings(enabled: true, path: harness.fake.mutator.path)
        ))
        #expect((try? Date(atRun.startedAt, strategy: PendingMutationRun.dateFormat)) != nil)
        #expect(harness.pending == atRun.naming(resultsFile: "\(name)_muter_logs/\(FakeMutator.folder)/results.jsonl"))
        #expect(FileClone.exists(harness.project))
    }

    @Test(
        """
        a run that stopped before its first mutant, one that finished and one that failed without a results file \
        leave no pending.json, though each had one while SwiftMutator ran, and leave no copy
        """,
        arguments: ["stopped", "full", "locked"]
    )
    func removedAfterTheRun(scenario name: String) throws {
        let scenario = name == "locked" ? try Self.locked() : try FakeMutator.recorded(name)
        let harness = try MutationRunHarness(scenario)
        defer { harness.remove() }

        let run = harness.run()

        #expect(run.status.state == (name == "full" ? .ran : .failed))
        #expect(harness.fake.pendingAtRun != nil)
        #expect(FileClone.exists(harness.directory.appendingPathComponent("pending.json")) == false)
        #expect(FileClone.exists(harness.directory.appendingPathComponent("work")) == false)
    }

    @Test("""
        a run discards a pending run it finds, saying when it started, and recovers its copy's build into \
        build-cache before making its own copy
        """)
    func discarded() throws {
        let harness = try MutationRunHarness(try FakeMutator.recorded("interrupted"))
        defer { harness.remove() }
        _ = harness.run()
        let started = try #require(harness.pending).startedAt
        try harness.fake.act(try FakeMutator.recorded("full"))

        let run = harness.run()

        let builds = try String(
            contentsOf: harness.directory.appendingPathComponent("build-cache/builds.txt"),
            encoding: .utf8
        )
        #expect(run.status.state == .ran)
        #expect(run.warnings.map(\.message) == ["swiftmutator: discarding the interrupted run of \(started)"])
        #expect(harness.fake.pendingAtRun != nil)
        #expect(harness.pending == nil)
        #expect(builds == "built\nbuilt\n")
        #expect(FileClone.exists(harness.directory.appendingPathComponent("work")) == false)
    }

    @Test("a pending.json that doesn't read refuses a resume, and a run discards it with a warning")
    func unreadable() throws {
        let harness = try MutationRunHarness(try FakeMutator.recorded("full"))
        defer { harness.remove() }
        let pending = harness.directory.appendingPathComponent("pending.json")
        try FileManager.default.createDirectory(at: harness.directory, withIntermediateDirectories: true)
        try "{\"startedAt\":".write(to: pending, atomically: true, encoding: .utf8)

        let resume = harness.run(.resume)
        let run = harness.run()

        #expect(resume.status.state == .failed)
        #expect(resume.status.reason == "pending.json doesn't read; run scan --mutation")
        #expect(harness.fake.calls(of: "swift-mutator").count == 2)
        #expect(run.status.state == .ran)
        #expect(run.warnings.map(\.message) == [
            "swiftmutator: discarding the interrupted run whose pending.json doesn't read"
        ])
        #expect(FileClone.exists(pending) == false)
    }
}
