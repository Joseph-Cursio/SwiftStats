//
//  Parallel.swift
//  SwiftStatsCore
//
//  Runs a transform over many inputs on every core, keeping input order.
//

import Foundation

/// Runs work on every core.
enum Parallel {
    /// Collects results from several threads at once.
    private final class Results<Value>: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [Value?]

        var all: [Value?] {
            lock.lock()
            defer { lock.unlock() }
            return values
        }

        init(count: Int) {
            values = Array(repeating: nil, count: count)
        }

        func set(_ value: Value, at index: Int) {
            lock.lock()
            values[index] = value
            lock.unlock()
        }

        deinit {
            // Nothing to release: the values free themselves.
        }
    }

    /// `transform` applied to each of `inputs` concurrently, in input order.
    static func map<Input: Sendable, Output: Sendable>(
        _ inputs: [Input],
        _ transform: @Sendable (Input) -> Output
    ) -> [Output] {
        let results = Results<Output>(count: inputs.count)
        DispatchQueue.concurrentPerform(iterations: inputs.count) { index in
            results.set(transform(inputs[index]), at: index)
        }
        return results.all.compactMap(\.self)
    }
}
