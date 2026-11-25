//
//  TimingEntry.swift
//  SwiftStatsCore
//
//  One type-check timing line of the T1 build's standard error (M7, design
//  §6.1), printed by `-debug-time-function-bodies` (three tab-separated
//  fields: the time, the declaration's name position and the declaration)
//  or `-debug-time-expression-type-checking` (two: the time and the
//  expression's position). The time is kept in integer hundredths of a
//  millisecond, as printed, so sums never meet floating-point rounding.
//

/// A type-check timing entry.
struct TimingEntry: Hashable, Sendable {
    /// Which flag printed the entry.
    enum Kind: String, Sendable {
        /// An expression's type-check time.
        case expression
        /// A function body's type-check time, its local functions and
        /// local types' members included.
        case function
    }

    /// Which flag printed it.
    let kind: Kind
    /// The time, in hundredths of a millisecond (`4.35ms` is 435).
    let hundredths: Int
    /// Where: a function's name position or an expression's start; nil for
    /// `<invalid loc>` (a synthesized member, such as `hash(into:)`).
    let place: BuildPlace?
    /// A function entry's third field, `<kind> <Module>.(file).<context>.
    /// <name>@<path>:<line>:<col>`; nil for an expression.
    let declaration: String?
}
