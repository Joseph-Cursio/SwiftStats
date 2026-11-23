//
//  MutationRunHarness.swift
//  SwiftStatsCoreTests
//
//  A temporary package (outside git, so its copy is a plain copy) whose
//  `.swiftstats.yml` points the SwiftMutator collector at a `FakeMutator`
//  acting out a scenario: `collectors.swiftmutator.path` its
//  `swift-mutator` and `collectors.coverage.path` its `swift`. A test runs
//  the collector directly, to see the run it gives, or through a scan.
//

import Foundation
@testable import SwiftStatsCore

/// A package and fake tools for the SwiftMutator collector's tests.
struct MutationRunHarness {
    /// The package's one source file.
    static let sourcePath = "Sources/Lib/Lib.swift"
    /// Its text.
    static let source = "public func one() -> Int { 1 }\n"

    /// The package.
    let package: TemporaryPackage
    /// The fake tools.
    let fake: FakeMutator

    /// The package's mutation folder.
    var directory: URL {
        package.root.appendingPathComponent(".swiftstats/mutation")
    }

    /// The copy's project folder while a run is under way, or after a
    /// resumable one.
    var project: URL {
        directory.appendingPathComponent("work").appendingPathComponent(package.root.lastPathComponent)
    }

    /// The real path of `project`, which needn't exist.
    var realProject: String {
        Self.realPath(package.root) + "/.swiftstats/mutation/work/" + package.root.lastPathComponent
    }

    /// A package and tools acting out `scenario`, its `.swiftstats.yml`
    /// pointing the collector at the tools.
    init(_ scenario: FakeMutator.Scenario) throws {
        try self.init(scenario) { tools in
            "collectors:\n  coverage:\n    path: \(tools.swift.path)\n"
                + "  swiftmutator:\n    path: \(tools.mutator.path)\n"
        }
    }

    /// A package and tools acting out `scenario`, its `.swiftstats.yml`
    /// what `configuration` writes for the tools.
    init(_ scenario: FakeMutator.Scenario, configuration: (FakeMutator) -> String) throws {
        let tools = try FakeMutator.make(scenario)
        package = try TemporaryPackage([Self.sourcePath: Self.source, ".swiftstats.yml": configuration(tools)])
        fake = tools
    }

    /// The real path of `url` (realpath(3)), or its path when it doesn't
    /// exist.
    static func realPath(_ url: URL) -> String {
        WorkCopyHarness.realPath(url)
    }

    /// Runs the collector with settings pointing at the fake tools.
    func run() -> MutationRun {
        run(settings: CollectorSettings(enabled: true, path: fake.mutator.path))
    }

    /// Runs the collector with `settings`, as a full run of the package
    /// checked against its source's hash.
    func run(settings: CollectorSettings) -> MutationRun {
        MutationAdapter.run(MutationJob(
            mutator: fake.mutator,
            swift: fake.swift,
            root: package.root,
            git: .outsideGit,
            scanned: [Self.sourcePath: ContentHash.sha256(Data(Self.source.utf8))],
            ignoring: [],
            settings: settings
        ))
    }

    /// Scans the package with no tools on PATH, asking for a full run: the
    /// swiftmutator status and the scan's warnings.
    func scan() throws -> (status: CollectorStatus?, warnings: [ScanWarning]) {
        try scan(.full)
    }

    /// Scans the package with no tools on PATH, making `request`: the
    /// swiftmutator status and the scan's warnings.
    func scan(_ request: MutationRequest) throws -> (status: CollectorStatus?, warnings: [ScanWarning]) {
        let report = try PackageScanner(describer: package.describer, tools: SnapshotHarness.noTools)
            .scan(packageAt: package.root, tiers: RequestedTiers(mutation: request))
        return (report.collectors.first { $0.name == MutationAdapter.name }, report.warnings)
    }

    /// Removes the package and the tools.
    func remove() {
        package.remove()
        fake.remove()
    }
}
