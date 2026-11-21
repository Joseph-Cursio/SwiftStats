//
//  CoverageLink.swift
//  SwiftStatsCore
//
//  How the tests of a public function are found (M5, PRD §7.8 tests per
//  public function), a heuristic labelled as one: a test counts when its
//  target's own test process ran the function and the test writes it (in
//  its body, its parameters, its `@Test` arguments or a test helper it
//  calls), by the rule of the function's kind: a call whose labels fit a
//  function or initialiser, a member read of an accessor's property
//  (`CoverageTestLinks`). A test the coverage run skipped never counts.
//  Operators are never names.
//

/// The link rule a public function's tests are counted by.
public enum CoverageLink: String, Codable, CaseIterable, Sendable {
    /// A subscript or a subscript's accessor, whose name no body writes:
    /// the body names the type, or the test's file is named for the
    /// subscript's file or type.
    case `subscript`
    /// A member of a protocol extension: the test calls it with fitting
    /// labels or reads it as a member, with no type named, the weaker rule,
    /// so these are counted apart; for an initialiser or a subscript, whose
    /// names no body writes, the body names the protocol, or the test's
    /// file is named for the member's file or protocol.
    case extensionMember = "extension"
    /// A free function: the test calls it with fitting labels, bare or
    /// qualified by its module; a free variable's accessor: the test reads
    /// it.
    case function
    /// A member of a concrete type (a function, an accessor, an
    /// initialiser): the body calls the member with fitting labels, reads
    /// its property as a member for an accessor, or calls the type for an
    /// initialiser; and names the type, unqualified or qualified by a
    /// suffix of its module and parents, or the test's file is named for the
    /// member's file or type (`TestNameMatcher`).
    case member
    /// A member witnessing a requirement of a standard protocol the type
    /// declares a conformance to (decided from syntax), which tests reach
    /// generically: neither linked nor unlinked, so no tests are counted.
    case witness
}
