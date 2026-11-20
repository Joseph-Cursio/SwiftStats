import Foundation
@testable import SwiftStatsCore
import Testing

/// SwiftCloneDetector's classes (PRD §7.12): the passes merged as the
/// tool's own `--all` merges them, exact subtree classes told from renamed
/// ones, copies attached to records, the roll-ups, the Clones section, and
/// a numbering that doesn't depend on the tool's order. The fixture's JSON
/// was written by the real tool at 97eee1c over the fixture's production
/// files.
@Suite("Clone classes")
struct CloneClassTests {
    /// A copy as (file, first line, first column, last line, last column).
    private static func place(_ instance: CloneInstance) -> String {
        let range = instance.range
        return "\(instance.file):\(range.start.line):\(range.start.column)-\(range.end.line):\(range.end.column)"
    }

    /// The class with ordinal `ordinal` in `report`.
    private static func cloneClass(_ ordinal: Int, in report: ScanReport) throws -> CloneClass {
        try #require(report.clones?.classes.first { $0.ordinal == ordinal })
    }

    /// `output` with its classes, and each class's copies, in reverse order.
    private static func reversed(_ name: String) throws -> String {
        var object = try #require(try JSONSerialization.jsonObject(with: Data(CloneHarness.recorded(name).utf8))
            as? [String: Any])
        let clones = try #require(object["clones"] as? [[String: Any]])
        object["clones"] = clones.reversed().map { clone in
            var clone = clone
            clone["instances"] = (clone["instances"] as? [Any]).map { Array($0.reversed()) }
            return clone
        }
        return String(bytes: try JSONSerialization.data(withJSONObject: object), encoding: .utf8) ?? ""
    }

    @Test("merging the subtree, near-miss and sequence runs gives the tool's own --all report, class for class")
    func mergeMatchesAll() throws {
        let outputs: [CloneDetectorPass: CloneDetectorOutput] = [
            .subtree: try CloneHarness.output("default"),
            .nearMiss: try CloneHarness.output("type3"),
            .sequence: try CloneHarness.output("sequence"),
            .type1: try CloneHarness.output("type1")
        ]
        let all = try CloneHarness.output("all")

        let merged = CloneMerge.merged(outputs)

        #expect(merged.map(\.clone.fingerprint) == all.clones.map(\.fingerprint))
        #expect(merged.map(\.clone.instances) == all.clones.map(\.instances))
        #expect(merged.map(\.clone.mass) == all.clones.map(\.mass))
        // The default run's statement classes inside the sequence run's
        // 233-mass class survive: a weaker claim never hides a stronger one.
        #expect(merged.map(\.pass) == [
            .nearMiss, .sequence, .nearMiss, .nearMiss, .subtree, .subtree, .subtree, .subtree, .subtree,
            .sequence, .subtree
        ])
        // The sequence run's copies of `total`'s body and of the `if`'s body
        // lie inside subtree classes, so the merge drops them.
        #expect(outputs[.sequence]?.clones.count == 4)
        #expect(merged.filter { $0.pass == .sequence }.count == 2)
    }

    @Test("""
        a subtree class is exact only when a --type1 class has exactly its copies; renamed copies, \
        and a class holding identical copies among renamed ones, are not
        """)
    func exactness() throws {
        let tool = try CloneHarness.recordedTool()
        defer { CloneHarness.remove(tool) }

        let report = try CloneHarness.scan(tool)

        let classes = try #require(report.clones?.classes)
        let subtree = classes.filter { $0.pass == .subtree }
        #expect(subtree.filter(\.exact).map(\.ordinal) == [3, 6, 9])
        #expect(subtree.filter { $0.exact == false }.map(\.ordinal) == [7, 8, 11])
        // Six copies of a case; --type1 finds only two of them identical.
        #expect(try Self.cloneClass(11, in: report).instances.count == 6)
        #expect(classes.filter { $0.pass != .subtree }.allSatisfy { $0.exact == false })
    }

    @Test("""
        a whole-function copy is its own containing record and its only whole; a statement's containing \
        record is its function, with no wholes; a whole type is held by no record
        """)
    func attachment() throws {
        let tool = try CloneHarness.recordedTool()
        defer { CloneHarness.remove(tool) }

        let report = try CloneHarness.scan(tool)

        let total = try Self.cloneClass(9, in: report)
        #expect(total.instances.map(Self.place) == [
            "Sources/Core/Totals.swift:2:1-8:1", "Sources/Extras/Ledger.swift:4:1-10:1"
        ])
        #expect(total.instances.map(\.containing) == [
            "Core::func total(of: [Item]) -> Int", "Extras::func total(of: [Item]) -> Int"
        ])
        #expect(total.instances.map(\.wholes) == [
            ["Core::func total(of: [Item]) -> Int"], ["Extras::func total(of: [Item]) -> Int"]
        ])
        let record = try #require(report.records.first { $0.key == "Core::func total(of: [Item]) -> Int" })
        #expect(record.range == total.instances[0].range)
        #expect(total.instances.map(\.strippedLines) == [7, 7])

        let statement = try Self.cloneClass(3, in: report)
        #expect(statement.instances.map(Self.place) == [
            "Sources/Core/Paths.swift:4:5-7:5", "Sources/Core/Paths.swift:15:5-18:5"
        ])
        #expect(statement.instances.map(\.containing) == [
            "Core::func load(_: String, log: inout[String]) -> String",
            "Core::func store(_: String, value: Int, log: inout[String]) -> Bool"
        ])
        #expect(statement.instances.flatMap(\.wholes).isEmpty)

        let types = try Self.cloneClass(8, in: report)
        #expect(types.instances.map(\.containing) == [nil, nil])
        #expect(types.instances.map(\.wholes) == [
            ["Core::Rectangle::func describe() -> String"], ["Extras::Box::func summary() -> String"]
        ])
    }

    @Test("""
        classes are numbered by first copy, then pass, then mass; copies are sorted; similarity keeps four \
        places; the report holds the file list's hash and the tool's own counts
        """)
    func numbering() throws {
        let tool = try CloneHarness.recordedTool()
        defer { CloneHarness.remove(tool) }

        let report = try CloneHarness.scan(tool)

        let clones = try #require(report.clones)
        #expect(clones.part == "production")
        #expect(clones.fileListHash == "sha256:" + ContentHash.sha256(Data(
            CloneHarness.files.map { $0 + "\n" }.joined().utf8
        )))
        #expect(clones.toolDuplicatedLines == CloneReport.DuplicatedLines(
            subtree: 39, type1: 18, sequence: 22, nearMiss: 38
        ))
        #expect(clones.classes.map(\.ordinal) == Array(1...11))
        #expect(clones.classes.map { Self.place($0.instances[0]) } == [
            "Sources/Core/Parsing.swift:2:1-14:1", "Sources/Core/Paths.swift:2:1-9:1",
            "Sources/Core/Paths.swift:4:5-7:5", "Sources/Core/Paths.swift:24:5-26:20",
            "Sources/Core/Reports.swift:3:5-14:5", "Sources/Core/Reports.swift:7:5-11:5",
            "Sources/Core/Reports.swift:12:5-14:5", "Sources/Core/Shapes.swift:2:1-11:1",
            "Sources/Core/Totals.swift:2:1-8:1", "Sources/Extras/Codes.swift:2:1-13:1",
            "Sources/Extras/Codes.swift:4:5-5:19"
        ])
        // The tool lists the larger near-miss copy first.
        let parsing = try Self.cloneClass(1, in: report)
        #expect(parsing.instances.map(\.range.start.line) == [2, 17])
        #expect(parsing.similarity == 0.9012)
        #expect(parsing.mass == 300 && parsing.lineSpan == 15 && parsing.fingerprint == "99cc60d40d3db1d2")
        #expect(clones.classes.filter { $0.pass != .nearMiss }.allSatisfy { $0.similarity == nil })
    }

    @Test("the tool's classes and copies in another order give the same report")
    func orderFree() throws {
        let forward = try CloneHarness.recordedTool()
        defer { CloneHarness.remove(forward) }
        let backward = try FakeTool.makeCloneDetector(
            outputs: [
                "default": try Self.reversed("default"),
                "--type3": try Self.reversed("type3"),
                "--sequence": try Self.reversed("sequence"),
                "--type1": try Self.reversed("type1")
            ],
            errors: [:],
            statuses: [:]
        )
        defer { CloneHarness.remove(backward) }

        let first = try ScanReportEncoder.encode(CloneHarness.scan(forward))
        let second = try ScanReportEncoder.encode(CloneHarness.scan(forward))
        let reordered = try CloneHarness.scan(backward)

        #expect(first == second)
        #expect(try CloneHarness.scan(forward).clones == reordered.clones)
    }

    @Test("""
        a class counts in each production module holding a copy, cloned lines count once however many \
        copies overlap, test scopes have none, and the metrics are SwiftCloneDetector's, better lower
        """)
    func rollups() throws {
        let tool = try CloneHarness.recordedTool()
        defer { CloneHarness.remove(tool) }

        let report = try CloneHarness.scan(tool)

        let clones = Dictionary(uniqueKeysWithValues: report.rollups.map { ($0.name, $0.clones) })
        #expect(clones["Core"]??.classes == CloneRollup.Classes(exact: 3, renamed: 2, sequence: 2, nearMiss: 2))
        #expect(clones["Extras"]??.classes == CloneRollup.Classes(exact: 1, renamed: 2, sequence: 0, nearMiss: 1))
        #expect(clones["production"]??.classes == CloneRollup.Classes(exact: 3, renamed: 3, sequence: 2, nearMiss: 3))
        // Paths.swift: the near-miss copies (lines 2–9, 12–20) hold the
        // exact `if` copies, and the sequence copies add 24–26 and 33–35.
        #expect(clones["Core"]??.clonedLines == 91)
        #expect(clones["Extras"]??.clonedLines == 42)
        #expect(clones["production"]??.clonedLines == 133)
        #expect(clones["CoreTests"] == .some(nil) && clones["tests"] == .some(nil))
        let production = try #require(report.rollups.first { $0.name == "production" })
        let metrics = try RollupMetrics.metrics(of: production).filter { $0.path.hasPrefix("clones.") }
        #expect(metrics.map(\.path) == [
            "clones.classes.exact", "clones.classes.nearMiss", "clones.classes.renamed", "clones.classes.sequence",
            "clones.clonedLines"
        ])
        #expect(metrics.allSatisfy { $0.collector == SwiftCloneDetectorAdapter.name })
        #expect(metrics.allSatisfy { MetricDirection.of($0.path) == .lowerIsBetter })
    }

    @Test("the Clones section counts classes by kind and the share of stripped lines copies cover")
    func markdown() throws {
        let tool = try CloneHarness.recordedTool()
        defer { CloneHarness.remove(tool) }

        let report = try CloneHarness.scan(tool)

        #expect(MarkdownClones.render(report) == [
            "SwiftCloneDetector's passes over the production files, generated ones left out, merged: "
                + "11 classes of 26 copies. Copies cover 133 of 158 stripped lines (84.2%).",
            "",
            "| Kind | Classes |",
            "| --- | --- |",
            "| exact | 3 |",
            "| renamed | 3 |",
            "| sequence | 2 |",
            "| near-miss | 3 |",
            "",
            "The tool's own duplicated lines, a hint only (each class's first copy, once per further copy, "
                + "nested classes counted again): subtree 39, type1 18, sequence 22, near-miss 38."
        ])
    }
}
