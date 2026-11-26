//
//  BuildEntryCount.swift
//  SwiftStatsCore
//
//  A class of type-check timing entries the mapping didn't place (M7,
//  design §6.2): how many, and the time they state, function-body and
//  expression entries summed as printed (stopping at `Int.max`
//  hundredths), in whole milliseconds rounded once, half up.
//

/// How many timing entries of a class, and their time.
public struct BuildEntryCount: Codable, Hashable, Sendable {
    /// Function-body and expression entries.
    public let entries: Int
    /// Their times summed (stopping at `Int.max` hundredths), in whole
    /// milliseconds.
    public let milliseconds: Int

    /// Creates the count. Fields are documented on their properties.
    public init(entries: Int, milliseconds: Int) {
        self.entries = entries
        self.milliseconds = milliseconds
    }
}
