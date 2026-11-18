//
//  LineRatio.swift
//  SwiftStatsCore
//
//  The raw counts behind the test-to-code line ratio (PRD §7.8); the ratio
//  itself is worked out at report time (D6).
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
    /// Whether dead code is left out of `productionLines`; false until
    /// Periphery runs (M7).
    public let deadCodeExcluded: Bool

    /// Creates a ratio. Fields are documented on their properties.
    public init(testLines: Int, testLinesByKind: [String: Int], productionLines: Int, deadCodeExcluded: Bool) {
        self.testLines = testLines
        self.testLinesByKind = testLinesByKind
        self.productionLines = productionLines
        self.deadCodeExcluded = deadCodeExcluded
    }
}
