//
//  LawReport.swift
//  SwiftStatsCore
//
//  What law detection found (PRD §7.11): every production pair the kit
//  covers with its state, and the counts that explain what couldn't be
//  attached. Always present from scan schema 6: it is a `swiftstats`
//  measurement, collected on every scan.
//

/// Law checks per production conformance.
public struct LawReport: Codable, Hashable, Sendable {
    /// The pairs, sorted by type, then protocol.
    public let checks: [LawCheck]
    /// Protocol checks in test targets whose subject can't be named: no
    /// `for: X.self`, `X.gen()` or `X.gen` argument, or a generic parameter.
    public let unresolvedCalls: Int
    /// Type names written in checks or suppression markers that more than
    /// one package type could be, sorted; such checks attach to none.
    public let ambiguousNames: [String]
    /// Distinct (type, protocol) pairs that only test-target extensions of
    /// production types declare, such as SwiftInferProperties' refactor
    /// writeouts; they make no pairs.
    public let testOnlyConformances: Int
    /// Whether the package depends on SwiftPropertyLaws: a
    /// `swiftpropertylaws` pin in `Package.resolved` or dependency in
    /// `Package.swift`.
    public let kitDependency: Bool

    /// Creates a report. Fields are documented on their properties.
    public init(
        checks: [LawCheck],
        unresolvedCalls: Int,
        ambiguousNames: [String],
        testOnlyConformances: Int,
        kitDependency: Bool
    ) {
        self.checks = checks
        self.unresolvedCalls = unresolvedCalls
        self.ambiguousNames = ambiguousNames
        self.testOnlyConformances = testOnlyConformances
        self.kitDependency = kitDependency
    }

    /// This report with `kitDependency` set.
    func with(kitDependency: Bool) -> Self {
        Self(
            checks: checks,
            unresolvedCalls: unresolvedCalls,
            ambiguousNames: ambiguousNames,
            testOnlyConformances: testOnlyConformances,
            kitDependency: kitDependency
        )
    }
}
