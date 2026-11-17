import SwiftParser
@testable import SwiftStatsCore
import Testing

@Suite("Sitrep-compatible counts")
struct SitrepCounterTests {
    private static func facts(_ source: String, path: String) -> SitrepFileFacts {
        SitrepFileVisitor.facts(for: Parser.parse(source: source), source: source, path: path)
    }

    @Test("lines are split on \\n bytes; lines of spaces count as non-empty")
    func lineArithmetic() {
        #expect(SitrepLines.newlineCount("a\nb\n") == 2)
        #expect(SitrepLines.nonEmptyLineCount("a\n\n   \nb") == 3)
        #expect(SitrepLines.nonEmptyLineCount("a\r\n\r\n") == 2)
        #expect(SitrepLines.nonEmptyLineCount("") == 0)
    }

    @Test("only types outside Sitrep's nodes count, as Sitrep sees them")
    func topLevelTypes() {
        let source = """
        struct Outer {
            struct Nested { }
        }
        actor Worker {
            struct InsideActor { }
        }
        func make() {
            struct InsideFunction { }
        }
        extension Outer: Equatable { }
        """
        let facts = Self.facts(source, path: "A.swift")

        #expect(facts.types.map(\.name) == ["Outer", "InsideActor", "Outer"])
        #expect(facts.types.map(\.kind) == ["struct", "struct", "extension"])
        #expect(facts.types[2].inheritance == ["Equatable"])
    }

    @Test("files are joined end to end, so each boundary merges two lines")
    func totals() {
        let first = Self.facts("import UIKit\n\nclass A: UIView {\n}\n", path: "Sources/A.swift")
        let second = Self.facts("import UIKit\nstruct B { }", path: "Sources/B.swift")
        let report = SitrepCounter.report(for: [first, second])

        #expect(report.scanStats.scannedFiles == 2)
        #expect(report.scanStats.totalLinesOfCode == 6)
        #expect(report.scanStats.totalStrippedLinesOfCode == 4)
        #expect(report.scanStats.longestFile == SitrepStat(name: "A.swift", value: 3))
        #expect(report.imports == [SitrepStat(name: "UIKit", value: 2)])
        #expect(report.inheritances[1] == SitrepStat(name: "UIView", value: 1))
        #expect(report.scanStats.uiKitLinesOfCode == 2)
    }

    @Test("longest type sums extensions; ties go to the first name")
    func longestType() {
        let file = Self.facts("struct B { }\nstruct A { }\nextension A { }\n", path: "A.swift")
        let tied = Self.facts("struct D { }\nstruct C { }\n", path: "B.swift")

        #expect(SitrepCounter.report(for: [file]).scanStats.longestType == SitrepStat(name: "A", value: 2))
        #expect(SitrepCounter.report(for: [tied]).scanStats.longestType == SitrepStat(name: "C", value: 1))
    }

    @Test("SwiftUI views follow Sitrep's two different rules")
    func swiftUIQuirks() {
        // The view count looks at every inherited type; the line count only
        // follows the first one, so `Equatable, View` counts as a view but not
        // as SwiftUI code.
        let source = "struct First: View { }\nstruct Second: Equatable, View { }\n"
        let report = SitrepCounter.report(for: [Self.facts(source, path: "A.swift")])

        #expect(report.inheritances[2] == SitrepStat(name: "SwiftUI.View", value: 2))
        #expect(report.scanStats.swiftUILinesOfCode == 1)
    }

    @Test("a name declared with different first parents follows its first declaration")
    func conflictingParents() {
        let iOSSource = "class ViewBase: UIView { }\nclass Leaf: ViewBase {\n    func a() { }\n}\n"
        let iOS = Self.facts(iOSSource, path: "iOS/Base.swift")
        let macOS = Self.facts("class ViewBase: NSView { }\n", path: "macOS/Base.swift")

        #expect(SitrepCounter.namesWithConflictingParents(in: [iOS, macOS]) == ["ViewBase"])
        // ViewBase resolves to UIView, and Sitrep matches by name, so both
        // ViewBase declarations count with Leaf: 1 + 3 + 1 lines.
        #expect(SitrepCounter.report(for: [iOS, macOS]).scanStats.uiKitLinesOfCode == 5)
        #expect(SitrepCounter.namesWithConflictingParents(in: [iOS]).isEmpty)

        // Different parents that don't change the UIKit or SwiftUI counts
        // aren't flagged.
        let codable = Self.facts("struct Model: Codable { }\n", path: "A.swift")
        let hashable = Self.facts("struct Model: Hashable { }\n", path: "B.swift")
        #expect(SitrepCounter.namesWithConflictingParents(in: [codable, hashable]).isEmpty)
    }
}
