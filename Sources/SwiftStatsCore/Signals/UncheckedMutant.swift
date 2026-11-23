//
//  UncheckedMutant.swift
//  SwiftStatsCore
//
//  A mutant the tests ran and didn't check (M6, design §7.1): one that
//  survived or timed out, as weak tests' `mutation` payload lists it, at
//  SwiftMutator's line and column, with the code it replaced.
//

/// A survived or timed-out mutant of a signal item's function.
public struct UncheckedMutant: Codable, Hashable, Sendable {
    /// The keys the report writes; `operator` is a keyword.
    private enum CodingKeys: String, CodingKey {
        case operatorID = "operator"
        case line
        case column
        case before
        case after
        case verdict
    }

    /// The operator's id.
    public let operatorID: String
    /// The line SwiftMutator gives.
    public let line: Int
    /// The UTF-8 column SwiftMutator gives.
    public let column: Int
    /// The code it replaces.
    public let before: String
    /// The code it puts in its place.
    public let after: String
    /// `survived` or `timedOut`.
    public let verdict: String
}
