//
//  TestKind.swift
//  SwiftStatsCore
//
//  What kind of test a test is (PRD §7.8). When a test is more than one
//  kind, the first that applies wins: property, idempotency,
//  parameterized, example.
//

/// A test's kind.
public enum TestKind: String, Codable, CaseIterable, Sendable {
    /// One example, checked once.
    case example
    /// Calls SwiftIdempotency's `#assertIdempotent` or `assertIdempotentEffects`.
    case idempotency
    /// A Swift Testing test with `arguments:`, run once per case.
    case parameterized
    /// Checks a property over generated inputs (`propertyCheck`, a
    /// `check…PropertyLaws` call, SwiftInferProperties' backend, or a
    /// wrapper built on them).
    case property
}
