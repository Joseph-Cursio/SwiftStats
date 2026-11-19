import Foundation
@testable import SwiftStatsCore
import Testing

/// Signal edge cases (PRD §8, §10): a subscript whose complexity is in its
/// accessors, and how a report and `top` say what they left out.
@Suite("Signal edges")
struct SignalEdgeTests {
    /// A struct whose subscript has a branching getter and a setter; `tweak`
    /// changes the setter's body.
    private static func odd(tweak: Int) -> String {
        """
        struct Odd {
            var stored = 0
            subscript(index: Int) -> Int {
                get {
                    if index > 1 {
                        return 1
                    }
                    return 0
                }
                set {
                    stored = newValue + \(tweak)
                }
            }
        }

        """
    }

    /// `count` member items of a signal.
    private static func items(_ count: Int) -> [SignalItem] {
        (1...count).map { rank in
            SignalItem(
                rank: rank,
                family: "Lib::func f\(rank)()",
                file: "Sources/Lib/F.swift",
                line: rank,
                score: Double(count - rank + 1),
                member: true,
                changes: 1,
                cognitive: 1,
                fixes: 0,
                allFixes: 0,
                fixScore: 0,
                reverts: 0,
                repeatedFixes: 0,
                testChanges: 0,
                firstSeen: nil,
                tracedBy: .key
            )
        }
    }

    @Test("a subscript with explicit accessors takes its cognitive complexity from them")
    func subscriptAccessors() throws {
        let repository = try HistoryRepository()
        defer { repository.remove() }
        try repository.write(["Sources/Lib/Odd.swift": Self.odd(tweak: 0)])
        try repository.commit("Add odd", day: 0)
        try repository.write(["Sources/Lib/Odd.swift": Self.odd(tweak: 1)])
        try repository.commit("Change the setter", day: 200)
        let workspace = try repository.workspace()
        let id = try workspace.scanWorkingTree().id

        let hotspot = try #require(try workspace.signals(id: id).first { $0.name == .hotspot })
        let item = try #require(hotspot.items.first { $0.family.contains("subscript") })

        #expect(item.cognitive == 1)
        #expect(item.score == 1)
    }

    @Test("a report's pointer to the rest of a signal asks top for all its members")
    func reportPointer() {
        let many = SignalResult(name: .safeToLeave, leftOut: nil, rule: "rule", candidates: 30, items: Self.items(25))
        let few = SignalResult(name: .safeToLeave, leftOut: nil, rule: "rule", candidates: 30, items: Self.items(15))

        let manyLines = MarkdownSignals.render([many], history: nil)
        let fewLines = MarkdownSignals.render([few], history: nil)

        #expect(manyLines.contains("15 more: `swiftstats top safe-to-leave --limit 25`."))
        #expect(fewLines.contains("5 more: `swiftstats top safe-to-leave`."))
    }

    @Test("top's JSON says how many items are ranked and are members before the cut")
    func topCounts() {
        let signal = SignalResult(name: .hotspot, leftOut: nil, rule: "rule", candidates: 30, items: Self.items(25))
        let info = SnapshotInfo(
            package: "Probe",
            git: GitState(commit: nil, branch: nil, isDirty: false, dirtyHash: nil, packagePath: ""),
            date: "2026-01-01T00:00:00Z",
            toolchain: SnapshotHarness.toolchain,
            collectors: []
        )

        let top = TopReport(snapshot: info, signal: signal, limit: 2)

        #expect(top.signal.items.count == 2)
        #expect(top.ranked == 25)
        #expect(top.members == 25)
    }
}
