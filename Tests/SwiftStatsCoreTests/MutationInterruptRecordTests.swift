import Foundation
@testable import SwiftStatsCore
import Testing

/// What an interrupted scan leaves of `pending.json` (M6, design §1.7, as
/// built): the scan ends by the signal once SwiftMutator has stopped, so
/// the step never records how the run ended; the interruption itself names
/// the run's results file, or removes the record when no file has a
/// readable header. The fake run is stopped as `MutationInterruptTests`
/// stops it, but with the registry's lock held, as an interrupted scan
/// holds it until it ends, so the step stays waiting and the record is
/// seen as the scan would leave it.
@Suite("Mutation interrupt record")
struct MutationInterruptRecordTests {
    /// How long the fake run may take to start waiting, and to end.
    private static let timeout: TimeInterval = 60
    /// A run folder older than the fake's, which a resume must not take.
    private static let otherFolder = "Nov 21, 2026 at 7:31 AM"

    /// Runs the harness's interruptible scenario, interrupts the run as a
    /// scan's interruption does, and returns `pending.json`'s bytes as the
    /// interrupted scan leaves them (nil when it leaves none), once the
    /// step, which goes on in a test, has ended.
    private static func interrupt(_ harness: MutationRunHarness) async throws -> Data? {
        let fake = harness.fake
        let pending = harness.directory.appendingPathComponent("pending.json")
        let running = ThreadRun { harness.run() }
        defer { running.wait(within: timeout) }
        defer {
            if running.isFinished == false, let pid = fake.runIdentifier, killpg(pid, SIGKILL) != 0 {
                kill(pid, SIGKILL)
            }
        }
        let seen = await ThreadRun { () -> Data?? in
            guard let pid = fake.waitingRun(within: timeout),
                  let registered = ScratchRegistry.shared.registeredProcesses.first(where: { entry in
                      entry.process.processIdentifier == pid
                  }) else {
                return nil
            }
            let left: Data? = ScratchRegistry.shared.interrupting([registered]) {
                FileClone.exists(pending) ? try? Data(contentsOf: pending) : nil
            }
            return .some(left)
        }.value
        let left = try #require(seen, "the fake run never waited to be stopped")
        _ = await running.value
        return left
    }

    @Test("""
        an interruption names the run's results file in pending.json before the scan ends, and a resume \
        continues that file though the log folder then holds another run folder with a results file
        """)
    func namesTheResultsFile() async throws {
        let harness = try MutationRunHarness(try FakeMutator.interruptible(.raising))
        defer { harness.remove() }

        let left = try #require(try await Self.interrupt(harness), "the interruption left no pending.json")
        let record = try JSONDecoder().decode(PendingMutationRun.self, from: left)
        #expect(record.resultsFile == MutationResumeTests.resultsPath(harness))

        // As the interrupted scan left it: the step went on here, as it
        // can't once the scan has ended.
        try left.write(to: harness.directory.appendingPathComponent("pending.json"))
        let named = MutationResumeTests.resultsFile(harness)
        let other = named
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(Self.otherFolder)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: named, to: other.appendingPathComponent("results.jsonl"))
        try harness.fake.act(try FakeMutator.resuming())

        let run = harness.run(.resume)

        #expect(run.status.state == .ran)
        #expect(run.results?.sessions == 2)
        let resume = try #require(harness.fake.calls(of: "swift-mutator").dropFirst().first)
        #expect(resume.last?.hasSuffix("/work/" + MutationResumeTests.resultsPath(harness)) == true)
    }

    @Test("an interruption before the run's results file has a readable header removes pending.json")
    func removesTheRecordWithoutAHeader() async throws {
        var scenario = try FakeMutator.interruptible(.raising)
        scenario.results = ""
        let harness = try MutationRunHarness(scenario)
        defer { harness.remove() }

        let left = try await Self.interrupt(harness)

        #expect(left == nil)
    }
}
