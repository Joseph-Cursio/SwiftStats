//
//  TypeCheckTotals+Given.swift
//  SwiftStatsCoreTests
//
//  Hand-made type-check totals (M7, design §6.4), each scope's total as a
//  test writes it, for the roll-ups built from hand-made build results,
//  whose entries' hundredths no test has; and the totals a report's
//  roll-ups already hold, for a test attaching that report's build again.
//

import Foundation
@testable import SwiftStatsCore

extension TypeCheckTotals {
    /// The totals `rollups` hold, for a test attaching the build of the
    /// report they come from again.
    init(rollups: [Rollup]) {
        let held = rollups.compactMap { rollup in
            rollup.typecheck.map { (Scope(scope: rollup.scope, name: rollup.name), $0.milliseconds.total) }
        }
        self.init(milliseconds: Dictionary(held) { first, _ in first })
    }

    /// The totals `json` gives: an object whose keys are a scope and a
    /// name (`"module Lib"`, `"project production"`) and whose values
    /// are whole milliseconds. A key naming no scope is left out.
    static func given(_ json: String) throws -> Self {
        let figures = try JSONDecoder().decode([String: Int].self, from: Data(json.utf8))
        let scoped = figures.compactMap { key, total -> (Scope, Int)? in
            guard let space = key.firstIndex(of: " "), let scope = RollupScope(rawValue: String(key[..<space])) else {
                return nil
            }
            return (Scope(scope: scope, name: String(key[key.index(after: space)...])), total)
        }
        return Self(milliseconds: Dictionary(scoped) { first, _ in first })
    }
}
