import Foundation
@testable import SwiftStatsCore
import Testing

/// `scan --mutation --resume` of a full run (M6, design §1.4 and §1.7),
/// through the fake tools acting out the Mutation fixture's interrupted
/// run and its resume: the resume continues the pending run's file in its
/// kept copy, whether the record names the file or the interrupted scan
/// left it to be found; a resume that stops before its first mutant is
/// read from its own run folder and keeps the run resumable, saying so
/// unless SwiftMutator refused it; and a resume through `scan` is stored
/// as ran. `MutationResumeRefusedTests` holds the refusals.
@Suite("Mutation resume")
struct MutationResumeTests {
    /// The results file of the run the harness's package left, relative to
    /// the copy's folder.
    static func resultsPath(_ harness: MutationRunHarness) -> String {
        "\(harness.package.root.lastPathComponent)_muter_logs/\(FakeMutator.folder)/results.jsonl"
    }

    /// That results file.
    static func resultsFile(_ harness: MutationRunHarness) -> URL {
        harness.directory.appendingPathComponent("work").appendingPathComponent(resultsPath(harness))
    }

    /// A harness whose package holds the copy and record of an interrupted
    /// run, its tools then acting out `scenario`.
    static func interrupted(then scenario: FakeMutator.Scenario) throws -> MutationRunHarness {
        let harness = try MutationRunHarness(try FakeMutator.recorded("interrupted"))
        _ = harness.run()
        try harness.fake.act(scenario)
        return harness
    }

    /// Removes `resultsFile` from the harness's `pending.json`, as a scan
    /// interrupted before it judged its run leaves it.
    static func forgetResultsFile(_ harness: MutationRunHarness) throws {
        let url = harness.directory.appendingPathComponent("pending.json")
        var record = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        record["resultsFile"] = nil
        try JSONSerialization.data(withJSONObject: record).write(to: url)
    }

    /// A workspace storing the harness package's snapshots, with no tools
    /// on PATH.
    static func workspace(_ harness: MutationRunHarness) throws -> SnapshotWorkspace {
        try SnapshotWorkspace(
            packageRoot: harness.package.root,
            configurationFile: nil,
            storeOverride: nil,
            build: SnapshotHarness.build,
            describer: harness.package.describer,
            tools: SnapshotHarness.noTools
        )
    }

    /// `scan --mutation --resume` of the harness's package, storing the
    /// snapshot.
    @discardableResult
    static func resume(_ harness: MutationRunHarness) throws -> (snapshot: ScannedSnapshot, id: Int64) {
        try workspace(harness).scanWorkingTree(history: .skipped("test"), tiers: RequestedTiers(mutation: .resume))
    }

    @Test(
        """
        a resume continues the pending run in its kept copy, running the run's command with --resume and its \
        results file, whether the record names it or it is found in the log folder; it builds nothing, keeps both \
        sessions' results in runs/<id>/, and ends the copy and the record, which names the file before \
        SwiftMutator starts, so an interrupted resume leaves it named
        """,
        arguments: [true, false]
    )
    func resumed(named: Bool) throws {
        let harness = try Self.interrupted(then: try FakeMutator.resuming())
        defer { harness.remove() }
        if named == false {
            try Self.forgetResultsFile(harness)
        }

        let run = harness.run(.resume)

        let calls = harness.fake.calls(of: "swift-mutator")
        let resume = try #require(calls.dropFirst().first)
        let configuration = harness.directory.appendingPathComponent("muter.conf.yml").standardizedFileURL.path
        let suffix = "/.swiftstats/mutation/work/" + Self.resultsPath(harness)
        let file = try #require(resume.last)
        let results = try #require(run.results)
        #expect(run.status.state == .ran)
        #expect(results.sessions == 2)
        #expect(results.tested == 35)
        #expect(results.complete)
        #expect(calls.count == 3)
        #expect(calls.first?.first == "run" && calls.last?.first == "report")
        #expect(Array(resume.dropLast()) == ["run", "-c", configuration, "--skip-update-check", "--resume"])
        #expect(file.hasSuffix(suffix))
        #expect(MutationRunHarness.realPath(URL(fileURLWithPath: String(file.dropLast(suffix.count))))
            == MutationRunHarness.realPath(harness.package.root))
        #expect(harness.fake.facts("cwd", of: "swift-mutator").dropFirst().first == harness.realProject)
        #expect(harness.fake.calls(of: "swift").count == 1)
        let atRun = try JSONDecoder().decode(
            PendingMutationRun.self,
            from: Data(try #require(harness.fake.pendingAtRun).utf8)
        )
        #expect(atRun.resultsFile == Self.resultsPath(harness))
        let kept = try #require(run.resultsFile)
        #expect(kept.hasPrefix(".swiftstats/mutation/runs/") && kept.hasSuffix("/results.jsonl"))
        #expect(FileClone.exists(harness.package.root.appendingPathComponent(kept)))
        #expect(harness.pending == nil)
        #expect(FileClone.exists(harness.directory.appendingPathComponent("work")) == false)
        let builds = try String(
            contentsOf: harness.directory.appendingPathComponent("build-cache/builds.txt"),
            encoding: .utf8
        )
        #expect(builds == "built\n")
    }

    @Test("""
        a resume whose new run folder holds a stopped line reads it: failed with the stop's reason and the resume \
        hint, keeping the pending run, its copy and the file it continued as they were
        """)
    func stoppedResume() throws {
        let harness = try Self.interrupted(then: try FakeMutator.recorded("stopped"))
        defer { harness.remove() }
        let pending = try #require(harness.pending)
        let file = Self.resultsFile(harness)
        let before = try Data(contentsOf: file)

        let run = harness.run(.resume)

        let stopped = harness.project.deletingLastPathComponent()
            .appendingPathComponent("\(harness.package.root.lastPathComponent)_muter_logs")
            .appendingPathComponent(FakeMutator.resumeFolder)
            .appendingPathComponent("results.jsonl")
        #expect(FileClone.exists(stopped))
        #expect(run.status.state == .failed)
        #expect(run.status.reason == "the baseline failed (baselineTestFailed); failing: alwaysFails(); "
            + "SwiftMutator needs passing tests; collectors.swiftmutator.arguments can --skip them; "
            + "scan --mutation --resume continues it")
        #expect(run.results == nil)
        #expect(run.resultsFile == nil)
        #expect(harness.pending == pending)
        #expect(FileClone.exists(harness.project))
        #expect(try Data(contentsOf: file) == before)
    }

    @Test("""
        a resume that is interrupted again keeps the pending run and its copy, the record naming the file it \
        continued
        """)
    func interruptedResume() throws {
        var scenario = try FakeMutator.resuming()
        scenario.signal = SIGTERM
        let harness = try Self.interrupted(then: scenario)
        defer { harness.remove() }
        try Self.forgetResultsFile(harness)

        let run = harness.run(.resume)

        #expect(run.status.state == .failed)
        #expect(run.status.reason == "interrupted by SIGTERM; scan --mutation --resume continues it")
        #expect(harness.pending?.resultsFile == Self.resultsPath(harness))
        #expect(FileClone.exists(harness.project))
    }

    @Test("""
        a resume signalled before its first mutant, which leaves only a stopped line in its own run folder, says \
        it can still be resumed, keeping the pending run, its copy and the file it continued
        """)
    func signalledBeforeItsFirstMutant() throws {
        var scenario = try FakeMutator.recorded("stopped")
        scenario.signal = SIGTERM
        let harness = try Self.interrupted(then: scenario)
        defer { harness.remove() }
        let pending = try #require(harness.pending)
        let file = Self.resultsFile(harness)
        let before = try Data(contentsOf: file)

        let run = harness.run(.resume)

        #expect(run.status.state == .failed)
        #expect(run.status.reason == "interrupted by SIGTERM; scan --mutation --resume continues it")
        #expect(harness.pending == pending)
        #expect(FileClone.exists(harness.project))
        #expect(try Data(contentsOf: file) == before)
    }

    @Test("""
        a resume SwiftMutator refuses (exit 5) keeps the pending run and its copy as they were, without saying a \
        resume continues it
        """)
    func refusedByTheMutator() throws {
        let harness = try Self.interrupted(
            then: FakeMutator.Scenario(errorText: "Refusing to resume: the project changed\n", status: 5)
        )
        defer { harness.remove() }
        let pending = try #require(harness.pending)

        let run = harness.run(.resume)

        let reason = try #require(run.status.reason)
        #expect(run.status.state == .failed)
        #expect(reason.hasPrefix("swift-mutator exited 5"))
        #expect(reason.hasSuffix(MutationExit.resumeHint) == false)
        #expect(harness.pending == pending)
        #expect(FileClone.exists(harness.project))
    }

    @Test("""
        scan --mutation --resume continues the run an interrupted scan --mutation left and stores it as ran, with \
        both sessions' results
        """)
    func resumedThroughTheStore() throws {
        let harness = try MutationRunHarness(try FakeMutator.recorded("interrupted"))
        defer { harness.remove() }
        let workspace = try Self.workspace(harness)
        let mutation = { (snapshot: ScannedSnapshot) in
            snapshot.info.collectors.first { $0.name == MutationAdapter.name }
        }

        let interrupted = try workspace.scanWorkingTree(
            history: .skipped("test"),
            tiers: RequestedTiers(mutation: .full)
        )
        try harness.fake.act(try FakeMutator.resuming())
        let resumed = try Self.resume(harness)

        #expect(mutation(interrupted.snapshot)?.state == .failed)
        #expect(mutation(resumed.snapshot)?.state == .ran)
        #expect(mutation(resumed.snapshot)?.identity == "sha256:\(MutationRunTests.recordedBuild)")
        #expect(try workspace.store.info(id: resumed.id).collectors.first { $0.name == MutationAdapter.name }?.state
            == .ran)
        #expect(harness.pending == nil)
        #expect(FileClone.exists(harness.directory.appendingPathComponent("work")) == false)
        #expect(harness.fake.calls(of: "swift-mutator").map(\.first) == ["run", "run", "report"])
    }
}
