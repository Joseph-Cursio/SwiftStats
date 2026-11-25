//
//  PeripheryTestTargetTests.swift
//  SwiftStatsCoreTests
//
//  Which outskirts entries are test code (M7, design §5.3, as built): the
//  target the scan reads an entry's file in decides, since test targets
//  come from Package.swift, never from folders. A production target whose
//  files lie in a test target's directory (shared through `sources:`, or
//  a `TestSupport` target beside a test target at `Tests`) stays
//  production; only a file the scan didn't parse falls back to the test
//  directory or modules reading.
//

import Foundation
@testable import SwiftStatsCore
import Testing

/// The `test` class of outskirts entries in shared directories.
@Suite("outskirts test targets")
struct PeripheryTestTargetTests {
    /// A package root that doesn't exist, so paths stay as written.
    private static let root = "/NoSuchPeripheryTestTargets"

    /// A context for a package at `root` described as `targets`, each
    /// file of `files` scanned in its target.
    private static func context(targets: [DescribedTarget], files: [String: String]) throws -> PeripheryOutput.Context {
        let package = DescribedPackage(name: "Probe", targets: targets)
        return PeripheryOutput.Context(
            root: root,
            scratch: root + "/.swiftstats/index-build",
            package: package,
            modules: try BuildSession.moduleMap(of: package),
            files: files,
            changedFiles: [],
            records: [],
            localUSRs: []
        )
    }

    /// The classes of entries at `places` (a path in the package and the
    /// entry's modules), decoded with `context`.
    private static func classes(
        _ places: [(String, [String])],
        context: PeripheryOutput.Context
    ) throws -> [PeripheryEntryClass] {
        let objects: [[String: Any]] = places.map { path, modules in
            [
                "accessibility": "internal", "attributes": [String](), "hints": ["unused"], "ids": ["s:probe"],
                "kind": "function.free", "location": root + "/" + path + ":1:6", "modifiers": [String](),
                "modules": modules, "name": "f()"
            ]
        }
        let data = try JSONSerialization.data(withJSONObject: objects)
        return try PeripheryOutput.decode(data, run: .production, context: context).map(\.entryClass)
    }

    /// A target `name` of `type` at `path` with `sources`.
    private static func target(_ name: String, _ type: String, path: String, sources: [String]) -> DescribedTarget {
        DescribedTarget(name: name, type: type, moduleType: "SwiftTarget", path: path, sources: sources)
    }

    @Test("a test target sharing a production target's directory through sources: leaves its files production")
    func sharedThroughSources() throws {
        let context = try Self.context(
            targets: [
                Self.target("Kit", "library", path: "Sources/Kits", sources: ["Relay.swift"]),
                Self.target("KitTests", "test", path: "Sources/Kits", sources: ["KitTests.swift"])
            ],
            files: ["Sources/Kits/Relay.swift": "Kit", "Sources/Kits/KitTests.swift": "KitTests"]
        )

        let classes = try Self.classes(
            [
                ("Sources/Kits/Relay.swift", ["Kit"]),
                ("Sources/Kits/KitTests.swift", ["KitTests"]),
                ("Sources/Kits/Unparsed.swift", ["Kit"])
            ],
            context: context
        )

        #expect(classes == [.production, .test, .test])
    }

    @Test("a TestSupport target beside a test target at Tests stays production; the tests stay test")
    func testSupportBesideTests() throws {
        let context = try Self.context(
            targets: [
                Self.target("TestSupport", "library", path: "Tests/TestSupport", sources: ["Helpers.swift"]),
                Self.target("AppTests", "test", path: "Tests", sources: ["AppTests/AppTests.swift"])
            ],
            files: ["Tests/TestSupport/Helpers.swift": "TestSupport", "Tests/AppTests/AppTests.swift": "AppTests"]
        )

        let classes = try Self.classes(
            [
                ("Tests/TestSupport/Helpers.swift", ["TestSupport"]),
                ("Tests/AppTests/AppTests.swift", ["AppTests"]),
                ("Sources/Gone.swift", ["AppTests"]),
                ("Sources/Gone.swift", ["TestSupport"])
            ],
            context: context
        )

        #expect(classes == [.production, .test, .test, .unscanned])
    }
}
