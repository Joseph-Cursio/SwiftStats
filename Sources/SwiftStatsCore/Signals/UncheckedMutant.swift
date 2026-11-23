//
//  UncheckedMutant.swift
//  SwiftStatsCore
//
//  A mutant the tests didn't check (M6, design §7.1, §7.3): one that
//  survived or timed out, as weak tests' `mutation` payload lists it, or,
//  in best property-test target's lists, any mutant not killed (no
//  coverage and not covered too), at SwiftMutator's line and column, with
//  the code it replaced.
//

/// A mutant of a signal item's function its tests didn't kill.
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
    /// `survived` or `timedOut`, or for best property-test target also
    /// `noCoverage` or `notCovered`.
    public let verdict: String

    /// `mutant` as a signal item lists it.
    init(_ mutant: Mutant) {
        operatorID = mutant.operatorID
        line = mutant.line
        column = mutant.column
        before = mutant.before
        after = mutant.after
        verdict = mutant.verdict.rawValue
    }
}
