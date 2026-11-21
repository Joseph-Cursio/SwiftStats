import Foundation
@testable import SwiftStatsCore
import Testing

/// The coverage collector's place in a scan (M5): it runs only when the
/// scan asks for it, its build identity is the toolchain's
/// `swift --version` line, and it compares only when SwiftStats' own
/// build does.
@Suite("Coverage collector")
struct CoverageCollectorTests {
    private static let files = ["Sources/Lib/Lib.swift": "public func one() -> Int { 1 }\n"]

    /// The coverage status of `files` (with `Self.files`) scanned with
    /// `tools`, the tools skipped for `toolSkipReason` when given, asking
    /// for coverage when `coverage` is set.
    private static func status(
        _ files: [String: String],
        tools: ToolLocator,
        toolSkipReason: String?,
        coverage: Bool
    ) throws -> CollectorStatus? {
        let package = try TemporaryPackage(Self.files.merging(files) { $1 })
        defer { package.remove() }
        let scanner = PackageScanner(describer: package.describer, tools: tools, toolSkipReason: toolSkipReason)
        return try scanner.scan(packageAt: package.root, coverage: coverage).collectors
            .first { $0.name == CoverageAdapter.name }
    }

    /// A snapshot's record of a run of `name`: `ran` with `identity`.
    private static func run(_ name: String, identity: String) -> CollectorRunInfo {
        CollectorRunInfo(
            name: name,
            state: .ran,
            reason: nil,
            version: "LLVM version 21.0.0",
            identity: identity,
            identityLabel: nil,
            options: ["tests: passed"],
            durationMilliseconds: 1
        )
    }

    /// A snapshot whose SwiftStats build is `build` and whose coverage run
    /// is identified by `coverage`.
    private static func info(build: String, coverage: String) -> SnapshotInfo {
        SnapshotInfo(
            package: "Probe",
            git: SnapshotHarness.git(commit: "c1"),
            date: "2027-01-15T08:00:00Z",
            toolchain: SnapshotHarness.toolchain,
            collectors: [run(CoverageAdapter.name, identity: coverage), run(SwiftStatsCollector.name, identity: build)]
        )
    }

    @Test("a scan that doesn't ask for coverage skips it, saying how to run it, even in a backfill")
    func notRequested() throws {
        let plain = try Self.status([:], tools: SnapshotHarness.noTools, toolSkipReason: nil, coverage: false)
        let backfill = try Self.status(
            [:],
            tools: SnapshotHarness.noTools,
            toolSkipReason: "backfill runs SwiftStats only",
            coverage: false
        )

        let expected = CollectorStatus(
            name: "coverage",
            state: .skipped,
            version: nil,
            reason: "not requested; scan --coverage runs it",
            options: []
        )
        #expect(plain == expected)
        #expect(backfill == expected)
    }

    @Test("""
        asked for, coverage is skipped when collectors.coverage.enabled is false, when no swift is found, when \
        its path isn't executable, and when the tools are skipped, each saying why
        """)
    func requestedSkips() throws {
        let disabled = try Self.status(
            [".swiftstats.yml": "collectors:\n  coverage:\n    enabled: false\n"],
            tools: SnapshotHarness.noTools,
            toolSkipReason: nil,
            coverage: true
        )
        let missing = try Self.status([:], tools: SnapshotHarness.noTools, toolSkipReason: nil, coverage: true)
        let badPath = try Self.status(
            [".swiftstats.yml": "collectors:\n  coverage:\n    path: tools/swift\n"],
            tools: SnapshotHarness.noTools,
            toolSkipReason: nil,
            coverage: true
        )
        let toolsSkipped = try Self.status(
            [:],
            tools: SnapshotHarness.noTools,
            toolSkipReason: "backfill runs SwiftStats only",
            coverage: true
        )

        #expect(disabled?.reason == "disabled by collectors.coverage.enabled")
        #expect(missing?.reason == "`swift` not found on PATH; set collectors.coverage.path")
        #expect(badPath?.reason == "collectors.coverage.path tools/swift is not an executable file")
        #expect(toolsSkipped?.reason == "backfill runs SwiftStats only")
        #expect([disabled, missing, badPath, toolsSkipped].allSatisfy { $0?.state == .skipped })
    }

    @Test("asked for with a swift found, the scan runs coverage with that swift's toolchain and reports its run")
    func requestedFound() throws {
        let toolchain = try FakeToolchain.make(try FakeToolchain.recorded())
        defer { toolchain.remove() }

        let status = try Self.status(
            [".swiftstats.yml": "collectors:\n  coverage:\n    path: \(toolchain.proxy.path)\n"],
            tools: SnapshotHarness.noTools,
            toolSkipReason: nil,
            coverage: true
        )

        #expect(status?.state == .ran)
        #expect(status?.reason == nil)
        #expect(status?.version == "Apple LLVM version 21.0.0 (fake)")
        #expect(status?.options.suffix(3) == [
            "tests: passed", "map: " + CoverageMapper.rule, "links: " + CoverageTestLinks.rule
        ])
        #expect(toolchain.calls(of: "swift").contains { $0.hasPrefix("test\t--skip-build") })
        #expect(toolchain.calls(of: "proxy") == ["-print-target-info"])
    }

    @Test("""
        the coverage run checks its bundles against the test targets its own toolchain's swift package describe \
        lists, not those of the scan's description, which another toolchain may have read differently
        """)
    func ownDescription() throws {
        // The scan's description lists only LibTests; the coverage
        // toolchain's lists the recorded bundles' test targets, as a
        // `Package@swift-<version>.swift` only it reads could.
        let toolchain = try FakeToolchain.make(try FakeToolchain.recorded())
        defer { toolchain.remove() }

        let status = try Self.status(
            [
                ".swiftstats.yml": "collectors:\n  coverage:\n    path: \(toolchain.proxy.path)\n",
                "Tests/LibTests/LibTests.swift": "import Testing\n"
            ],
            tools: SnapshotHarness.noTools,
            toolSkipReason: nil,
            coverage: true
        )

        #expect(status?.state == .ran)
        #expect(status?.reason == nil)
        let describe = toolchain.calls(of: "swift").filter { $0.hasPrefix("package\t") }
        #expect(describe.count == 1)
        #expect(describe.allSatisfy { call in
            call.hasPrefix("package\t--scratch-path\t")
                && call.hasSuffix("/.swiftstats/coverage-build\tdescribe\t--type\tjson")
        })
    }

    @Test("scanWorkingTree passes --coverage to the scan, and a skipped coverage run has no build identity")
    func workspaceThreading() throws {
        let package = try TemporaryPackage(
            Self.files.merging([".swiftstats.yml": "collectors:\n  coverage:\n    enabled: false\n"]) { $1 }
        )
        defer { package.remove() }
        let workspace = try SnapshotWorkspace(
            packageRoot: package.root,
            configurationFile: nil,
            storeOverride: nil,
            build: SnapshotHarness.build,
            describer: package.describer,
            tools: SnapshotHarness.noTools
        )

        let asked = try workspace.scanWorkingTree(history: .skipped("test"), coverage: true).snapshot
        let plain = try workspace.scanWorkingTree(history: .skipped("test")).snapshot

        let askedRun = asked.info.collectors.first { $0.name == CoverageAdapter.name }
        let plainRun = plain.info.collectors.first { $0.name == CoverageAdapter.name }
        #expect(askedRun?.reason == "disabled by collectors.coverage.enabled")
        #expect(plainRun?.reason == "not requested; scan --coverage runs it")
        #expect(askedRun?.identity == nil && plainRun?.identity == nil)
    }

    @Test("a coverage run's identity is the swift --version line its run reported, not its executable's hash")
    func identity() throws {
        let package = try TemporaryPackage(Self.files)
        defer { package.remove() }
        let report = try package.scan(tools: SnapshotHarness.noTools)
        let skippedEffects = CollectorStatus(
            name: EffectCollector.name,
            state: .skipped,
            version: nil,
            reason: "test",
            options: []
        )
        let ran = CollectorStatus(
            name: "coverage",
            state: .ran,
            version: "LLVM version 21.0.0",
            reason: nil,
            options: []
        )
        let outcome = ScanOutcome(
            report: report,
            configuration: SwiftStatsConfiguration(),
            measureMilliseconds: 0,
            adapters: [
                TimedAdapterResult(
                    result: AdapterResult(status: ran, findings: [], warnings: []),
                    executable: URL(fileURLWithPath: "/usr/bin/true"),
                    identity: CoverageAdapter.identity(versionLine: "Apple Swift version 6.4.2"),
                    milliseconds: 7
                )
            ],
            effects: PackageScanner.EffectScan(facts: [:], summary: nil, status: skippedEffects, milliseconds: 0),
            dependencies: PackageScanner.DependencyScan(
                report: report.dependencies,
                status: skippedEffects,
                warnings: [],
                executable: nil,
                milliseconds: 0
            )
        )

        let info = SnapshotScanner.info(for: ran, outcome: outcome, toolchain: SnapshotHarness.toolchain)
        let skipped = CollectorStatus(name: "coverage", state: .skipped, version: nil, reason: "test", options: [])
        let skippedInfo = SnapshotScanner.info(for: skipped, outcome: outcome, toolchain: SnapshotHarness.toolchain)

        #expect(info.identity == "swift:Apple Swift version 6.4.2")
        #expect(info.identityLabel == nil)
        #expect(info.durationMilliseconds == 7)
        #expect(skippedInfo.identity == nil)
    }

    @Test("coverage compares only when SwiftStats' own build does, since SwiftStats' own code maps it")
    func comparability() {
        let older = Self.info(build: "inputs:aaa", coverage: "swift:Apple Swift version 6.4.2")
        let otherBuild = Self.info(build: "inputs:bbb", coverage: "swift:Apple Swift version 6.4.2")
        let otherSwift = Self.info(build: "inputs:aaa", coverage: "swift:Swift version 6.4.1")

        let coverage = { (new: SnapshotInfo) in
            Comparability.compare(older, new).first { $0.name == CoverageAdapter.name }
        }

        #expect(coverage(older)?.outcome == .compared)
        #expect(coverage(otherBuild)?.outcome == .notComparable)
        #expect(coverage(otherBuild)?.reason == "SwiftStats' build differs, and its own code maps the coverage")
        #expect(coverage(otherSwift)?.outcome == .notComparable)
        #expect(coverage(otherSwift)?.reason == "different builds")
    }
}
