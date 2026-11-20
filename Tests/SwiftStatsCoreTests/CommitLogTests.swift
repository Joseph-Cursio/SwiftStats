import Foundation
@testable import SwiftStatsCore
import Testing

/// History's commit log and each family's changes (PRD §7.13, M4), as the
/// scan JSON carries them and the store keeps them.
@Suite("Commit log")
struct CommitLogTests {
    /// A repository of six commits, one touching no Swift file, with a fix,
    /// an excluded fix subject and a sweep, and an uncommitted function.
    private static func repository() throws -> HistoryRepository {
        let repository = try HistoryRepository()
        try repository.write([
            ".swiftstats.yml": "history:\n  bulk_files: 3\n",
            "Sources/Lib/Shape.swift": HistorySources.area(),
            "Sources/Lib/Other.swift": "func other() -> Int {\n    1\n}\n",
            "Sources/Lib/Third.swift": "func third() -> Int {\n    3\n}\n"
        ])
        try repository.commit("Add the shapes", day: 0)
        try repository.write(["README.md": "Shapes.\n"])
        try repository.commit("Write the readme", day: 5)
        try repository.write(["Sources/Lib/Shape.swift": HistorySources.area(extra: "_ = 1\n        ")])
        try repository.commit("Fix the area", day: 10)
        try repository.write(["Sources/Lib/Other.swift": "func other() -> Int {\n    2\n}\n"])
        try repository.commit("Tweak the other", day: 12)
        try repository.write(["Sources/Lib/Shape.swift": HistorySources.area(extra: "_ = 2\n        ")])
        try repository.commit("Fix the SwiftLint warnings", day: 14)
        try repository.write([
            "Sources/Lib/Shape.swift": HistorySources.area(extra: "_ = 3\n        "),
            "Sources/Lib/Other.swift": "func other() -> Int {\n    3\n}\n",
            "Sources/Lib/Third.swift": "func third() -> Int {\n    4\n}\n",
            "Sources/Lib/Fourth.swift": "func fourth() -> Int {\n    4\n}\n"
        ])
        try repository.commit("Fix everything at once", day: 16)
        try repository.write(["Sources/Lib/Fifth.swift": "func fifth() -> Int {\n    5\n}\n"])
        return repository
    }

    @Test("the log holds the commits that changed Swift files, newest first, flagging sweeps and counted fixes")
    func commitLog() throws {
        let repository = try Self.repository()
        defer { repository.remove() }

        let history = try repository.history()

        let hashes = try repository.git(["log", "--format=%H", "--", "Sources"]).split(separator: "\n").map(String.init)
        #expect(history.commitLog.map(\.hash) == hashes)
        #expect(history.commitLog.count == history.commits)
        #expect(history.commitLog.map(\.sweep) == [true, false, false, false, false])
        #expect(history.commitLog.map(\.fix) == [false, false, false, true, false])
        let days = [16, 14, 12, 10, 0].map { day in
            HistoryCollector.date(HistoryRepository.dayZero + day * HistoryCollector.day)
        }
        #expect(history.commitLog.map(\.date) == days)
    }

    @Test("a family's changedBy indexes the log, sweeps included; a family with no history has none")
    func changedBy() throws {
        let repository = try Self.repository()
        defer { repository.remove() }

        let history = try repository.history()

        let area = try #require(history.family("func area()"))
        #expect(area.changedBy == CommitOrdinals([0, 1, 3, 4]))
        #expect(area.changedBy?.ordinals.count == area.allChanges)
        #expect(history.family("func other()")?.changedBy == CommitOrdinals([0, 2, 4]))
        #expect(history.family("func fourth()")?.changedBy == CommitOrdinals([0]))
        let fifth = try #require(history.family("func fifth()"))
        #expect(fifth.tracedBy == .uncommitted)
        #expect(fifth.changedBy == nil)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let areaJSON = String(bytes: try encoder.encode(area), encoding: .utf8) ?? ""
        let fifthJSON = String(bytes: try encoder.encode(fifth), encoding: .utf8) ?? ""
        #expect(areaJSON.contains(#""changedBy":[0,1,3,4]"#))
        #expect(fifthJSON.contains("changedBy") == false)
        #expect(try JSONDecoder().decode(HistoryReport.self, from: try encoder.encode(history)) == history)
    }

    @Test("the store keeps the log and one row per family change, none for a family with no history")
    func storedChanges() throws {
        let repository = try Self.repository()
        defer { repository.remove() }
        let workspace = try repository.workspace()

        let (snapshot, id) = try workspace.scanWorkingTree()
        let stored = try workspace.store.load(id: id)

        let history = try #require(snapshot.report.history)
        #expect(stored.historyCommits == history.commitLog)
        let expected = history.families.flatMap { family in
            (family.changedBy?.ordinals ?? []).map { "\(family.family)|\(family.file)|\($0)" }
        }
        let rows = stored.familyChanges.map { "\($0.family)|\($0.file)|\($0.commitOrdinal)" }
        #expect(rows.sorted() == expected.sorted())
        #expect(stored.familyChanges.filter { $0.family.contains("func area()") }.map(\.commitOrdinal) == [0, 1, 3, 4])
        #expect(stored.familyChanges.contains { $0.family.contains("func fifth()") } == false)
        #expect(try workspace.store.report(id: id) == snapshot.report)
    }
}
