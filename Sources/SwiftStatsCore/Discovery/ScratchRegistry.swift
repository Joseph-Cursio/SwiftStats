//
//  ScratchRegistry.swift
//  SwiftStatsCore
//
//  The temporary files and directories SwiftStats makes, and the processes
//  it starts, while they exist, so an interrupted command can stop the one
//  and remove the other (`InterruptCleanup`): a `defer` never runs when a
//  signal ends the process, and a child outlives its parent.
//

import Foundation

/// Temporary files and running child processes to clean up when a
/// command is interrupted.
final class ScratchRegistry: @unchecked Sendable {
    /// The registry SwiftStats' own temporary files and processes join.
    static let shared = ScratchRegistry()

    /// How long an interrupted process gets to exit before it is
    /// terminated.
    private static let terminationGrace: TimeInterval = 2
    /// How long a terminated process gets to exit before it is killed.
    private static let killGrace: TimeInterval = 0.5
    /// How often to look whether terminated processes have exited, in
    /// microseconds.
    private static let pollInterval: useconds_t = 10_000

    /// Guards everything below. An interruption takes it and never gives it
    /// back, so no process starts while the process ends.
    private let lock = NSLock()
    /// The temporary files and directories that exist.
    private var paths: Set<URL> = []
    /// The running processes, by identity.
    private var processes: [ObjectIdentifier: Process] = [:]
    /// The signal sources an installed handler keeps alive.
    private var sources: [any DispatchSourceSignal] = []

    /// The temporary files and directories registered, for tests.
    var registeredPaths: Set<URL> {
        lock.lock()
        defer { lock.unlock() }
        return paths
    }

    /// The running processes registered, for tests.
    var registeredProcesses: [Process] {
        lock.lock()
        defer { lock.unlock() }
        return Array(processes.values)
    }

    /// Waits until none of `processes` runs or `grace` passes.
    private static func wait(for processes: [Process], grace: TimeInterval) {
        let deadline = Date().addingTimeInterval(grace)
        while processes.contains(where: \.isRunning), Date() < deadline {
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

    /// Starts `process` and registers it until `finished(_:)`.
    func start(_ process: Process) throws {
        lock.lock()
        defer { lock.unlock() }
        try process.run()
        processes[ObjectIdentifier(process)] = process
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

    /// Interrupts every registered process, terminates any still running
    /// after a grace period and kills any still running after a shorter
    /// one, then removes every registered path.
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
        Thread.sleep(forTimeInterval: Self.terminationGrace)
        _exit(EXIT_FAILURE)
    }

    /// `cleanUp()`'s work; the caller holds the lock. SIGINT goes first:
    /// SwiftPM's `swift test` forwards it to the test processes it started
    /// in process groups of their own, which neither SIGTERM nor SIGKILL
    /// of `swift` reaches (M5), and every other tool ends on it as well.
    private func cleanUpHoldingLock() {
        let running = processes.values.filter(\.isRunning)
        running.forEach { $0.interrupt() }
        Self.wait(for: running, grace: Self.terminationGrace)
        let stubborn = running.filter(\.isRunning)
        stubborn.forEach { $0.terminate() }
        Self.wait(for: stubborn, grace: Self.killGrace)
        for process in stubborn where process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
        for path in paths {
            try? FileManager.default.removeItem(at: path)
        }
        paths.removeAll()
    }

    deinit {
        // Nothing to release: the lock and collections free themselves.
    }
}
