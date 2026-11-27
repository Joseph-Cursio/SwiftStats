//
//  Pick.swift
//  SwiftStatsCoreTests
//
//  Draws an element of a fixed list by its index, so the engine shrinks a
//  failing draw toward the list's first element. The engine's own
//  `Gen.element(of:)` doesn't shrink at all, and returns an optional.
//  Lists are ordered simplest first, so a shrunk counterexample shows the
//  plainest fragment that still fails.
//

import PropertyBased

/// Draws elements of fixed lists, shrinking toward the first.
enum Pick {
    /// An element of `values`, which must not be empty, drawn by index so
    /// it shrinks toward the first.
    static func element<Value: Sendable>(of values: [Value]) -> Generator<Value, Shrink.Integer<Int>> {
        Gen<Int>.value(in: values.indices).map { values[$0] }
    }
}
