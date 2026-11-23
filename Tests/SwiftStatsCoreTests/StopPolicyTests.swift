import Foundation
@testable import SwiftStatsCore
import Testing

/// How an interrupted command stops the processes it started (M6, design
/// §1.6): each by its own `StopPolicy`, SwiftMutator by SIGTERM, a long
/// grace and SIGKILL with no SIGINT, every other tool by M5's SIGINT
/// first, and all of them at once. The tests use graces of a fraction of
/// a second in place of the real ones.
@Suite("Stop policy")
struct StopPolicyTests {
    /// A shell that logs each SIGINT and SIGTERM it hears to the returned
    /// file and goes on, or ends on SIGTERM when `endsOnTerm`, after
    /// writing a file saying its traps are set. When `wrapped`, the
    /// process is a wrapper shell that runs the listening shell in the
    /// foreground, in the wrapper's process group, and forwards no signal.
    private struct Listener {
        /// The process, not yet started.
        let process: Process
        /// The signals the listening shell heard, one a line.
        let heard: URL
        /// The file it writes once its traps are set.
        let ready: URL
        /// The file holding the listening shell's process identifier.
        let pidFile: URL

        /// The signals it heard, in order.
        var signals: [String] {
            ((try? String(contentsOf: heard, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init)
        }

        /// The listening shell's process identifier, once it is ready.
        var listenerPID: pid_t? {
            ((try? String(contentsOf: pidFile, encoding: .utf8)) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .split(separator: "\n").first.flatMap { pid_t(String($0)) }
        }

        /// A listener writing its files as `name` in `directory`.
        init(_ name: String, in directory: URL, endsOnTerm: Bool, wrapped: Bool = false) throws {
            heard = directory.appendingPathComponent("\(name).signals")
            ready = directory.appendingPathComponent("\(name).ready")
            pidFile = directory.appendingPathComponent("\(name).pid")
            let onTerm = endsOnTerm ? "exit 0" : ":"
            let script = """
                echo $$ > "\(pidFile.path)"
                trap 'echo INT >> "\(heard.path)"' INT
                trap 'echo TERM >> "\(heard.path)"; \(onTerm)' TERM
                : > "\(ready.path)"
                while :; do /bin/sleep 0.05; done
                """
            process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            if wrapped {
                let scriptFile = directory.appendingPathComponent("\(name).sh")
                try script.write(to: scriptFile, atomically: true, encoding: .utf8)
                // The wrapper catches both signals, so it neither ends on
                // them nor passes them on, and runs a command after the
                // listener, so it doesn't exec it.
                process.arguments = ["-c", "trap : INT TERM; /bin/sh '\(scriptFile.path)'; :"]
            } else {
                process.arguments = ["-c", script]
            }
        }

        /// Kills the process, and a wrapped listening shell, if they still
        /// run.
        func kill() {
            if process.isRunning {
                Darwin.kill(process.processIdentifier, SIGKILL)
            }
            if let listenerPID, listenerPID != process.processIdentifier {
                Darwin.kill(listenerPID, SIGKILL)
            }
        }
    }

    /// A test's short grace.
    private static let shortGrace: TimeInterval = 0.2
    /// How long a test waits for a process to get ready or to end.
    private static let timeout: TimeInterval = 15
    /// How often to look, in microseconds.
    private static let pollInterval: useconds_t = 20_000

    /// Waits until `condition` holds or `timeout` passes; whether it held.
    private static func wait(until condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while condition() == false {
            guard Date() < deadline else {
                return false
            }
            usleep(pollInterval)
        }
        return true
    }

    /// Starts each of `listeners` in `registry` by its policy and waits
    /// until each has set its traps.
    private static func start(_ listeners: [(Listener, StopPolicy)], in registry: ScratchRegistry) throws {
        for (listener, policy) in listeners {
            try registry.start(listener.process, stop: policy)
        }
        for (listener, _) in listeners {
            try #require(wait { FileManager.default.fileExists(atPath: listener.ready.path) })
        }
    }

    @Test("the standard policy is M5's SIGINT, 2 s, SIGTERM, 0.5 s; SwiftMutator's is SIGTERM, 35 s, then SIGKILL")
    func policies() {
        #expect(StopPolicy.standard == StopPolicy(firstSignal: SIGINT, grace: 2, killGrace: 0.5))
        #expect(StopPolicy.standard.terminates && StopPolicy.standard.killAfter == 2.5)
        #expect(StopPolicy.swiftMutator.firstSignal == SIGTERM && StopPolicy.swiftMutator.grace == 35)
        #expect(StopPolicy.swiftMutator.terminates == false && StopPolicy.swiftMutator.killAfter == 35)
    }

    @Test("a process registered without a policy, as coverage's are, gets the standard one")
    func standardByDefault() throws {
        let registry = ScratchRegistry()
        let sleeper = Process()
        sleeper.executableURL = URL(fileURLWithPath: "/bin/sleep")
        sleeper.arguments = ["30"]
        try registry.start(sleeper)
        defer { kill(sleeper.processIdentifier, SIGKILL) }

        let registered = registry.registeredProcesses
        #expect(registered.map(\.process.processIdentifier) == [sleeper.processIdentifier])
        #expect(registered.first?.policy == .standard)
    }

    @Test("a process that ignores SIGTERM under a SIGTERM-first policy is SIGKILLed after the grace, with no SIGINT")
    func stubbornKilled() throws {
        let directory = try SnapshotHarness.temporaryDirectory("StopPolicy")
        defer { try? FileManager.default.removeItem(at: directory) }
        let registry = ScratchRegistry()
        let listener = try Listener("stubborn", in: directory, endsOnTerm: false)
        let unused: TimeInterval = 5
        let policy = StopPolicy(firstSignal: SIGTERM, grace: Self.shortGrace, killGrace: unused)
        try Self.start([(listener, policy)], in: registry)
        defer { listener.kill() }

        let start = Date()
        registry.cleanUp()
        let elapsed = Date().timeIntervalSince(start)

        try #require(Self.wait { listener.process.isRunning == false })
        #expect(listener.process.terminationReason == .uncaughtSignal)
        #expect(listener.process.terminationStatus == SIGKILL)
        #expect(Self.wait { listener.signals == ["TERM"] })
        // The kill grace isn't waited after a first SIGTERM.
        #expect(elapsed >= Self.shortGrace && elapsed < unused)
    }

    @Test("a process that exits on SIGTERM under a SIGTERM-first policy never gets SIGINT and isn't waited for")
    func endsOnTerm() throws {
        let directory = try SnapshotHarness.temporaryDirectory("StopPolicy")
        defer { try? FileManager.default.removeItem(at: directory) }
        let registry = ScratchRegistry()
        let listener = try Listener("polite", in: directory, endsOnTerm: true)
        try Self.start([(listener, .swiftMutator)], in: registry)
        defer { listener.kill() }

        let start = Date()
        registry.cleanUp()
        let elapsed = Date().timeIntervalSince(start)

        #expect(listener.process.isRunning == false)
        #expect(listener.process.terminationReason == .exit && listener.process.terminationStatus == 0)
        #expect(listener.signals == ["TERM"])
        #expect(elapsed < Self.timeout)
    }

    @Test("""
        processes with different policies are stopped together: the standard-shaped one gets SIGINT, then SIGTERM, \
        then SIGKILL, the SIGTERM-first one SIGTERM then SIGKILL, and the waits overlap
        """)
    func mixedPolicies() throws {
        let directory = try SnapshotHarness.temporaryDirectory("StopPolicy")
        defer { try? FileManager.default.removeItem(at: directory) }
        let registry = ScratchRegistry()
        let coverage = try Listener("coverage", in: directory, endsOnTerm: false)
        let mutator = try Listener("mutator", in: directory, endsOnTerm: false)
        let grace: TimeInterval = 1
        let coveragePolicy = StopPolicy(firstSignal: SIGINT, grace: grace, killGrace: grace)
        let mutatorPolicy = StopPolicy(firstSignal: SIGTERM, grace: grace * 2, killGrace: grace)
        try Self.start([(coverage, coveragePolicy), (mutator, mutatorPolicy)], in: registry)
        defer {
            coverage.kill()
            mutator.kill()
        }

        let start = Date()
        registry.cleanUp()
        let elapsed = Date().timeIntervalSince(start)

        try #require(Self.wait { coverage.process.isRunning == false && mutator.process.isRunning == false })
        #expect(coverage.process.terminationStatus == SIGKILL && mutator.process.terminationStatus == SIGKILL)
        #expect(Self.wait { coverage.signals == ["INT", "TERM"] && mutator.signals == ["TERM"] })
        // Both are killed 2 s after the first signals; one after the
        // other would take 4 s.
        #expect(elapsed >= grace * 2 && elapsed < grace * 3)
    }

    @Test("""
        the first signal and SIGTERM reach the child's whole process group, as M5's interrupt() and terminate() did, \
        so a wrapper that forwards no signal still stops the tool it runs
        """)
    func processGroup() throws {
        let directory = try SnapshotHarness.temporaryDirectory("StopPolicy")
        defer { try? FileManager.default.removeItem(at: directory) }
        let registry = ScratchRegistry()
        let listener = try Listener("wrapped", in: directory, endsOnTerm: true, wrapped: true)
        let killGrace: TimeInterval = 2
        let policy = StopPolicy(firstSignal: SIGINT, grace: Self.shortGrace, killGrace: killGrace)
        try Self.start([(listener, policy)], in: registry)
        defer { listener.kill() }
        let wrapper = listener.process.processIdentifier
        let inner = try #require(listener.listenerPID)
        // The listening shell is the wrapper's child, in its group.
        #expect(inner != wrapper)
        #expect(getpgid(inner) == wrapper && getpgid(wrapper) == wrapper)

        registry.cleanUp()

        try #require(Self.wait { listener.process.isRunning == false })
        // The wrapper ended once its child did, by SIGTERM, not by SIGKILL.
        #expect(listener.process.terminationReason == .exit)
        #expect(Self.wait { listener.signals == ["INT", "TERM"] })
        #expect(Self.wait { kill(inner, 0) != 0 && errno == ESRCH })
    }
}
