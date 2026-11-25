//
//  BlockingAsync.swift
//  SwiftStatsCore
//
//  The one bridge from SwiftStatsCore's synchronous code to an `async`
//  call (M7, design §2.1). SwiftStatsCore is synchronous throughout; the
//  only `async` function it calls is indexstore-db's
//  `IndexStoreLibrary.at(dylibPath:)`, which loads a libIndexStore.dylib
//  through an actor registry. The call runs in a detached task while the
//  calling thread waits on a semaphore until the task has finished. Call
//  it on a thread of its own, such as the scan's (the command's main
//  thread), never on the main actor or from a task on the cooperative
//  pool: a thread waiting there is one the task may need to run on.
//

import Foundation

/// Runs an `async` operation to its end from synchronous code.
enum BlockingAsync {
    /// What an operation gave: set by its task, read by the waiting thread
    /// once the task has signalled.
    private final class Outcome<Value: Sendable>: @unchecked Sendable {
        /// Guards `result`.
        private let lock = NSLock()
        /// The operation's value or error; cancelled until it is set.
        private var result: Result<Value, any Error> = .failure(CancellationError())

        /// Records what the operation gave.
        func set(_ value: Result<Value, any Error>) {
            lock.lock()
            defer { lock.unlock() }
            result = value
        }

        /// What the operation gave.
        func get() -> Result<Value, any Error> {
            lock.lock()
            defer { lock.unlock() }
            return result
        }

        deinit {
            // Nothing to release.
        }
    }

    /// What `operation` returns, or the error it throws, once it has run
    /// to its end in a detached task; the calling thread waits meanwhile.
    static func run<Value: Sendable>(_ operation: @escaping @Sendable () async throws -> Value) throws -> Value {
        let outcome = Outcome<Value>()
        let finished = DispatchSemaphore(value: 0)
        Task.detached {
            do {
                outcome.set(.success(try await operation()))
            } catch {
                outcome.set(.failure(error))
            }
            finished.signal()
        }
        finished.wait()
        return try outcome.get().get()
    }
}
