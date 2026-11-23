import Foundation
@testable import SwiftStatsCore
import Testing

/// An interrupted SwiftMutator run (M6, design §1.5 and §1.6): the run is
/// registered under SwiftMutator's stop policy, so an interruption sends
/// it SIGTERM and never SIGINT; SwiftMutator then writes its end line and
/// ends by raising the signal again, or by its fallback exit 143, and
/// either way the collector fails with the resume hint and keeps the copy.
@Suite("Mutation interrupts")
struct MutationInterruptTests {
    /// How long the fake run may take to start waiting, and to end.
    private static let timeout: TimeInterval = 60

    @Test(
        """
        an interrupted run is stopped by SIGTERM alone, writes its end line and reads as interrupted, failed with \
        the resume hint and the copy kept, whether it raises the signal again or exits 143
        """,
        arguments: [FakeMutator.Interrupt.raising, .exiting143]
    )
    func interrupted(ending: FakeMutator.Interrupt) async throws {
        let harness = try MutationRunHarness(try FakeMutator.interruptible(ending))
        defer { harness.remove() }
        let fake = harness.fake
        let running = Task.detached { harness.run() }

        let pid = try #require(fake.waitingRun(within: Self.timeout))
        defer { kill(pid, SIGKILL) }
        let registered = try #require(ScratchRegistry.shared.registered(pid))
        #expect(registered.policy == .swiftMutator)
        let start = Date()
        ScratchRegistry.stop([registered])
        let elapsed = Date().timeIntervalSince(start)
        let run = await running.value

        #expect(elapsed < Self.timeout)
        #expect(fake.signalsHeard == ["TERM"])
        #expect(run.status.state == .failed)
        #expect(run.status.reason == "interrupted by SIGTERM; scan --mutation --resume continues it")
        #expect(run.results == nil)
        #expect(FileClone.exists(harness.project))
        let logFolder = harness.project.deletingLastPathComponent()
            .appendingPathComponent(harness.project.lastPathComponent + "_muter_logs")
        let file = logFolder.appendingPathComponent(FakeMutator.folder).appendingPathComponent("results.jsonl")
        guard case .results(let results) = try MutationResultsFile.read(try Data(contentsOf: file)) else {
            Issue.record("the kept results file holds no results")
            return
        }
        #expect(results.end?.reason == "interrupted")
        #expect(results.tested == 8)
        let log = try String(contentsOf: harness.directory.appendingPathComponent("swift-mutator.log"), encoding: .utf8)
        let ended = ending == .raising ? "ended by SIGTERM" : "exited 143"
        #expect(log.contains("=== swiftstats: swift-mutator run \(ended) after "))
    }
}
