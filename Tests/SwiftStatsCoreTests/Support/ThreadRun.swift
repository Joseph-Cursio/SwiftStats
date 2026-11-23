//
//  ThreadRun.swift
//  SwiftStatsCoreTests
//
//  Blocking work a test runs on a thread of its own rather than on Swift
//  concurrency's cooperative pool, which has a thread per core and a
//  queue of other tests ahead of any task started on it: a test that
//  waits for a detached task while that task waits for a pool thread can
//  wait past its timeout. The work starts as the value is made; a test
//  awaits its result without holding a pool thread, or waits for it from
//  synchronous code (a `defer`) with a timeout.
//

import Foundation

/// Work running on a thread of its own, and its result once it ends.
final class ThreadRun<Value: Sendable>: @unchecked Sendable { // every `var` is behind `lock`
    /// Guards `result` and `waiting`.
    private let lock = NSLock()
    /// Signalled once `result` is set.
    private let ended = DispatchSemaphore(value: 0)
    /// The work's result, once it has ended.
    private var result: Value?
    /// The task awaiting the result before it was set.
    private var waiting: CheckedContinuation<Value, Never>?

    /// Whether the work has ended.
    var isFinished: Bool {
        lock.withLock { result != nil }
    }

    /// The work's result, once it ends.
    var value: Value {
        get async {
            await withCheckedContinuation { continuation in
                let done: Value? = lock.withLock {
                    if result == nil {
                        waiting = continuation
                    }
                    return result
                }
                if let done {
                    continuation.resume(returning: done)
                }
            }
        }
    }

    /// Starts `body` on a new thread.
    init(_ body: @escaping @Sendable () -> Value) {
        let thread = Thread { [self] in
            finish(body())
        }
        thread.start()
    }

    /// Waits, blocking, until the work ends or `timeout` seconds pass;
    /// whether it ended.
    @discardableResult
    func wait(within timeout: TimeInterval) -> Bool {
        guard isFinished == false else {
            return true
        }
        guard ended.wait(timeout: .now() + timeout) == .success else {
            return false
        }
        ended.signal()
        return true
    }

    /// Records `value` as the result and hands it to any awaiting task.
    private func finish(_ value: Value) {
        let continuation = lock.withLock {
            result = value
            defer { waiting = nil }
            return waiting
        }
        ended.signal()
        continuation?.resume(returning: value)
    }

    deinit {
        // Nothing to release: the thread holds the value until it ends.
    }
}
