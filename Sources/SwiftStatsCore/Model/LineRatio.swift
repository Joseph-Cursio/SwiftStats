//
//  LineRatio.swift
//  SwiftStatsCore
//
//  The raw counts behind the test-to-code line ratio (PRD §7.8), with the
//  dead lines outskirts finds once the `periphery` collector ran (M7); the
//  ratio itself is worked out at report time (D6).
//

/// Test and production stripped lines for a roll-up.
public struct LineRatio: Codable, Hashable, Sendable {
    /// Stripped lines of the tests counted, helpers and generated tests left
    /// out. For a production module, the tests in test targets that depend
    /// on it; for a test target or the project, its own tests.
    public let testLines: Int
    /// `testLines` by test kind.
    public let testLinesByKind: [String: Int]
    /// Stripped lines of the production files measured against: the
    /// module's own; for a test target, the production targets it depends
    /// on; for the project, every production file.
    public let productionLines: Int
    /// Whether the dead lines of the production files measured against
    /// are known (`deadLines`): true exactly when the `periphery` collector
    /// ran (M7, design §7).
    public internal(set) var deadCodeExcluded: Bool
    /// The stripped lines of the production files measured against that
    /// outskirts' `roots` run finds dead, summed over the maximal covered
    /// units (M7, design §5.4, §7), for the ratio with dead code left out:
    /// `testLines / (productionLines - deadLines)`; nil when the
    /// `periphery` collector didn't run.
    public internal(set) var deadLines: Int?

    /// Creates a ratio. Fields are documented on their properties.
    public init(
        testLines: Int,
        testLinesByKind: [String: Int],
        productionLines: Int,
        deadCodeExcluded: Bool,
        deadLines: Int?
    ) {
        self.testLines = testLines
        self.testLinesByKind = testLinesByKind
        self.productionLines = productionLines
        self.deadCodeExcluded = deadCodeExcluded
        self.deadLines = deadLines
    }

    /// The ratio with `deadLines` as its dead lines, dead code excluded
    /// exactly when they are known.
    func with(deadLines: Int?) -> Self {
        var ratio = self
        ratio.deadLines = deadLines
        ratio.deadCodeExcluded = deadLines != nil
        return ratio
    }
}
