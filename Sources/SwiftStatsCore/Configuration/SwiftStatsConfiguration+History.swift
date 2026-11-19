//
//  SwiftStatsConfiguration+History.swift
//  SwiftStatsCore
//
//  Parsing `history:` and `signals:` (PRD §10.1). Unknown sub-keys, bad
//  durations and invalid regular expressions are errors, like unknown
//  top-level keys.
//

import Foundation
import Yams

extension SwiftStatsConfiguration {
    /// The keys `history:` may hold.
    private static let historyKeys: Set<String> = [
        "window", "fix_patterns", "fix_exclude_patterns", "repeat_window", "half_life", "bulk_files", "ignore_revs",
        "coupling"
    ]

    /// The smallest `history.coupling.min_support` the file may set.
    private static let minimumCouplingSupport = 2
    /// The shortest abbreviated commit hash `history.ignore_revs` accepts.
    private static let minimumRevisionLength = 7

    /// The `history:` options, or the defaults when absent.
    static func historyOptions(_ value: Node?, path: String) throws -> HistoryOptions {
        guard let value, value.null == nil else {
            return .standard
        }
        let mapping = try Self.mapping(value, key: "history", allowed: historyKeys, path: path)
        let standard = HistoryOptions.standard
        let minSupport = try couplingMinSupport(mapping["coupling"], path: path)
        let windowDays = try mapping["window"].map { node in
            try days(node, key: "history.window", path: path)
        }
        let fixPatterns = try mapping["fix_patterns"].map { node in
            try patterns(node, key: "history.fix_patterns", path: path)
        }
        let fixExcludePatterns = try mapping["fix_exclude_patterns"].map { node in
            try patterns(node, key: "history.fix_exclude_patterns", path: path)
        }
        let repeatWindowDays = try mapping["repeat_window"].map { node in
            try days(node, key: "history.repeat_window", path: path)
        }
        let halfLifeDays = try mapping["half_life"].map { node in
            try days(node, key: "history.half_life", path: path)
        }
        let bulkFiles = try mapping["bulk_files"].map { node in
            try integer(node, key: "history.bulk_files", minimum: 1, path: path)
        }
        let ignoreRevs = try mapping["ignore_revs"].map { node in
            try revisions(node, path: path)
        }
        return HistoryOptions(
            windowDays: windowDays ?? standard.windowDays,
            fixPatterns: fixPatterns ?? standard.fixPatterns,
            fixExcludePatterns: fixExcludePatterns ?? standard.fixExcludePatterns,
            repeatWindowDays: repeatWindowDays ?? standard.repeatWindowDays,
            halfLifeDays: halfLifeDays ?? standard.halfLifeDays,
            bulkFiles: bulkFiles ?? standard.bulkFiles,
            ignoreRevs: ignoreRevs ?? standard.ignoreRevs,
            couplingMinSupport: minSupport
        )
    }

    /// `history.coupling.min_support`, or the default when absent.
    private static func couplingMinSupport(_ coupling: Node?, path: String) throws -> Int {
        let standard = HistoryOptions.standard.couplingMinSupport
        guard let coupling, coupling.null == nil else {
            return standard
        }
        let couplingMapping = try Self.mapping(
            coupling,
            key: "history.coupling",
            allowed: ["min_support"],
            path: path
        )
        let minSupport = try couplingMapping["min_support"].map { node in
            try integer(
                node,
                key: "history.coupling.min_support",
                minimum: minimumCouplingSupport,
                path: path
            )
        }
        return minSupport ?? standard
    }

    /// The `signals:` thresholds, or the defaults when absent.
    static func signalThresholds(_ value: Node?, path: String) throws -> SignalThresholds {
        guard let value, value.null == nil else {
            return SignalThresholds()
        }
        let mapping = try Self.mapping(value, key: "signals", allowed: SignalThresholds.rankedSignals, path: path)
        var percents: [String: Double] = [:]
        for name in SignalThresholds.rankedSignals {
            guard let entry = mapping[name], entry.null == nil else {
                continue
            }
            let settings = try Self.mapping(entry, key: "signals.\(name)", allowed: ["threshold"], path: path)
            guard let threshold = settings["threshold"] else {
                continue
            }
            guard let number = threshold.scalar.flatMap({ Double($0.string) }), number > 0, number <= 100 else {
                throw ScanError.configurationInvalid(path, "`signals.\(name).threshold` must be a percent in (0, 100]")
            }
            percents[name] = number
        }
        return SignalThresholds(percents: percents)
    }

    /// `value` as a mapping whose keys are all in `allowed`.
    private static func mapping(
        _ value: Node,
        key: String,
        allowed: Set<String>,
        path: String
    ) throws -> Node.Mapping {
        guard let mapping = value.mapping else {
            throw ScanError.configurationInvalid(path, "`\(key)` must be a mapping")
        }
        let keys = mapping.keys.compactMap(\.string)
        let unknown = Set(keys).subtracting(allowed).sorted()
        guard unknown.isEmpty else {
            let names = unknown.joined(separator: ", ")
            throw ScanError.configurationInvalid(path, "unknown key(s) under `\(key)`: \(names)")
        }
        guard Set(keys).count == keys.count else {
            throw ScanError.configurationInvalid(path, "a key under `\(key)` is given more than once")
        }
        return mapping
    }

    /// A duration written `<days>d`, such as `90d`.
    private static func days(_ value: Node, key: String, path: String) throws -> Int {
        guard let text = value.scalar?.string, text.hasSuffix("d"),
              let number = Int(text.dropLast()), number > 0 else {
            throw ScanError.configurationInvalid(path, "`\(key)` must be a number of days, such as 90d")
        }
        return number
    }

    /// A whole number no smaller than `minimum`.
    private static func integer(_ value: Node, key: String, minimum: Int, path: String) throws -> Int {
        guard let number = value.scalar.flatMap({ Int($0.string) }), number >= minimum else {
            throw ScanError.configurationInvalid(path, "`\(key)` must be a whole number of at least \(minimum)")
        }
        return number
    }

    /// A list of valid regular expressions.
    private static func patterns(_ value: Node, key: String, path: String) throws -> [String] {
        guard let sequence = value.sequence else {
            throw ScanError.configurationInvalid(path, "`\(key)` must be a list of regular expressions")
        }
        return try sequence.map { item in
            guard let pattern = item.scalar?.string,
                  (try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])) != nil else {
                throw ScanError.configurationInvalid(path, "`\(key)` holds an invalid regular expression")
            }
            return pattern
        }
    }

    /// A list of commit hashes.
    private static func revisions(_ value: Node, path: String) throws -> [String] {
        guard let sequence = value.sequence else {
            throw ScanError.configurationInvalid(path, "`history.ignore_revs` must be a list of commit hashes")
        }
        return try sequence.map { item in
            guard let text = item.scalar?.string.lowercased(), text.count >= minimumRevisionLength,
                  text.allSatisfy(\.isHexDigit) else {
                throw ScanError.configurationInvalid(path, "`history.ignore_revs` must be a list of commit hashes")
            }
            return text
        }
    }
}
