//
//  OutskirtsEdgeDraft.swift
//  SwiftStatsCoreTests
//
//  P15.1's dead-code input: an outskirts run of two unused free functions
//  of the target `Lib`, each in the scanned file without a byte order
//  mark, located at a line and a column that are integer edges, written
//  in decimal as outskirts writes them (`path:line:column`). The path is
//  under a root that doesn't exist, so making it real touches nothing on
//  disk.
//

import Foundation
import Testing

/// An outskirts run whose locations are integer edges.
struct OutskirtsEdgeDraft: Sendable, CustomTestStringConvertible {
    /// An entry's location.
    struct Location: Hashable, Sendable {
        /// Its 1-based line.
        let line: Int
        /// Its 1-based UTF-8 column.
        let column: Int
    }

    /// How many entries a run has.
    static let entryCount = 2

    /// The entries' locations, in the run's order.
    let locations: [Location]

    /// Each entry's line and column.
    var testDescription: String {
        "entries at " + locations.map { "\($0.line):\($0.column)" }.joined(separator: ", ")
    }

    /// The run's JSON, its paths under `root`.
    func data(root: String) throws -> Data {
        let entries: [[String: Any]] = locations.map { location in
            [
                "accessibility": "internal", "attributes": [String](), "hints": ["unused"], "ids": ["s:3Lib5firstSiyF"],
                "kind": "function.free",
                "location": "\(root)/\(IntegerEdgeGen.plainFile):\(location.line):\(location.column)",
                "modifiers": [String](), "modules": ["Lib"], "name": "first()"
            ]
        }
        return try JSONSerialization.data(withJSONObject: entries, options: [.sortedKeys])
    }
}
