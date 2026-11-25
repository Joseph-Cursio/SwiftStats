import Foundation
@testable import SwiftStatsCore
import Testing

/// `backfill` and `trend` at the edges (PRD §7.13, §10): a renamed package,
/// a package newer than its repository, results a backfill can't collect
/// (`BackfillHeldTests` covers coverage, mutation and T1 results),
/// collectors that ran on neither side, and snapshots no longer reachable.
@Suite("Backfill and trend edges")
struct BackfillEdgeTests {
    /// A plan picking every `step`th commit.
    private static func every(_ step: Int, rerun: Bool = false, withTools: Bool = false) -> BackfillPlan {
        BackfillPlan(selection: .every(step), since: nil, maximumCommits: nil, rerun: rerun, withTools: withTools)
    }

    /// Backfills with `plan`.
    private static func backfill(_ workspace: SnapshotWorkspace, _ plan: BackfillPlan) throws -> [BackfillStep] {
        try workspace.backfill(plan) { _ in
            // Progress isn't checked here.
        }
    }

    /// A function `one` returning `value`.
    private static func one(_ value: Int) -> String {
        "func one() -> Int {\n    \(value)\n}\n"
    }

    @Test("a snapshot taken under the package's old name is skipped, not replaced")
    func renamedPackage() throws {
        let repository = try HistoryRepository()
        defer { repository.remove() }
        try repository.write([
            "Package.swift": "// swift-tools-version: 6.0\nlet name = Package(name: \"Demo\")\n",
            "Sources/Lib/One.swift": Self.one(1)
        ])
        let first = try repository.commit("One", day: 0)
        let workspace = try repository.workspace()
        let scanned = try workspace.scanWorkingTree().id
        try repository.write(["Package.swift": "// swift-tools-version: 6.0\nlet name = Package(name: \"Renamed\")\n"])
        try repository.commit("Rename the package", day: 1)

        let steps = try Self.backfill(workspace, Self.every(1))
        let again = try Self.backfill(workspace, Self.every(1))

        #expect(steps.map(\.action) == [.skipped, .scanned])
        #expect(again.map(\.action) == [.skipped, .skipped])
        let kept = try workspace.store.snapshotID(package: "Demo", packagePath: "", commit: first, isDirty: false)
        #expect(kept == scanned)
        let history = try workspace.store.info(id: scanned).collectors.first { $0.name == HistoryCollector.name }
        #expect(history?.state == .ran)
    }

    @Test("a package newer than its repository is backfilled from its first commit, and nothing fails")
    func newerPackage() throws {
        let repository = try HistoryRepository()
        defer { repository.remove() }
        try repository.write(["Sources/Outer/Outer.swift": "func outer() {}\n"])
        try repository.commit("Outer", day: 0)
        try repository.write([
            "Packages/Inner/Package.swift": "// swift-tools-version: 6.0\n",
            "Packages/Inner/Sources/Inner/One.swift": Self.one(1)
        ])
        let created = try repository.commit("Add the inner package", day: 1)
        try repository.write(["Packages/Inner/Sources/Inner/One.swift": Self.one(2)])
        let changed = try repository.commit("Change it", day: 2)
        let workspace = try SnapshotWorkspace(
            packageRoot: repository.root.appendingPathComponent("Packages/Inner"),
            configurationFile: nil,
            storeOverride: nil,
            build: SnapshotHarness.build,
            describer: HistoryRepository.DiskDescriber(),
            tools: SnapshotHarness.noTools
        )

        let everySecond = try Self.backfill(workspace, Self.every(2))
        let all = try Self.backfill(workspace, Self.every(1))

        #expect(everySecond.map(\.commit) == [created])
        #expect(everySecond.map(\.action) == [.scanned])
        #expect(all.map(\.commit) == [created, changed])
        #expect(all.map(\.action) == [.skipped, .scanned])
    }

    @Test("--rerun keeps a snapshot holding results the new scan didn't collect")
    func rerunKeepsLostResults() throws {
        let repository = try HistoryRepository()
        defer { repository.remove() }
        try repository.write(["Sources/Lib/One.swift": Self.one(1)])
        try repository.commit("One", day: 0)
        let tool = try FakeTool.make(outputs: ["0.65.1\n", "[]"], errorText: "", statuses: [0])
        defer { try? FileManager.default.removeItem(at: tool.deletingLastPathComponent()) }
        let linted = try SnapshotWorkspace(
            packageRoot: repository.root,
            configurationFile: nil,
            storeOverride: nil,
            build: SnapshotHarness.build,
            describer: HistoryRepository.DiskDescriber(),
            tools: ToolLocator { $0 == "swiftlint" ? tool : nil }
        )
        let id = try linted.scanWorkingTree(history: .skipped("test")).id
        let lint = try linted.store.info(id: id).collectors.first { $0.name == SwiftLintAdapter.name }
        try #require(lint?.state == .ran)
        let other = try repository.workspace(build: SwiftStatsBuild(identity: "inputs:other", label: nil))

        let steps = try Self.backfill(other, Self.every(1, rerun: true, withTools: true))

        #expect(steps.map(\.action) == [.kept])
        #expect(steps.first?.note?.contains("swiftlint") == true)
        #expect(try other.store.snapshotID(package: "Probe", packagePath: "", commit: steps[0].commit, isDirty: false)
            == id)
    }

    @Test("--rerun without tools keeps a snapshot holding SwiftInferProperties' results")
    func rerunKeepsHeldSuggestions() throws {
        let repository = try HistoryRepository()
        defer { repository.remove() }
        try repository.write(["Sources/Lib/One.swift": Self.one(1)])
        try repository.commit("One", day: 0)
        let row = PropertyHarness.Row(identity: "0x00000000000000AA", location: "@ROOT@/Sources/Lib/One.swift:1")
        let tool = try FakeTool.makeIndexer(
            indexes: ["Lib": PropertyHarness.index([row])],
            errors: [:],
            statuses: [:],
            delays: [:]
        )
        defer { PropertyHarness.remove(tool) }
        let indexed = try SnapshotWorkspace(
            packageRoot: repository.root,
            configurationFile: nil,
            storeOverride: nil,
            build: SnapshotHarness.build,
            describer: HistoryRepository.DiskDescriber(),
            tools: PropertyHarness.locator(tool)
        )
        let id = try indexed.scanWorkingTree(history: .skipped("test")).id
        let run = try indexed.store.info(id: id).collectors.first { $0.name == SwiftInferPropertiesAdapter.name }
        try #require(run?.state == .ran)
        #expect(run?.identity?.hasPrefix("sha256:") == true)
        let other = try repository.workspace(build: SwiftStatsBuild(identity: "inputs:other", label: nil))

        let steps = try Self.backfill(other, Self.every(1, rerun: true))

        #expect(steps.map(\.action) == [.kept])
        #expect(steps.first?.note?.contains("swiftinferproperties") == true)
        #expect(try other.store.snapshotID(package: "Probe", packagePath: "", commit: steps[0].commit, isDirty: false)
            == id)
    }

    @Test("--rerun without tools keeps a snapshot holding SwiftCloneDetector's results")
    func rerunKeepsHeldClones() throws {
        let repository = try HistoryRepository()
        defer { repository.remove() }
        try repository.write(["Sources/Lib/One.swift": Self.one(1)])
        try repository.commit("One", day: 0)
        let empty = """
            {"cloneCount": 0, "clones": [], "duplicatedLines": 0, "fileCount": 1, "mode": "type1-2",
             "tool": "swift-clone-detector", "version": "0.1.0"}
            """
        let runs = ["default", "--type3", "--sequence", "--type1"]
        let outputs = Dictionary(uniqueKeysWithValues: runs.map { ($0, empty) })
        let tool = try FakeTool.makeCloneDetector(outputs: outputs, errors: [:], statuses: [:])
        defer { CloneHarness.remove(tool) }
        let detected = try SnapshotWorkspace(
            packageRoot: repository.root,
            configurationFile: nil,
            storeOverride: nil,
            build: SnapshotHarness.build,
            describer: HistoryRepository.DiskDescriber(),
            tools: CloneHarness.locator(tool)
        )
        let id = try detected.scanWorkingTree(history: .skipped("test")).id
        let run = try detected.store.info(id: id).collectors.first { $0.name == SwiftCloneDetectorAdapter.name }
        try #require(run?.state == .ran)
        #expect(run?.identity?.hasPrefix("sha256:") == true)
        let other = try repository.workspace(build: SwiftStatsBuild(identity: "inputs:other", label: nil))

        let steps = try Self.backfill(other, Self.every(1, rerun: true))

        #expect(steps.map(\.action) == [.kept])
        #expect(steps.first?.note?.contains("swiftclonedetector") == true)
        #expect(try other.store.snapshotID(package: "Probe", packagePath: "", commit: steps[0].commit, isDirty: false)
            == id)
    }

    @Test("a tool metric doesn't break between snapshots where the tool ran on neither side")
    func toolMetricWithoutTool() throws {
        let repository = try HistoryRepository()
        defer { repository.remove() }
        for day in 0..<3 {
            try repository.write(["Sources/Lib/One.swift": Self.one(day)])
            try repository.commit("Day \(day)", day: day)
        }
        let workspace = try repository.workspace()
        _ = try Self.backfill(workspace, Self.every(1))

        let trend = try workspace.trend(metric: "findings.swiftlint.total", scope: .project, name: "production")

        #expect(trend.points.count == 3)
        #expect(trend.points.allSatisfy { $0.breakReason == nil })
    }

    @Test("trend counts snapshots of merged branches as off the line, not those no longer reachable")
    func offLine() throws {
        let repository = try HistoryRepository()
        defer { repository.remove() }
        try repository.write(["Sources/Lib/One.swift": Self.one(0)])
        try repository.commit("Start", day: 0)
        let workspace = try repository.workspace()
        _ = try workspace.scanWorkingTree(history: .skipped("test"))
        for (branch, day) in [("merged", 1), ("gone", 3)] {
            try repository.git(["checkout", "-q", "-b", branch, "main"])
            try repository.write(["Sources/Lib/One.swift": Self.one(day)])
            try repository.commit("On \(branch)", day: day)
            _ = try workspace.scanWorkingTree(history: .skipped("test"))
            try repository.git(["checkout", "-q", "main"])
        }
        try repository.git(["merge", "-q", "--no-ff", "-m", "Merge", "merged"], environment: HistoryRepository.dated(2))
        try repository.git(["branch", "-q", "-D", "gone"])

        let trend = try workspace.trend(metric: "fileLength.total", scope: .project, name: "production")

        #expect(trend.points.count == 1)
        #expect(trend.offLine == 1)
    }
}
