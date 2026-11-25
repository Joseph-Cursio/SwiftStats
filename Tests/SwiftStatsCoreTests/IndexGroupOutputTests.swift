import Foundation
@testable import SwiftStatsCore
import Testing

/// What a scan makes of the T1 build it ran (M7, design §1.7, §6): the
/// Index fixture's recorded output becomes the scan's `build` block and its
/// warnings `swiftc` findings, attached to records and counted for the
/// `build` collector, with or without a store; and the build runs alone,
/// once the background runs have ended. A fake toolchain acts out every
/// build.
@Suite("Index group output")
struct IndexGroupOutputTests {
    /// An executable script that sleeps a second, then appends `label` and
    /// ` end` to `log` and fails: a background tool whose end the T1 build
    /// must wait for.
    private static func sleeper(_ label: String, log: URL) throws -> URL {
        let tool = try SnapshotHarness.temporaryDirectory("Sleeper").appendingPathComponent(label)
        try "#!/bin/sh\n/bin/sleep 1\necho '\(label) end' >> '\(log.path)'\nexit 1\n"
            .write(to: tool, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)
        return tool
    }

    @Test("""
        the recorded build's output becomes the scan's build block, as the reader, the timing mapper and the \
        warning reader give it, and its warnings swiftc findings attached to the records and counted in the \
        roll-ups for the build collector
        """)
    func recordedBuild() throws {
        try IndexGroupHarness.scanFixture(try FakeToolchain.recordedBuild(), extra: "") { fixture, outcome in
            let output = try fixture.output()
            let warnings = fixture.warningReader(changedFiles: []).read(output.diagnostics)
            let expected = BuildReport(
                output: output,
                timings: fixture.mapper(changedFiles: []).map(output.entries),
                warnings: warnings,
                changedFiles: 0,
                complete: true
            )
            let block = try #require(outcome.report.build)
            #expect(block == expected)
            #expect(block.records.count > 90)
            #expect(block.unmapped.macro.entries > 0 && block.dropped.outsideRoot.entries > 0)

            let mapper = FindingMapper(measured: fixture.measured)
            let swiftc = outcome.report.findings.filter { $0.tool == "swiftc" }
            #expect(swiftc == warnings.findings.map(mapper.finding(for:)).sorted(by: PackageScanner.findingOrder))
            #expect(swiftc.count == 8)
            let expectedRules: Set<String> = ["variable_never_mutated", "pound_warning", "no_throw_in_try"]
            #expect(Set(swiftc.map(\.rule)).isSuperset(of: expectedRules))
            let modules = outcome.report.rollups.filter { $0.scope == .module }
            let counts: [Int] = modules.flatMap { rollup -> [Int] in Array((rollup.findings["swiftc"] ?? [:]).values) }
            #expect(counts.reduce(0, +) == 8)
            #expect(modules.allSatisfy { $0.findings["swiftc"] != nil && $0.findingKinds["swiftc"] != nil })
            let metrics = try modules.flatMap(RollupMetrics.metrics(of:))
                .filter { $0.path.hasPrefix("findings.swiftc.") }
            #expect(metrics.isEmpty == false)
            #expect(metrics.allSatisfy { $0.collector == "build" })
        }
    }

    @Test("""
        attaching the history keeps the build block, and diff counts the compiler's warnings per function only \
        when the build compares, as the build collector's
        """)
    func buildKept() throws {
        try IndexGroupHarness.scanFixture(try FakeToolchain.recordedBuild(), extra: "") { _, outcome in
            let history = outcome.report.with(history: nil, status: HistoryCollector.notRequested)
            #expect(history.build == outcome.report.build)
            #expect(history.build != nil)
            let rows = outcome.report.findings.filter { $0.tool == "swiftc" }
                .flatMap { FindingRow.rows(for: $0, snapshotId: 1) }
            let compared = FindingCounts(old: rows, new: rows, tools: ["build", "swiftstats"])
            let notCompared = FindingCounts(old: rows, new: rows, tools: ["swiftstats", "swiftc"])
            let counted = compared.old.values.flatMap(\.keys)
            #expect(counted.isEmpty == false)
            #expect(counted.allSatisfy { $0.hasPrefix("findings.swiftc.") })
            #expect(notCompared.old.isEmpty)
            #expect(RollupMetrics.collector(of: ["findings", "swiftc", "pound_warning"]) == "build")
            #expect(RollupMetrics.collector(of: ["findingKinds", "swiftc", "defect"]) == "build")
        }
    }

    @Test("""
        a scan with no store gives the same build block and swiftc findings as a stored one, and encodes the \
        same twice
        """)
    func noStoreScan() throws {
        try IndexGroupHarness.scanFixture(try FakeToolchain.recordedBuild(), extra: "") { fixture, outcome in
            let plain = try PackageScanner(describer: fixture.package.describer, tools: SnapshotHarness.noTools)
                .scan(packageAt: outcome.root, tiers: RequestedTiers(index: true))
            #expect(plain.build == outcome.report.build)
            #expect(plain.findings == outcome.report.findings)
            let again = try PackageScanner(describer: fixture.package.describer, tools: SnapshotHarness.noTools)
                .scan(packageAt: outcome.root, tiers: RequestedTiers(index: true))
            #expect(try ScanReportEncoder.encode(again) == ScanReportEncoder.encode(plain))
        }
    }

    @Test("""
        the build starts only once the coverage run, SwiftInferProperties and the clone detector have all ended
        """)
    func runsAlone() throws {
        let directory = try SnapshotHarness.temporaryDirectory("IndexOrder")
        defer { try? FileManager.default.removeItem(at: directory) }
        let log = directory.appendingPathComponent("order.log")
        let xcrun = try Self.sleeper("coverage", log: log)
        let infer = try Self.sleeper("swiftinferproperties", log: log)
        let clones = try Self.sleeper("swiftclonedetector", log: log)
        defer {
            for tool in [xcrun, infer, clones] {
                try? FileManager.default.removeItem(at: tool.deletingLastPathComponent())
            }
        }
        let tools = ToolLocator { name in
            ["xcrun": xcrun, "swift-infer": infer, "swift-clone-detector": clones][name]
        }
        var scenario = try IndexGroupHarness.emptyBuild()
        scenario.script = "echo 'build start' >> '\(log.path)'\n"

        try IndexGroupHarness.scanSmall(
            scenario,
            extra: "",
            tiers: RequestedTiers(coverage: true, index: true),
            tools: tools
        ) { outcome in
            let lines = ((try? String(contentsOf: log, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init)
            let start = try #require(lines.firstIndex(of: "build start"))
            for label in ["coverage", "swiftinferproperties", "swiftclonedetector"] {
                let end = try #require(lines.lastIndex(of: "\(label) end"), "\(label)")
                #expect(end < start, "\(label)")
                #expect(outcome.report.collectors.first { $0.name == label }?.state == .failed, "\(label)")
            }
            #expect(outcome.statuses["build"]?.state == .ran)
        }
    }
}
