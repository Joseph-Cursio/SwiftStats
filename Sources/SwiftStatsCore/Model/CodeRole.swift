//
//  CodeRole.swift
//  SwiftStatsCore
//
//  Whether a record is production code, a test, or test-target code that is
//  not itself a test (PRD §7.8). Test targets come from `Package.swift`, never
//  from file names or folders.
//

/// The role a record plays in the package.
public enum CodeRole: String, Codable, CaseIterable, Sendable {
    /// Code in a test target that is not itself a test: fixtures, mocks,
    /// builders, utilities.
    case helper
    /// Code in any non-test target.
    case production
    /// A Swift Testing `@Test` function, or an XCTest `test…` method on an
    /// `XCTestCase` subclass.
    case test
}
