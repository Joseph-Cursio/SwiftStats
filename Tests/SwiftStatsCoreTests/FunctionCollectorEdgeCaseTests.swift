import Testing

/// Cases found by scanning real packages (swift-nio, SwiftLint, GRDB, the
/// DocC tutorials in swift-syntax): legal code that once produced duplicate
/// keys.
@Suite("FunctionCollector: edge cases from real packages")
struct FunctionCollectorEdgeCaseTests {
    @Test("local functions sharing a name in sibling blocks are numbered")
    func siblingLocalFunctions() {
        let source = """
        func open(flag: Bool) {
            if flag {
                func makePath() -> String { "a" }
            } else {
                func makePath() -> String { "b" }
            }
        }
        """
        #expect(CollectorHarness.keys(source) == [
            "Lib::func open(flag: Bool)",
            "Lib::func open(flag: Bool) / func makePath() -> String",
            "Lib::func open(flag: Bool) / func makePath() -> String #2"
        ])
    }

    @Test("declarations inside freestanding macro arguments get no record")
    func macroArguments() {
        let source = """
        struct Rule {
            static let examples = [
                #example { func f(a: Int) { } },
                #example { func f(a: Int) { _ = a } }
            ]
        }
        #Preview { func helper() { } }
        """
        #expect(CollectorHarness.keys(source).isEmpty)
    }

    @Test("an unmodified extension of a file's private type is file-scoped too")
    func extensionOfPrivateType() {
        let source = """
        private struct Book {
            struct Page { }
        }
        extension Book {
            func open() { }
        }
        extension Book.Page {
            func turn() { }
        }
        struct Shelf { }
        extension Shelf {
            func dust() { }
        }
        """
        #expect(CollectorHarness.keys(source, file: "Tests/A.swift") == [
            "Lib::Book::func open() @ Tests/A.swift",
            "Lib::Book.Page::func turn() @ Tests/A.swift",
            "Lib::Shelf::func dust()"
        ])
    }
}
