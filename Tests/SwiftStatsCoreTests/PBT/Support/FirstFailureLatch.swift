//
//  FirstFailureLatch.swift
//  SwiftStatsCoreTests
//
//  Whether one property check has printed its first failing input. A
//  property makes one in its test body, outside `propertyCheck`, and passes
//  it to every `PBTTrace.firstFailure(_:latch:)` call, so the check prints
//  its first failing input and no later one. One latch per check, not one
//  per process: a test that runs again in the same process (repetitions,
//  or a second check in one body) gets a fresh latch and prints again. Safe
//  to claim from the engine's parallel runs: a class behind an `NSLock`,
//  the pattern `ThreadRun` uses, since `Mutex` needs macOS 15 and the
//  package targets macOS 14.
//

import Foundation

/// Whether one property check has printed its first failing input.
final class FirstFailureLatch: @unchecked Sendable { // every `var` is behind `lock`
    /// Guards `isClaimed`.
    private let lock = NSLock()
    /// Whether the latch has been claimed.
    private var isClaimed = false

    /// Claims the latch; whether this was its first claim.
    func claim() -> Bool {
        lock.withLock {
            let isFirst = isClaimed == false
            isClaimed = true
            return isFirst
        }
    }

    deinit {
        // Nothing to release.
    }
}
