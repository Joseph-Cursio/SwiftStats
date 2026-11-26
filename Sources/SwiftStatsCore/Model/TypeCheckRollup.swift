//
//  TypeCheckRollup.swift
//  SwiftStatsCore
//
//  Type-check time over a module or a part of the project (M7, design
//  §6.2, §6.4): the function-body time without double counting, the
//  slowest record, the slowest expression on a record, and the records
//  timed. Every scope has it, test modules and the `tests` part included,
//  since the T1 build times every role; absent when the `build` collector
//  didn't run. Its metric names are `typecheck.milliseconds.total`,
//  `typecheck.milliseconds.max`, `typecheck.slowestExpression.max` and
//  `typecheck.functions.timed`, all neutral in `diff`, since the figures
//  depend on the machine and its load.
//

/// Type-check figures over one scope.
public struct TypeCheckRollup: Codable, Hashable, Sendable {
    /// Function-body time.
    public struct Milliseconds: Codable, Hashable, Sendable {
        /// The function-body entries on the scope's records not nested in
        /// a body, on its types and on its files, summed in hundredths
        /// (stopping at `Int.max` hundredths) and rounded to whole
        /// milliseconds once, half up; 0 when it has none.
        public let total: Int
        /// The largest record figure (`BuildRecordTiming.milliseconds`),
        /// records nested in a body included; nil when no record has one.
        public let max: Int?
    }

    /// The slowest expression.
    public struct SlowestExpression: Codable, Hashable, Sendable {
        /// The largest record figure (`BuildRecordTiming.slowestExpression`),
        /// records nested in a body included; nil when no record has one.
        public let max: Int?
    }

    /// Records timed.
    public struct Functions: Codable, Hashable, Sendable {
        /// Records with a function-body figure, records nested in a body
        /// included.
        public let timed: Int
    }

    /// Function-body time: the total and the slowest record.
    public let milliseconds: Milliseconds
    /// The slowest expression on a record.
    public let slowestExpression: SlowestExpression
    /// The records timed.
    public let functions: Functions

    /// The figures of a scope whose total is `total` and whose records'
    /// figures are `timings`.
    init(total: Int, timings: [BuildRecordTiming]) {
        let timed = timings.compactMap(\.milliseconds)
        milliseconds = Milliseconds(total: total, max: timed.max())
        slowestExpression = SlowestExpression(max: timings.compactMap(\.slowestExpression).max())
        functions = Functions(timed: timed.count)
    }
}
