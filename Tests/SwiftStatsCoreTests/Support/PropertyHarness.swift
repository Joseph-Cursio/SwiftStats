import Foundation
@testable import SwiftStatsCore

/// A package with a library, a macro, an executable, a plugin and a test
/// target, and `swift-infer` index rows to feed a fake indexer, for the
/// SwiftInferProperties tests.
enum PropertyHarness {
    /// One algebraic row of an index; `location` may use `@ROOT@` for the
    /// directory the tool runs in.
    struct Row {
        /// The identity hash.
        var identity: String
        /// The location as the tool writes it.
        var location: String
        /// The template.
        var template = "idempotence"
        /// The function as the tool names it.
        var function = "doubled()"
        /// The score.
        var score = 80
        /// The tier as written.
        var tier = "Strong"
        /// The structural blocker, as JSON (`null` or a quoted string).
        var blocker = "null"
        /// Whether the subject is a computed property.
        var computed = false
        /// When the row was first seen.
        var seen = "2026-11-19T00:00:00Z"
        /// More fields, each as `, "key": value`.
        var extra = ""

        /// The row as JSON.
        var json: String {
            """
            {"identityHash": "\(identity)", "templateName": "\(template)", "primaryFunctionName": "\(function)",
             "location": "\(location)", "score": \(score), "tier": "\(tier)", "typeName": "Money",
             "qualifiedTypeName": "Money", "firstSeenAt": "\(seen)", "lastSeenAt": "\(seen)",
             "isComputedProperty": \(computed), "isInstanceMethod": true, "isMutatingMethod": false, "isNullary": true,
             "returnsSelfType": false, "parameterTypeNames": [], "structuralBlocker": \(blocker),
             "subjectFingerprint": null, "documentedRange": null, "secondaryMemberShape": null\(extra)}
            """
        }
    }

    /// The library's file. Line numbers matter: rows name them.
    static let values = """
    public struct Money {
        public var cents: Int

        public func doubled() -> Money {
            Money(cents: cents * 2)
        }

        public var isEmpty: Bool {
            cents == 0
        }

        public func encoded() -> String {
            String(cents)
        }

        public static func decoded(_ text: String) -> Money {
            Money(cents: Int(text) ?? 0)
        }

        private func secret(_ value: Int) -> Int {
            value
        }
    }

    public protocol Shape {
        func area() -> Double
    }

    func reduce(_ state: Int, _ action: Int) -> Int {
        state + action
    }
    """

    /// The test target's file; line 5 asserts a law.
    static let tests = """
    import Testing
    @testable import Core

    @Test func doubling() {
        #expect(Money(cents: 1).doubled().cents == 2)
    }
    """

    /// The package's files.
    static let files = [
        "Sources/Core/Values.swift": values,
        "Sources/Macros/Macro.swift": "func expand() -> Int {\n    1\n}\n",
        "Sources/Tool/main.swift": "print(\"hi\")\n",
        "Plugins/Plug/Plugin.swift": "func plugin() {}\n",
        "Tests/CoreTests/MoneyTests.swift": tests
    ]

    /// The package's targets, as SwiftPM would describe them.
    static let targets = [
        target("Core", "library", "Sources/Core", ["Values.swift"]),
        target("CoreTests", "test", "Tests/CoreTests", ["MoneyTests.swift"]),
        target("Macros", "macro", "Sources/Macros", ["Macro.swift"]),
        target("Plug", "plugin", "Plugins/Plug", ["Plugin.swift"]),
        target("Tool", "executable", "Sources/Tool", ["main.swift"])
    ]

    /// An index with no rows.
    static let emptyIndex = index([])

    /// A described Swift target.
    static func target(_ name: String, _ type: String, _ path: String, _ sources: [String]) -> DescribedTarget {
        DescribedTarget(name: name, type: type, moduleType: "SwiftTarget", path: path, sources: sources)
    }

    /// A schema-5 index holding `rows` and no interaction rows.
    static func index(_ rows: [Row]) -> String {
        index(rows, interactions: [], schemaVersion: SwiftInferIndex.schemaVersion)
    }

    /// An index with `schemaVersion` holding `rows` and the interaction
    /// rows `interactions`, each a JSON object.
    static func index(_ rows: [Row], interactions: [String], schemaVersion: Int) -> String {
        """
        {"entries": [\(rows.map(\.json).joined(separator: ","))],
         "interactionEntries": [\(interactions.joined(separator: ","))],
         "schemaVersion": \(schemaVersion), "sourceFileByTypeName": {}, "typeShapes": {},
         "updatedAt": "2026-11-19T00:00:00Z"}
        """
    }

    /// The package on disk, with `extra` files added.
    static func package(_ extra: [String: String]) throws -> TemporaryPackage {
        try TemporaryPackage(files.merging(extra) { _, new in new }, targets: targets)
    }

    /// A locator that finds `tool` as `swift-infer`.
    static func locator(_ tool: URL) -> ToolLocator {
        ToolLocator { $0 == "swift-infer" ? tool : nil }
    }

    /// The SwiftInferProperties collector's status in `report`.
    static func status(_ report: ScanReport) -> CollectorStatus? {
        report.collectors.first { $0.name == SwiftInferPropertiesAdapter.name }
    }

    /// Removes the fake tool at `tool` and its logs.
    static func remove(_ tool: URL) {
        try? FileManager.default.removeItem(at: tool.deletingLastPathComponent())
    }
}
