//
//  TestFacts.swift
//  SwiftStatsCore
//
//  What a test function's syntax says about it (PRD §7.8): its framework,
//  kind, cases, assertions and trials, and for a property test the base
//  names of the functions it calls (§7.11).
//

import SwiftSyntax

/// Facts about one test function.
struct TestFacts: Equatable {
    /// Names of calls that make a test a property test.
    static let propertyCalls: Set<String> = [
        "propertyCheck", "assertIdempotentProperty", "assertIdempotentEffectsProperty"
    ]
    /// The trials `propertyCheck` runs when it gives no `count:`.
    static let defaultTrials = 100

    let framework: TestFramework
    let kind: TestKind
    let cases: Int?
    let assertions: Int
    let trials: Int?
    /// The base names of the functions a property test calls; empty for
    /// any other kind.
    let callees: Set<String>

    /// The facts of `function`.
    init(_ function: FunctionDeclSyntax) {
        let test = AttributeFacts.testAttribute(in: function.attributes)
        let body = TestBodyScan(viewMode: .sourceAccurate)
        if let statements = function.body {
            body.walk(statements)
        }
        framework = test == nil ? .xctest : .swiftTesting
        let isParameterized = test.map(ParameterCases.isParameterized) ?? false
        if body.isProperty {
            kind = .property
        } else if body.isIdempotency {
            kind = .idempotency
        } else if isParameterized {
            kind = .parameterized
        } else {
            kind = .example
        }
        cases = kind == .parameterized ? test.flatMap(ParameterCases.count(in:)) : nil
        assertions = body.assertions
        trials = kind == .property && body.hasUnreadableTrials == false ? body.trials : nil
        callees = kind == .property ? body.callees : []
    }
}
