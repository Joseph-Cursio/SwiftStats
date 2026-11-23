//
//  MutationOptions.swift
//  SwiftStatsCore
//
//  `collectors.swiftmutator.options` (M6, design §1.1): `workers` and
//  `timeout`, passed to `swift-mutator run` as `--workers` and `--timeout`.
//  `options` is the key PRD §10.1 reserves for per-collector settings;
//  swiftmutator is the first collector to read it, and any other key under
//  it is an error.
//

import Yams

/// Reads the SwiftMutator collector's `options`.
enum MutationOptions {
    /// The keys `options` may hold.
    static let keys: Set<String> = ["timeout", "workers"]
    /// The longest per-mutant time limit accepted, in seconds: a day.
    static let longestTimeout: Double = 86_400

    /// The workers and timeout `value` gives, each nil when absent; an
    /// absent or null `options` gives neither. `path` names the
    /// configuration file in errors.
    static func parse(_ value: Node?, path: String) throws -> (workers: Int?, timeout: Double?) {
        guard let value, value.null == nil else {
            return (nil, nil)
        }
        let key = "collectors.\(MutationAdapter.name).options"
        guard let mapping = value.mapping else {
            throw ScanError.configurationInvalid(path, "`\(key)` must be a mapping of workers and timeout")
        }
        let names = mapping.keys.map { $0.string ?? "\($0)" }
        let unknown = Set(names).subtracting(keys).sorted()
        guard unknown.isEmpty else {
            let listed = unknown.map { "\(key).\($0)" }.joined(separator: ", ")
            throw ScanError.configurationInvalid(path, "unknown key(s): \(listed)")
        }
        return (
            try workers(mapping["workers"], key: "\(key).workers", path: path),
            try timeout(mapping["timeout"], key: "\(key).timeout", path: path)
        )
    }

    /// An integer of at least 1, nil when absent, or an error naming `key`.
    private static func workers(_ value: Node?, key: String, path: String) throws -> Int? {
        guard let value, value.null == nil else {
            return nil
        }
        guard let count = value.int, count >= 1 else {
            throw ScanError.configurationInvalid(path, "`\(key)` must be a whole number of at least 1")
        }
        return count
    }

    /// A number of seconds above 0 and at most a day, nil when absent, or
    /// an error naming `key`.
    private static func timeout(_ value: Node?, key: String, path: String) throws -> Double? {
        guard let value, value.null == nil else {
            return nil
        }
        // NaN fails both comparisons; infinity fails the second.
        guard let seconds = value.float, seconds > 0, seconds <= longestTimeout else {
            throw ScanError.configurationInvalid(
                path,
                "`\(key)` must be a number of seconds above 0 and at most \(Int(longestTimeout))"
            )
        }
        return seconds
    }
}
