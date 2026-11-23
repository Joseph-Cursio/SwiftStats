import Foundation
import SwiftParser
@testable import SwiftStatsCore
import Testing

/// Joining SwiftCodeMetrics' scores onto records (PRD §7.3).
@Suite("Complexity scorer")
struct ComplexityScorerTests {
    /// Records and scores for `source`, as one production file.
    private static func score(_ source: String) -> (records: [FunctionRecord], warnings: [ScanWarning]) {
        let file = ParsedFile(
            path: "Sources/Lib/File.swift",
            source: source,
            tree: Parser.parse(source: source),
            hasByteOrderMark: false,
            sha256: ContentHash.sha256(Data(source.utf8))
        )
        return ComplexityScorer.score(
            CollectorHarness.collect(source),
            files: [(module: "Lib", file: file)],
            ignoresCaseStatements: false
        )
    }

    @Test("records get their scores; a subscript with accessors is scored through them")
    func joins() {
        let (records, warnings) = Self.score("""
        struct Grid {
            func pick(_ flag: Bool) -> Int { flag ? 1 : 0 }
            subscript(row: Int) -> Int {
                get { row > 0 ? row : 0 }
                set {}
            }
        }
        """)

        #expect(records.map(\.complexity?.decisionCount) == [1, nil, 1, 0])
        #expect(warnings.isEmpty)
    }

    @Test("a score inside a macro's arguments, which has no record, is reported")
    func macroArguments() {
        let (records, warnings) = Self.score("""
        func check(_ flag: Bool) {
            #expect(throws: Never.self) {
                func helper() { if flag { return } }
                helper()
            }
        }
        """)

        #expect(records.count == 1)
        let expected = "complexity of helper() at line 3 (inside a macro's arguments?) joins no record"
        #expect(warnings.map(\.message) == [expected])
    }

    @Test("a result builder hint names the attribute, or the opaque result's protocol")
    func resultBuilders() {
        let (records, warnings) = Self.score("""
        import SwiftUI
        struct Card: View {
            @ViewBuilder
            func badge(_ flag: Bool) -> some View {
                if flag { Text("on") }
            }
            var body: some View { Text("card") }
        }
        """)

        #expect(records.map(\.complexity?.resultBuilder) == ["ViewBuilder", "View"])
        #expect(warnings.isEmpty)
    }
}
