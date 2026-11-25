//
//  BlockingAsyncTests.swift
//  SwiftStatsCoreTests
//
//  `BlockingAsync` (M7, design §2.1), the one bridge from synchronous code
//  to an `async` call: called from several tests at once, each call
//  finishes within a timeout with its own value, and an operation's error
//  reaches its caller. Each call is made on a thread of its own
//  (`ThreadRun`), as the bridge requires, and the tests await the result
//  without holding a pool thread.
//

import Foundation
@testable import SwiftStatsCore
import Testing

/// The bridge from synchronous code to an `async` call.
@Suite("Blocking async")
struct BlockingAsyncTests {
    /// Counts the operations that reached it, an actor as the library
    /// registry the bridge exists for is.
    private actor Counter {
        /// How many operations reached it.
        private(set) var count = 0

        /// Counts one more operation; the new count.
        func increment() -> Int {
            count += 1
            return count
        }
    }

    /// An operation's own error.
    private struct Refusal: Error, Equatable {
        /// Which refusal.
        let code: Int
    }

    /// The calls each parallel test makes in turn.
    private static let calls = 5
    /// How long a test waits for its thread, in seconds: long enough that
    /// a full test run's synchronous tests, which hold the cooperative
    /// pool's threads the bridge's detached task needs, can't use it up
    /// (30 s did: the bridged calls start only once a pool thread frees,
    /// about 50 s into a run), while a deadlocked bridge still fails.
    private static let timeout: TimeInterval = 180

    /// The parallel tests' numbers.
    private static let callers = Array(0..<8)

    /// What `run` gave, awaited by polling so no pool thread waits; nil
    /// when it hasn't ended within `timeout` seconds.
    private static func result<Value: Sendable>(of run: ThreadRun<Value>) async -> Value? {
        let deadline = Date().addingTimeInterval(timeout)
        while run.isFinished == false {
            guard Date() < deadline else {
                return nil
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return await run.value
    }

    @Test("calls from several tests at once each finish within the timeout with their own values", arguments: callers)
    func parallel(caller: Int) async throws {
        let counter = Counter()
        let run = ThreadRun { () -> [Int] in
            (0..<Self.calls).map { step in
                let value = try? BlockingAsync.run {
                    try await Task.sleep(for: .milliseconds(5))
                    await Task.yield()
                    _ = await counter.increment()
                    return caller * 100 + step
                }
                return value ?? -1
            }
        }

        let values = try #require(await Self.result(of: run))
        #expect(values == (0..<Self.calls).map { caller * 100 + $0 })
        #expect(await counter.count == Self.calls)
    }

    @Test("an operation's error is thrown to the caller, after the operation has ended")
    func error() async throws {
        let counter = Counter()
        let run = ThreadRun { () -> Result<Int, any Error> in
            Result {
                try BlockingAsync.run { () async throws -> Int in
                    _ = await counter.increment()
                    throw Refusal(code: 7)
                }
            }
        }

        let result = try #require(await Self.result(of: run))
        #expect(throws: Refusal(code: 7)) { try result.get() }
        #expect(await counter.count == 1)
    }
}
