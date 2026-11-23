//
//  ScratchRegistry.swift
//  SwiftStatsCore
//
//  The temporary files and directories SwiftStats makes, and the processes
//  it starts, while they exist, so an interrupted command can stop the one
//  and remove the other (`InterruptCleanup`): a `defer` never runs when a
//  signal ends the process, and a child outlives its parent. It also holds
//  the files of the user's package a running command may change
//  (`PreservedFile`), so an interruption puts them back. Each process is
//  stopped by its own `StopPolicy`, all at once: the signals go out
//  together and each process's waits run from the same moment, so an
//  interruption takes as long as the slowest policy needs, not their sum.
//  The first signal and SIGTERM go to the child's process group, as M5's
//  `Process.interrupt()` and `terminate()` sent them: Foundation starts
//  each child as the leader of a group of its own, so they reach the
//  descendants that stay in it, such as the real `swift` under a wrapper
//  script that forwards no signal. SIGKILL goes to the child alone, as in
//  M5.
//

import Foundation

/// Temporary files and running child processes to clean up when a
/// command is interrupted.
final class ScratchRegistry: @unchecked Sendable {
    /// A running process and how to stop it.
    struct Registered {
        /// The process.
        let process: Process
        /// How an interruption stops it.
        let policy: StopPolicy
    }

    /// A process being stopped: when it gets SIGTERM and SIGKILL, and
    /// whether it has had SIGTERM.
    private struct Stopping {
        /// The process.
        let process: Process
        /// When it gets SIGTERM, if its policy sends one.
        let terminateAt: Date
        /// When it gets SIGKILL.
        let killAt: Date
        /// Whether its policy sends SIGTERM after the first signal.
        let terminates: Bool
        /// Whether it has had that SIGTERM.
        var terminated = false
    }

    /// The registry SwiftStats' own temporary files and processes join.
    static let shared = ScratchRegistry()

    /// How long this process waits for the signal it sent itself to end
    /// it, after cleaning up.
    private static let selfSignalWait: TimeInterval = 2
    /// How often to look whether stopped processes have exited, in
    /// microseconds.
    private static let pollInterval: useconds_t = 10_000

    /// Guards everything below. An interruption takes it and never gives it
    /// back, so no process starts while the process ends.
    private let lock = NSLock()
    /// The temporary files and directories that exist.
    private var paths: Set<URL> = []
    /// The running processes and their stop policies, by identity.
    private var processes: [ObjectIdentifier: Registered] = [:]
    /// The package files to put back, by path.
    private var preserved: [URL: PreservedFile] = [:]
    /// The signal sources an installed handler keeps alive.
    private var sources: [any DispatchSourceSignal] = []

    /// The temporary files and directories registered, for tests.
    var registeredPaths: Set<URL> {
        lock.lock()
        defer { lock.unlock() }
        return paths
    }

    /// The paths of the package files registered to be put back, for tests.
    var preservedPaths: Set<URL> {
        lock.lock()
        defer { lock.unlock() }
        return Set(preserved.keys)
    }

    /// The running processes registered, with their stop policies, for
    /// tests.
    var registeredProcesses: [Registered] {
        lock.lock()
        defer { lock.unlock() }
        return Array(processes.values)
    }

    /// Sends `number` to the process group `process` leads, or to
    /// `process` alone when no such group exists. A process never started
    /// has the identifier 0, which `killpg(2)` reads as SwiftStats' own
    /// group, so it gets nothing.
    private static func signalGroup(of process: Process, _ number: Int32) {
        let pid = process.processIdentifier
        guard pid > 0 else {
            return
        }
        if killpg(pid, number) != 0 {
            kill(pid, number)
        }
    }

    /// Stops every process of `registered` still running, each by its
    /// policy: its first signal now, then, while it still runs, SIGTERM
    /// after its grace unless that was the first signal, and SIGKILL after
    /// its kill grace. The first signal and SIGTERM go to the process's
    /// group, SIGKILL to the process alone. Returns once each has ended
    /// or had SIGKILL.
    static func stop(_ registered: [Registered]) {
        let start = Date()
        var stopping: [Stopping] = []
        for entry in registered where entry.process.isRunning {
            signalGroup(of: entry.process, entry.policy.firstSignal)
            stopping.append(Stopping(
                process: entry.process,
                terminateAt: start.addingTimeInterval(entry.policy.grace),
                killAt: start.addingTimeInterval(entry.policy.killAfter),
                terminates: entry.policy.terminates
            ))
        }
        while true {
            stopping.removeAll { $0.process.isRunning == false }
            guard stopping.isEmpty == false else {
                return
            }
            let now = Date()
            for index in stopping.indices
            where stopping[index].terminates && stopping[index].terminated == false
                && now >= stopping[index].terminateAt {
                signalGroup(of: stopping[index].process, SIGTERM)
                stopping[index].terminated = true
            }
            for entry in stopping where now >= entry.killAt {
                kill(entry.process.processIdentifier, SIGKILL)
            }
            stopping.removeAll { now >= $0.killAt }
            usleep(pollInterval)
        }
    }

    /// Registers `url`, a temporary file or directory about to be made.
    func track(_ url: URL) {
        lock.lock()
        paths.insert(url)
        lock.unlock()
    }

    /// Removes the temporary file or directory at `url` and forgets it. It
    /// stays registered while it is removed, and the lock is not held
    /// meanwhile, so a large copy doesn't hold up processes starting.
    func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
        lock.lock()
        paths.remove(url)
        lock.unlock()
    }

    /// Registers `file`, to be put back if the command is interrupted
    /// before `putBack(_:)`.
    func preserve(_ file: PreservedFile) {
        lock.lock()
        preserved[file.url] = file
        lock.unlock()
    }

    /// Puts `file` back as it was and forgets it. The lock is held
    /// meanwhile, so an interruption doesn't put it back at the same time.
    func putBack(_ file: PreservedFile) throws {
        lock.lock()
        defer { lock.unlock() }
        preserved[file.url] = nil
        try file.restore()
    }

    /// Starts `process` and registers it until `finished(_:)`, to be
    /// stopped by the standard policy.
    func start(_ process: Process) throws {
        try start(process, stop: .standard)
    }

    /// Starts `process` and registers it until `finished(_:)`, to be
    /// stopped by `policy`.
    func start(_ process: Process, stop policy: StopPolicy) throws {
        lock.lock()
        defer { lock.unlock() }
        try process.run()
        processes[ObjectIdentifier(process)] = Registered(process: process, policy: policy)
    }

    /// Forgets `process`, which has exited.
    func finished(_ process: Process) {
        lock.lock()
        processes[ObjectIdentifier(process)] = nil
        lock.unlock()
    }

    /// Keeps `source` alive.
    func keep(_ source: any DispatchSourceSignal) {
        lock.lock()
        sources.append(source)
        lock.unlock()
    }

    /// Stops every registered process by its policy (`stop(_:)`), then
    /// puts every preserved file back and removes every registered path.
    func cleanUp() {
        lock.lock()
        defer { lock.unlock() }
        cleanUpHoldingLock()
    }

    /// Cleans up as `cleanUp()` does, then ends this process with the
    /// default action of the signal `number`. The lock is never released,
    /// so no other thread starts a process meanwhile.
    func end(by number: Int32) -> Never {
        lock.lock()
        cleanUpHoldingLock()
        signal(number, SIG_DFL)
        // Sent to the process, not raised on this thread: a dispatch
        // thread blocks signals, so another thread takes it.
        kill(getpid(), number)
        Thread.sleep(forTimeInterval: Self.selfSignalWait)
        _exit(EXIT_FAILURE)
    }

    /// `cleanUp()`'s work; the caller holds the lock. Each process's
    /// policy says what it gets first (`StopPolicy`).
    private func cleanUpHoldingLock() {
        Self.stop(Array(processes.values))
        for file in preserved.values {
            try? file.restore()
        }
        preserved.removeAll()
        for path in paths {
            try? FileManager.default.removeItem(at: path)
        }
        paths.removeAll()
    }

    deinit {
        // Nothing to release: the lock and collections free themselves.
    }
}
