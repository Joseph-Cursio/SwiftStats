//
//  CorpusEntry.swift
//  SwiftStatsCoreTests
//
//  A counterexample a property found, kept as a literal example. Seeds
//  replay only under the same generator code and standard library, so the
//  shrunk input itself is what the suite keeps: each entry is replayed by a
//  parameterized example calling the property's own check, and says which
//  defect it pins ("B1: a 17-digit timing traps"), which is also how the
//  test report names the case.
//

import Testing

/// A shrunk counterexample and the defect it pins.
struct CorpusEntry<Input: Sendable>: Sendable, CustomTestStringConvertible {
    /// The input, exactly as the property's check takes it.
    let input: Input
    /// The defect the input pins, as `Bn: what went wrong`.
    let pins: String

    /// The pinned defect, which names the case in a test report.
    var testDescription: String {
        pins
    }
}
