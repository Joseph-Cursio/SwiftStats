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
        let package = try TemporaryPackage([:], targets: targets)
        defer { package.remove() }
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
        return try PackageScanner(describer: package.describer, tools: SnapshotHarness.noTools)
            .scan(packageAt: package.root, coverage: true)
    }
}
