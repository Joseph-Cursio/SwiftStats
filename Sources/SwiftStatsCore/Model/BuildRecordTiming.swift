//
//  BuildRecordTiming.swift
//  SwiftStatsCore
//
//  A record's type-check time in the T1 build (M7, design §6.2): the sum of
//  the function-body entries at positions it holds, inclusive of its local
//  functions and local types' members, and its slowest single expression,
//  each rounded to whole milliseconds once, half up. Figures vary between
//  runs, so they are kept as collected and never compared as better or
//  worse.
//

/// One record's type-check figures.
public struct BuildRecordTiming: Codable, Hashable, Sendable {
    /// The record's key.
    public let key: String
    /// The sum of its function-body entries, in whole milliseconds; nil
    /// when it has none.
    public let milliseconds: Int?
    /// Its largest expression entry, in whole milliseconds; nil when it has
    /// none.
    public let slowestExpression: Int?

    /// Creates the figures. Fields are documented on their properties.
    public init(key: String, milliseconds: Int?, slowestExpression: Int?) {
        self.key = key
        self.milliseconds = milliseconds
        self.slowestExpression = slowestExpression
    }
}
