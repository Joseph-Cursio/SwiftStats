//
//  MutationOptions.swift
//  SwiftStatsCore
//
//  `collectors.swiftmutator.options` (M6, design §1.1): `workers` and
//  `timeout`, passed to `swift-mutator run` as `--workers` and `--timeout`.
//  `options` is the key PRD §10.1 reserves for per-collector settings;
//  swiftmutator is the first collector to read it, and any other key under
//  it is an error. `workers` is read as Yams reads a YAML 1.1 integer
//  (`0x10`, `010`, `1_000`, base 60 `1:30`), but a base-60 text is read
//  here, with every step checked, since Yams' own reading traps on
//  overflow (design B30).
//

import Yams

/// Reads the SwiftMutator collector's `options`.
enum MutationOptions {
    /// The keys `options` may hold.
    static let keys: Set<String> = ["timeout", "workers"]
    /// The longest per-mutant time limit accepted, in seconds: a day.
    static let longestTimeout: Double = 86_400
    /// The radix of YAML 1.1's base-60 integers (`1:30` is 90).
    private static let sexagesimalRadix = 60

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
        guard let count = wholeNumber(value), count >= 1 else {
            throw ScanError.configurationInvalid(path, "`\(key)` must be a whole number of at least 1")
        }
        return count
    }

    /// The whole number `value` holds, as Yams reads a YAML 1.1 integer, or
    /// nil. Yams reads a plain text holding `:` in base 60 (`1:30` is 90),
    /// working out each place's value and the one after the last, and
    /// multiplies, adds and negates without overflow checks, so eleven
    /// places (`1:0:0:0:0:0:0:0:0:0:0`: its value fits `Int`, the twelfth
    /// place value, 60^11, doesn't), a place too large or a negated
    /// `Int.min` trap the process (design B30). Such a text is read here
    /// instead, as Yams would read it, and one whose value, place values
    /// or sign would overflow is not a whole number.
    private static func wholeNumber(_ value: Node) -> Int? {
        guard let scalar = value.scalar, scalar.string.contains(":") else {
            return value.int
        }
        let text = scalar.string.replacingOccurrences(of: "_", with: "")
        let unsigned = text.hasPrefix("-") || text.hasPrefix("+") ? text.dropFirst() : Substring(text)
        // Yams reads only plain integers, and after one sign a leading `0`
        // starts a radix prefix, in which no text holding `:` reads.
        guard scalar.style == .any || scalar.style == .plain, unsigned.hasPrefix("0") == false else {
            return nil
        }
        return baseSixty(text)
    }

    /// `text`, places of decimal integers each optionally signed, joined by
    /// `:`, after at most one `-` or `+`, read in base 60 with every step
    /// Yams takes checked, the place value after the last included; nil
    /// when a place isn't an integer or a step overflows, so for more than
    /// ten places.
    private static func baseSixty(_ text: String) -> Int? {
        let isNegative = text.hasPrefix("-")
        let places = (isNegative || text.hasPrefix("+") ? text.dropFirst() : Substring(text))
            .split(separator: ":", omittingEmptySubsequences: false)
        var value = 0
        var placeValue = 1
        for place in places.reversed() {
            guard let digit = Int(place) else {
                return nil
            }
            let (scaled, scaleOverflow) = digit.multipliedReportingOverflow(by: placeValue)
            let (sum, sumOverflow) = value.addingReportingOverflow(scaled)
            let (next, nextOverflow) = placeValue.multipliedReportingOverflow(by: sexagesimalRadix)
            guard scaleOverflow == false, sumOverflow == false, nextOverflow == false else {
                return nil
            }
            value = sum
            placeValue = next
        }
        guard isNegative else {
            return value
        }
        let (negated, overflow) = 0.subtractingReportingOverflow(value)
        return overflow ? nil : negated
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
