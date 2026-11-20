//
//  BackgroundJob.swift
//  SwiftStatsCore
//
//  Work started on another thread and waited for later, so a slow external
//  tool runs while the scan measures the package (PRD §9).
//

import Foundation

/// A value computed on a background thread.
final class BackgroundJob<Value: Sendable>: @unchecked Sendable {
    /// Left when the value is set.
    private let group = DispatchGroup()
    /// Guards `value`.
    private let lock = NSLock()
    /// The value, once computed.
    private var value: Value?

    /// Starts computing `work` on a background thread.
    init(_ work: @escaping @Sendable () -> Value) {
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            let result = work()
            lock.lock()
            value = result
            lock.unlock()
            group.leave()
        }
    }

    /// The value, waiting for it when it isn't ready.
    func wait() -> Value {
        group.wait()
        lock.lock()
        defer { lock.unlock() }
        guard let value else {
            preconditionFailure("a background job finished without a value")
        }
        return value
    }

    deinit {
        // Nothing to release: the group and lock free themselves.
    }
}
