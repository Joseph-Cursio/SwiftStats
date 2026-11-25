//
//  IndexWalkHarness.swift
//  SwiftStatsCoreTests
//
//  The Index fixture's recorded dumps (M7, design §13) set up for the unit
//  filter and the index walk: a temporary package root holding an empty
//  file at each source path the dump lists (so main files exist or don't
//  as they did when it was recorded), the dump read through
//  `RecordedIndexSource` with its paths put back under that root, and the
//  T1 describe that goes with it. The stale dump's describe is the
//  recorded one with the stale case's edits applied: `Formatting.swift`
//  renamed `LineFormatting.swift`, and `Relay.swift` moved from
//  `index-kit` to `index-support`. Nothing is built.
//

import Foundation
@testable import SwiftStatsCore

/// A recorded dump over a temporary package root.
struct IndexWalkHarness {
    /// The package root's real path.
    let root: String
    /// The T1 describe.
    let package: DescribedPackage
    /// The recorded dump, its paths put back.
    let source: RecordedIndexSource

    /// The scratch folder's real path, `.swiftstats/index-build` in the
    /// root.
    var build: String {
        Self.build(of: root)
    }

    /// IndexDep's root as the dump's paths are put back: beside the root.
    var dependency: String {
        Self.dependency(of: root)
    }

    /// The recording's units, by name.
    var units: [IndexUnitFact] {
        source.units.values.sorted { $0.name < $1.name }
    }

    /// The recording's records, by name.
    var records: [IndexRecordFact] {
        source.records.values.sorted { $0.name < $1.name }
    }

    /// A unit filter for the root, the scratch folder and the describe.
    var filter: UnitFilter {
        get throws {
            try UnitFilter(root: root, scratch: build, package: package)
        }
    }

    /// Creates the harness for the recorded dump `dump` with `package`: a
    /// fresh root holding an empty file at each path the dump's `files`
    /// lists.
    private init(dump: String, package: DescribedPackage) throws {
        let manager = FileManager.default
        let parent = manager.temporaryDirectory.appendingPathComponent("IndexWalkHarness-\(UUID().uuidString)")
        let rootURL = parent.appendingPathComponent("Index")
        try manager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let realRoot = WorkCopyHarness.realPath(rootURL)
        let data = try IndexFixture.data(dump)
        let prefix = IndexFixture.rootToken + "/"
        for file in try JSONDecoder().decode(IndexFixture.DumpFiles.self, from: data).files {
            let url = URL(fileURLWithPath: realRoot).appendingPathComponent(String(file.path.dropFirst(prefix.count)))
            try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data().write(to: url)
        }
        root = realRoot
        self.package = package
        source = try RecordedIndexSource(
            recording: data,
            restoring: [
                IndexFixture.rootToken: realRoot,
                IndexFixture.buildToken: Self.build(of: realRoot),
                IndexFixture.dependencyToken: Self.dependency(of: realRoot)
            ]
        )
    }

    /// The first build's dump, `reader.json`, with the recorded describe.
    static func fresh() throws -> Self {
        try Self(dump: "reader.json", package: recordedPackage())
    }

    /// The stale case's dump, `reader-stale.json`, with the describe the
    /// stale case's manifest gives.
    static func stale() throws -> Self {
        let recorded = try recordedPackage()
        let targets = recorded.targets.map { target in
            DescribedTarget(
                name: target.name,
                type: target.type,
                moduleType: target.moduleType,
                path: target.path,
                sources: staleSources(of: target),
                targetDependencies: target.targetDependencies,
                c99name: target.c99name
            )
        }
        return try Self(
            dump: "reader-stale.json",
            package: DescribedPackage(
                name: recorded.name,
                targets: targets,
                dependencies: recorded.dependencies,
                products: recorded.products
            )
        )
    }

    /// The recorded T1 describe.
    static func recordedPackage() throws -> DescribedPackage {
        try JSONDecoder().decode(DescribedPackage.self, from: IndexFixture.data("describe.json"))
    }

    /// The scratch folder of the root at `root`.
    private static func build(of root: String) -> String {
        root + "/.swiftstats/index-build"
    }

    /// IndexDep's root beside the root at `root`.
    private static func dependency(of root: String) -> String {
        URL(fileURLWithPath: root).deletingLastPathComponent().appendingPathComponent("IndexDep").path
    }

    /// `target`'s sources after the stale case's edits.
    private static func staleSources(of target: DescribedTarget) -> [String] {
        switch target.name {
        case "IndexCore":
            target.sources.map { $0 == "Formatting.swift" ? "LineFormatting.swift" : $0 }.sorted()
        case "index-kit":
            target.sources.filter { $0 != "Relay.swift" }
        case "index-support":
            target.sources + ["Relay.swift"]
        default:
            target.sources
        }
    }

    /// The recording's unit named `name`.
    func unit(_ name: String) throws -> IndexUnitFact {
        try source.unit(named: name)
    }

    /// The recording with `units` added, replacing any of the same name.
    func adding(_ units: [IndexUnitFact]) -> RecordedIndexSource {
        RecordedIndexSource(units: self.units + units, records: records)
    }
}
