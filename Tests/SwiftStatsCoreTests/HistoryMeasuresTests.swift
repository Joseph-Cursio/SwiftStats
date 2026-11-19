import Foundation
@testable import SwiftStatsCore
import Testing

/// What history measures from a lineage: test matching, test changes,
/// change coupling and commit classification (PRD §7.13).
@Suite("History measures")
struct HistoryMeasuresTests {
    @Test("tests are found by file name: exact, then topical, then the enclosing type")
    func testNames() {
        let matcher = TestNameMatcher(testFiles: [
            "Tests/LibTests/FunctionScannerBodyTests.swift",
            "Tests/LibTests/FunctionScannerHeaderTests.swift",
            "Tests/LibTests/InteractiveTriageAcceptTests.swift",
            "Tests/LibTests/ShapeTests.swift",
            "Tests/LibTests/ParserSpec.swift"
        ])

        #expect(matcher.matches(file: "Sources/Lib/Shape.swift", typeName: nil) == ["Shape"])
        #expect(matcher.matches(file: "Sources/Lib/FunctionScanner.swift", typeName: nil)
            == ["FunctionScannerBody", "FunctionScannerHeader"])
        #expect(matcher.matches(file: "Sources/Lib/InteractiveTriage+Accept.swift", typeName: nil)
            == ["InteractiveTriageAccept"])
        #expect(matcher.matches(file: "Sources/Lib/Grammar.swift", typeName: "Parser") == ["Parser"])
        #expect(matcher.matches(file: "Sources/Lib/Unrelated.swift", typeName: "Nothing").isEmpty)
        #expect(TestNameMatcher.typeName(of: "Lib::Outer.Inner::func f()") == "Inner")
        #expect(TestNameMatcher.typeName(of: "Lib::func f()") == nil)
    }

    @Test("a change that also touches a matching test counts as a test change")
    func testChanges() throws {
        let repository = try HistoryRepository()
        defer { repository.remove() }
        try repository.write([
            "Sources/Lib/Shape.swift": HistorySources.area(),
            "Tests/LibTests/ShapeTests.swift": "func testArea() {}\n"
        ])
        try repository.commit("Add the shape and its test", day: 0)
        try repository.write([
            "Sources/Lib/Shape.swift": HistorySources.area(extra: "_ = 1\n        "),
            "Tests/LibTests/ShapeTests.swift": "func testArea() { _ = 1 }\n"
        ])
        try repository.commit("Change both", day: 1)
        try repository.write(["Sources/Lib/Shape.swift": HistorySources.area(extra: "_ = 2\n        ")])
        try repository.commit("Change the shape only", day: 2)

        let area = try #require(try repository.history().family("func area()"))

        #expect(area.hasTests)
        #expect(area.changes == 3)
        #expect(area.testChanges == 2)
    }

    @Test("families changed together often enough are coupled")
    func coupling() throws {
        let repository = try HistoryRepository()
        defer { repository.remove() }
        try repository.write([
            "Sources/Lib/Shape.swift": HistorySources.area(),
            "Sources/Lib/Other.swift": "func other() -> Int {\n    0\n}\n"
        ])
        try repository.commit("Add", day: 0)
        for step in 1...2 {
            try repository.write([
                "Sources/Lib/Shape.swift": HistorySources.area(extra: "_ = \(step)\n        "),
                "Sources/Lib/Other.swift": "func other() -> Int {\n    \(step)\n}\n"
            ])
            try repository.commit("Change both, \(step)", day: step)
        }

        let pairs = try repository.history().coupling

        #expect(pairs.count == 1)
        #expect(pairs.first?.support == 3)
        let namesAreCoupled = pairs.first.map { pair in
            [pair.familyA, pair.familyB].allSatisfy { family in family.contains("area") || family.contains("other") }
        }
        #expect(namesAreCoupled == true)
    }

    @Test("fix and revert subjects, and .git-blame-ignore-revs lines, are recognised")
    func classification() {
        let modules = ModuleMap(targets: [], anchorTree: [], excluded: [])
        let classifier = CommitClassifier(options: .standard, ignored: ["abcdef1"], windowStart: 0, modules: modules)
        let commit = { (subject: String, hash: String) in
            classifier.facts(of: HistoryCommit(hash: hash, time: 1, subject: subject, body: "", changes: []))
        }

        #expect(commit("Fix the parser", "1111111").isFix)
        #expect(commit("fixes #12", "1111111").isFix)
        #expect(commit("Resolve the protocols as a fixed point", "1111111").isFix == false)
        #expect(commit("Correct a regression in the lexer", "1111111").isFix)
        #expect(commit("Fix the mechanical SwiftLint warnings", "1111111").isFix == false)
        #expect(commit("Fix the parser", "abcdef1234").isFix == false)
        #expect(commit("Revert \"Add it\"", "1111111").isRevert)
        #expect(CommitClassifier.ignoreRevs(in: "# sweeps\nABCDEF1234 # format\n\nnot-a-hash\n") == ["abcdef1234"])
    }

    @Test("the Jaccard similarity of two sorted lists")
    func jaccard() {
        #expect(HistoryMatcher.jaccard([1, 2, 3], [2, 3, 4]) == 0.5)
        #expect(HistoryMatcher.jaccard([], []) == 0)
        #expect(HistoryMatcher.jaccard([1], [1]) == 1)
    }
}
