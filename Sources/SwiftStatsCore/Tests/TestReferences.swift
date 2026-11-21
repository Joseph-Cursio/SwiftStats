//
//  TestReferences.swift
//  SwiftStatsCore
//
//  What a test names (M5): in its body, its parameter clause and its
//  `@Test` arguments, the names a public function's link to its tests is
//  read from, a heuristic labelled as one. Names are kept without the
//  backticks an escaped identifier is written with, and records' names are
//  compared the same way (`unescaped(_:)`).
//

/// The names one test refers to and the names it calls.
struct TestReferences: Equatable {
    /// Each identifier read, called or reached as a member, and each type
    /// named; operators excluded.
    let names: Set<String>
    /// Each callee's base name, `T` for `T.init(…)` and `T<U>.init(…)`, and
    /// the annotated type an implicit `.init(…)` initialises; operators
    /// excluded.
    let calls: Set<String>

    /// `name` without the pair of backticks an escaped identifier is
    /// written with (`` `default` `` is `default`), as `names` and `calls`
    /// hold it.
    static func unescaped(_ name: String) -> String {
        let inner = name.dropFirst().dropLast()
        guard name.hasPrefix("`"), name.hasSuffix("`"), inner.isEmpty == false else {
            return name
        }
        return String(inner)
    }
}
