//
//  TestReferences.swift
//  SwiftStatsCore
//
//  What a test, or a test helper, writes (M5): in its body, its parameter
//  clause and its `@Test` arguments, the names a public function's link to
//  its tests is read from, a heuristic labelled as one. The paths of the
//  names it writes tell which types it names, and by what qualifier.
//  The members it reads link accessors. The calls, with their labels, link
//  functions and initialisers. Names are kept without the backticks an
//  escaped identifier is written with, and records' names are compared the
//  same way (`unescaped(_:)`).
//

/// The names one test or helper writes, reads as members and calls.
struct TestReferences: Equatable, Sendable {
    /// No references.
    static let empty = Self(paths: [], members: [], calls: [])

    /// The paths of the names written, their components joined by `.`:
    /// each identifier written alone (`x`, `f(…)`, `T`), each chain of
    /// names rooted in one (`a.b.c` gives `a.b` and `a.b.c`), and each type
    /// written (`A.B` gives `A` and `A.B`); generic arguments are dropped
    /// and operators are not names.
    let paths: Set<String>
    /// The names read as members: `x.name`, `.name`, `T.name`, each
    /// component of a key path (`\.name`, `\T.name`), and a member called
    /// with no argument labels (`x.name()`, `x.name(1)`), which may call the
    /// closure a property holds.
    let members: Set<String>
    /// The calls, and the unapplied references written with labels.
    let calls: Set<CallReference>

    /// `name` without the pair of backticks an escaped identifier is
    /// written with (`` `default` `` is `default`), as the references hold
    /// it.
    static func unescaped(_ name: String) -> String {
        let inner = name.dropFirst().dropLast()
        guard name.hasPrefix("`"), name.hasSuffix("`"), inner.isEmpty == false else {
            return name
        }
        return String(inner)
    }

    /// These references with each call of the enclosing type resolved to
    /// the type at `typePath`, its components (`CallReference.resolvingSelf(as:)`).
    func resolvingSelf(as typePath: [String]) -> Self {
        guard typePath.isEmpty == false else {
            return self
        }
        return Self(paths: paths, members: members, calls: Set(calls.map { $0.resolvingSelf(as: typePath) }))
    }

    /// These references and `other`'s.
    func union(_ other: Self) -> Self {
        Self(paths: paths.union(other.paths), members: members.union(other.members), calls: calls.union(other.calls))
    }
}
