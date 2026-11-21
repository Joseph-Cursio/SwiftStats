//
//  TestReferences.swift
//  SwiftStatsCore
//
//  What a test's body names (M5): the names a public function's link to
//  its tests is read from, a heuristic labelled as one.
//

/// The names one test's body refers to and the names it calls.
struct TestReferences: Equatable {
    /// Each identifier read, called or reached as a member, and each type
    /// named; operators excluded.
    let names: Set<String>
    /// Each callee's base name, and `T` for `T.init(…)` and `T<U>.init(…)`;
    /// operators excluded.
    let calls: Set<String>
}
