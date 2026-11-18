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

    @Test("local declarations in property and global initialisers don't collide with members")
    func initializerClosures() {
        let source = """
        struct Holder {
            func helper() -> Int { 1 }
            let first: Int = { func helper() -> Int { 2 }; return helper() }()
            lazy var second: Int = { func helper() -> Int { 3 }; return helper() }()
            let third: Int = { struct Box { func open() -> Int { 4 } }; return Box().open() }()
            struct Box { func open() -> Int { 5 } }
        }
        let global: Int = { func make() -> Int { 1 }; return make() }()
        """
        let records = CollectorHarness.collect(source)

        #expect(records.map(\.key) == [
            "Lib::Holder::func helper() -> Int",
            "Lib::Holder::let first: Int = <initializer> / func helper() -> Int",
            "Lib::Holder::var second: Int = <initializer> / func helper() -> Int",
            "Lib::Holder::let third: Int = <initializer> / Box::func open() -> Int",
            "Lib::Holder.Box::func open() -> Int",
            "Lib::let global: Int = <initializer> / func make() -> Int"
        ])
        #expect(records.allSatisfy { $0.parentKey == nil })
    }

    @Test("declarations inside top-level statements belong to the top-level-code record")
    func topLevelBlocks() {
        let source = """
        func run() { }
        do {
            func run() { print("a") }
            run()
        }
        if Bool.random() {
            func step() { }
        } else {
            func step() { print("b") }
        }
        """
        let records = CollectorHarness.collect(source, file: "Sources/Tool/main.swift")
        let topLevel = "Lib::<top-level code> @ Sources/Tool/main.swift"

        #expect(records.map(\.key) == [
            topLevel,
            "Lib::func run()",
            "\(topLevel) / func run()",
            "\(topLevel) / func step()",
            "\(topLevel) / func step() #2"
        ])
        #expect(records[2].parentKey == topLevel)
    }

    @Test("top-level statements inside #if belong to the top-level-code record")
    func topLevelIfConfig() {
        let source = """
        import Foundation
        #if os(macOS)
        print("mac")
        exit(0)
        #else
        print("other")
        #endif
        """
        let records = CollectorHarness.collect(source, file: "Sources/Tool/main.swift")

        #expect(records.count == 1)
        #expect(records.first?.kind == .topLevelCode)
        #expect(records.first?.range.start.line == 3)
        #expect(records.first?.range.end.line == 6)
        #expect(records.first?.strippedLines == 3)
    }

    @Test("an #elseif condition with || keeps its own parentheses")
    func elseIfPrecedence() {
        let source = "#if A\nfunc f() { }\n#elseif B || C\nfunc f() { }\n#endif\n"
        #expect(CollectorHarness.collect(source).map(\.ifConfig) == ["A", "!(A) && (B || C)"])
    }

    @Test("trailing commas don't change keys or body hashes")
    func trailingCommas() {
        let compact = "struct S { func g<T, U>(a: (Int, String), f: @escaping (Int, Int) -> Void) -> [Int] { [1, 2] } }"
        let vertical = """
        struct S {
            func g<
                T,
                U,
            >(
                a: (Int, String,),
                f: @escaping (Int, Int,) -> Void,
            ) -> [Int] {
                [1, 2,]
            }
        }
        """
        let before = CollectorHarness.collect(compact)[0]
        let after = CollectorHarness.collect(vertical)[0]

        #expect(before.key == after.key)
        #expect(before.bodyHash == after.bodyHash)
    }

    @Test("a private type nested in an extension doesn't file-scope a same-named top-level type")
    func nestedPrivateTypeInExtension() {
        let source = """
        extension Shelf {
            fileprivate struct Tag { }
        }
        extension Shelf.Tag {
            func label() { }
        }
        extension Tag {
            func shout() { }
        }
        """
        #expect(CollectorHarness.keys(source, file: "Sources/Lib/B.swift") == [
            "Lib::Shelf.Tag::func label() @ Sources/Lib/B.swift",
            "Lib::Tag::func shout()"
        ])
    }

    @Test("an XCTest method that returns a value is not a test")
    func xcTestReturnType() {
        let source = """
        final class MathTests: XCTestCase {
            func testVoid() { }
            func testExplicitVoid() -> Void { }
            func testReturns() -> Int { 1 }
        }
        """
        let records = CollectorHarness.collect(source, isTestTarget: true, testCaseClasses: ["MathTests"])
        #expect(records.map(\.role) == [.test, .test, .helper])
    }

    @Test("requirements without bodies get no record; a class method's key says class")
    func requirementsAndClassMethods() {
        let source = """
        protocol Source {
            init(name: String)
            func next() -> Int
        }
        class Factory {
            class func make() -> Factory { Factory() }
        }
        """
        #expect(CollectorHarness.keys(source) == ["Lib::Factory::class func make() -> Factory"])
    }

    @Test("declarations inside a member-level freestanding macro get no record")
    func memberMacro() {
        let source = """
        struct Screen {
            #hidden { func helper() { } }
            func show() { }
        }
        """
        #expect(CollectorHarness.keys(source) == ["Lib::Screen::func show()"])
    }

    @Test("a @Test inside an #if in the attribute list makes a test")
    func conditionalTestAttribute() {
        let source = """
        struct MathTests {
            #if canImport(Testing)
            @Test
            #endif
            func adds() { }
        }
        """
        let records = CollectorHarness.collect(source, isTestTarget: true, testCaseClasses: [])
        #expect(records.map(\.role) == [.test])
    }

    @Test("an #if in the attribute list doesn't hide the @Test after it")
    func conditionalAttributeBeforeTest() {
        let source = """
        struct MathTests {
            #if DEBUG
            @available(*, deprecated)
            #endif
            @Test
            func adds() { }
        }
        """
        let records = CollectorHarness.collect(source, isTestTarget: true, testCaseClasses: [])
        #expect(records.map(\.role) == [.test])
    }
}
