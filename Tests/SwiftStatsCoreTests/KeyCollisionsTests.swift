@testable import SwiftStatsCore
import Testing

@Suite("KeyCollisions")
struct KeyCollisionsTests {
    private static func record(_ key: String, file: String, line: Int, parent: String?) -> FunctionRecord {
        FunctionRecord(
            key: key,
            module: "Lib",
            kind: .function,
            name: "f",
            accessorKind: nil,
            file: file,
            range: SourceSpan(start: SourcePosition(line: line, column: 1), end: SourcePosition(line: line, column: 9)),
            strippedLines: 1,
            bodyHash: "0",
            parentKey: parent,
            ifConfig: nil,
            role: .production
        )
    }

    @Test("unique keys pass through untouched")
    func uniqueKeys() {
        let records = [Self.record("Lib::func a()", file: "A.swift", line: 1, parent: nil)]
        let (resolved, warnings) = KeyCollisions.resolve(records)

        #expect(resolved == records)
        #expect(warnings.isEmpty)
    }

    @Test("colliding keys get the file, then the line, and children follow their parent")
    func collisions() {
        let records = [
            Self.record("Lib::func a()", file: "A.swift", line: 1, parent: nil),
            Self.record("Lib::func a() / func b()", file: "A.swift", line: 2, parent: "Lib::func a()"),
            Self.record("Lib::func a()", file: "B.swift", line: 1, parent: nil),
            Self.record("Lib::func a()", file: "B.swift", line: 5, parent: nil)
        ]
        let (resolved, warnings) = KeyCollisions.resolve(records)

        #expect(resolved.map(\.key) == [
            "Lib::func a() @ A.swift",
            "Lib::func a() / func b()",
            "Lib::func a() @ B.swift:1",
            "Lib::func a() @ B.swift:5"
        ])
        #expect(resolved[1].parentKey == "Lib::func a() @ A.swift")
        #expect(warnings.count == 1)
    }
}
