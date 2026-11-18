//
//  FunctionComplexity.swift
//  SwiftStatsCore
//
//  A record's complexity scores (PRD §7.3), computed by SwiftCodeMetrics so
//  SwiftStats and SwiftProjectLint report the same numbers. The definition
//  version they follow is the report's `metrics`.
//

/// The three complexity scores of one record, and the nesting depth.
public struct FunctionComplexity: Codable, Hashable, Sendable {
    /// Swift cognitive complexity.
    public let cognitive: Int
    /// McCabe decision count: every branch point (`mccabe` is this plus 1).
    public let decisionCount: Int
    /// SwiftLint's `cyclomatic_complexity` value, for parity checks.
    public let swiftLintCompatible: Int
    /// Whether SwiftLint scores this kind at all (only `func` and `init`).
    public let swiftLintScored: Bool
    /// The deepest nesting level any construct gives its contents; 0 for none.
    public let maxNesting: Int
    /// The result builder the body is written in (`ViewBuilder`, or `View`
    /// for a `some View` result), when it is one.
    public let resultBuilder: String?
    /// Whether the declaration has syntax errors, which make the scores unreliable.
    public let hasSyntaxErrors: Bool

    /// Creates scores. Fields are documented on their properties.
    public init(
        cognitive: Int,
        decisionCount: Int,
        swiftLintCompatible: Int,
        swiftLintScored: Bool,
        maxNesting: Int,
        resultBuilder: String?,
        hasSyntaxErrors: Bool
    ) {
        self.cognitive = cognitive
        self.decisionCount = decisionCount
        self.swiftLintCompatible = swiftLintCompatible
        self.swiftLintScored = swiftLintScored
        self.maxNesting = maxNesting
        self.resultBuilder = resultBuilder
        self.hasSyntaxErrors = hasSyntaxErrors
    }
}
