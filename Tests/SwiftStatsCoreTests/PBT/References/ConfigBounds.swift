//
//  ConfigBounds.swift
//  SwiftStatsCoreTests
//
//  Every edge of the bounds PRD §10.1 states for configuration values,
//  written here from its text, with the reasons the reader gives: each
//  duration (`history.window`, `.repeat_window`, `.half_life`) at least a
//  day and at most 106,751,991,167,300 days; `history.bulk_files` at
//  least 1 and `history.coupling.min_support` at least 2 (the reader's
//  stated floors); each ranked signal's threshold a percent in (0, 100];
//  each M6 and M7 limit percent from 0 to 100, each count a whole number
//  from 1 to 1,000,000, genuinely under-tested's ratio above 0, uneven
//  clone mutation's `high` above its `low` (each as set, else its
//  default, 80 and 20); swiftmutator's `workers` at least 1 and `timeout`
//  above 0 and at most 86,400 seconds. Unbounded sides (a whole number's
//  top) aren't edges.
//

@testable import SwiftStatsCore

/// The edges P11.2 walks.
enum ConfigBounds {
    /// The longest duration, in days (PRD §10.1).
    static let longestDays = 106_751_991_167_300
    /// The most mutants or commits a count limit takes (PRD §10.1).
    static let mostCount = 1_000_000
    /// Uneven clone mutation's signal.
    static let clone = "uneven-clone-mutation"
    /// Uneven clone mutation's `high`.
    static let highPath = ["signals", clone, "high"]
    /// Uneven clone mutation's `low`.
    static let lowPath = ["signals", clone, "low"]
    /// The reason a `high` not above its `low` is refused.
    static let cloneReason = "`signals.uneven-clone-mutation.high` must be above `signals.uneven-clone-mutation.low`"
    /// The smallest positive `Double`, written plain.
    static let leastPositive = "5e-324"
    /// The negative `Double` nearest 0, written plain.
    static let leastNegative = "-5e-324"
    /// The `Double` after 100, written plain.
    static let pastHundred = "100.00000000000001"

    /// Every edge, in PRD §10.1's order.
    static let all: [ConfigBound] = durations + floors + thresholds + percents + clones + counts + ratios + mutator

    /// The durations, each with its reader.
    static let durationReaders: [(key: String, read: @Sendable (SwiftStatsConfiguration) -> Double?)] = [
        ("window", { Double($0.history.windowDays) }),
        ("repeat_window", { Double($0.history.repeatWindowDays) }),
        ("half_life", { Double($0.history.halfLifeDays) })
    ]

    /// Each duration at least a day and at most the longest.
    static let durations: [ConfigBound] = durationReaders.flatMap { key, read in
        let reason = "`history.\(key)` must be a number of days, such as 90d"
        let path = ["history", key]
        return [
            quotable("history.\(key) at least a day", path, ("1d", "0d"), reason, read),
            quotable(
                "history.\(key) at most \(longestDays) days",
                path,
                ("\(longestDays)d", "\(longestDays + 1)d"),
                reason,
                read
            )
        ]
    }

    /// The sweep and coupling floors.
    static let floors: [ConfigBound] = [
        quotable(
            "history.bulk_files at least 1",
            ["history", "bulk_files"],
            ("1", "0"),
            "`history.bulk_files` must be a whole number of at least 1"
        ) { Double($0.history.bulkFiles) },
        quotable(
            "history.coupling.min_support at least 2",
            ["history", "coupling", "min_support"],
            ("2", "1"),
            "`history.coupling.min_support` must be a whole number of at least 2"
        ) { Double($0.history.couplingMinSupport) }
    ]

    /// Each ranked signal's threshold in (0, 100].
    static let thresholds: [ConfigBound] = ["hotspot", "bug-prone", "clone-hotspot"].flatMap { signal in
        let reason = "`signals.\(signal).threshold` must be a percent in (0, 100]"
        let path = ["signals", signal, "threshold"]
        let read: @Sendable (SwiftStatsConfiguration) -> Double? = { $0.signals.percents[signal] }
        return [
            quotable("\(signal) threshold above 0", path, (leastPositive, "0"), reason, read),
            quotable("\(signal) threshold at most 100", path, ("100", pastHundred), reason, read)
        ]
    }

    /// Each limit percent from 0 to 100, uneven clone mutation's aside.
    static let percents: [ConfigBound] = [
        ("weak-tests", "coverage"), ("weak-tests", "score"), ("genuinely-under-tested", "coverage"),
        ("genuinely-under-tested", "score"), ("hidden-coupling", "confidence")
    ]
    .flatMap { signal, limit in
        let read = limitReader(signal, limit)
        let reason = "`signals.\(signal).\(limit)` must be a percent from 0 to 100"
        return [
            quotable("\(signal).\(limit) at least 0", ["signals", signal, limit], ("0", leastNegative), reason, read),
            quotable("\(signal).\(limit) at most 100", ["signals", signal, limit], ("100", pastHundred), reason, read)
        ]
    }

    /// Uneven clone mutation's `high` at most 100 and `low` at least 0,
    /// each with the other at its default, and `high` above `low`: the
    /// default low, the default high, and a set low.
    static let clones: [ConfigBound] = [
        ConfigBound(
            name: "uneven-clone-mutation.high at most 100",
            path: highPath,
            edge: "100",
            outside: pastHundred,
            reason: "`signals.uneven-clone-mutation.high` must be a percent from 0 to 100",
            read: limitReader(clone, "high"),
            isQuotable: true,
            others: [(lowPath, nil)]
        ),
        ConfigBound(
            name: "uneven-clone-mutation.low at least 0",
            path: lowPath,
            edge: "0",
            outside: leastNegative,
            reason: "`signals.uneven-clone-mutation.low` must be a percent from 0 to 100",
            read: limitReader(clone, "low"),
            isQuotable: true,
            others: [(highPath, nil)]
        ),
        ConfigBound(
            name: "uneven-clone-mutation.high above the default low, 20",
            path: highPath,
            edge: "20.000000000000004",
            outside: "20",
            reason: cloneReason,
            read: limitReader(clone, "high"),
            isQuotable: true,
            others: [(lowPath, nil)]
        ),
        ConfigBound(
            name: "uneven-clone-mutation.low below the default high, 80",
            path: lowPath,
            edge: "79.99999999999999",
            outside: "80",
            reason: cloneReason,
            read: limitReader(clone, "low"),
            isQuotable: true,
            others: [(highPath, nil)]
        ),
        ConfigBound(
            name: "uneven-clone-mutation.high above a low of 50",
            path: highPath,
            edge: "50.00000000000001",
            outside: "50",
            reason: cloneReason,
            read: limitReader(clone, "high"),
            isQuotable: true,
            others: [(lowPath, "50")]
        )
    ]

    /// Each count from 1 to a million.
    static let counts: [ConfigBound] = [
        ("weak-tests", "mutants"), ("genuinely-under-tested", "mutants"), (clone, "mutants"),
        ("hidden-coupling", "support")
    ]
    .flatMap { signal, limit in
        let read = limitReader(signal, limit)
        let path = ["signals", signal, limit]
        let reason = "`signals.\(signal).\(limit)` must be a whole number from 1 to \(mostCount)"
        return [
            quotable("\(signal).\(limit) at least 1", path, ("1", "0"), reason, read),
            quotable(
                "\(signal).\(limit) at most \(mostCount)",
                path,
                ("\(mostCount)", "\(mostCount + 1)"),
                reason,
                read
            )
        ]
    }

    /// Genuinely under-tested's ratio above 0.
    static let ratios: [ConfigBound] = [
        quotable(
            "genuinely-under-tested.ratio above 0",
            ["signals", "genuinely-under-tested", "ratio"],
            (leastPositive, "0"),
            "`signals.genuinely-under-tested.ratio` must be a number above 0",
            limitReader("genuinely-under-tested", "ratio")
        )
    ]

    /// swiftmutator's `workers` at least 1, and `timeout` above 0 and at
    /// most a day, written as YAML numbers only.
    static let mutator: [ConfigBound] = {
        let options = ["collectors", "swiftmutator", "options"]
        let workers = "`collectors.swiftmutator.options.workers` must be a whole number of at least 1"
        let timeout = "`collectors.swiftmutator.options.timeout` must be a number of seconds above 0 and at most 86400"
        let readWorkers: @Sendable (SwiftStatsConfiguration) -> Double? = { configuration in
            configuration.collectors["swiftmutator"]?.workers.map(Double.init)
        }
        let readTimeout: @Sendable (SwiftStatsConfiguration) -> Double? = { $0.collectors["swiftmutator"]?.timeout }
        return [
            numeric("workers at least 1", options + ["workers"], ("1", "0"), workers, readWorkers),
            numeric(
                "timeout above 0",
                options + ["timeout"],
                (leastPositive, "0"),
                timeout,
                readTimeout
            ),
            numeric(
                "timeout at most a day",
                options + ["timeout"],
                ("86400", "86400.00000000001"),
                timeout,
                readTimeout
            )
        ]
    }()

    /// The reader of the limit `limit` of `signal`, as set.
    static func limitReader(_ signal: String, _ limit: String) -> @Sendable (SwiftStatsConfiguration) -> Double? {
        { $0.signals.limits[signal]?[limit] }
    }

    /// An edge that may be quoted and needs no other key.
    static func quotable(
        _ name: String,
        _ path: [String],
        _ values: (edge: String, outside: String),
        _ reason: String,
        _ read: @escaping @Sendable (SwiftStatsConfiguration) -> Double?
    ) -> ConfigBound {
        ConfigBound(
            name: name,
            path: path,
            edge: values.edge,
            outside: values.outside,
            reason: reason,
            read: read,
            isQuotable: true,
            others: []
        )
    }

    /// An edge written as a YAML number only, needing no other key.
    static func numeric(
        _ name: String,
        _ path: [String],
        _ values: (edge: String, outside: String),
        _ reason: String,
        _ read: @escaping @Sendable (SwiftStatsConfiguration) -> Double?
    ) -> ConfigBound {
        ConfigBound(
            name: name,
            path: path,
            edge: values.edge,
            outside: values.outside,
            reason: reason,
            read: read,
            isQuotable: false,
            others: []
        )
    }
}
