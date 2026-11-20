import Foundation
@testable import SwiftStatsCore
import Testing

/// How SwiftStats numbers clone classes that share their first copy
/// (PRD §7.12): by pass, the most specific first, then by mass, largest
/// first, whatever the tool's order or the merge's. The outputs are
/// hand-written over the Clones fixture's files, since the recorded runs
/// have no two classes with the same first copy.
@Suite("Clone numbering ties")
struct CloneNumberingTests {
    /// `total` in Core: the first copy of every class here.
    private static var total: [String: Any] {
        copy("Sources/Core/Totals.swift", (2, 1), (8, 2))
    }

    /// A copy as the tool writes it, from `start` to `end` as (line,
    /// column), the end column exclusive.
    private static func copy(_ path: String, _ start: (Int, Int), _ end: (Int, Int)) -> [String: Any] {
        ["path": path, "startLine": start.0, "startColumn": start.1, "endLine": end.0, "endColumn": end.1]
    }

    /// A class as the tool writes it; `similarity` only for near-miss runs.
    private static func clone(
        _ fingerprint: String,
        mass: Int,
        _ instances: [[String: Any]],
        similarity: Double? = nil
    ) -> [String: Any] {
        var clone: [String: Any] = [
            "fingerprint": fingerprint, "mass": mass, "lineSpan": 7, "instances": instances
        ]
        clone["similarity"] = similarity
        return clone
    }

    /// A run's JSON report holding `clones`, in the given order.
    private static func report(_ clones: [[String: Any]]) throws -> String {
        let object: [String: Any] = [
            "tool": "swift-clone-detector", "version": "0.1.0", "duplicatedLines": 0, "clones": clones
        ]
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(bytes: data, encoding: .utf8) ?? ""
    }

    /// A fake tool whose runs report, all with `total` as their first copy:
    /// two subtree classes of masses 100 and 50, a sequence class of mass
    /// 150 and a near-miss class of mass 200, each class's copies in
    /// `reversedCopies` order and the subtree run's classes smaller first.
    private static func tool(reversedCopies: Bool) throws -> URL {
        let order = { (copies: [[String: Any]]) in reversedCopies ? Array(copies.reversed()) : copies }
        let ledger = copy("Sources/Extras/Ledger.swift", (4, 1), (10, 2))
        let codes = copy("Sources/Extras/Codes.swift", (2, 1), (13, 2))
        let ledgerBody = copy("Sources/Extras/Ledger.swift", (5, 5), (9, 15))
        let boxes = copy("Sources/Extras/Boxes.swift", (2, 1), (11, 2))
        return try FakeTool.makeCloneDetector(
            outputs: [
                "default": try report([
                    clone("smallsubtree0000", mass: 50, order([total, codes])),
                    clone("largesubtree0000", mass: 100, order([total, ledger]))
                ]),
                "--sequence": try report([clone("sequence00000000", mass: 150, order([total, ledgerBody]))]),
                "--type3": try report([
                    clone("nearmiss00000000", mass: 200, order([total, boxes]), similarity: 0.8)
                ]),
                "--type1": try report([])
            ],
            errors: [:],
            statuses: [:]
        )
    }

    @Test("""
        classes sharing their first copy are numbered by pass, subtree before sequence before near-miss, \
        then by mass, largest first, not in the tool's or the merge's order
        """)
    func ties() throws {
        let tool = try Self.tool(reversedCopies: false)
        defer { CloneHarness.remove(tool) }

        let report = try CloneHarness.scan(tool)

        let classes = try #require(report.clones?.classes)
        #expect(classes.map(\.ordinal) == [1, 2, 3, 4])
        #expect(classes.map(\.fingerprint) == [
            "largesubtree0000", "smallsubtree0000", "sequence00000000", "nearmiss00000000"
        ])
        #expect(classes.map(\.pass) == [.subtree, .subtree, .sequence, .nearMiss])
        #expect(classes.map(\.mass) == [100, 50, 150, 200])
        let first = try #require(classes.first?.instances.first)
        #expect(first.file == "Sources/Core/Totals.swift")
        #expect(first.range == SourceSpan(
            start: SourcePosition(line: 2, column: 1), end: SourcePosition(line: 8, column: 1)
        ))
        #expect(classes.allSatisfy { $0.instances.first == first })
    }

    @Test("the copies in another order give the same numbering")
    func tiesOrderFree() throws {
        let forward = try Self.tool(reversedCopies: false)
        defer { CloneHarness.remove(forward) }
        let backward = try Self.tool(reversedCopies: true)
        defer { CloneHarness.remove(backward) }

        let first = try CloneHarness.scan(forward)
        let second = try CloneHarness.scan(backward)

        #expect(first.clones?.classes.map(\.fingerprint) == second.clones?.classes.map(\.fingerprint))
        #expect(first.clones == second.clones)
    }
}
