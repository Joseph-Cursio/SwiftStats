//
//  CoverageSamples.swift
//  SwiftStatsCoreTests
//
//  Hand-made coverage (M5) for the roll-up and store tests, written as the
//  scan JSON writes it: a package whose records take every shape a roll-up
//  tells apart, with coverage for them, and coverage covering every column
//  and list of the store's v4 tables.
//

import Foundation
@testable import SwiftStatsCore

/// Hand-made coverage reports.
enum CoverageSamples {
    /// A library with a sequence, a subscript with both accessors, a
    /// protocol extension member and an internal helper, a second library
    /// with a free function, and a test target.
    static let shapesFiles = [
        "Sources/Lib/Lib.swift": """
        public struct Bag: Sequence {
            public var items: [Int] = []

            public func makeIterator() -> IndexingIterator<[Int]> {
                items.makeIterator()
            }

            public func total() -> Int {
                items.reduce(0, +)
            }

            public subscript(index: Int) -> Int {
                get { items[index] }
                set { items[index] = newValue }
            }
        }

        public protocol Shape {}

        extension Shape {
            public func describe() -> String {
                "shape"
            }
        }

        func helper() -> Int {
            1
        }
        """,
        "Sources/Kit/Kit.swift": "public func kit() -> Int {\n    2\n}\n",
        "Tests/LibTests/LibTests.swift": "func testBag() {\n    _ = 1\n}\n"
    ]

    /// The package's targets.
    static let shapesTargets = [
        DescribedTarget(
            name: "Kit",
            type: "library",
            moduleType: "SwiftTarget",
            path: "Sources/Kit",
            sources: ["Kit.swift"]
        ),
        DescribedTarget(
            name: "Lib",
            type: "library",
            moduleType: "SwiftTarget",
            path: "Sources/Lib",
            sources: ["Lib.swift"]
        ),
        DescribedTarget(
            name: "LibTests",
            type: "test",
            moduleType: "SwiftTarget",
            path: "Tests/LibTests",
            sources: ["LibTests.swift"],
            targetDependencies: ["Lib"]
        )
    ]

    /// Coverage covering every nullable column and both kinds of list: a
    /// record with data, a record with none for a reason, a container, a
    /// witness, a saturated count in a run and an unmapped entry, an entry
    /// no name was demangled for, a partly run run, an empty file, skipped
    /// ranges, and unmapped entries out of their sorted order, which the
    /// report keeps. Records are in key order, as a scan gives them.
    private static let storedJSON = """
        {"records": [
           {"key": "Lib::Grid::subscript(_: Int) -> Int", "testTargets": []},
           {"key": "Lib::Ring::func makeIterator() -> Ring.Iterator", "lines": {"covered": 0, "total": 1},
            "regions": {"covered": 0, "total": 1}, "testTargets": [], "link": "witness"},
           {"key": "Lib::func one() -> Int", "lines": {"covered": 2, "total": 3}, "regions": {"covered": 1, "total": 2},
            "testTargets": ["ATests", "BTests"], "link": "function", "linkedTests": 4},
           {"key": "Lib::func two()", "testTargets": [], "reason": "no coverage data"},
           {"key": "Lib::func é()", "lines": {"covered": 1, "total": 1}, "regions": {"covered": 1, "total": 1},
            "testTargets": ["ATests"]}
         ],
         "attachments": [
           {"owner": "Sources/Lib/Lib.swift", "attachedTo": "file", "lines": {"covered": 0, "total": 1},
            "regions": {"covered": 0, "total": 2}},
           {"owner": "Lib::Grid @ Sources/Lib/Lib.swift", "attachedTo": "type", "lines": {"covered": 1, "total": 1},
            "regions": {"covered": 3, "total": 3}}
         ],
         "unmapped": [
           {"file": "Sources/Lib/Z.swift", "startLine": 9, "startColumn": 1, "endLine": 9, "endColumn": 20,
            "count": 9223372036854775807, "name": "$s3Lib1zyyF", "reason": "not parsed"},
           {"file": "Sources/Lib/A.swift", "startLine": 1, "startColumn": 1, "endLine": 2, "endColumn": 2, "count": 0,
            "name": "$s3Lib1ayyF", "demangled": "Lib.a() -> ()", "reason": "excluded"}
         ],
         "dropped": {"build": 10, "outsideRoot": 1, "testFiles": 28, "otherPackage": 2, "otherLanguage": 3},
         "bundles": ["ATests", "BTests"],
         "tests": "failing",
         "saturated": [{"file": "Sources/Lib/Lib.swift", "line": 5}],
         "files": [
           {"file": "Sources/Lib/Empty.swift", "lines": [], "skipped": []},
           {"file": "Sources/Lib/Lib.swift",
            "lines": [{"start": 1, "end": 3, "count": 5, "partlyRun": true},
                      {"start": 4, "end": 4, "count": 0, "partlyRun": false},
                      {"start": 5, "end": 6, "count": 9223372036854775807, "partlyRun": false}],
            "skipped": [{"start": 9, "end": 9}, {"start": 11, "end": 12}]}
         ]}
        """

    /// Coverage for the records of `shapesFiles`, `@name` standing for the
    /// key of the record named so (`@get`, `@set` and `@subscript` for the
    /// subscript's): a witness, a member, the subscript's getter with data
    /// and setter without, the subscript itself as a container, a protocol
    /// extension member, an internal helper that never ran and a free
    /// function in `Kit`; a type attachment in `Lib`, a file attachment in
    /// `Kit`, an unmapped entry, and line data with a partly run and a
    /// saturated run.
    private static let shapesJSON = """
        {"records": [
           {"key": "@makeIterator", "lines": {"covered": 1, "total": 1}, "regions": {"covered": 1, "total": 1},
            "testTargets": ["LibTests"], "link": "witness"},
           {"key": "@total", "lines": {"covered": 1, "total": 1}, "regions": {"covered": 2, "total": 3},
            "testTargets": ["LibTests"], "link": "member", "linkedTests": 3},
           {"key": "@get", "lines": {"covered": 1, "total": 1}, "regions": {"covered": 1, "total": 1},
            "testTargets": ["LibTests"], "link": "subscript", "linkedTests": 0},
           {"key": "@set", "testTargets": [], "reason": "no coverage data", "link": "subscript"},
           {"key": "@subscript", "testTargets": []},
           {"key": "@describe", "lines": {"covered": 1, "total": 1}, "regions": {"covered": 1, "total": 1},
            "testTargets": ["LibTests"], "link": "extension", "linkedTests": 1},
           {"key": "@helper", "lines": {"covered": 0, "total": 1}, "regions": {"covered": 0, "total": 1},
            "testTargets": []},
           {"key": "@kit", "lines": {"covered": 1, "total": 1}, "regions": {"covered": 1, "total": 1},
            "testTargets": ["LibTests"], "link": "function", "linkedTests": 2}
         ],
         "attachments": [
           {"owner": "Sources/Kit/Kit.swift", "attachedTo": "file", "lines": {"covered": 0, "total": 1},
            "regions": {"covered": 0, "total": 1}},
           {"owner": "Lib::Bag", "attachedTo": "type", "lines": {"covered": 1, "total": 1},
            "regions": {"covered": 2, "total": 2}}
         ],
         "unmapped": [
           {"file": "Sources/Lib/Lib.swift", "startLine": 2, "startColumn": 5, "endLine": 2, "endColumn": 9,
            "count": 1, "name": "$s3Lib1xvpfi", "reason": "macro or expansion region"}
         ],
         "dropped": {"build": 0, "outsideRoot": 0, "testFiles": 1, "otherPackage": 0, "otherLanguage": 0},
         "bundles": ["LibTests"],
         "tests": "passed",
         "saturated": [{"file": "Sources/Lib/Lib.swift", "line": 5}],
         "files": [
           {"file": "Sources/Kit/Kit.swift", "lines": [{"start": 1, "end": 1, "count": 0, "partlyRun": false}],
            "skipped": []},
           {"file": "Sources/Lib/Lib.swift",
            "lines": [{"start": 1, "end": 3, "count": 5, "partlyRun": true},
                      {"start": 4, "end": 4, "count": 0, "partlyRun": false},
                      {"start": 5, "end": 6, "count": 9223372036854775807, "partlyRun": false}],
            "skipped": [{"start": 9, "end": 9}]}
         ]}
        """

    /// `json` decoded as coverage.
    private static func decoded(_ json: String) throws -> CoverageReport {
        try JSONDecoder().decode(CoverageReport.self, from: Data(json.utf8))
    }

    /// The coverage for the store's columns.
    static func stored() throws -> CoverageReport {
        try decoded(storedJSON)
    }

    /// The coverage for `records`, the records of `shapesFiles` scanned.
    static func shapes(records: [FunctionRecord]) throws -> CoverageReport {
        var json = shapesJSON
        for record in records {
            let name = record.accessorKind ?? (record.kind == .subscriptDeclaration ? "subscript" : record.name)
            json = json.replacingOccurrences(of: "\"@\(name)\"", with: "\"\(record.key)\"")
        }
        return try decoded(json)
    }
}
