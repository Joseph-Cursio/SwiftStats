//
//  PeripheryPlace.swift
//  SwiftStatsCoreTests
//
//  P9.4's input: a sound location and a hint, and the outskirts entry that
//  holds them beside sound values of the other seven keys, written as a
//  run's JSON array of that one entry. A failure report shows the location
//  and the hint as they are written, and what each should read as, in
//  ASCII (`PBTTrace.ascii`).
//

import Foundation
import Testing

/// A location and a hint, and the entry holding them.
struct PeripheryPlace: Sendable, CustomTestStringConvertible {
    /// The location; never flawed.
    let location: LocationDraft
    /// The hint.
    let hint: HintDraft

    /// The entry holding the location and the hint.
    var entry: JSONText {
        .object([
            JSONText.Member(key: "accessibility", value: .string("internal")),
            JSONText.Member(key: "attributes", value: .array([])),
            JSONText.Member(key: "hints", value: .array([.string(hint.rendered)])),
            JSONText.Member(key: "ids", value: .array([.string("s:9IndexCore1fyyF")])),
            JSONText.Member(key: "kind", value: .string("function.free")),
            JSONText.Member(key: "location", value: .string(location.rendered)),
            JSONText.Member(key: "modifiers", value: .array([])),
            JSONText.Member(key: "modules", value: .array([.string("IndexCore")])),
            JSONText.Member(key: "name", value: .string("f()"))
        ])
    }

    /// The run's output: an array of the one entry.
    var data: Data {
        PeripheryEntryDraft.data(of: entry)
    }

    /// The location and the hint, each as written and as it should read.
    var testDescription: String {
        let expected = hint.expected
        let split = expected.text.map { "name \(expected.name.debugDescription), text \($0.debugDescription)" }
            ?? "whole"
        return PBTTrace.ascii(
            "location \(location.rendered.debugDescription) (path \(location.path.debugDescription), "
                + "line \(location.line), column \(location.column)); "
                + "hint \(hint.rendered.debugDescription) (\(split))"
        )
    }
}
