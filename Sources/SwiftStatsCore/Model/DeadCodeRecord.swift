//
//  DeadCodeRecord.swift
//  SwiftStatsCore
//
//  A record an unused production entry of an outskirts run covers (M7,
//  design §5.4, §9.1's `deadRecord`): the record, the run, the covering
//  entry's ordinal in that run and the rule. A record covered twice in one
//  run keeps the entry with the lower ordinal. Every covered record is
//  dead in its run: dead with tests as roots in the `roots` run,
//  production-dead in the `production` run.
//

/// A record covered by an outskirts entry.
public struct DeadCodeRecord: Codable, Hashable, Sendable {
    /// The record's key.
    public let key: String
    /// The run whose entry covers it.
    public let run: DeadCodeRun
    /// The covering entry's 1-based ordinal in that run.
    public let declaration: Int
    /// The rule by which it is covered.
    public let via: DeadCodeVia

    /// Creates a row. Fields are documented on their properties.
    public init(key: String, run: DeadCodeRun, declaration: Int, via: DeadCodeVia) {
        self.key = key
        self.run = run
        self.declaration = declaration
        self.via = via
    }
}
