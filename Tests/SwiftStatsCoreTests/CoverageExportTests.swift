import Foundation
@testable import SwiftStatsCore
import Testing

/// Reading `llvm-cov export`'s JSON (M5): its type and version are checked,
/// every count is a 64-bit integer, and one beyond `Int64.max` saturates.
@Suite("Coverage export")
struct CoverageExportTests {
    /// An export whose type, version and data are `type`, `version` and
    /// `data`.
    private static func document(type: String, version: String, data: String) -> Data {
        Data(#"{"data":\#(data),"type":"\#(type)","version":"\#(version)"}"#.utf8)
    }

    /// An export of one data element holding `functions`.
    private static func document(functions: String) -> Data {
        document(
            type: "llvm.coverage.json.export",
            version: "3.0.1",
            data: #"[{"files":[],"functions":[\#(functions)],"totals":{}}]"#
        )
    }

    /// Why `data` failed to decode, or nil when it decoded.
    private static func failure(_ data: Data) -> String? {
        do {
            _ = try CoverageExport.decode(data)
            return nil
        } catch {
            return (error as? CoverageFailure)?.description ?? "\(error)"
        }
    }

    @Test("the recorded export decodes: its files with their segments, its entries with their regions")
    func recorded() throws {
        let data = try Data(contentsOf: FakeToolchain.recordedDirectory.appendingPathComponent("export.json"))

        let export = try CoverageExport.decode(data)

        let counter = try #require(export.files.first { $0.filename == "@ROOT@/Sources/Probe/Counter.swift" })
        #expect(counter.segments.first == CoverageSegment(
            line: 4,
            column: 24,
            executionCount: 2,
            hasCount: true,
            isRegionEntry: true,
            isGapRegion: false
        ))
        let platform = try #require(export.functions.first { $0.name == "$s5Probe8platformSSyF" })
        #expect(platform.count == 1)
        #expect(platform.filenames == ["@ROOT@/Sources/Probe/Overloads.swift"])
        #expect(platform.regions.map(\.kind) == [0, 2, 2])
        #expect(platform.regions[1] == CoverageRegion(
            start: SourcePosition(line: 21, column: 5),
            end: SourcePosition(line: 23, column: 10),
            executionCount: 0,
            fileID: 0,
            expandedFileID: 0,
            kind: 2
        ))
        #expect(export.files.map(\.filename) == export.files.map(\.filename).sorted())
    }

    @Test("an export of another type or version, or without exactly one data element, fails with a reason")
    func unknownShapes() {
        #expect(Self.failure(Self.document(type: "llvm.coverage.json.export", version: "2.0.1", data: "[]"))
            == "`llvm-cov export` wrote type llvm.coverage.json.export, version 2.0.1; "
            + "SwiftStats reads llvm.coverage.json.export 3.0.1")
        #expect(Self.failure(Self.document(type: "other", version: "3.0.1", data: "[]"))
            == "`llvm-cov export` wrote type other, version 3.0.1; SwiftStats reads llvm.coverage.json.export 3.0.1")
        #expect(Self.failure(Self.document(type: "llvm.coverage.json.export", version: "3.0.1", data: "[]"))
            == "`llvm-cov export` wrote 0 data elements; SwiftStats reads one")
        let two = #"[{"files":[],"functions":[]},{"files":[],"functions":[]}]"#
        #expect(Self.failure(Self.document(type: "llvm.coverage.json.export", version: "3.0.1", data: two))
            == "`llvm-cov export` wrote 2 data elements; SwiftStats reads one")
    }

    @Test("a malformed export says where it broke")
    func malformed() {
        let function = #"{"name":"f","count":1,"filenames":["/a.swift"],"regions":[[1,2,3]]}"#

        let reason = Self.failure(Self.document(functions: function))

        let expected = "could not read `llvm-cov export`'s output: at .data[0].functions[0].regions[0]"
        #expect(reason?.hasPrefix(expected) == true)
    }

    @Test("counts are read as 64-bit integers, never through a double, and one beyond Int64.max saturates")
    func counts() throws {
        let function = """
            {"name":"f","count":18446744073709551615,"filenames":["/a.swift"],
             "regions":[[1,2,3,4,9007199254740993,0,0,0],[1,3,1,9,9223372036854775807,0,0,0]]}
            """

        let export = try CoverageExport.decode(Self.document(functions: function))

        let entry = try #require(export.functions.first)
        #expect(entry.count == Int64.max)
        #expect(entry.regions.map(\.executionCount) == [9_007_199_254_740_993, Int64.max])
        #expect(entry.regions.map { CoverageCount.isSaturated($0.executionCount) } == [false, true])
    }

    @Test("a run whose export SwiftStats can't read fails, and records no map rule")
    func unreadableRun() throws {
        var scenario = try FakeToolchain.recorded()
        scenario.export = #"{"data":[],"type":"llvm.coverage.json.export","version":"4.0.0"}"#

        try CoverageHarness.run(scenario) { outcome in
            #expect(outcome.run.status.state == .failed)
            #expect(outcome.run.status.reason
                == "`llvm-cov export` wrote type llvm.coverage.json.export, version 4.0.0; "
                + "SwiftStats reads llvm.coverage.json.export 3.0.1")
            #expect(outcome.run.status.options.contains { $0.hasPrefix("map: ") } == false)
            #expect(outcome.run.export == nil && outcome.run.profiles == nil)
        }
    }
}
