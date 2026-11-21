//
//  TestFacts.swift
//  SwiftStatsCore
//
//  What a test function's syntax says about it (PRD §7.8): its framework,
//  kind, cases, assertions and trials, for a property test the base
//  names of the functions it calls (§7.11), and for every test the names
//  it refers to (M5): its body's, its parameters' types and its `@Test`
//  `arguments:` collections', where a parameterized test often names its
//  subject; the display name and traits are not read.
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
    /// The names the body, the parameter clause and the `@Test`
    /// `arguments:` collections refer to and call, for every kind.
    let references: TestReferences

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
        // Only names: a parameter's default or a `@Test` argument is no
        // assertion and makes no property test. Only the `arguments:`
        // collections: a trait such as `.timeLimit(.minutes(1))` names no
        // subject.
        let declaration = TestBodyScan(viewMode: .sourceAccurate)
        declaration.walk(function.signature.parameterClause)
        for collection in test.map(ParameterCases.collections(in:)) ?? [] {
            declaration.walk(collection)
        }
        references = TestReferences(
            names: body.names.union(declaration.names),
            calls: body.calls.union(declaration.calls)
        )
    }
}
