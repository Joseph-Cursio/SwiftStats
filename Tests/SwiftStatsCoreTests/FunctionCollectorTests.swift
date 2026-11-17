import SwiftParser
@testable import SwiftStatsCore
import SwiftSyntax
import Testing

@Suite("FunctionCollector")
struct FunctionCollectorTests {
    // MARK: - Kinds and keys

    @Test("every function-like kind gets a record with the expected key")
    func kindsAndKeys() {
        let source = """
        struct Box<T> {
            init?(value: T) { }
            deinit { }
            func map<U>(_ transform: (T) throws -> U) rethrows -> Box<U>? where U: Equatable { nil }
            static func make() -> Self? { nil }
            subscript(index: Int) -> T { fatalError() }
            var count: Int { 0 }
            var flag = false { didSet { } }
            var stored = 1
        }
        func global(label name: String, _ other: Int = 3, rest: Int...) async throws -> Bool { true }
        """
        let records = CollectorHarness.collect(source)

        #expect(records.map(\.key) == [
            "Lib::Box::init?(value: T)",
            "Lib::Box::deinit",
            "Lib::Box::func map<U>(_: (T) throws -> U) rethrows -> Box<U>? where U: Equatable",
            "Lib::Box::static func make() -> Self?",
            "Lib::Box::subscript(_: Int) -> T",
            "Lib::Box::var count: Int { get }",
            "Lib::Box::var flag { didSet }",
            "Lib::func global(label: String, _: Int, rest: Int...) async throws -> Bool"
        ])
        #expect(records.map(\.kind) == [
            .initializer, .deinitializer, .function, .function, .subscriptDeclaration,
            .accessor, .accessor, .function
        ])
        #expect(records.map(\.name) == ["init", "deinit", "map", "make", "subscript", "count", "flag", "global"])
        #expect(records[5].accessorKind == "get")
        #expect(records[6].accessorKind == "didSet")
    }

    @Test("protocol requirements without a body get no record; protocol extension methods do")
    func protocolRequirements() {
        let source = """
        protocol Shape {
            var area: Double { get }
            func draw()
            subscript(index: Int) -> Int { get set }
        }
        extension Shape where Self: Equatable {
            func draw() { }
        }
        """
        #expect(CollectorHarness.keys(source) == ["Lib::Shape where Self: Equatable::func draw()"])
    }

    @Test("nested functions and subscript accessors take the parent's key as prefix")
    func nesting() {
        let source = """
        struct Grid {
            func outer() {
                func helper() { }
                struct Local {
                    func method() { }
                }
            }
            subscript(row: Int) -> Int {
                get { 0 }
                set { }
            }
        }
        """
        let records = CollectorHarness.collect(source)

        #expect(records.map(\.key) == [
            "Lib::Grid::func outer()",
            "Lib::Grid::func outer() / func helper()",
            "Lib::Grid::func outer() / Local::func method()",
            "Lib::Grid::subscript(_: Int) -> Int",
            "Lib::Grid::subscript(_: Int) -> Int / { get }",
            "Lib::Grid::subscript(_: Int) -> Int / { set }"
        ])
        #expect(records[1].parentKey == "Lib::Grid::func outer()")
        #expect(records[2].parentKey == "Lib::Grid::func outer()")
        #expect(records[4].parentKey == "Lib::Grid::subscript(_: Int) -> Int")
        #expect(records[0].parentKey == nil)
    }

    @Test("nested functions with the same name in different methods don't collide")
    func nestedFunctionsDistinct() {
        let source = """
        struct Worker {
            func first() { func helper() { } }
            func second() { func helper() { } }
        }
        """
        let keys = CollectorHarness.keys(source)
        #expect(Set(keys).count == keys.count)
    }

    @Test("overloads that differ only in what Swift allows still get distinct keys")
    func overloads() {
        let source = """
        struct Counter {
            static prefix func ++ (value: inout Counter) -> Counter { value }
            static postfix func ++ (value: inout Counter) -> Counter { value }
            func value() -> Int { 0 }
            func value() -> String { "" }
            func load() async { }
            func load() { }
            static func make() { }
            func make() { }
            func pick<T: Numeric>(_ item: T) { }
            func pick<T: StringProtocol>(_ item: T) { }
        }
        """
        let keys = CollectorHarness.keys(source)

        #expect(keys.count == 10)
        #expect(Set(keys).count == keys.count)
        #expect(keys.contains("Lib::Counter::static prefix func ++(value: inout Counter) -> Counter"))
        #expect(keys.contains("Lib::Counter::static postfix func ++(value: inout Counter) -> Counter"))
    }

    @Test("#if conditions are part of the key and recorded on the record")
    func ifConfig() {
        let source = """
        #if os(macOS)
        func platform() -> String { "mac" }
        #elseif os(Linux)
        func platform() -> String { "linux" }
        #else
        func platform() -> String { "other" }
        #endif
        """
        let records = CollectorHarness.collect(source)

        #expect(records.map(\.key) == [
            "Lib::func platform() -> String #if os(macOS)",
            "Lib::func platform() -> String #if !(os(macOS)) && os(Linux)",
            "Lib::func platform() -> String #if !(os(macOS)) && !(os(Linux))"
        ])
        #expect(records[0].ifConfig == "os(macOS)")
    }

    @Test("private and fileprivate declarations carry the file; others don't")
    func fileScope() {
        let source = """
        private func hidden() { }
        fileprivate func alsoHidden() { }
        func visible() { }
        private extension String {
            func shout() -> String { self }
        }
        private struct Secret {
            func reveal() { }
        }
        struct Open {
            private(set) var count: Int { get { 0 } set { } }
        }
        """
        let keys = CollectorHarness.keys(source, file: "Sources/Lib/A.swift")

        #expect(keys == [
            "Lib::func hidden() @ Sources/Lib/A.swift",
            "Lib::func alsoHidden() @ Sources/Lib/A.swift",
            "Lib::func visible()",
            "Lib::String::func shout() -> String @ Sources/Lib/A.swift",
            "Lib::Secret::func reveal() @ Sources/Lib/A.swift",
            "Lib::Open::var count: Int { get }",
            "Lib::Open::var count: Int { set }"
        ])
    }

    @Test("top-level statements get one synthetic record per file")
    func topLevelCode() {
        let source = """
        import Foundation
        let greeting = "hi"
        print(greeting)
        func helper() { }
        if greeting.isEmpty { print("empty") }
        """
        let records = CollectorHarness.collect(source, file: "Sources/Tool/main.swift")

        #expect(records.map(\.key) == [
            "Lib::<top-level code> @ Sources/Tool/main.swift",
            "Lib::func helper()"
        ])
        #expect(records[0].kind == .topLevelCode)
        #expect(records[0].range.start.line == 3)
        #expect(records[0].range.end.line == 5)
        #expect(records[0].strippedLines == 2)
    }

    @Test("a file of declarations only has no top-level record")
    func noTopLevelCode() {
        #expect(CollectorHarness.keys("let value = 1\nfunc f() { }\n") == ["Lib::func f()"])
    }

    // MARK: - Measurements

    @Test("range covers attributes; stripped lines skip attributes, comments and blank lines")
    func rangeAndStrippedLines() {
        let source = """
        /// Documented.
        @discardableResult
        func work() -> Int {
            // a comment

            let value = 1
            /* block
               comment */
            return value
        }
        """
        let record = CollectorHarness.collect(source)[0]

        #expect(record.range.start == SourcePosition(line: 2, column: 1))
        #expect(record.range.end == SourcePosition(line: 10, column: 1))
        #expect(record.strippedLines == 4)
    }
}
