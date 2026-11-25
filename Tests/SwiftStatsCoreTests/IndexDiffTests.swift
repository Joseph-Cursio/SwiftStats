//
//  IndexDiffTests.swift
//  SwiftStatsCoreTests
//
//  The index in `diff` (M7, design §3.6, §10.3), on the Diff fixture's
//  recorded dumps: the recorded USRs first, since the rule rests on what
//  the compiler names (one USR across `[Int]` → `Array<Int>` and across a
//  file move, another after a typealias is retargeted); then, with the
//  index compared, the spelling change and both moved `size(of:)`
//  overloads (whose key collision suffixes moved) matched by `usr`, and
//  the retargeted typealias giving `usr changed` under its family, in the
//  JSON and the Markdown; none of it when the index doesn't compare, the
//  build differing or one side holding no index; and the M7 roll-ups'
//  directions.
//

import Foundation
@testable import SwiftStatsCore
import Testing

@Suite("Index diff")
struct IndexDiffTests {
    /// `total(of:)` before its parameter's spelling changed.
    private static let totalBefore = "Spelling::func total(of: [Int]) -> Int"
    /// `total(of:)` after it.
    private static let totalAfter = "Spelling::func total(of: Array<Int>) -> Int"
    /// `doubled(_:)`, whose key stays while `Length` is retargeted.
    private static let doubled = "Spelling::func doubled(_: Length) -> Length"
    /// The `size(of:)` overloads' key, without its collision suffix.
    private static let size = "Spelling::func size(of: Data) -> Int"
    /// `total(of:)`'s USR on both sides.
    private static let totalUSR = "s:8Spelling5total2ofSiSaySiG_tF"
    /// `doubled(_:)`'s USR while `Length` is `Int`.
    private static let doubledInt = "s:8Spelling7doubledyS2iF"
    /// `doubled(_:)`'s USR once `Length` is `Double`.
    private static let doubledDouble = "s:8Spelling7doubledyS2dF"
    /// The `Foundation.Data` overload's USR on both sides.
    private static let foundationSize = "s:8Spelling4size2ofSi10Foundation4DataV_tF"
    /// The `Glossary.Data` overload's USR on both sides.
    private static let glossarySize = "s:8Spelling4size2ofSi8Glossary4DataV_tF"

    /// The `size(of:)` key in `file` of the Spelling module.
    private static func size(in file: String) -> String {
        "\(size) @ Sources/Spelling/\(file)"
    }

    /// `old` and `new` stored in a fresh store, read back and diffed.
    private static func diff(_ old: ScannedSnapshot, _ new: ScannedSnapshot) throws -> SnapshotDiffReport {
        let directory = try SnapshotHarness.temporaryDirectory("IndexDiff")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SnapshotStore(at: directory.appendingPathComponent("stats.sqlite"))
        let older = try store.load(id: try store.save(old))
        let newer = try store.load(id: try store.save(new))
        return SnapshotDiff.diff(older, newer)
    }

    /// The Spelling module's family changes, as `status+status key [method]`.
    private static func spelling(_ diff: SnapshotDiffReport) -> [String] {
        diff.families.filter { $0.key.hasPrefix("Spelling::") }.map { family in
            let method = family.matchedBy.map { " [\($0.rawValue)]" } ?? ""
            return family.statuses.map(\.rawValue).joined(separator: "+") + " " + family.key + method
        }
    }

    @Test("""
        the recorded index gives total(of:) one USR across [Int] → Array<Int>, each size(of:) overload one USR \
        across its move, and doubled(_:) another USR once its typealias is retargeted
        """)
    func recordedUSRs() throws {
        let before = try DiffIndexFixture.usrs("before")
        let after = try DiffIndexFixture.usrs("after")

        #expect(before[Self.totalBefore] == Self.totalUSR)
        #expect(after[Self.totalAfter] == Self.totalUSR)
        #expect(before[Self.size(in: "Bytes.swift")] == Self.foundationSize)
        #expect(after[Self.size(in: "ByteSize.swift")] == Self.foundationSize)
        #expect(before[Self.size(in: "Words.swift")] == Self.glossarySize)
        #expect(after[Self.size(in: "WordCount.swift")] == Self.glossarySize)
        #expect(before[Self.doubled] == Self.doubledInt)
        #expect(after[Self.doubled] == Self.doubledDouble)
    }

    @Test("""
        with the index compared, the spelling change and both moved size(of:) overloads are matched by usr, the \
        retargeted typealias gives usr changed under its family, and the JSON and the Markdown say so
        """)
    func matchedByUSR() throws {
        let old = try DiffIndexFixture.snapshot("before", commit: "c1")
        let new = try DiffIndexFixture.snapshot("after", commit: "c2")

        let diff = try Self.diff(old, new)

        #expect(diff.schemaVersion == 4)
        #expect(diff.collectors.first { $0.name == IndexAdapter.name }?.outcome == .compared)
        #expect(Self.spelling(diff) == [
            "usr-changed \(Self.doubled) [key]",
            "moved \(Self.size(in: "ByteSize.swift")) [usr]",
            "moved \(Self.size(in: "WordCount.swift")) [usr]",
            "renamed \(Self.totalAfter) [usr]"
        ])
        let total = try #require(diff.families.first { $0.key == Self.totalAfter })
        #expect(total.oldKey == Self.totalBefore)
        #expect(total.changedRecords.isEmpty && total.usrChanges.isEmpty)
        let bytes = try #require(diff.families.first { $0.key == Self.size(in: "ByteSize.swift") })
        #expect(bytes.oldKey == Self.size(in: "Bytes.swift"))
        #expect(bytes.oldFile == "Sources/Spelling/Bytes.swift" && bytes.newFile == "Sources/Spelling/ByteSize.swift")
        let words = try #require(diff.families.first { $0.key == Self.size(in: "WordCount.swift") })
        #expect(words.oldKey == Self.size(in: "Words.swift"))
        let retargeted = try #require(diff.families.first { $0.key == Self.doubled })
        #expect(retargeted.usrChanges == [
            USRChange(key: Self.doubled, before: Self.doubledInt, after: Self.doubledDouble)
        ])
        #expect(retargeted.changedRecords.isEmpty)
        // Neither is a delta: no function metric moved in Spelling.
        #expect(diff.functions.contains { $0.key.hasPrefix("Spelling::") } == false)
        #expect(diff.families.filter { $0.key.hasPrefix("Shapes::") }.count == 4)

        let json = try JSONEncoder().encode(diff)
        let decoded = try JSONDecoder().decode(SnapshotDiffReport.self, from: json)
        #expect(decoded == diff)
        let object = try #require(try JSONSerialization.jsonObject(with: json) as? [String: Any])
        let families = try #require(object["families"] as? [[String: Any]])
        #expect(families.filter { $0["usrChanges"] != nil }.compactMap { $0["key"] as? String } == [Self.doubled])
        #expect(families.contains { $0["matchedBy"] as? String == "usr" })

        let markdown = MarkdownDiff.render(diff)
        #expect(markdown.contains(
            "| \(Self.totalAfter) (was \(Self.totalBefore)) | renamed | Sources/Spelling/Spelling.swift | usr |"
        ))
        #expect(markdown.contains("| \(Self.doubled) | usr-changed | Sources/Spelling/Spelling.swift | key |"))
        #expect(markdown.contains("Records whose key now names another declaration (the index's USR changed):"))
        #expect(markdown.contains("| \(Self.doubled) | `\(Self.doubledInt)` | `\(Self.doubledDouble)` |"))
        #expect(markdown.contains("1 usr-changed"))
    }

    @Test("""
        when the builds differ, the index and the dead code aren't comparable, and nothing is matched by usr or \
        reported as usr changed; nor when one side holds no index
        """)
    func notCompared() throws {
        let old = try DiffIndexFixture.snapshot("before", commit: "c1")
        let otherBuild = try DiffIndexFixture.snapshot("after", commit: "c2", build: "swift-6.4.1-test")
        let expected = [
            "added \(Self.size(in: "ByteSize.swift"))",
            "removed \(Self.size(in: "Bytes.swift"))",
            "added \(Self.size(in: "WordCount.swift"))",
            "removed \(Self.size(in: "Words.swift"))",
            "added \(Self.totalAfter)",
            "removed \(Self.totalBefore)"
        ]

        let differentBuilds = try Self.diff(old, otherBuild)

        let index = try #require(differentBuilds.collectors.first { $0.name == IndexAdapter.name })
        #expect(index.outcome == .notComparable)
        #expect(index.reason == "the build differs: the index and the dead code come from it")
        #expect(differentBuilds.collectors.first { $0.name == BuildAdapter.name }?.outcome == .notComparable)
        #expect(differentBuilds.collectors.first { $0.name == SwiftStatsCollector.name }?.outcome == .compared)
        #expect(Self.spelling(differentBuilds) == expected)
        #expect(differentBuilds.families.allSatisfy { $0.usrChanges.isEmpty && $0.matchedBy != .usr })

        let plain = IndexStoreSamples.plain(try DiffIndexFixture.snapshot("after", commit: "c2"))
        let oneSided = try Self.diff(old, plain)

        #expect(oneSided.collectors.first { $0.name == IndexAdapter.name }?.outcome == .notCollected)
        #expect(Self.spelling(oneSided) == expected)
        #expect(MarkdownDiff.render(oneSided).contains("USR before") == false)
    }

    @Test("a snapshot holding index results diffed with itself is empty")
    func selfDiff() throws {
        let snapshot = try DiffIndexFixture.snapshot("after", commit: "c2")

        let diff = try Self.diff(snapshot, snapshot)

        #expect(diff.isEmpty, "\(diff)")
        #expect(diff.collectors.first { $0.name == IndexAdapter.name }?.outcome == .compared)
        #expect(MarkdownDiff.render(diff).contains("No changes."))
    }

    @Test("""
        M7's roll-ups diff as design §10.3 says: disagreements, type cycles, unused declarations, dead records, \
        dead lines and compiler warnings lower; records with and without a USR, module edges, declarations \
        without a line count and type-check times neutral
        """)
    func directions() {
        let lower = [
            "index.disagreements", "index.typeCycles", "index.typesInCycles",
            "deadCode.unused.function", "deadCode.unused.enumCase", "deadCode.records", "deadCode.productionRecords",
            "tests.lineRatio.deadLines", "findings.swiftc.pbd_never_used"
        ]
        let neutral = [
            "index.withUSR", "index.withoutUSR.inactiveIfBranch", "index.withoutUSR.unexplained", "index.moduleEdges",
            "deadCode.unsized", "typecheck.milliseconds.total", "typecheck.milliseconds.max",
            "typecheck.slowestExpression.max", "typecheck.functions.timed"
        ]

        #expect(lower.contains { MetricDirection.of($0) != .lowerIsBetter } == false)
        #expect(neutral.contains { MetricDirection.of($0) != .neutral } == false)
        #expect(MetricDirection.of("tests.lineRatio.testLines") == .higherIsBetter)
        #expect(MetricDelta(metric: "tests.lineRatio.deadLines", before: 30, after: 12).verdict == .better)
        #expect(MetricDelta(metric: "index.withoutUSR.inactiveIfBranch", before: 0, after: 3).verdict == .neutral)
    }
}
