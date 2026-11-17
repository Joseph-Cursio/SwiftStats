@testable import SwiftStatsCore
import Testing

@Suite("KeyCollisions")
struct KeyCollisionsTests {
    private static func record(
        _ key: String,
        file: String,
        lines: ClosedRange<Int>,
        parent: String?
    ) -> FunctionRecord {
        let start = SourcePosition(line: lines.lowerBound, column: 1)
        return record(key, file: file, start: start, endLine: lines.upperBound, parent: parent)
    }

    private static func record(
        _ key: String,
        file: String,
        start: SourcePosition,
        endLine: Int,
        parent: String?
    ) -> FunctionRecord {
        FunctionRecord(
            key: key,
            module: "Lib",
            kind: .function,
            name: "f",
            accessorKind: nil,
            file: file,
            range: SourceSpan(start: start, end: SourcePosition(line: endLine, column: 1)),
            strippedLines: 1,
            bodyHash: "0",
            parentKey: parent,
            ifConfig: nil,
            role: .production
        )
    }

    @Test("unique keys pass through untouched")
    func uniqueKeys() {
        let records = [Self.record("Lib::func a()", file: "A.swift", lines: 1...1, parent: nil)]
        let (resolved, warnings) = KeyCollisions.resolve(records)

        #expect(resolved == records)
        #expect(warnings.isEmpty)
    }

    @Test("colliding keys get the file, then the line")
    func fileThenLine() {
        let records = [
            Self.record("Lib::func a()", file: "A.swift", lines: 1...1, parent: nil),
            Self.record("Lib::func a()", file: "B.swift", lines: 1...1, parent: nil),
            Self.record("Lib::func a()", file: "B.swift", lines: 5...5, parent: nil)
        ]
        let (resolved, warnings) = KeyCollisions.resolve(records)

        #expect(resolved.map(\.key) == [
            "Lib::func a() @ A.swift",
            "Lib::func a() @ B.swift:1",
            "Lib::func a() @ B.swift:5"
        ])
        #expect(warnings.count == 1)
    }

    @Test("colliding parents in one file keep their own children, whose keys follow")
    func childrenFollowTheirOwnParent() {
        let records = [
            Self.record("Lib::func outer()", file: "A.swift", lines: 2...5, parent: nil),
            Self.record("Lib::func outer() / func inner()", file: "A.swift", lines: 3...3, parent: "Lib::func outer()"),
            Self.record("Lib::func outer()", file: "A.swift", lines: 8...11, parent: nil),
            Self.record("Lib::func outer() / func inner()", file: "A.swift", lines: 9...9, parent: "Lib::func outer()")
        ]
        let (resolved, _) = KeyCollisions.resolve(records)

        #expect(resolved.map(\.key) == [
            "Lib::func outer() @ A.swift:2",
            "Lib::func outer() @ A.swift:2 / func inner()",
            "Lib::func outer() @ A.swift:8",
            "Lib::func outer() @ A.swift:8 / func inner()"
        ])
        #expect(resolved[1].parentKey == "Lib::func outer() @ A.swift:2")
        #expect(resolved[3].parentKey == "Lib::func outer() @ A.swift:8")
    }

    @Test("collisions on one line are told apart by column")
    func sameLine() {
        let first = SourcePosition(line: 1, column: 10)
        let second = SourcePosition(line: 1, column: 40)
        let records = [
            Self.record("Lib::func run()", file: "A.swift", start: first, endLine: 1, parent: nil),
            Self.record("Lib::func run()", file: "A.swift", start: second, endLine: 1, parent: nil)
        ]
        let keys = KeyCollisions.resolve(records).records.map(\.key)

        #expect(keys == ["Lib::func run() @ A.swift:1:10", "Lib::func run() @ A.swift:1:40"])
    }
}
