//
//  TestRecord.swift
//  SwiftStatsCore
//
//  One test in the inventory (PRD §7.8).
//

/// A test: its record, framework, kind and what it checks.
public struct TestRecord: Codable, Hashable, Sendable {
    /// The test's function record key.
    public let key: String
    /// The test target.
    public let module: String
    /// Path relative to the package root.
    public let file: String
    /// Swift Testing or XCTest.
    public let framework: TestFramework
    /// Example, property, idempotency or parameterized.
    public let kind: TestKind
    /// For a parameterized test, the number of cases when the arguments
    /// are literal (arrays, dictionaries, integer ranges, `zip` of them);
    /// nil otherwise.
    public let cases: Int?
    /// `#expect`, `#require` and `XCTAssert…` calls in the body.
    public let assertions: Int
    /// For a property test, the trials its `propertyCheck` calls run
    /// (`count:`, default 100); nil when it makes none, or one whose
    /// `count:` isn't a literal.
    public let trials: Int?
    /// Whether the test is in a generated file (PRD D8).
    public let generated: Bool

    /// Creates a record. Fields are documented on their properties.
    public init(
        key: String,
        module: String,
        file: String,
        framework: TestFramework,
        kind: TestKind,
        cases: Int?,
        assertions: Int,
        trials: Int?,
        generated: Bool
    ) {
        self.key = key
        self.module = module
        self.file = file
        self.framework = framework
        self.kind = kind
        self.cases = cases
        self.assertions = assertions
        self.trials = trials
        self.generated = generated
    }
}
