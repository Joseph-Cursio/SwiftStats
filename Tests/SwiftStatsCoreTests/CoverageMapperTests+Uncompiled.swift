import Foundation
@testable import SwiftStatsCore
import Testing

/// The coverage mapping's edge cases (M5) for code no record can hold
/// data for: top-level statements the compiler didn't compile, and files
/// that aren't Swift.
extension CoverageMapperTests {
    @Test("""
        top-level statements in a `#if` with no active clause, for which the compiler emits nothing, are skipped \
        lines; a top-level entry with no region on a statement line leaves the record null, not 0 of 0
        """)
    func inactiveTopLevelCode() throws {
        let lib = #""@ROOT@/Sources/Lib/Lib.swift""#
        let key = "Lib::<top-level code> @ Sources/Lib/Lib.swift"
        // The compiler's export of `main` here: one region, the global's.
        let inactiveOnly = try Self.mapping(
            files: #"{"filename":\#(lib),"segments":[[1,1,0,true,true,false],[1,15,0,false,false,false]]}"#,
            functions: #"{"name":"main","count":0,"filenames":[\#(lib)],"regions":[[1,1,1,15,0,0,0,0]]}"#,
            text: "let config = 1\n#if os(Linux)\nprint(config)\n#endif\n"
        )
        let mixed = try Self.mapping(
            files: #"{"filename":\#(lib),"segments":[[1,1,0,true,true,false],[2,14,0,false,false,false]]}"#,
            functions: #"{"name":"main","count":0,"filenames":[\#(lib)],"#
                + #""regions":[[1,1,1,15,0,0,0,0],[2,1,2,14,0,0,0,0]]}"#,
            text: "let config = 1\nprint(config)\n#if os(Linux)\nprint(config)\nprint(config)\n#endif\n"
        )

        let record = try #require(inactiveOnly.records.first { $0.key == key })
        #expect(record.lines == nil)
        #expect(record.regions == nil)
        #expect(record.reason == CoverageMapper.noData)
        #expect(inactiveOnly.files.first?.skipped == [CoverageLineRange(start: 3, end: 3)])
        let ran = try #require(mixed.records.first { $0.key == key })
        #expect(ran.regions == CoverageTally(covered: 0, total: 1))
        #expect(mixed.files.first?.skipped == [CoverageLineRange(start: 4, end: 5)])
    }

    @Test("""
        a C target's file, which SwiftPM instruments, is dropped as not Swift: neither another package's nor an \
        unmapped production file
        """)
    func cTargetFile() throws {
        let lib = #""@ROOT@/Sources/Lib/Lib.swift""#
        let cfoo = #""@ROOT@/Sources/CFoo/cfoo.c""#

        let report = try Self.mapping(
            files: #"{"filename":\#(lib),"segments":[]},{"filename":\#(cfoo),"segments":[[1,20,1,true,true,false]]}"#,
            functions: #"{"name":"cfoo","count":1,"filenames":[\#(cfoo)],"regions":[[1,20,1,32,1,0,0,0]]}"#,
            text: "public func first() -> Int {\n    1\n}\n"
        )

        let dropped = CoverageDropped(build: 0, outsideRoot: 0, testFiles: 0, otherPackage: 0, otherLanguage: 1)
        #expect(report.dropped == dropped)
        #expect(report.unmapped.isEmpty)
        #expect(report.files.map(\.file) == ["Sources/Lib/Lib.swift"])
    }
}
