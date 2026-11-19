import Foundation
@testable import SwiftStatsCore
import Testing

/// The history collector on repositories built at test time (PRD §7.13).
@Suite("History")
struct HistoryTests {
    @Test("changes are counted per commit, a pure move isn't a change, and the first commit is the first sighting")
    func churnAndMoves() throws {
        let repository = try HistoryRepository()
        defer { repository.remove() }
        try repository.write(["Sources/Lib/Shape.swift": HistorySources.area()])
        try repository.commit("Add the shape", day: 0)
        try repository.write(["Sources/Lib/Shape.swift": HistorySources.area(extra: "_ = 1\n        ")])
        try repository.commit("Tweak the area", day: 10)
        try repository.write(["Sources/Lib/Shape.swift": HistorySources.area(extra: "_ = 2\n        ")])
        try repository.commit("Tweak it again", day: 20)
        try repository.move("Sources/Lib/Shape.swift", to: "Sources/Lib/Geometry/Shape.swift")
        try repository.commit("Move the shape", day: 30)

        let history = try repository.history()
        let area = try #require(history.family("func area()"))

        #expect(area.changes == 3)
        #expect(area.allChanges == 3)
        #expect(area.file == "Sources/Lib/Geometry/Shape.swift")
        #expect(area.firstSeen == HistoryCollector.date(HistoryRepository.dayZero))
        #expect(area.lastChanged == HistoryCollector.date(HistoryRepository.dayZero + 20 * HistoryCollector.day))
        #expect(area.tracedBy == .key)
        #expect(history.commits == 4)
        #expect(history.date == HistoryCollector.date(HistoryRepository.dayZero + 30 * HistoryCollector.day))
    }

    @Test("a signature change with a body edit keeps the lineage, matched by name, and counts as a change")
    func signatureChange() throws {
        let repository = try HistoryRepository()
        defer { repository.remove() }
        try repository.write(["Sources/Lib/Shape.swift": HistorySources.area()])
        try repository.commit("Add the shape", day: 0)
        let scaled = HistorySources.area(extra: "_ = scale\n        ", parameters: "scale: Int")
        try repository.write(["Sources/Lib/Shape.swift": scaled])
        try repository.commit("Scale the area", day: 5)

        let area = try #require(try repository.history().family("func area(scale: Int)"))

        #expect(area.allChanges == 2)
        #expect(area.firstSeen == HistoryCollector.date(HistoryRepository.dayZero))
        #expect(area.tracedBy == .sameName)
    }

    @Test("a rename with a small edit is matched by a similar body, and labelled a guess")
    func similarBody() throws {
        let repository = try HistoryRepository()
        defer { repository.remove() }
        let body = { (name: String, last: String) in
            """
            func \(name)() -> Int {
                let first = 1
                let second = 2
                let third = 3
                let fourth = 4
                let fifth = 5
                let sixth = 6
                return first + second + third + fifth + sixth + \(last)
            }

            """
        }
        try repository.write(["Sources/Lib/Sum.swift": body("total", "fourth")])
        try repository.commit("Add the sum", day: 0)
        try repository.write(["Sources/Lib/Sum.swift": body("sum", "fourth * 2")])
        try repository.commit("Rename the sum", day: 3)

        let sum = try #require(try repository.history().family("func sum()"))

        #expect(sum.allChanges == 2)
        #expect(sum.tracedBy == .similarBody)
    }

    @Test("a move to another target keeps the lineage")
    func moduleMove() throws {
        let repository = try HistoryRepository()
        defer { repository.remove() }
        try repository.write([
            "Sources/Old/Shape.swift": HistorySources.area(),
            "Sources/New/Keep.swift": "func keep() {}\n"
        ])
        try repository.commit("Add the shape", day: 0)
        try repository.move("Sources/Old/Shape.swift", to: "Sources/New/Shape.swift")
        try repository.commit("Move it to New", day: 4)

        let area = try #require(try repository.history().family("New::Shape::func area()"))

        #expect(area.allChanges == 1)
        #expect(area.firstSeen == HistoryCollector.date(HistoryRepository.dayZero))
        #expect(area.tracedBy == .moduleMovedKey)
    }

    @Test("fixes, excluded subjects, reverts, repeated fixes and sweeps are told apart")
    func commitKinds() throws {
        let repository = try HistoryRepository()
        defer { repository.remove() }
        try repository.write([
            ".swiftstats.yml": "history:\n  bulk_files: 3\n",
            "Sources/Lib/Shape.swift": HistorySources.area(),
            "Sources/Lib/Other.swift": "func other() -> Int {\n    1\n}\n",
            "Sources/Lib/Third.swift": "func third() -> Int {\n    3\n}\n"
        ])
        try repository.commit("Add the shapes", day: 0)
        try repository.write(["Sources/Lib/Shape.swift": HistorySources.area(extra: "_ = 1\n        ")])
        try repository.commit("Fix the area", day: 10)
        try repository.write(["Sources/Lib/Shape.swift": HistorySources.area(extra: "_ = 2\n        ")])
        try repository.commit("Fix the area again", day: 12)
        try repository.write(["Sources/Lib/Shape.swift": HistorySources.area(extra: "_ = 3\n        ")])
        try repository.commit("Fix the SwiftLint warnings", day: 14)
        try repository.write(["Sources/Lib/Shape.swift": HistorySources.area(extra: "_ = 2\n        ")])
        try repository.commit("Revert \"Fix the SwiftLint warnings\"", day: 15)
        try repository.write([
            "Sources/Lib/Shape.swift": HistorySources.area(extra: "_ = 4\n        "),
            "Sources/Lib/Other.swift": "func other() -> Int {\n    2\n}\n",
            "Sources/Lib/Third.swift": "func third() -> Int {\n    4\n}\n",
            "Sources/Lib/Fourth.swift": "func fourth() -> Int {\n    4\n}\n"
        ])
        try repository.commit("Fix everything at once", day: 16)

        let history = try repository.history()
        let area = try #require(history.family("func area()"))

        #expect(area.allChanges == 6)
        #expect(area.changes == 5)
        #expect(area.sweepChanges == 1)
        #expect(area.fixes == 2)
        #expect(area.allFixes == 2)
        #expect(area.repeatedFixes == 1)
        #expect(area.reverts == 1)
        #expect(history.sweepCommits.map(\.subject) == ["Fix everything at once"])
        let excluded = history.fixCommits.filter { $0.excluded != nil }.map { "\($0.subject): \($0.excluded ?? "")" }
        #expect(excluded.sorted() == ["Fix everything at once: sweep", "Fix the SwiftLint warnings: excluded-subject"])
        #expect(history.revertCommits.count == 1)
        // Two fixes, 6 and 4 days before the analysed commit, with a 90-day half-life.
        let expected = pow(0.5, 6.0 / 90) + pow(0.5, 4.0 / 90)
        #expect(abs((area.fixScore ?? 0) - expected) < 0.0001)
    }

    @Test("the window comes from the analysed commit's date: older changes count only in all-time totals")
    func window() throws {
        let repository = try HistoryRepository()
        defer { repository.remove() }
        try repository.write([
            ".swiftstats.yml": "history:\n  window: 30d\n",
            "Sources/Lib/Shape.swift": HistorySources.area()
        ])
        try repository.commit("Add the shape", day: 0)
        try repository.write(["Sources/Lib/Shape.swift": HistorySources.area(extra: "_ = 1\n        ")])
        try repository.commit("Change it", day: 100)

        let history = try repository.history()
        let area = try #require(history.family("func area()"))

        #expect(area.changes == 1)
        #expect(area.allChanges == 2)
        #expect(history.windowDays == 30)
        #expect(history.windowCommits == 1)
    }

    @Test("on a dirty tree, an uncommitted function has no history and an uncommitted rename keeps it")
    func dirtyTree() throws {
        let repository = try HistoryRepository()
        defer { repository.remove() }
        try repository.write(["Sources/Lib/Shape.swift": HistorySources.area()])
        try repository.commit("Add the shape", day: 0)
        try repository.write(["Sources/Lib/Shape.swift": HistorySources.area(extra: "_ = 1\n        ")])
        try repository.commit("Change it", day: 1)
        try repository.write([
            "Sources/Lib/Shape.swift": HistorySources.area("surface", extra: "_ = 1\n        "),
            "Sources/Lib/New.swift": "func brandNew() -> Int {\n    1\n}\n"
        ])

        let history = try repository.history()
        let fresh = try #require(history.family("func brandNew()"))
        let renamed = try #require(history.family("func surface()"))

        #expect(fresh.tracedBy == .uncommitted)
        #expect(fresh.changes == nil && fresh.allChanges == nil && fresh.firstSeen == nil)
        #expect(renamed.allChanges == 2)
        #expect(renamed.tracedBy == .bodyHash)
    }

    @Test("a package in a subdirectory reads only its own history, with paths from its root")
    func subdirectoryPackage() throws {
        let repository = try HistoryRepository()
        defer { repository.remove() }
        try repository.write([
            "Packages/Inner/Package.swift": "// swift-tools-version: 6.0\n",
            "Packages/Inner/Sources/Inner/Shape.swift": HistorySources.area(),
            "Sources/Outer/Outer.swift": "func outer() {}\n"
        ])
        try repository.commit("Add both", day: 0)
        try repository.write(["Sources/Outer/Outer.swift": "func outer() { _ = 1 }\n"])
        try repository.commit("Change the outer package", day: 2)
        let inner = repository.root.appendingPathComponent("Packages/Inner")

        let report = try repository.scanner().scan(
            packageAt: inner,
            configurationFile: nil,
            toolchain: SnapshotHarness.toolchain,
            date: SnapshotHarness.date
        ).report
        let history = try #require(report.history)

        #expect(history.commits == 1)
        #expect(history.family("func area()")?.file == "Sources/Inner/Shape.swift")
        #expect(history.family("func area()")?.allChanges == 1)
    }

    @Test("history doesn't depend on the repository's own git settings, and reads the same twice")
    func pinnedSettings() throws {
        let repository = try HistoryRepository()
        defer { repository.remove() }
        try repository.write(["Sources/Lib/Shape.swift": HistorySources.area()])
        try repository.commit("Add the shape", day: 0)
        try repository.move("Sources/Lib/Shape.swift", to: "Sources/Lib/Renamed.swift")
        try repository.commit("Rename the file", day: 1)
        let plain = try repository.history()

        for setting in ["log.showRoot=false", "diff.renames=false", "diff.relative=true", "core.quotepath=true"] {
            let parts = setting.split(separator: "=").map(String.init)
            try repository.git(["config", parts[0], parts[1]])
        }

        #expect(try repository.history() == plain)
        #expect(plain.family("func area()")?.allChanges == 1)
    }
}
