//
//  RiskyFixture.swift
//  SwiftStatsCoreTests
//
//  The Risky fixture (M5, risky + untested) copied to a temporary package
//  and scanned with `--coverage` through a `FakeToolchain` serving the
//  real tools' recorded output (`Tests/Fixtures/Risky/Recorded`, made by
//  `Scripts/record-coverage-fixture.sh <work directory> Risky`), and with a
//  fake SwiftProjectLint reporting a marker at each risky line, found by
//  its text, so the signal is computed from a real coverage run without
//  building or running anything. SwiftStats' own implicitly unwrapped
//  optional markers are its real ones. One file is generated, by the
//  default `*.generated.swift` glob.
//

import Foundation
@testable import SwiftStatsCore

/// Scans the Risky fixture with recorded coverage and fake SwiftProjectLint findings.
enum RiskyFixture {
    /// One SwiftProjectLint finding: its rule, its file, and the line
    /// holding `text` after the first holding `after`.
    struct Marker {
        /// The rule.
        let rule: String
        /// The file, relative to the package root.
        let file: String
        /// Text on the finding's line.
        let text: String
        /// Text on a line before it, narrowing the search; empty for none.
        let after: String
    }

    /// The fixture's directory.
    static let directory = FakeToolchain.recordedDirectory
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Risky")

    /// The fixture's files, relative to its root.
    static let files = [
        "Sources/Orphan/Orphan.swift", "Sources/Risky/Crash.swift", "Sources/Risky/Globals.swift",
        "Sources/Risky/Race.swift", "Sources/Risky/Stubs.generated.swift", "Tests/RiskyTests/Support.swift",
        "Tests/RiskyTests/Unit/RiskyTests.swift"
    ]

    /// The fixture's targets, as `swift package describe` lists them.
    static let targets = [
        DescribedTarget(
            name: "Orphan",
            type: "library",
            moduleType: "SwiftTarget",
            path: "Sources/Orphan",
            sources: ["Orphan.swift"]
        ),
        DescribedTarget(
            name: "Risky",
            type: "library",
            moduleType: "SwiftTarget",
            path: "Sources/Risky",
            sources: ["Crash.swift", "Globals.swift", "Race.swift", "Stubs.generated.swift"]
        ),
        DescribedTarget(
            name: "RiskyTests",
            type: "test",
            moduleType: "SwiftTarget",
            path: "Tests/RiskyTests",
            sources: ["Support.swift", "Unit/RiskyTests.swift"],
            targetDependencies: ["Risky"]
        )
    ]

    /// SwiftProjectLint's markers in the fixture: every force unwrap,
    /// `try!`, `as!`, `@unchecked Sendable` and `nonisolated(unsafe)`, the
    /// two force unwraps on one line as two findings, a trap the signal
    /// leaves out, a force unwrap and a file's `nonisolated(unsafe)` global
    /// in test code, and a function's, a type's and a file's marker in the
    /// generated file.
    static let markers = [
        Marker(rule: "forceUnwrap", file: crash, text: "value!", after: "func unwrapped"),
        Marker(rule: "forceUnwrap", file: crash, text: "value!", after: "func neverRun("),
        Marker(rule: "forceUnwrap", file: crash, text: "other!", after: "func fallback"),
        Marker(rule: "forceUnwrap", file: crash, text: "value!", after: "func branch"),
        Marker(rule: "forceUnwrap", file: crash, text: "value!", after: "func inactive"),
        Marker(rule: "forceUnwrap", file: crash, text: "other!", after: "func outer"),
        Marker(rule: "forceUnwrap", file: crash, text: "first!", after: "func pair"),
        Marker(rule: "forceUnwrap", file: crash, text: "second!", after: "func pair"),
        Marker(rule: "unconditionalTrap", file: crash, text: "fatalError", after: ""),
        Marker(rule: "forceUnwrap", file: crash, text: "first!", after: "func twice"),
        Marker(rule: "forceUnwrap", file: crash, text: "second!", after: "func twice"),
        Marker(rule: "forceUnwrap", file: crash, text: "let base = value!", after: "func mixed"),
        Marker(rule: "forceUnwrap", file: crash, text: "base + value!", after: "func mixed"),
        Marker(rule: "forceCast", file: crash, text: "as! Int", after: "func cast"),
        Marker(rule: "uncheckedSendable", file: race, text: "class Worked", after: ""),
        Marker(rule: "uncheckedSendable", file: race, text: "class OnlyBuilt", after: ""),
        Marker(rule: "uncheckedSendable", file: race, text: "class Untouched", after: ""),
        Marker(rule: "uncheckedSendable", file: race, text: "class Bare", after: ""),
        Marker(rule: "uncheckedSendable", file: race, text: "class Boxed", after: ""),
        Marker(rule: "uncheckedSendable", file: race, text: "class Released", after: ""),
        Marker(rule: "nonisolatedUnsafe", file: race, text: "nonisolated(unsafe)", after: ""),
        Marker(rule: "forceTry", file: race, text: "try!", after: "struct Settings"),
        Marker(rule: "forceTry", file: race, text: "try!", after: "struct UnbuiltSettings"),
        Marker(rule: "nonisolatedUnsafe", file: globals, text: "nonisolated(unsafe)", after: ""),
        Marker(rule: "forceTry", file: globals, text: "try!", after: ""),
        Marker(rule: "nonisolatedUnsafe", file: generated, text: "nonisolated(unsafe)", after: ""),
        Marker(rule: "uncheckedSendable", file: generated, text: "class GeneratedWorker", after: ""),
        Marker(rule: "forceUnwrap", file: generated, text: "value!", after: ""),
        Marker(rule: "forceUnwrap", file: "Sources/Orphan/Orphan.swift", text: "value!", after: ""),
        Marker(rule: "forceUnwrap", file: "Tests/RiskyTests/Unit/RiskyTests.swift", text: "Worked()", after: ""),
        Marker(rule: "nonisolatedUnsafe", file: support, text: "nonisolated(unsafe)", after: "")
    ]

    /// The file of the crash cases.
    static let crash = "Sources/Risky/Crash.swift"
    /// The file of the race cases.
    static let race = "Sources/Risky/Race.swift"
    /// The file of the globals.
    static let globals = "Sources/Risky/Globals.swift"
    /// The generated file.
    static let generated = "Sources/Risky/Stubs.generated.swift"
    /// The test file holding no function.
    static let support = "Tests/RiskyTests/Support.swift"

    /// The text of the fixture's file at `path`.
    static func source(_ path: String) throws -> String {
        try String(contentsOf: directory.appendingPathComponent(path), encoding: .utf8)
    }

    /// The line `marker` names.
    static func line(of marker: Marker) throws -> Int {
        SignalHarness.line(of: marker.text, after: marker.after, in: try source(marker.file))
    }

    /// The fixture scanned with coverage and the fake SwiftProjectLint as
    /// a snapshot of a clean tree, stored in a new store and read back.
    static func stored() throws -> StoredSnapshot {
        let toolchain = try FakeToolchain.make(FakeToolchain.recorded(in: directory.appendingPathComponent("Recorded")))
        defer { toolchain.remove() }
        var contents: [String: String] = [:]
        for file in files {
            contents[file] = try source(file)
        }
        contents[SwiftStatsConfiguration.fileName] = "collectors:\n  coverage:\n    path: \(toolchain.proxy.path)\n"
        let package = try TemporaryPackage(contents, targets: targets)
        defer { package.remove() }
        let lint = try FakeTool.make(outputs: [try report(), report([])], errorText: "", statuses: [1, 0])
        defer { try? FileManager.default.removeItem(at: lint.deletingLastPathComponent()) }
        let tools = ToolLocator { $0 == SwiftProjectLintAdapter.name ? lint : nil }
        let snapshot = try SnapshotScanner(
            scanner: PackageScanner(describer: package.describer, tools: tools),
            build: SnapshotHarness.build
        )
        .scan(
            packageAt: package.root,
            configurationFile: StoreLocation.localConfiguration(packageRoot: package.root),
            git: SnapshotHarness.git(commit: "c1"),
            toolchain: SnapshotHarness.toolchain,
            date: SnapshotHarness.date,
            tiers: .coverage
        )
        let storeDirectory = try SnapshotHarness.temporaryDirectory("Risky")
        defer { try? FileManager.default.removeItem(at: storeDirectory) }
        let store = try SnapshotStore(at: storeDirectory.appendingPathComponent("stats.sqlite"))
        return try store.load(id: try store.save(snapshot))
    }

    /// SwiftProjectLint's JSON report of `markers`.
    private static func report() throws -> String {
        report(try markers.map { marker in
            """
            {"category": "safety", "kind": "defect",
             "locations": [{"filePath": "\(marker.file)", "lineNumber": \(try line(of: marker))}],
             "message": "\(marker.rule) here", "ruleIdentifier": "\(marker.rule)", "ruleName": "\(marker.rule)",
             "severity": "Warning", "suggestion": "fix it", "symbol": null}
            """
        })
    }

    /// A SwiftProjectLint JSON report holding the issues `issues`.
    private static func report(_ issues: [String]) -> String {
        """
        {"issues": [\(issues.joined(separator: ","))], "schemaVersion": 1,
         "summary": {"totalIssues": \(issues.count)}, "tool": {"name": "SwiftProjectLint", "version": "9.9.9"}}
        """
    }
}
