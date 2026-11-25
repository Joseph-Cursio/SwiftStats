//
//  IndexGroupHarness.swift
//  SwiftStatsCoreTests
//
//  Scans with the T1 group asked for (`scan --index`, M7, design §1.7)
//  against a `FakeToolchain` acting out a build scenario, whose proxy
//  `swift` is the coverage collector's (`collectors.coverage.path`), so the
//  build runs and its recorded output is read without building anything.
//  Either a small package or a copy of the Index fixture (`BuildFixture`),
//  scanned as a snapshot so each run's identity is recorded too. Nothing
//  real is built or run.
//

import Foundation
@testable import SwiftStatsCore

/// Scans with the T1 group against fake toolchains.
enum IndexGroupHarness {
    /// What a scan gave, with the toolchain and package it ran with.
    struct Outcome {
        /// The scan.
        let snapshot: ScannedSnapshot
        /// The fake toolchain.
        let toolchain: FakeToolchain
        /// The package root.
        let root: URL

        /// The scan report.
        var report: ScanReport {
            snapshot.report
        }

        /// The statuses of the T1 group's collectors, by name.
        var statuses: [String: CollectorStatus] {
            Dictionary(uniqueKeysWithValues: report.collectors.filter { names.contains($0.name) }.map { ($0.name, $0) })
        }

        /// Whether the toolchain's `swift` was asked to build.
        var built: Bool {
            toolchain.calls(of: "swift").contains { $0.hasPrefix("build\t") }
        }

        /// The snapshot's record of collector `name`'s run.
        func run(_ name: String) -> CollectorRunInfo? {
            snapshot.info.collectors.first { $0.name == name }
        }
    }

    /// The T1 group's collectors, in the order a scan lists them.
    static let names = ["build", "index", "periphery"]
    /// The small package's files.
    static let files = ["Sources/Lib/Lib.swift": "public func one() -> Int { 1 }\n"]

    /// The `.swiftstats.yml` naming `toolchain`'s proxy as the coverage
    /// collector's `swift`, then `extra`, lines of further collector keys
    /// indented as under `collectors:`.
    static func configuration(_ toolchain: FakeToolchain, extra: String) -> String {
        "collectors:\n  coverage:\n    path: \(toolchain.proxy.path)\n" + extra
    }

    /// A scenario of an empty build: the Index fixture's description and
    /// no output, exiting 0.
    static func emptyBuild() throws -> FakeToolchain.BuildScenario {
        FakeToolchain.BuildScenario(describe: try IndexFixture.text("describe.json"), stdout: "", stderr: "")
    }

    /// An executable `outskirts` stand-in that logs its calls beside
    /// itself and fails every one, for scans in which outskirts must not
    /// run (`FakePeriphery` acts out real runs).
    static func outskirts() throws -> URL {
        try FakeTool.make(outputs: ["[]"], errorText: "unexpected", statuses: [1])
    }

    /// Scans the small package as a snapshot, asking for `tiers`, with a
    /// fake toolchain acting out `scenario` and further collector keys
    /// `extra`, finding tools with `tools`, and passes what it gave to
    /// `check`.
    static func scanSmall(
        _ scenario: FakeToolchain.BuildScenario,
        extra: String,
        tiers: RequestedTiers,
        tools: ToolLocator,
        check: (Outcome) throws -> Void
    ) throws {
        let toolchain = try FakeToolchain.make(build: scenario)
        defer { toolchain.remove() }
        let package = try TemporaryPackage(
            files.merging([".swiftstats.yml": configuration(toolchain, extra: extra)]) { $1 }
        )
        defer { package.remove() }
        let snapshot = try scan(
            root: package.root,
            describer: package.describer,
            tiers: tiers,
            tools: tools,
            failedBuild: nil
        )
        try check(Outcome(snapshot: snapshot, toolchain: toolchain, root: package.root))
    }

    /// Scans a copy of the Index fixture as a snapshot with `--index`,
    /// with a fake toolchain acting out `scenario` and further collector
    /// keys `extra`, and passes the copy and what the scan gave to `check`.
    static func scanFixture(
        _ scenario: FakeToolchain.BuildScenario,
        extra: String,
        check: (BuildFixture, Outcome) throws -> Void
    ) throws {
        let toolchain = try FakeToolchain.make(build: scenario)
        defer { toolchain.remove() }
        let fixture = try BuildFixture()
        defer { fixture.remove() }
        let root = fixture.package.root
        try configuration(toolchain, extra: extra)
            .write(to: root.appendingPathComponent(".swiftstats.yml"), atomically: true, encoding: .utf8)
        let snapshot = try scan(
            root: root,
            describer: fixture.package.describer,
            tiers: RequestedTiers(index: true),
            tools: SnapshotHarness.noTools,
            failedBuild: nil
        )
        try check(fixture, Outcome(snapshot: snapshot, toolchain: toolchain, root: root))
    }

    /// The package at `root`, described by `describer`, scanned as a
    /// snapshot of the test build at a clean commit with its own
    /// `.swiftstats.yml`, asking for `tiers`, finding tools with `tools`
    /// and recording a failed build's task log in `failedBuild`; the
    /// history isn't read.
    static func scan(
        root: URL,
        describer: any PackageDescriber,
        tiers: RequestedTiers,
        tools: ToolLocator,
        failedBuild: FailedBuildLog?
    ) throws -> ScannedSnapshot {
        let scanner = PackageScanner(describer: describer, tools: tools).recording(failedBuild: failedBuild)
        return try SnapshotScanner(scanner: scanner, build: SnapshotHarness.build)
            .scan(
                packageAt: root,
                configurationFile: StoreLocation.localConfiguration(packageRoot: root),
                git: SnapshotHarness.git(commit: "c1"),
                toolchain: SnapshotHarness.toolchain,
                date: SnapshotHarness.date,
                history: .skipped("test"),
                tiers: tiers
            )
    }
}
