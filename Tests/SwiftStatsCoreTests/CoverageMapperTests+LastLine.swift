import Foundation
@testable import SwiftStatsCore
import Testing

/// The coverage mapping's edge cases (M5) at the top of what an Int holds:
/// an export whose segments end on line `Int.max`.
extension CoverageMapperTests {
    @Test("""
        a kept file's segments ending on the largest line an Int holds map through that line and stop there \
        instead of trapping
        """)
    func segmentsOnTheLastLine() throws {
        let lib = #""@ROOT@/Sources/Lib/Lib.swift""#
        let files = """
            {"filename":\(lib),"segments":[[9223372036854775806,1,1,true,true,false],
             [9223372036854775807,3,0,false,false,false]]}
            """

        let report = try Self.mapping(files: files, functions: "", text: "public func first() -> Int {\n    1\n}\n")

        let lastRun = CoverageLineRun(start: Int.max - 1, end: Int.max, count: 1, partlyRun: false)
        #expect(report.files == [CoverageFileLines(file: "Sources/Lib/Lib.swift", lines: [lastRun], skipped: [])])
        #expect(report.attachments == [
            CoverageAttachment(
                owner: "Sources/Lib/Lib.swift",
                attachedTo: .file,
                lines: CoverageTally(covered: 2, total: 2),
                regions: CoverageTally(covered: 0, total: 0)
            )
        ])
    }
}
