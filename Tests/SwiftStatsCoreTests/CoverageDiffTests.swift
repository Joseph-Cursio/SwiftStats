import Foundation
@testable import SwiftStatsCore
import Testing

/// Coverage in `diff` and `trend` (M5, design §5): matched records'
/// coverage percentages and the coverage roll-ups change only when the
/// coverage collector's results compare; test bundles that came or went
/// are a fact, not a reason coverage can't compare; and a coverage
/// roll-up's trend breaks where coverage didn't compare, never reading a
/// missing number as 0.
@Suite("Coverage diff and trend")
struct CoverageDiffTests {
    /// The fixture's executable helper, run by its tests.
    private static let helper = "Exe::func exeHelper(_: Int) -> Int"
    /// The fixture's top-level code, which no test runs.
    private static let topLevel = "Exe::<top-level code> @ Sources/Exe/main.swift"

    /// `snapshot`'s coverage run.
    private static func run(of snapshot: ScannedSnapshot) throws -> CollectorRunInfo {
        try #require(snapshot.info.collectors.first { $0.name == CoverageAdapter.name })
    }

    /// The fixture's coverage with the helper run less, the top-level code
    /// run, a test bundle added and one removed.
    private static func changed(_ coverage: CoverageReport) -> CoverageReport {
        let helperLess = CoverageSnapshots.changing(
            coverage,
            key: helper,
            lines: CoverageTally(covered: 1, total: 3),
            regions: CoverageTally(covered: 0, total: 1)
        )
        let topLevelRun = CoverageSnapshots.changing(
            helperLess,
            key: topLevel,
            lines: CoverageTally(covered: 2, total: 2),
            regions: CoverageTally(covered: 2, total: 2)
        )
        return CoverageSnapshots.with(bundles: ["NewTests", "ProbeTests"], in: topLevelRun)
    }

    /// `old` and `new` stored in a fresh store, read back and diffed.
    private static func diff(_ old: ScannedSnapshot, _ new: ScannedSnapshot) throws -> SnapshotDiffReport {
        let directory = try SnapshotHarness.temporaryDirectory("CoverageDiff")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SnapshotStore(at: directory.appendingPathComponent("stats.sqlite"))
        let older = try store.load(id: try store.save(old))
        let newer = try store.load(id: try store.save(new))
        return SnapshotDiff.diff(older, newer)
    }

    /// The coverage of a library whose one file maps `total` lines, of
    /// which `covered` ran.
    private static func lines(covered: Int, total: Int) -> CoverageReport {
        let runs = [
            CoverageLineRun(start: 1, end: covered, count: 1, partlyRun: false),
            CoverageLineRun(start: covered + 1, end: total, count: 0, partlyRun: false)
        ]
        return CoverageReport(
            records: [],
            attachments: [],
            unmapped: [],
            dropped: CoverageDropped(build: 0, outsideRoot: 0, testFiles: 0, otherPackage: 0, otherLanguage: 0),
            bundles: ["LibTests"],
            tests: "passed",
            saturated: [],
            files: [
                CoverageFileLines(file: "Sources/Lib/One.swift", lines: runs.filter { $0.end >= $0.start }, skipped: [])
            ]
        )
    }

    @Test("""
        when coverage compares, matched records' coverage percentages that moved are deltas, better higher; \
        coverage roll-up deltas come from coverage; and test bundles that came or went are a fact
        """)
    func compared() throws {
        let old = try CoverageFixture.snapshot(commit: "c1")
        let coverage = try #require(old.report.coverage)
        let new = CoverageSnapshots.replacing(
            old,
            git: SnapshotHarness.git(commit: "c2"),
            coverage: Self.changed(coverage),
            run: try Self.run(of: old)
        )

        let diff = try Self.diff(old, new)

        #expect(diff.schemaVersion == 4)
        #expect(diff.collectors.first { $0.name == CoverageAdapter.name }?.outcome == .compared)
        let helperDelta = try #require(diff.functions.first { $0.key == Self.helper })
        #expect(helperDelta.metrics == [
            MetricDelta(metric: "coverage.lines.percent", before: 100, after: 33.33),
            MetricDelta(metric: "coverage.regions.percent", before: 100, after: 0)
        ])
        #expect(helperDelta.metrics.allSatisfy { $0.verdict == .worse })
        let topLevelDelta = try #require(diff.functions.first { $0.key == Self.topLevel })
        #expect(topLevelDelta.metrics.map(\.metric) == ["coverage.lines.percent", "coverage.regions.percent"])
        #expect(topLevelDelta.metrics.allSatisfy { $0.before == 0 && $0.after == 100 && $0.verdict == .better })
        #expect(diff.functions.count == 2)
        let regions = try #require(diff.rollups.first { delta in
            delta.scope == .module && delta.name == "Exe" && delta.delta.metric == "coverage.regions.percent"
        })
        #expect(regions.collector == CoverageAdapter.name)
        #expect(regions.delta.before == 16.67 && regions.delta.after == 33.33 && regions.delta.verdict == .better)
        #expect(diff.rollups.contains { $0.delta.metric.hasPrefix("coverage.lines.") } == false)
        #expect(diff.bundles?.added == ["NewTests"] && diff.bundles?.removed == ["SwiftTestKitTests"])
        #expect(diff.isEmpty == false)
        let markdown = MarkdownDiff.render(diff)
        #expect(markdown.contains("Test bundles added `NewTests`; removed `SwiftTestKitTests`."))
        #expect(markdown.contains("| \(Self.helper) | coverage.lines.percent | 100 | 33.33 |"))
    }

    @Test("""
        when coverage doesn't compare, or one side didn't collect it, no record or roll-up coverage delta \
        appears; changed bundles stay a fact while both sides hold coverage; the same coverage twice is no change
        """)
    func notCompared() throws {
        let old = try CoverageFixture.snapshot(commit: "c1")
        let coverage = try #require(old.report.coverage)
        let run = try Self.run(of: old)
        let failing = CollectorRunInfo(
            name: run.name,
            state: run.state,
            reason: "tests failing (swift test exited 1); coverage merged from the test processes' profiles",
            version: run.version,
            identity: run.identity,
            identityLabel: run.identityLabel,
            options: run.options.map { $0 == "tests: passed" ? "tests: failing" : $0 },
            durationMilliseconds: run.durationMilliseconds
        )
        #expect(failing.options != run.options)
        let failed = CoverageSnapshots.replacing(
            old,
            git: SnapshotHarness.git(commit: "c2"),
            coverage: Self.changed(coverage),
            run: failing
        )
        let plain = CoverageSnapshots.replacing(
            old,
            git: SnapshotHarness.git(commit: "c3"),
            coverage: nil,
            run: CoverageSnapshots.skipped
        )
        let same = CoverageSnapshots.replacing(
            old,
            git: SnapshotHarness.git(commit: "c4"),
            coverage: coverage,
            run: run
        )

        let other = try Self.diff(old, failed)
        let collected = try Self.diff(old, plain)
        let unchanged = try Self.diff(old, same)

        let comparison = other.collectors.first { $0.name == CoverageAdapter.name }
        #expect(comparison?.outcome == .notComparable && comparison?.reason == "different options")
        #expect(other.functions.isEmpty)
        #expect(other.rollups.allSatisfy { $0.collector != CoverageAdapter.name })
        #expect(other.bundles?.added == ["NewTests"] && other.bundles?.removed == ["SwiftTestKitTests"])
        #expect(collected.collectors.first { $0.name == CoverageAdapter.name }?.outcome == .notCollected)
        #expect(collected.functions.isEmpty && collected.bundles == nil)
        #expect(collected.rollups.allSatisfy { $0.collector != CoverageAdapter.name })
        #expect(unchanged.isEmpty && unchanged.bundles == nil && unchanged.functions.isEmpty)
    }

    @Test("""
        a coverage roll-up's trend reads nil where coverage wasn't collected, never 0, and breaks where coverage \
        ran on one side only or with other options; other metrics don't watch coverage
        """)
    func trend() throws {
        let repository = try HistoryRepository()
        defer { repository.remove() }
        let workspace = try repository.workspace()
        let plan: [(coverage: CoverageReport?, options: [String])] = [
            (Self.lines(covered: 1, total: 2), ["tests: passed"]),
            (nil, []),
            (Self.lines(covered: 3, total: 4), ["tests: passed"]),
            (Self.lines(covered: 3, total: 3), ["tests: passed"]),
            (Self.lines(covered: 3, total: 3), ["tests: failing"])
        ]
        for (day, step) in plan.enumerated() {
            try repository.write(["Sources/Lib/One.swift": "func one() -> Int {\n    \(day)\n}\n"])
            try repository.commit("Day \(day)", day: day)
            let scanned = try repository.scan()
            let run = step.coverage == nil ? CoverageSnapshots.skipped : CoverageSnapshots.ran(options: step.options)
            try workspace.store.save(
                CoverageSnapshots.replacing(scanned, git: scanned.info.git, coverage: step.coverage, run: run)
            )
        }

        let trend = try workspace.trend(metric: "coverage.lines.percent", scope: .project, name: "production")
        let lengths = try workspace.trend(metric: "fileLength.total", scope: .project, name: "production")

        #expect(trend.points.map(\.value) == [50, nil, 75, 100, 100])
        #expect(trend.points.map { $0.breakReason == nil } == [true, false, false, true, false])
        #expect(trend.points[1].breakReason?.hasPrefix("coverage: skipped in the newer snapshot") == true)
        #expect(trend.points[4].breakReason == "coverage: different options")
        #expect(lengths.points.count == plan.count)
        #expect(lengths.points.allSatisfy { $0.breakReason == nil })
    }
}
