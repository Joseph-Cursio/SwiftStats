import Foundation
@testable import SwiftStatsCore
import Testing

/// A SwiftMutator run an earlier scan started that still runs in the
/// leftover copy (M6, design §1.2's lifecycle), as after that scan was
/// killed with SIGKILL: it holds its lock on `<project>_mutated.lock`
/// beside the project, so a scan, or a resume, fails naming it before it
/// touches the copy, the record or the log; once the lock is free, the
/// next scan discards the earlier run as usual.
@Suite("Mutation live run")
struct MutationLiveRunTests {
    /// The process the lock file records as its holder.
    private static let holder: Int32 = 4_242

    /// The bytes of the file at `url`; nil when there is none.
    private static func bytes(_ url: URL) -> Data? {
        try? Data(contentsOf: url)
    }

    @Test("""
        a scan and a resume each fail, leaving work/, pending.json and the log as they were, while a run holds \
        SwiftMutator's lock in the copy; once it is free, the next scan discards the earlier run and runs
        """)
    func heldLock() throws {
        let harness = try MutationResumeTests.interrupted(then: try FakeMutator.recorded("full"))
        defer { harness.remove() }
        let work = harness.directory.appendingPathComponent("work")
        let lock = MutationLiveRun.lockFile(of: harness.project)
        #expect(lock.deletingLastPathComponent().path == work.path)
        try "\(Self.holder) 1\ncopy \(harness.project.path)\n".write(to: lock, atomically: true, encoding: .utf8)
        let descriptor = open(lock.path, O_RDWR | O_CLOEXEC)
        try #require(descriptor >= 0)
        defer { close(descriptor) }
        try #require(flock(descriptor, LOCK_EX | LOCK_NB) == 0)
        #expect(MutationLiveRun.holder(of: lock) == .held(process: Self.holder))
        let pending = harness.directory.appendingPathComponent("pending.json")
        let log = harness.directory.appendingPathComponent("swift-mutator.log")
        let before = (pending: Self.bytes(pending), log: Self.bytes(log))
        try #require(before.pending != nil)
        let calls = harness.fake.calls(of: "swift-mutator").count

        for request in [MutationRequest.full, .resume] {
            let run = harness.run(request)

            #expect(run.status.state == .failed)
            #expect(run.status.reason == """
                a SwiftMutator run an earlier scan started is still running in .swiftstats/mutation/work \
                (process \(Self.holder)); stop it, or wait for it to end, then scan again
                """)
            #expect(FileClone.exists(harness.project))
            #expect(Self.bytes(pending) == before.pending)
            #expect(Self.bytes(log) == before.log)
            #expect(harness.fake.calls(of: "swift-mutator").count == calls)
        }

        flock(descriptor, LOCK_UN)
        #expect(MutationLiveRun.holder(of: lock) == .free)
        let run = harness.run(.full)

        #expect(run.status.state == .ran)
        #expect(run.warnings.contains { $0.message.contains("discarding the interrupted run") })
        #expect(FileClone.exists(work) == false)
    }
}
