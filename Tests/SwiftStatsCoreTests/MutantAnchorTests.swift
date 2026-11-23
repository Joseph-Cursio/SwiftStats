import Foundation
@testable import SwiftStatsCore
import Testing

/// Mutants' anchors (M6, design §3) on hand-written sources: the point
/// SwiftMutator gives depends on the operator, and the anchor is a position
/// inside a token of the scanned file, so a mutant pointed past a
/// statement's trailing comment, or at the end of the line before an
/// operator that starts a line, still lands in the code it changes.
@Suite("Mutant anchors")
struct MutantAnchorTests {
    /// The file of statements, operators and comparisons.
    private static let effects = """
        public func work(_ log: inout [Int]) {
            log.append(1) // keeps a note
            log.append(2)
        }

        public func ping(_ log: inout [Int]) { log.append(3) }

        public func both(_ first: Bool, _ second: Bool) -> Bool {
            first
                && second
        }

        public func big(_ value: Int) -> Bool {
            value > 10
        }

        """
    /// A file whose first line follows a byte order mark.
    private static let marked = "\u{FEFF}public func marked() -> Int { 1 }\npublic func plain() -> Int {\n    2\n}\n"
    /// A file whose last line has no line break.
    private static let tail = "public func tail() -> Int { 1 }"

    /// The package holding the three files, measured.
    private static func harness() throws -> MappingHarness {
        let package = try TemporaryPackage([
            "Sources/Lib/Effects.swift": effects,
            "Sources/Lib/Marked.swift": marked,
            "Sources/Lib/Tail.swift": tail
        ])
        do {
            return try MappingHarness(package)
        } catch {
            package.remove()
            throw error
        }
    }

    /// A mutant placed on the record `owner` at `line`:`column`.
    private static func placed(_ owner: String, _ line: Int, _ column: Int) -> MutationMapper.Placed {
        MutationMapper.Placed(
            place: .record,
            owner: owner,
            reason: nil,
            anchor: SourcePosition(line: line, column: column)
        )
    }

    @Test("""
        a mutant pointed one past its statement after the statement's trailing comment, or at the end of a file \
        with no last line break, is anchored on the statement's last character
        """)
    func endAnchored() throws {
        let harness = try Self.harness()
        defer { harness.remove() }

        let commented = try harness.place(
            "Sources/Lib/Effects.swift",
            line: 2,
            column: 34,
            operatorID: "RemoveSideEffects",
            after: ""
        )
        let atEnd = try harness.place(
            "Sources/Lib/Tail.swift",
            line: 1,
            column: 32,
            operatorID: "RemoveSideEffects",
            after: ""
        )

        #expect(commented == Self.placed("Lib::func work(_: inout[Int])", 2, 17))
        #expect(atEnd == Self.placed("Lib::func tail() -> Int", 1, 31))
    }

    @Test("""
        a point on a token's start is the anchor, so a one-line body's statement pointed past its trailing space is \
        anchored on the body's closing brace, still inside the function; a point inside a token is its own anchor
        """)
    func onTokens() throws {
        let harness = try Self.harness()
        defer { harness.remove() }

        let brace = try harness.place(
            "Sources/Lib/Effects.swift",
            line: 6,
            column: 54,
            operatorID: "RemoveSideEffects",
            after: ""
        )
        let inside = try harness.place(
            "Sources/Lib/Effects.swift",
            line: 14,
            column: 6,
            operatorID: "ReplaceReturnValue",
            after: "0"
        )

        #expect(brace == Self.placed("Lib::func ping(_: inout[Int])", 6, 54))
        #expect(inside == Self.placed("Lib::func big(_: Int) -> Bool", 14, 6))
    }

    @Test("""
        a logical connector starting a line, pointed at the end of the line before, is anchored on the operator; a \
        relational replacement making false, pointed past the comparison, is anchored on its last character, though \
        making != from the same point would anchor forward
        """)
    func operatorRule() throws {
        let harness = try Self.harness()
        defer { harness.remove() }
        let path = "Sources/Lib/Effects.swift"

        let connector = try harness.place(
            path,
            line: 9,
            column: 10,
            operatorID: "ChangeLogicalConnector",
            after: "||"
        )
        let falseConstant = try harness.place(
            path,
            line: 14,
            column: 15,
            operatorID: "RelationalOperatorReplacement",
            after: "false"
        )
        let trueConstant = try harness.place(
            path,
            line: 14,
            column: 5,
            operatorID: "RelationalOperatorReplacement",
            after: "true"
        )
        let swap = try harness.place(
            path,
            line: 14,
            column: 15,
            operatorID: "RelationalOperatorReplacement",
            after: "!="
        )

        #expect(connector == Self.placed("Lib::func both(_: Bool, _: Bool) -> Bool", 10, 9))
        #expect(falseConstant == Self.placed("Lib::func big(_: Int) -> Bool", 14, 14))
        #expect(trueConstant == Self.placed("Lib::func big(_: Int) -> Bool", 14, 5))
        #expect(swap == Self.placed("Lib::func big(_: Int) -> Bool", 15, 1))
        #expect(MutantAnchoring.anchorsForward(operatorID: "RelationalBoundary", after: "false"))
        #expect(MutantAnchoring.anchorsForward(operatorID: "SwapTernary", after: "") == false)
    }

    @Test("a byte order mark adds its 3 bytes to line 1's anchors, as records count them, and nothing to later lines")
    func byteOrderMark() throws {
        let harness = try Self.harness()
        defer { harness.remove() }

        let first = try harness.place(
            "Sources/Lib/Marked.swift",
            line: 1,
            column: 31,
            operatorID: "ReplaceReturnValue",
            after: "0"
        )
        let later = try harness.place(
            "Sources/Lib/Marked.swift",
            line: 3,
            column: 5,
            operatorID: "ReplaceReturnValue",
            after: "0"
        )

        #expect(first == Self.placed("Lib::func marked() -> Int", 1, 34))
        #expect(later == Self.placed("Lib::func plain() -> Int", 3, 5))
    }

    @Test("a point its file doesn't hold, past its last line or past the end of its line, is unmapped")
    func outsideTheFile() throws {
        let harness = try Self.harness()
        defer { harness.remove() }

        let pastLines = try harness.place(
            "Sources/Lib/Effects.swift",
            line: 99,
            column: 1,
            operatorID: "ReplaceReturnValue",
            after: "0"
        )
        let pastLine = try harness.place(
            "Sources/Lib/Effects.swift",
            line: 2,
            column: 200,
            operatorID: "ReplaceReturnValue",
            after: "0"
        )

        let expected = MutationMapper.Placed(
            place: .unmapped,
            owner: nil,
            reason: "position outside its file",
            anchor: nil
        )
        #expect(pastLines == expected)
        #expect(pastLine == expected)
    }
}
