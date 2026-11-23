import Foundation
@testable import SwiftStatsCore
import Testing

/// An interrupted SwiftMutator run (M6, design §1.5 and §1.6): the run is
/// registered under SwiftMutator's stop policy, so an interruption sends
/// it SIGTERM and never SIGINT; SwiftMutator then writes its end line and
/// ends by raising the signal again, or by its fallback exit 143, and
/// either way the collector fails with the resume hint and keeps the copy.
/// The run goes on a thread of its own (`ThreadRun`), and so does the
/// stop: waiting for the run to wait, finding it in the registry and
/// stopping it happen on one thread with no `await` between, never on the
/// cooperative pool the other tests queue on, so a busy suite can't hold
/// the test back between seeing the run wait and stopping it.
@Suite("Mutation interrupts")
struct MutationInterruptTests {
    /// What the stopping thread saw.
    private struct Stopped: Sendable {
        /// The stop policy the run was registered under; nil when the
        /// registry didn't hold it.
        let policy: StopPolicy?
        /// How long the stop took, in seconds.
        let elapsed: TimeInterval
    }

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
        let running = ThreadRun { harness.run() }
        defer { running.wait(within: Self.timeout) }

        // Only while the run hasn't returned: once it has, the process is
        // reaped and its identifier free for another. To its group, which
        // Foundation makes it lead, so its long sleep ends with it.
        defer {
            if running.isFinished == false, let pid = fake.runIdentifier, killpg(pid, SIGKILL) != 0 {
                kill(pid, SIGKILL)
            }
        }
        let stopped = await ThreadRun { () -> Stopped? in
            guard let pid = fake.waitingRun(within: Self.timeout) else {
                return nil
            }
            let registered = ScratchRegistry.shared.registeredProcesses.first { $0.process.processIdentifier == pid }
            let start = Date()
            if let registered {
                ScratchRegistry.stop([registered])
            }
            return Stopped(policy: registered?.policy, elapsed: Date().timeIntervalSince(start))
        }.value
        let stop = try #require(stopped, "the fake run never waited to be stopped")
        #expect(stop.policy == .swiftMutator)
        let run = await running.value

        #expect(stop.elapsed < Self.timeout)
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
