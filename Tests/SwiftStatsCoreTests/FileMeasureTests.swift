@testable import SwiftStatsCore
import Testing

/// File length (PRD §7.2).
@Suite("File measure")
struct FileMeasureTests {
    @Test("physical lines count an unterminated last line once")
    func physicalLines() {
        #expect(FileMeasure.physicalLines(in: "") == 0)
        #expect(FileMeasure.physicalLines(in: "a") == 1)
        #expect(FileMeasure.physicalLines(in: "a\n") == 1)
        #expect(FileMeasure.physicalLines(in: "a\n\nb") == 3)
    }
}
