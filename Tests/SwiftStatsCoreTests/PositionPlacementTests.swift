import Foundation
@testable import SwiftStatsCore
import Testing

/// Placing positions on records, types and files (M5, M6): coverage
/// gives a region's start and end, mutation an anchor with no end.
@Suite("Position placement")
struct PositionPlacementTests {
    /// A function, a type with a stored property and a method, and a global.
    private static let source = """
        public func first() -> Int {
            1
        }
        public struct Holder {
            public var value = 0
            public func get() -> Int { value }
        }
        let global = 3

        """

    @Test(
        "a position goes to the innermost record holding it, else its type, else its file; only an end unmaps it"
    )
    func places() throws {
        let package = try TemporaryPackage(["Sources/Lib/Lib.swift": Self.source])
        defer { package.remove() }
        let targets = TargetResolver.resolve(try package.describer.describePackage(at: package.root))
        let measured = PackageScanner.measure(targets, root: package.root, configuration: SwiftStatsConfiguration())
        let placement = PositionPlacement(measured: measured)
        let file = "Sources/Lib/Lib.swift"
        let first = try #require(measured.records.first { $0.name == "first" }).key
        let get = try #require(measured.records.first { $0.name == "get" }).key
        let place = { (line: Int, column: Int, end: SourcePosition?) in
            placement.place(at: SourcePosition(line: line, column: column), end: end, in: file)
        }

        #expect(place(2, 5, nil) == .record(first))
        #expect(place(2, 5, SourcePosition(line: 2, column: 6)) == .record(first))
        #expect(place(2, 5, SourcePosition(line: 5, column: 1)) == .unmapped(PositionPlacement.pastRecord))
        #expect(place(6, 32, nil) == .record(get))
        #expect(place(5, 24, nil) == .type("Lib::Holder"))
        #expect(place(8, 14, nil) == .file)
    }

    @Test("""
        a coverage region ending at the smallest column an Int holds ends before its record does, so its \
        entry maps to the record instead of trapping
        """)
    func smallestEndColumn() throws {
        let lib = #""@ROOT@/Sources/Lib/Lib.swift""#
        let functions = """
            {"name":"$s3Lib5firstSiyF","count":1,"filenames":[\(lib)],
             "regions":[[2,5,2,-9223372036854775808,1,0,0,0]]}
            """

        let report = try CoverageMapperTests.mapping(
            files: #"{"filename":\#(lib),"segments":[]}"#,
            functions: functions,
            text: "public func first() -> Int {\n    1\n}\n"
        )

        #expect(report.unmapped.isEmpty)
        let first = try #require(report.records.first { $0.key == "Lib::func first() -> Int" })
        #expect(first.reason == nil)
        #expect(first.regions == CoverageTally(covered: 1, total: 1))
    }

    @Test("production placement, the default, never places on a test; placing on every role does")
    func roles() throws {
        let package = try TemporaryPackage([
            "Sources/Lib/Lib.swift": Self.source,
            "Tests/LibTests/LibTests.swift": "import Testing\n\n@Test func checksFirst() {\n    #expect(true)\n}\n"
        ])
        defer { package.remove() }
        let targets = TargetResolver.resolve(try package.describer.describePackage(at: package.root))
        let measured = PackageScanner.measure(targets, root: package.root, configuration: SwiftStatsConfiguration())
        let test = try #require(measured.records.first { $0.name == "checksFirst" }).key
        let file = "Tests/LibTests/LibTests.swift"
        let position = SourcePosition(line: 3, column: 12)
        let byDefault = PositionPlacement(measured: measured)
        let production = PositionPlacement(measured: measured, roles: .production)
        let every = PositionPlacement(measured: measured, roles: .every)
        #expect(byDefault.place(at: position, end: nil, in: file) == .file)
        #expect(production.place(at: position, end: nil, in: file) == .file)
        #expect(every.place(at: position, end: nil, in: file) == .record(test))
        let first = try #require(measured.records.first { $0.name == "first" }).key
        let inLibrary = SourcePosition(line: 2, column: 5)
        #expect(every.place(at: inLibrary, end: nil, in: "Sources/Lib/Lib.swift") == .record(first))
    }

    /// To accept a deliberate change to where coverage and mutation place,
    /// run with `SWIFTSTATS_UPDATE_GOLDEN=1` and review the diff of
    /// `Tests/Fixtures/ProductionPlacement.golden.txt`.
    @Test("the default placement places every position of the Coverage and Mutation fixtures as recorded before M7")
    func productionAsRecorded() throws {
        let actual = try PlacementTable.text()
        if ProcessInfo.processInfo.environment["SWIFTSTATS_UPDATE_GOLDEN"] == "1" {
            try actual.write(to: PlacementTable.golden, atomically: true, encoding: .utf8)
        }
        let expected = try String(contentsOf: PlacementTable.golden, encoding: .utf8)
        #expect(
            actual == expected,
            "placement differs from ProductionPlacement.golden.txt; to accept, set SWIFTSTATS_UPDATE_GOLDEN=1"
        )
    }
}
