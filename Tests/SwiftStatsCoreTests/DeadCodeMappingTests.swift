import Foundation
@testable import SwiftStatsCore
import Testing

/// outskirts' entries mapped onto the Index fixture's records (M7, design
/// §5.4, §7): a copy scanned with `--index` against its recorded build,
/// the `index` collector reading `reader.json` and a fake outskirts acting
/// out the recorded runs, some with entries added, removed or reordered.
/// The rows, dead lines and roll-ups were checked by hand and agree with
/// the independent checker's (`index-check.py dead`) on a real scan of a
/// copy. Serialized, each scan on a thread of its own, as the index
/// collector's tests are.
@Suite("Dead-code mapping", .serialized)
struct DeadCodeMappingTests {
    /// The recorded runs' covered records with the index: run, the
    /// covering entry's ordinal, rule and key.
    private static let recordedRows = [
        "roots 1 property IndexCore::Storage::var unusedComputed: Int { get }",
        "roots 6 type IndexCore::Unused::func first() -> Int",
        "roots 6 type IndexCore::Unused::func second() -> Int",
        "roots 5 extension IndexCore::Unused::func third() -> Int",
        "roots 4 usr IndexCore::func neverCalled() -> Int",
        "roots 3 usr IndexCore::func summarize(_: [Int]) -> Int / func unusedHelper() -> Int",
        "roots 7 usr index-kit::func relay() -> Int",
        "production 1 property IndexCore::Storage::var unusedComputed: Int { get }",
        "production 7 type IndexCore::Unused::func first() -> Int",
        "production 7 type IndexCore::Unused::func second() -> Int",
        "production 6 extension IndexCore::Unused::func third() -> Int",
        "production 5 usr IndexCore::func neverCalled() -> Int",
        "production 4 usr IndexCore::func onlyTestsCall() -> Int",
        "production 3 usr IndexCore::func summarize(_: [Int]) -> Int / func unusedHelper() -> Int",
        "production 8 usr index-kit::func relay() -> Int",
        "production 9 usr index-support::func parseLine(_: String) -> [String]"
    ]
    /// The recorded runs' dead lines with the index: `Unused` is 8 lines
    /// and its extension in `Unused+Extra.swift` 5; the unused computed
    /// property's getter, `unusedHelper()`, `neverCalled()` and `relay()`
    /// 3 each; `onlyTestsCall()` 4 and `parseLine(_:)` 3 in the production
    /// run only.
    private static let recordedLines = [
        "roots": ["IndexCore": 22, "index-kit": 3],
        "production": ["IndexCore": 26, "index-kit": 3, "index-support": 3]
    ]
    /// The USR of `summarize(_:)`, which holds the unused local function.
    private static let summarizeUSR = "s:9IndexCore9summarizeySiSaySiGF"

    /// `report`'s covered records as `recordedRows` writes them.
    private static func rows(_ report: DeadCodeReport) -> [String] {
        report.records.map { "\($0.run.rawValue) \($0.declaration) \($0.via.rawValue) \($0.key)" }
    }

    /// Scans the fixture with a fake outskirts playing `scenario`, the
    /// configuration given `extra` keys, and passes the outcome to `check`.
    private static func scanned(
        _ scenario: FakePeriphery.Scenario,
        extra: String,
        check: (IndexGroupHarness.Outcome) throws -> Void
    ) async throws {
        let fake = try FakePeriphery.make(scenario)
        defer { fake.remove() }
        var scan = try IndexFixtureScan()
        scan.extra = fake.configuration + extra
        try await scan.run { _, outcome in
            try check(outcome)
        }
    }

    /// The roll-up `name` of `report`.
    private static func rollup(_ name: String, in report: ScanReport) throws -> Rollup {
        try #require(report.rollups.first { $0.name == name })
    }

    @Test("""
        with the index, the recorded runs cover records by USR, by property, by type and by extension, the lower \
        ordinal keeping a record covered twice, and dead lines come from the maximal units
        """)
    func recordedWithIndex() async throws {
        try await Self.scanned(try FakePeriphery.recorded(), extra: "") { outcome in
            let dead = try #require(outcome.report.deadCode)
            #expect(Self.rows(dead) == Self.recordedRows)
            #expect(dead.deadLines == Self.recordedLines)
            #expect(dead.version == "3.28.0")
            #expect(dead.runs == [
                DeadCodeRunResults(name: .roots, results: 8), DeadCodeRunResults(name: .production, results: 10)
            ])
            let dropped = DeadCodeDropped(build: 0, fileChanged: 0, local: 1, outsideRoot: 1, test: 0, unscanned: 0)
            #expect(dead.dropped == ["roots": dropped, "production": dropped])
            // The Codable and Equatable structs and their stored
            // properties are retained: of Support.swift, either run lists
            // only parseLine(_:), and only the production run.
            #expect(dead.declarations.filter { $0.file == "Sources/Kits/Support.swift" }
                .map { "\($0.run.rawValue) \($0.kind) \($0.name)" } == ["production function.free parseLine(_:)"])
            let retained: Set = ["Record", "name", "note", "Pair", "left", "right"]
            #expect(dead.declarations.allSatisfy { !retained.contains($0.name) })
            let roots = dead.declarations.filter { $0.run == .roots }
            #expect(roots.map(\.strippedLines) == [3, nil, 3, 3, 5, 13, 3, nil])
            #expect(roots[5].place == .type && roots[5].owner == "IndexCore::Unused" && roots[5].module == "IndexCore")
            #expect(roots[2].place == .function
                && roots[2].owner == "IndexCore::func summarize(_: [Int]) -> Int / func unusedHelper() -> Int")
            #expect(roots[7].entryClass == .outsideRoot && roots[7].file == nil)
            #expect(roots[7].place == .unscanned && roots[7].owner == nil && roots[7].module == nil)
            let options = try #require(outcome.statuses["periphery"]?.options)
            #expect(options.suffix(2) == ["classes: " + PeripheryOutput.rule, "map: " + DeadCodeMapper.rule])
        }
    }

    @Test("""
        an unused type covers its two methods and the extension method in another file: by type when no \
        extension entry covers it first, by the lower ordinal when one does, its dead lines both type records' sum
        """)
    func typeCoversItsExtension() async throws {
        var scenario = try FakePeriphery.recorded()
        scenario = try FakePeriphery.editing(scenario, .roots) { entries in
            entries.filter { $0["kind"] as? String != "extension.struct" }
        }
        // The production run lists the type before its extension.
        scenario = try FakePeriphery.editing(scenario, .production) { entries in
            var reordered = entries
            reordered.swapAt(5, 6)
            return reordered
        }
        try await Self.scanned(scenario, extra: "") { outcome in
            let dead = try #require(outcome.report.deadCode)
            let unused = Self.rows(dead).filter { $0.contains("IndexCore::Unused::") }
            #expect(unused == [
                "roots 5 type IndexCore::Unused::func first() -> Int",
                "roots 5 type IndexCore::Unused::func second() -> Int",
                "roots 5 type IndexCore::Unused::func third() -> Int",
                "production 6 type IndexCore::Unused::func first() -> Int",
                "production 6 type IndexCore::Unused::func second() -> Int",
                "production 6 type IndexCore::Unused::func third() -> Int"
            ])
            #expect(dead.deadLines == Self.recordedLines)
            let production = dead.declarations.filter { $0.run == .production }
            #expect(production[5].kind == "struct" && production[5].strippedLines == 13)
            #expect(production[6].kind == "extension.struct" && production[6].strippedLines == 5)
        }
    }

    @Test("""
        an unused local function outskirts lists inside an unused function isn't counted twice: the enclosing \
        function's lines hold it
        """)
    func localFunctionCountsOnce() async throws {
        var scenario = try FakePeriphery.recorded()
        let added = FakePeriphery.unusedEntry(
            kind: "function.free",
            name: "summarize(_:)",
            ids: [Self.summarizeUSR],
            location: "Sources/IndexCore/Locals.swift:25:13"
        )
        scenario = try FakePeriphery.editing(scenario, .roots) { $0 + [added] }
        try await Self.scanned(scenario, extra: "") { outcome in
            let dead = try #require(outcome.report.deadCode)
            let summarize = [
                "roots 9 usr IndexCore::func summarize(_: [Int]) -> Int",
                "roots 3 usr IndexCore::func summarize(_: [Int]) -> Int / func unusedHelper() -> Int"
            ]
            #expect(Self.rows(dead).filter { $0.hasPrefix("roots ") && $0.contains("summarize") } == summarize)
            // 22 - unusedHelper()'s 3 + summarize(_:)'s 7.
            #expect(dead.deadLines["roots"] == ["IndexCore": 26, "index-kit": 3])
        }
    }

    @Test("""
        an unused type covers the records of a type nested in it, before the nested type's own entry can, and the \
        nested type adds no lines the outer type holds
        """)
    func nestedTypeHeld() async throws {
        let nested = FakePeriphery.unusedEntry(
            kind: "struct",
            name: "Index",
            ids: ["s:9IndexCore6LedgerV0A0V"],
            location: "Sources/IndexCore/Types.swift:29:12"
        )
        let outer = FakePeriphery.unusedEntry(
            kind: "struct",
            name: "Ledger",
            ids: ["s:9IndexCore6LedgerV"],
            location: "Sources/IndexCore/Types.swift:24:8"
        )
        let scenario = try FakePeriphery.editing(try FakePeriphery.recorded(), .roots) { $0 + [outer, nested] }
        try await Self.scanned(scenario, extra: "") { outcome in
            let dead = try #require(outcome.report.deadCode)
            let ledger = [
                "roots 9 type IndexCore::Ledger.Index::func entry(in: Ledger) -> Int",
                "roots 9 type IndexCore::Ledger::func index(at: Int) -> Index"
            ]
            #expect(Self.rows(dead).filter { $0.contains("Ledger") } == ledger)
            // 22 + Ledger's 12, which hold Ledger.Index's 6.
            #expect(dead.deadLines["roots"] == ["IndexCore": 34, "index-kit": 3])
            #expect(dead.declarations.filter { $0.run == .roots }.suffix(2).map(\.strippedLines) == [12, 6])
        }
    }

    @Test("""
        an extension of a type the package doesn't declare covers the records in its range and no other, and \
        adds its own lines
        """)
    func externalTypeExtension() async throws {
        var scenario = try FakePeriphery.recorded()
        let added = FakePeriphery.unusedEntry(
            kind: "extension.struct",
            name: "Array",
            ids: ["s:e:s:Sa9IndexCoreE10secondItemxSgyF"],
            location: "Sources/IndexCore/Types.swift:53:11"
        )
        scenario = try FakePeriphery.editing(scenario, .roots) { $0 + [added] }
        try await Self.scanned(scenario, extra: "") { outcome in
            let dead = try #require(outcome.report.deadCode)
            #expect(Self.rows(dead).filter { $0.contains("Array") }
                == ["roots 9 extension IndexCore::Array::func secondItem() -> Element?"])
            #expect(dead.deadLines["roots"] == ["IndexCore": 27, "index-kit": 3])
            #expect(dead.declarations.last { $0.run == .roots }?.strippedLines == 5)
        }
    }

    @Test("""
        without the index, functions map by their name position, types and extensions by their place, and the \
        unused computed property covers nothing, counted without lines
        """)
    func positionWithoutIndex() async throws {
        try await Self.scanned(try FakePeriphery.recorded(), extra: "  index:\n    enabled: false\n") { outcome in
            let dead = try #require(outcome.report.deadCode)
            let roots = [
                "roots 6 type IndexCore::Unused::func first() -> Int",
                "roots 6 type IndexCore::Unused::func second() -> Int",
                "roots 5 extension IndexCore::Unused::func third() -> Int",
                "roots 4 location IndexCore::func neverCalled() -> Int",
                "roots 3 location IndexCore::func summarize(_: [Int]) -> Int / func unusedHelper() -> Int",
                "roots 7 location index-kit::func relay() -> Int"
            ]
            #expect(Self.rows(dead).filter { $0.hasPrefix("roots ") } == roots)
            #expect(dead.records.count { $0.run == .production && $0.via == .location } == 5)
            #expect(dead.deadLines == [
                "roots": ["IndexCore": 19, "index-kit": 3],
                "production": ["IndexCore": 23, "index-kit": 3, "index-support": 3]
            ])
            let core = try Self.rollup("IndexCore", in: outcome.report)
            #expect(core.deadCode?.unsized == 1 && core.deadCode?.records == 5)
            #expect(core.tests.lineRatio.deadLines == 19)
        }
    }

    @Test("dead lines and covered records don't depend on the order outskirts lists the entries in")
    func orderIndependent() async throws {
        var scenario = try FakePeriphery.recorded()
        scenario = try FakePeriphery.editing(scenario, .roots) { Array($0.reversed()) }
        scenario = try FakePeriphery.editing(scenario, .production) { entries in
            Array(entries[5...]) + Array(entries[..<5])
        }
        try await Self.scanned(scenario, extra: "") { outcome in
            let dead = try #require(outcome.report.deadCode)
            #expect(dead.deadLines == Self.recordedLines)
            let covered = Set(dead.records.map { "\($0.run.rawValue) \($0.key)" })
            let recorded = Set(Self.recordedRows.map { row in
                let parts = row.split(separator: " ", maxSplits: 3)
                return "\(parts[0]) \(parts[3])"
            })
            #expect(covered == recorded)
        }
    }
}
