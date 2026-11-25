import Foundation
@testable import SwiftStatsCore
import Testing

/// The T1 build leaves the package's `Package.resolved` as it found it (M7,
/// design §1.3 step 4, §1.6): SwiftPM resolves dependencies in the package
/// root whatever the scratch path, so the session puts the file's bytes
/// back, or removes the file, when the build ends, however it ends. An
/// interrupted build is stopped as a scan's interruption stops it, with
/// the preserved file registered meanwhile so the interruption would put
/// it back.
@Suite("Build session and Package.resolved")
struct BuildLockfileTests {
    /// What the interruption saw while it held the registry.
    private struct Looked: Sendable {
        /// The slow build's process identifier.
        let pid: pid_t
        /// The policy the build was registered with.
        let policy: StopPolicy
        /// Whether `Package.resolved` was preserved for the interruption.
        let preserved: Bool
        /// Whether the build had rewritten it.
        let rewritten: Bool
        /// Whether the build had ended.
        let stopped: Bool
    }

    /// What the fake build writes over `Package.resolved`.
    private static let rewritten = "{\n  \"pins\" : [],\n  \"version\" : 3\n}\n"
    /// A committed lockfile, with bytes a rewrite would change.
    private static let committed = Data("{\r\n  \"pins\" : [ ],\r\n  \"version\" : 2\r\n}".utf8)
    /// How long the slow build may take to start waiting, and to end.
    private static let timeout: TimeInterval = 60
    /// The graces the interrupted build gets, short so the test is quick.
    private static let grace: TimeInterval = 0.2

    /// The lockfile of the package at `root`.
    private static func lockfile(of root: URL) -> URL {
        root.appendingPathComponent("Package.resolved")
    }

    /// The recorded build, writing `Package.resolved` in the package root
    /// first, then exiting with `status`.
    private static func writingScenario(status: Int32) throws -> FakeToolchain.BuildScenario {
        var scenario = try FakeToolchain.recordedBuild()
        scenario.script = "printf '%s' '\(rewritten)' > Package.resolved\n"
        scenario.status = status
        return scenario
    }

    @Test(
        "a build that writes Package.resolved leaves none when there was none, passing or failing",
        arguments: [Int32(0), 1]
    )
    func absentBefore(status: Int32) throws {
        try BuildHarness.run(try Self.writingScenario(status: status)) { outcome in
            #expect(outcome.run.status.state == (status == 0 ? .ran : .failed))
            #expect(outcome.built)
            #expect(FileClone.exists(Self.lockfile(of: outcome.realRoot)) == false)
            #expect(ScratchRegistry.shared.preservedPaths.contains(Self.lockfile(of: outcome.root)) == false)
        }
    }

    @Test(
        "a build that rewrites Package.resolved leaves its bytes as they were, passing or failing",
        arguments: [Int32(0), 1]
    )
    func presentBefore(status: Int32) throws {
        let plant = { (root: URL) in try Self.committed.write(to: Self.lockfile(of: root)) }
        try BuildHarness.run(try Self.writingScenario(status: status), prepare: plant) { outcome in
            #expect(outcome.run.status.state == (status == 0 ? .ran : .failed))
            let contents = try Data(contentsOf: Self.lockfile(of: outcome.realRoot))
            #expect(contents == Self.committed)
        }
    }

    @Test("""
        an interrupted build, stopped while Package.resolved is preserved for the interruption, ends the \
        session with the file put back and the build named as ended by its signal
        """)
    func interruption() async throws {
        var scenario = try Self.writingScenario(status: 0)
        scenario.slow = true
        let toolchain = try FakeToolchain.make(build: scenario)
        defer { toolchain.remove() }
        let package = try TemporaryPackage(BuildHarness.files)
        defer { package.remove() }
        let lockfile = Self.lockfile(of: package.root)
        try Self.committed.write(to: lockfile)

        let running = ThreadRun { BuildAdapter.run(swift: toolchain.proxy, root: package.root, files: []) { $0 } }
        defer { running.wait(within: Self.timeout) }
        defer {
            if running.isFinished == false, let pid = toolchain.waitingBuild(within: 0), killpg(pid, SIGKILL) != 0 {
                kill(pid, SIGKILL)
            }
        }
        let seen = await ThreadRun { () -> Looked? in
            guard let pid = toolchain.waitingBuild(within: Self.timeout),
                  let registered = ScratchRegistry.shared.registeredProcesses.first(where: { entry in
                      entry.process.processIdentifier == pid
                  }) else {
                return nil
            }
            // Read before the interruption: the registry's accessors take
            // the lock `interrupting` holds.
            let preserved = ScratchRegistry.shared.preservedPaths.contains(lockfile)
            let policy = StopPolicy(firstSignal: SIGINT, grace: Self.grace, killGrace: Self.grace)
            let stopping = ScratchRegistry.Registered(process: registered.process, policy: policy, afterStop: nil)
            return ScratchRegistry.shared.interrupting([stopping]) {
                Looked(
                    pid: pid,
                    policy: registered.policy,
                    preserved: preserved,
                    rewritten: (try? Data(contentsOf: lockfile)) == Data(Self.rewritten.utf8),
                    stopped: registered.process.isRunning == false
                )
            }
        }.value
        let looked = try #require(seen, "the slow build never waited to be stopped")
        #expect(looked.policy == .standard)
        #expect(looked.preserved && looked.rewritten && looked.stopped)

        let run = await running.value
        #expect(run.status.state == .failed)
        #expect(run.status.reason == "swift build ended by SIGINT")
        #expect(try Data(contentsOf: lockfile) == Self.committed)
        #expect(ScratchRegistry.shared.preservedPaths.contains(lockfile) == false)
        let left = ScratchRegistry.shared.registeredProcesses.map(\.process.processIdentifier)
        #expect(left.contains(looked.pid) == false)
    }
}
