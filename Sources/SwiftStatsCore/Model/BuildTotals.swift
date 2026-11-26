//
//  BuildTotals.swift
//  SwiftStatsCore
//
//  The T1 build's timing totals (M7, design §6.2): how many entries its
//  standard error held, and the type-check time of the package's own code
//  without double counting. A function's entry already includes its local
//  functions' and local types' members, so the total adds the
//  function-body entries placed on records not nested in a body, on types
//  and on files (stopping at `Int.max` hundredths), rounded to whole
//  milliseconds once, half up.
//

/// The timing totals.
public struct BuildTotals: Codable, Hashable, Sendable {
    /// Function-body entries the build printed, every class.
    public let functionEntries: Int
    /// Expression entries the build printed, every class.
    public let expressionEntries: Int
    /// The mapped function-body time, records nested in a body left out
    /// (stopping at `Int.max` hundredths), in whole milliseconds.
    public let milliseconds: Int

    /// Creates the totals. Fields are documented on their properties.
    public init(functionEntries: Int, expressionEntries: Int, milliseconds: Int) {
        self.functionEntries = functionEntries
        self.expressionEntries = expressionEntries
        self.milliseconds = milliseconds
    }
}
