//
//  PropertyTargetHarness.swift
//  SwiftStatsCoreTests
//
//  Snapshots for best property-test target (M6, design §7.3): a library
//  `Core` and its test target, scanned with a fake `swift-infer` giving
//  chosen suggestions, then given hand-made mutation results (each
//  function's mutants by verdict, on the line after its first) and stored
//  and read back, so the signal reads what `report` reads. Recording
//  swift-infer is out of scope (design §11), so the suggestions come from
//  index rows written here.
//

import Foundation
@testable import SwiftStatsCore

/// Stores snapshots with chosen suggestions and mutation results.
enum PropertyTargetHarness {
    /// What the package holds and what its results say.
    struct Setup {
        /// The library's and test target's files beyond `Sources/Core/Values.swift`
        /// and `Tests/CoreTests/MoneyTests.swift`, by path.
        var files: [String: String] = [:]
        /// The index rows `swift-infer` gives `Core`.
        var rows: [PropertyHarness.Row] = []
        /// Interaction rows, each a JSON object.
        var interactions: [String] = []
        /// Each function's mutants, by record key.
        var mutants: [String: [MutationSignalHarness.Planted]] = [:]
        /// Each Swift file's disposition, by path; tested when absent.
        var dispositions: [String: MutationFileDisposition] = [:]
        /// Whether the results list code no test ran.
        var listsNotCovered = true
        /// Whether `swift-infer` is found; when false the collector is skipped.
        var indexed = true
        /// Whether the snapshot holds mutation results.
        var withMutation = true
        /// The store to keep the snapshot in; a new one, removed again, when nil.
        var store: SnapshotStore?
    }

    /// The library's main file. Line numbers matter: rows name them.
    static let values = """
    public struct Money {
        public func encoded(_ value: Int) -> String {
            String(value * 2)
        }

        public func decoded(_ text: String) -> Int {
            (Int(text) ?? 0) / 2
        }

        public func doubled(_ value: Int) -> Int {
            value * 2
        }

        public func halved(_ value: Int) -> Int {
            value / 2
        }

        public func clamped(_ value: Int) -> Int {
            max(0, value)
        }

        private func hidden(_ value: Int) -> Int {
            value + 1
        }

        public func built(_ value: Int) -> Int {
            value - 1
        }

        public func bare() -> Int {
            1
        }
    }
    """

    /// The library's main file's path.
    static let valuesPath = "Sources/Core/Values.swift"

    /// The test target's file.
    static let tests = """
    import Testing
    @testable import Core

    @Test func doubling() {
        #expect(Money().doubled(1) == 2)
    }
    """

    /// The column of a function's first mutant.
    private static let firstColumn = 5

    /// The key of `Money`'s method `signature`, such as `func doubled(_: Int) -> Int`.
    static func key(_ signature: String) -> String {
        "Core::Money::\(signature)"
    }

    /// `location` in the tool's terms: `@ROOT@/<path>:<line>`.
    static func location(_ path: String, _ line: Int) -> String {
        "@ROOT@/\(path):\(line)"
    }

    /// The package `setup` describes, scanned with a fake indexer giving
    /// `Core` its rows (no indexer when `setup.indexed` is false), given
    /// mutation results holding `setup.mutants` (none when
    /// `setup.withMutation` is false), stored in `setup.store` (a new one
    /// when nil) and read back.
    static func stored(_ setup: Setup) throws -> StoredSnapshot {
        var files = setup.files
        files[valuesPath] = values
        files["Tests/CoreTests/MoneyTests.swift"] = tests
        let corePrefix = "Sources/Core/"
        let testPrefix = "Tests/CoreTests/"
        let core = files.keys.filter { $0.hasPrefix(corePrefix) }.sorted()
        let testFiles = files.keys.filter { $0.hasPrefix(testPrefix) }.sorted()
        let targets = [
            PropertyHarness.target(
                "Core",
                "library",
                "Sources/Core",
                core.map { String($0.dropFirst(corePrefix.count)) }
            ),
            DescribedTarget(
                name: "CoreTests",
                type: "test",
                moduleType: "SwiftTarget",
                path: "Tests/CoreTests",
                sources: testFiles.map { String($0.dropFirst(testPrefix.count)) },
                targetDependencies: ["Core"]
            )
        ]
        let index = PropertyHarness.index(
            setup.rows,
            interactions: setup.interactions,
            schemaVersion: SwiftInferIndex.schemaVersion
        )
        let tool = try FakeTool.makeIndexer(indexes: ["Core": index], errors: [:], statuses: [:], delays: [:])
        defer { PropertyHarness.remove(tool) }
        let package = try TemporaryPackage(files, targets: targets)
        defer { package.remove() }
        let tools = setup.indexed ? PropertyHarness.locator(tool) : SnapshotHarness.noTools
        var snapshot = try SnapshotHarness.scan(package, commit: "c1", build: SnapshotHarness.build, tools: tools)
        if setup.withMutation {
            snapshot = MutationSnapshots.replacing(
                snapshot,
                git: snapshot.info.git,
                mutation: report(setup, records: snapshot.report.records, files: core),
                run: MutationSnapshots.ran(identity: MutationSnapshots.identity)
            )
        }
        if let store = setup.store {
            return try store.load(id: try store.save(snapshot))
        }
        let directory = try SnapshotHarness.temporaryDirectory("PropertyTarget")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SnapshotStore(at: directory.appendingPathComponent("stats.sqlite"))
        return try store.load(id: try store.save(snapshot))
    }

    /// The mutation results `setup` describes over `records`, its library
    /// `files` each with its disposition.
    private static func report(_ setup: Setup, records: [FunctionRecord], files: [String]) -> MutationReport {
        let byKey = Dictionary(records.map { ($0.key, $0) }) { first, _ in first }
        let mutants = setup.mutants.keys.sorted().flatMap { key -> [Mutant] in
            guard let record = byKey[key] else {
                return []
            }
            return (setup.mutants[key] ?? []).enumerated().map { offset, planted in
                MutationSignalHarness.mutant(
                    planted,
                    path: record.file,
                    line: record.range.start.line + 1,
                    column: firstColumn + offset,
                    owner: key
                )
            }
        }
        return MutationReport(
            collectedAt: "2026-11-21T09:00:00.000Z",
            complete: true,
            listsNotCovered: setup.listsNotCovered,
            mode: .full,
            base: nil,
            files: files.map { path in
                MutationFile(
                    path: path,
                    sha256: "abc",
                    disposition: setup.dispositions[path] ?? .tested,
                    changedTest: false,
                    run: 0
                )
            },
            runs: [MutationSignalHarness.run(listsNotCovered: setup.listsNotCovered)],
            suspectTests: [],
            mutants: mutants
        )
    }
}
