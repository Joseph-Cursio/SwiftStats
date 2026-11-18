//
//  TestFramework.swift
//  SwiftStatsCore
//
//  Which framework a test is written for (PRD §7.8).
//

/// A test's framework.
public enum TestFramework: String, Codable, CaseIterable, Sendable {
    /// A Swift Testing `@Test` function.
    case swiftTesting = "swift-testing"
    /// An XCTest `test…` method on an `XCTestCase` subclass.
    case xctest
}
