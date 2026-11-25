//
//  SwiftStatsConfiguration+Signals.swift
//  SwiftStatsCore
//
//  Parsing the signals' limits under `signals:` (M6, design §7; M7, design
//  §8; PRD §10.1): `signals.<name>.<limit>` for weak tests, genuinely
//  under-tested, uneven clone mutation and hidden coupling. A percent lies
//  from 0 to 100, a fewest number of mutants or of commits (hidden
//  coupling's `support`) is a whole number from 1 to a million, genuinely
//  under-tested's ratio is a number above 0, and uneven clone mutation's
//  `high` must lie above its `low` (each as set, else its default).
//  Unknown keys and invalid values are errors naming the key, checked in
//  the order of the signals' and limits' names.
//

import Yams

extension SwiftStatsConfiguration {
    /// The highest percent a limit may be.
    private static let wholePercent = 100.0
    /// The most scored mutants (or commits) a limit may ask for: far above
    /// any function's, and small enough that every count is exact as the
    /// `Double` thresholds hold and converts back to `Int` without trapping.
    private static let mostMutants = 1_000_000

    /// The mutation signals' and hidden coupling's limits `mapping` (the
    /// `signals:` mapping) sets, by signal, then limit.
    static func signalLimits(_ mapping: Node.Mapping, path: String) throws -> [String: [String: Double]] {
        var limits: [String: [String: Double]] = [:]
        for (signal, kinds) in SignalThresholds.limitKinds.sorted(by: { $0.key < $1.key }) {
            guard let entry = mapping[signal], entry.null == nil else {
                continue
            }
            let settings = try Self.mapping(entry, key: "signals.\(signal)", allowed: Set(kinds.keys), path: path)
            for (name, kind) in kinds.sorted(by: { $0.key < $1.key }) {
                guard let node = settings[name], node.null == nil else {
                    continue
                }
                let key = "signals.\(signal).\(name)"
                limits[signal, default: [:]][name] = try limit(node, kind: kind, key: key, path: path)
            }
        }
        let thresholds = SignalThresholds(limits: limits)
        let clones = SignalThresholds.unevenCloneMutation
        if let high = thresholds.limit(SignalThresholds.high, of: clones),
           let low = thresholds.limit(SignalThresholds.low, of: clones), high <= low {
            throw ScanError.configurationInvalid(
                path,
                "`signals.\(clones).\(SignalThresholds.high)` must be above `signals.\(clones).\(SignalThresholds.low)`"
            )
        }
        return limits
    }

    /// The limit `node` sets, valid for `kind`.
    private static func limit(
        _ node: Node,
        kind: SignalThresholds.LimitKind,
        key: String,
        path: String
    ) throws -> Double {
        let text = node.scalar?.string ?? ""
        switch kind {
        case .percent:
            guard let number = Double(text), number >= 0, number <= wholePercent else {
                throw ScanError.configurationInvalid(path, "`\(key)` must be a percent from 0 to 100")
            }
            return number

        case .count:
            guard let number = Int(text), number >= 1, number <= mostMutants else {
                throw ScanError.configurationInvalid(path, "`\(key)` must be a whole number from 1 to \(mostMutants)")
            }
            return Double(number)

        case .ratio:
            guard let number = Double(text), number.isFinite, number > 0 else {
                throw ScanError.configurationInvalid(path, "`\(key)` must be a number above 0")
            }
            return number
        }
    }
}
