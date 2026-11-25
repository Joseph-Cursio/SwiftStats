//
//  TestSummary.swift
//  SwiftStatsCore
//
//  A roll-up's test inventory (PRD §7.8).
//

/// Tests by framework and kind, with assertions, helpers and the line ratio.
public struct TestSummary: Codable, Hashable, Sendable {
    /// Tests in the roll-up's modules, generated ones left out, by framework
    /// (`swiftTesting`, `xctest`), then kind.
    public let tests: [String: [String: Int]]
    /// Tests in generated files, counted apart from `tests`.
    public let generatedTests: Int
    /// Functions in test targets that aren't tests.
    public let helpers: Int
    /// Cases of the parameterized tests whose case count is known.
    public let parameterizedCases: Int
    /// Parameterized tests whose case count can't be read from the source.
    public let parameterizedUnknownCases: Int
    /// Assertions in each test, generated ones left out.
    public let assertionsPerTest: Distribution
    /// XCTest tests with no `XCTAssert…` call.
    public let xctestWithoutAssertions: Int
    /// Swift Testing tests SwiftProjectLint's `testMissingAssertion` names;
    /// nil when it didn't run.
    public let swiftTestingWithoutAssertions: Int?
    /// The counts behind the test-to-code line ratio.
    public internal(set) var lineRatio: LineRatio

    /// Creates a summary. Fields are documented on their properties.
    public init(
        tests: [String: [String: Int]],
        generatedTests: Int,
        helpers: Int,
        parameterizedCases: Int,
        parameterizedUnknownCases: Int,
        assertionsPerTest: Distribution,
        xctestWithoutAssertions: Int,
        swiftTestingWithoutAssertions: Int?,
        lineRatio: LineRatio
    ) {
        self.tests = tests
        self.generatedTests = generatedTests
        self.helpers = helpers
        self.parameterizedCases = parameterizedCases
        self.parameterizedUnknownCases = parameterizedUnknownCases
        self.assertionsPerTest = assertionsPerTest
        self.xctestWithoutAssertions = xctestWithoutAssertions
        self.swiftTestingWithoutAssertions = swiftTestingWithoutAssertions
        self.lineRatio = lineRatio
    }
}
