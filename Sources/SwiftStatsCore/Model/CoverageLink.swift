//
//  CoverageLink.swift
//  SwiftStatsCore
//
//  How the tests of a public function are found (M5, PRD §7.8 tests per
//  public function), a heuristic labelled as one: a test counts when its
//  target's own test process ran the function and its body names it, by
//  the rule of the function's kind. Operators are never names.
//

/// The link rule a public function's tests are counted by.
public enum CoverageLink: String, Codable, CaseIterable, Sendable {
    /// A subscript or a subscript's accessor, whose name no body writes:
    /// the body names the type, or the test's file is named for the
    /// subscript's file or type.
    case `subscript`
    /// A member of a protocol extension: the body names it, the weaker rule,
    /// so these are counted apart; for an initialiser or a subscript, whose
    /// names no body writes, the body names the protocol, or the test's
    /// file is named for the member's file or protocol.
    case extensionMember = "extension"
    /// A free function: the body names it.
    case function
    /// A member of a concrete type (a function, an accessor, an
    /// initialiser): the body names the member (its property's name for an
    /// accessor, a call of the type for an initialiser) and the type's
    /// simple name, or the test's file is named for the member's file or
    /// type (`TestNameMatcher`).
    case member
    /// A member witnessing a requirement of a standard protocol the type
    /// declares a conformance to (decided from syntax), which tests reach
    /// generically: neither linked nor unlinked, so no tests are counted.
    case witness
}
