import Foundation
@testable import SwiftStatsCore
import Testing

/// `backfill` and `trend` (PRD §7.13, §10).
@Suite("Backfill and trend")
struct BackfillTests {
    /// A first-parent line of `count` commits, one a day from day zero.
    private static func line(_ count: Int, every seconds: Int = HistoryCollector.day) -> [(commit: String, time: Int)] {
        (0..<count).map { ("c\($0)", HistoryRepository.dayZero + $0 * seconds) }
    }

    /// A plan with `selection` and nothing else set.
    private static func plan(
        _ selection: BackfillSelection,
        since: Int? = nil,
        maximum: Int? = nil,
        rerun: Bool = false
    ) -> BackfillPlan {
        BackfillPlan(selection: selection, since: since, maximumCommits: maximum, rerun: rerun, withTools: false)
    }

    /// Backfills with `plan`, checking that every returned step was also reported as progress.
    private static func backfill(_ workspace: SnapshotWorkspace, _ plan: BackfillPlan) throws -> [BackfillStep] {
        var reported: [BackfillStep] = []
        let steps = try workspace.backfill(plan) { step in
            reported.append(step)
        }
        #expect(reported.map(\.commit) == steps.map(\.commit))
        return steps
    }

    @Test("every Nth pick counts from the root, so a new commit never moves earlier picks")
    func everyN() {
        #expect(SnapshotWorkspace.picks(Self.line(7), plan: Self.plan(.every(3))) == ["c0", "c3", "c6"])
        #expect(SnapshotWorkspace.picks(Self.line(8), plan: Self.plan(.every(3))) == ["c0", "c3", "c6"])
        #expect(SnapshotWorkspace.picks(Self.line(7), plan: Self.plan(.every(3), maximum: 2)) == ["c3", "c6"])
        let since = HistoryRepository.dayZero + 2 * HistoryCollector.day
        #expect(SnapshotWorkspace.picks(Self.line(7), plan: Self.plan(.every(3), since: since)) == ["c3", "c6"])
    }

    @Test("a weekly pick is each ISO week's latest commit, in UTC")
    func weekly() {
        // Day zero, 2026-01-01, is a Thursday: days 0-3 are one ISO week, 4-10 the next.
        #expect(SnapshotWorkspace.picks(Self.line(12), plan: Self.plan(.weekly)) == ["c3", "c10", "c11"])
        // Two commits 23 hours apart on either side of Sunday-to-Monday midnight UTC.
        let late = HistoryRepository.dayZero + 3 * HistoryCollector.day + 23 * 3_600
        let early = HistoryRepository.dayZero + 4 * HistoryCollector.day + 3_600
        #expect(SnapshotWorkspace.picks([("sunday", late), ("monday", early)], plan: Self.plan(.weekly))
            == ["sunday", "monday"])
    }

    @Test("""
        backfill scans picks once, skips them after, keeps a snapshot holding history on --rerun, \
        and trend follows the first-parent line with breaks where the build changed
        """)
    func backfillAndTrend() throws {
        let repository = try HistoryRepository()
        defer { repository.remove() }
        var body = "func grow() -> Int {\n    var total = 0\n"
        for week in 0..<3 {
            body += "    total += \(week)\n"
            try repository.write(["Sources/Lib/Grow.swift": body + "    return total\n}\n"])
            try repository.commit("Week \(week)", day: week * 7)
        }
        let workspace = try repository.workspace()
        _ = try workspace.scanWorkingTree()

        let first = try Self.backfill(workspace, Self.plan(.weekly))
        let second = try Self.backfill(workspace, Self.plan(.weekly))

        #expect(first.map(\.action) == [.scanned, .scanned, .skipped])
        #expect(second.map(\.action) == [.skipped, .skipped, .skipped])
        let trend = try workspace.trend(metric: "fileLength.total", scope: .project, name: "production")
        #expect(trend.points.compactMap(\.value) == [5, 6, 7])
        #expect(trend.points.allSatisfy { $0.breakReason == nil })

        let other = try repository.workspace(build: SwiftStatsBuild(identity: "inputs:other", label: nil))
        let rerun = try Self.backfill(other, Self.plan(.weekly, rerun: true))
        #expect(rerun.map(\.action) == [.scanned, .scanned, .kept])
        let rebuilt = try other.trend(metric: "fileLength.total", scope: .project, name: "production")
        #expect(rebuilt.points.map { $0.breakReason == nil } == [true, true, false])
        #expect(rebuilt.points.last?.breakReason?.hasPrefix("swiftstats: different builds") == true)
        let markdown = MarkdownTrend.render(rebuilt)
        #expect(markdown.contains("| Commit | Date | Value | Break |"))
    }

    @Test("a backfilled snapshot has no history and no tools, and says why, but has side effects")
    func backfilledCollectors() throws {
        let repository = try HistoryRepository()
        defer { repository.remove() }
        try repository.write(["Sources/Lib/One.swift": "func one() -> Int {\n    1\n}\n"])
        let commit = try repository.commit("One", day: 0)
        try repository.write(["Sources/Lib/One.swift": "func one() -> Int {\n    2\n}\n"])
        try repository.commit("Two", day: 7)
        let workspace = try repository.workspace()

        _ = try Self.backfill(workspace, Self.plan(.every(1), maximum: 2))

        let stored = try workspace.store.snapshotID(package: "Probe", packagePath: "", commit: commit, isDirty: false)
        let id = try #require(stored)
        let runs = Dictionary(uniqueKeysWithValues: try workspace.store.info(id: id).collectors.map { ($0.name, $0) })
        #expect(runs["history"]?.state == .skipped)
        #expect(runs["history"]?.reason == "backfill")
        #expect(runs["swiftlint"]?.reason == "backfill runs SwiftStats only; --with-tools adds the tools")
        #expect(runs["swiftinferproperties"]?.reason == "backfill runs SwiftStats only; --with-tools adds the tools")
        #expect(runs["swiftclonedetector"]?.reason == "backfill runs SwiftStats only; --with-tools adds the tools")
        #expect(runs["coverage"]?.state == .skipped)
        #expect(runs["coverage"]?.reason == "not requested; scan --coverage runs it")
        #expect(runs["swiftstats"]?.state == .ran)
        #expect(runs["swifteffectinference"]?.state == .ran)
        #expect(runs["swifteffectinference"]?.identity == EffectInferenceRevision.identity)
    }

    @Test("""
        a keyed count that falls to zero trends as 0, not missing, but stays missing where its module wasn't there \
        or its collector didn't run
        """)
    func keyedCountFallsToZero() throws {
        let repository = try HistoryRepository()
        defer { repository.remove() }
        let workspace = try repository.workspace()
        let logged = "func writeLog(_ text: String) {\n    print(text)\n}\n"
        let quiet = "func writeLog(_ text: String) {\n    _ = text\n}\n"
        let steps: [[String: String]] = [
            ["Sources/Core/Core.swift": "func core() -> Int {\n    1\n}\n"],
            ["Sources/Extras/Log.swift": logged],
            ["Sources/Extras/Log.swift": quiet],
            [".swiftstats.yml": "collectors:\n  swifteffectinference:\n    enabled: false\n"]
        ]
        for (day, files) in steps.enumerated() {
            try repository.write(files)
            try repository.commit("Step \(day)", day: day)
            _ = try workspace.scanWorkingTree()
        }

        let trend = try workspace.trend(metric: "effects.purity.refuted", scope: .module, name: "Extras")

        #expect(trend.points.map(\.value) == [nil, 1, 0, nil])
        #expect(trend.points.map { $0.breakReason == nil } == [true, true, true, false])
    }

    @Test("""
        a keyed count trends as 0 only beside a point that stores it, so one never collected in test code, \
        or a misspelt key, stays missing
        """)
    func keyedCountNeverStored() throws {
        let repository = try HistoryRepository()
        defer { repository.remove() }
        let workspace = try repository.workspace()
        let logged = "func writeLog(_ text: String) {\n    print(text)\n}\n"
        let quiet = "func writeLog(_ text: String) {\n    _ = text\n}\n"
        let testLog = "func logFromTest(_ text: String) {\n    print(text)\n}\n"
        let steps: [[String: String]] = [
            ["Sources/Extras/Log.swift": logged, "Tests/ExtrasTests/LogTests.swift": testLog],
            ["Sources/Extras/Log.swift": quiet]
        ]
        for (day, files) in steps.enumerated() {
            try repository.write(files)
            try repository.commit("Step \(day)", day: day)
            _ = try workspace.scanWorkingTree()
        }

        let production = try workspace.trend(metric: "effects.purity.refuted", scope: .module, name: "Extras")
        let testModule = try workspace.trend(metric: "effects.purity.refuted", scope: .module, name: "ExtrasTests")
        let testPart = try workspace.trend(metric: "effects.tier.pure", scope: .project, name: "tests")
        let misspelt = try workspace.trend(metric: "laws.state.not_run", scope: .module, name: "Extras")

        #expect(production.points.map(\.value) == [1, 0])
        #expect(testModule.points.map(\.value) == [nil, nil])
        #expect(testPart.points.map(\.value) == [nil, nil])
        #expect(misspelt.points.map(\.value) == [nil, nil])
    }
}
