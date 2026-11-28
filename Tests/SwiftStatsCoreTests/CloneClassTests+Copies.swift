import Foundation
@testable import SwiftStatsCore
import Testing

/// Copies `CloneMapper` orders and counts, on a measured package and a
/// hand-written subtree class: copies in one file at one start come
/// shortest first whatever order the tool lists them in, and a copy's
/// stripped lines leave out an attribute's line, as a record's do, a bare
/// attribute ending an unfinished file's too.
extension CloneClassTests {
    /// A package of two functions, the second under an attribute on its
    /// own line, and an unfinished file ending in a bare attribute.
    private static let attributed = [
        "Sources/Lib/Copies.swift": """
            func first() -> Int {
                let value = 1
                return value
            }

            @discardableResult
            func second() -> Int {
                let value = 2
                return value
            }

            """,
        "Sources/Lib/Unfinished.swift": "func third() -> Int {\n    3\n}\n@discardableResult\n"
    ]

    /// The span from `start` to `end`, each a line and a column.
    private static func span(_ start: (Int, Int), _ end: (Int, Int)) -> SourceSpan {
        SourceSpan(
            start: SourcePosition(line: start.0, column: start.1),
            end: SourcePosition(line: end.0, column: end.1)
        )
    }

    /// The copies of one subtree class, each a file and a span as the tool
    /// writes it, mapped onto `harness`'s package.
    private static func mapped(
        _ copies: [(String, SourceSpan)],
        onto harness: MappingHarness
    ) throws -> [CloneInstance] {
        let instances = copies.map { file, span in
            "{\"endColumn\": \(span.end.column), \"endLine\": \(span.end.line), \"path\": \"\(file)\", "
                + "\"startColumn\": \(span.start.column), \"startLine\": \(span.start.line)}"
        }
        let clone = "{\"fingerprint\": \"0123456789abcdef\", \"instances\": [\(instances.joined(separator: ", "))], "
            + "\"lineSpan\": 4, \"mass\": 40}"
        var outputs: [CloneDetectorPass: CloneDetectorOutput] = [:]
        for pass in CloneDetectorPass.runOrder {
            let report = """
                {"cloneCount": 0, "clones": [\(pass == .subtree ? clone : "")], "duplicatedLines": 0, "fileCount": 2, \
                "mode": "type1-2", "tool": "swift-clone-detector", "version": "0.1.0"}
                """
            outputs[pass] = try SwiftCloneDetectorAdapter.read(Data(report.utf8), pass: pass)
        }
        let status = CollectorStatus(
            name: SwiftCloneDetectorAdapter.name,
            state: .ran,
            version: nil,
            reason: nil,
            options: []
        )
        let run = CloneRun(status: status, executable: nil, milliseconds: 0, fileListHash: "", outputs: outputs)
        return try #require(CloneMapper(measured: harness.measured).mapping(of: run)).report.classes
            .flatMap(\.instances)
    }

    @Test("""
        a class's copies in one file at one start come shortest first, in either order; a copy counts the \
        stripped lines its record does, an attribute's line left out, a bare one ending an unfinished file's too
        """)
    func copiesOfOneStart() throws {
        let harness = try MappingHarness(TemporaryPackage(Self.attributed))
        defer { harness.remove() }
        let file = "Sources/Lib/Copies.swift"
        let short = (file, Self.span((1, 1), (3, 17)))
        let long = (file, Self.span((1, 1), (4, 2)))
        let ends = { (instances: [CloneInstance]) in instances.map { "\($0.file) \($0.range.end.line)" } }

        let shortFirst = try Self.mapped([short, long], onto: harness)
        let longFirst = try Self.mapped([long, short], onto: harness)
        let unfinished = ("Sources/Lib/Unfinished.swift", Self.span((1, 1), (5, 1)))
        let attributedCopies = try Self.mapped([(file, Self.span((6, 1), (10, 2))), unfinished], onto: harness)

        #expect(ends(shortFirst) == ["\(file) 3", "\(file) 4"])
        #expect(ends(longFirst) == ends(shortFirst))
        let record = try #require(harness.measured.records.first { $0.key.hasSuffix("func second() -> Int") })
        #expect(record.strippedLines == 4)
        #expect(attributedCopies.map(\.strippedLines) == [4, 3])
    }
}
