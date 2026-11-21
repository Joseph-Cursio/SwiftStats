//
//  CoverageFixture.swift
//  SwiftStatsCoreTests
//
//  The Coverage fixture (M5) copied to a temporary package and scanned with
//  `--coverage` through a `FakeToolchain`, so the mapping's tests run on the
//  real tools' recorded output without building or running anything. The
//  copy is described as SwiftPM describes the fixture; its configuration
//  excludes `Excluded.swift`, marks `Generated.swift` generated and points
//  the coverage collector at the fake toolchain.
//

import Foundation
@testable import SwiftStatsCore

/// Scans copies of the Coverage fixture with coverage.
enum CoverageFixture {
    /// The fixture's directory.
    static let directory = FakeToolchain.recordedDirectory.deletingLastPathComponent()

    /// The fixture's targets, as `swift package describe` lists them.
    static let targets = [
        DescribedTarget(
            name: "Exe",
            type: "executable",
            moduleType: "SwiftTarget",
            path: "Sources/Exe",
            sources: ["main.swift"]
        ),
        DescribedTarget(
            name: "Probe",
            type: "library",
            moduleType: "SwiftTarget",
            path: "Sources/Probe",
            sources: [
                "Accessors.swift", "Attached.swift", "Bom.swift", "Counter.swift", "Dependency.swift",
                "Excluded.swift", "Generated.swift", "Nested.swift", "Overloads.swift", "Secrets.swift",
                "Wrappers.swift"
            ]
        ),
        DescribedTarget(
            name: "ProbeTests",
            type: "test",
            moduleType: "SwiftTarget",
            path: "Tests/ProbeTests",
            sources: ["CounterTests.swift", "CounterXCTests.swift", "MappingTests.swift"],
            targetDependencies: ["Exe", "Probe"]
        ),
        DescribedTarget(
            name: "SwiftTestKitTests",
            type: "test",
            moduleType: "SwiftTarget",
            path: "Tests/SwiftTestKitTests",
            sources: ["KitTests.swift"],
            targetDependencies: ["Probe"]
        ),
        DescribedTarget(
            name: "Unlinked",
            type: "library",
            moduleType: "SwiftTarget",
            path: "Sources/Unlinked",
            sources: ["Unlinked.swift"]
        )
    ]

    /// The fixture's report scanned with coverage, the fake toolchain
    /// acting out the recorded run.
    static func report() throws -> ScanReport {
        try report(FakeToolchain.recorded())
    }

    /// The fixture's report scanned with coverage, the fake toolchain
    /// acting out `scenario`.
    static func report(_ scenario: FakeToolchain.Scenario) throws -> ScanReport {
        let toolchain = try FakeToolchain.make(scenario)
        defer { toolchain.remove() }
        let package = try copy(toolchain: toolchain)
        defer { package.remove() }
        return try PackageScanner(describer: package.describer, tools: SnapshotHarness.noTools)
            .scan(packageAt: package.root, coverage: true)
    }

    /// The fixture scanned with coverage as a snapshot of a clean tree at
    /// `commit`, as the test build, the fake toolchain acting out the
    /// recorded run.
    static func snapshot(commit: String) throws -> ScannedSnapshot {
        let toolchain = try FakeToolchain.make(FakeToolchain.recorded())
        defer { toolchain.remove() }
        let package = try copy(toolchain: toolchain)
        defer { package.remove() }
        return try SnapshotScanner(
            scanner: PackageScanner(describer: package.describer, tools: SnapshotHarness.noTools),
            build: SnapshotHarness.build
        )
        .scan(
            packageAt: package.root,
            configurationFile: StoreLocation.localConfiguration(packageRoot: package.root),
            git: SnapshotHarness.git(commit: commit),
            toolchain: SnapshotHarness.toolchain,
            date: SnapshotHarness.date,
            coverage: true
        )
    }

    /// A temporary copy of the fixture whose configuration points the
    /// coverage collector at `toolchain`; removed again if it can't be made.
    private static func copy(toolchain: FakeToolchain) throws -> TemporaryPackage {
        let package = try TemporaryPackage([:], targets: targets)
        do {
            try fill(package, toolchain: toolchain)
        } catch {
            package.remove()
            throw error
        }
        return package
    }

    /// Copies the fixture into `package`, with a configuration pointing the
    /// coverage collector at `toolchain`.
    private static func fill(_ package: TemporaryPackage, toolchain: FakeToolchain) throws {
        for part in ["Sources", "Tests", "Nested"] {
            try FileManager.default.copyItem(
                at: directory.appendingPathComponent(part),
                to: package.root.appendingPathComponent(part)
            )
        }
        let settings = """
            excluded:
              - Sources/Probe/Excluded.swift
            generated:
              - Sources/Probe/Generated.swift
            collectors:
              coverage:
                path: \(toolchain.proxy.path)

            """
        try settings.write(
            to: package.root.appendingPathComponent(SwiftStatsConfiguration.fileName),
            atomically: true,
            encoding: .utf8
        )
    }
}
