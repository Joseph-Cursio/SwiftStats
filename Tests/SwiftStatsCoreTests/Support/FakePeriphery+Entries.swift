//
//  FakePeriphery+Entries.swift
//  SwiftStatsCoreTests
//
//  A fake outskirts' scenario with a run's entries edited, for the
//  dead-code mapping's tests (M7, design §5.4): entries added that the
//  recordings don't hold (an unused enclosing function, an extension of a
//  type the package doesn't declare), removed, or put in another order.
//

import Foundation
@testable import SwiftStatsCore

extension FakePeriphery {
    /// An unused entry of outskirts' `kind`, `name` and `ids` at
    /// `location`, a path in the package (`@ROOT@` put before it), in
    /// module `IndexCore`, as outskirts writes one.
    static func unusedEntry(kind: String, name: String, ids: [String], location: String) -> [String: Any] {
        [
            "accessibility": "internal",
            "attributes": [String](),
            "hints": ["unused"],
            "ids": ids,
            "kind": kind,
            "location": IndexFixture.rootToken + "/" + location,
            "modifiers": [String](),
            "modules": ["IndexCore"],
            "name": name
        ]
    }

    /// `scenario` with `run`'s entries replaced by what `change` makes of
    /// them, in outskirts' order.
    static func editing(
        _ scenario: Scenario,
        _ run: PeripheryCommand.Run,
        _ change: ([[String: Any]]) -> [[String: Any]]
    ) throws -> Scenario {
        var edited = scenario
        let data = Data((scenario.outputs[run] ?? "[]").utf8)
        guard let entries = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw IndexFixtureScanError(description: "the \(run.rawValue) run's output isn't an array of objects")
        }
        let written = try JSONSerialization.data(
            withJSONObject: change(entries),
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        edited.outputs[run] = String(bytes: written, encoding: .utf8) ?? "[]"
        return edited
    }
}
