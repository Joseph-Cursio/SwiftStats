import SwiftParser
@testable import SwiftStatsCore
import SwiftSyntax
import Testing

/// What a test's syntax says about it (PRD §7.8).
@Suite("Test facts")
struct TestFactsTests {
    /// The facts of the first function in `source`.
    private static func facts(_ source: String) throws -> TestFacts {
        let tree = Parser.parse(source: source)
        let function = try #require(tree.statements.first?.item.as(FunctionDeclSyntax.self))
        return TestFacts(function)
    }

    @Test("literal arguments give a case count; others don't", arguments: [
        ("[1, 2, 3]", 3), ("[\"a\": 1, \"b\": 2]", 2), ("[:]", 0), ("1...4", 4), ("-2..<2", 4),
        ("zip([1, 2, 3], [4, 5])", 2), ("[1, 2], [true, false, true]", 6), ("([1, 2])", 2)
    ])
    func literalCases(arguments: String, expected: Int) throws {
        let facts = try Self.facts("@Test(arguments: \(arguments)) func check(value: Int) { }")
        #expect(facts.kind == .parameterized)
        #expect(facts.cases == expected)
    }

    @Test("arguments it can't size leave the count unknown", arguments: [
        "Mode.allCases", "1...count", "zip(names, [1])", "stride(from: 0, to: 9, by: 3)"
    ])
    func unknownCases(arguments: String) throws {
        let facts = try Self.facts("@Test(\"named\", arguments: \(arguments)) func check(value: Int) { }")
        #expect(facts.kind == .parameterized)
        #expect(facts.cases == nil)
    }

    @Test("property checks win over idempotency and parameters; trials add up")
    func kinds() throws {
        let property = try Self.facts("""
        @Test(arguments: [1]) func laws(value: Int) async {
            await propertyCheck(input: Gen.int()) { _ in }
            await propertyCheck(count: 1_000, input: Gen.int()) { _ in }
            #assertIdempotent { 1 }
        }
        """)
        let lawKit = try Self.facts("@Test func kit() async { await checkSetAlgebraPropertyLaws(for: Set<Int>.self) }")
        let backend = try Self.facts("@Test func stub() { SwiftPropertyBasedBackend().check(trials: 10) { } }")
        let unreadable = try Self.facts(
            "@Test func varying() async { await propertyCheck(count: n, input: g) { _ in } }"
        )
        let effects = try Self.facts("func testEffects() { assertIdempotentEffects { save() } }")

        #expect(property.kind == .property)
        #expect(property.trials == 1_100)
        #expect(property.cases == nil)
        #expect(lawKit.kind == .property)
        #expect(lawKit.trials == nil)
        #expect(backend.kind == .property)
        #expect(unreadable.trials == nil)
        #expect(effects.kind == .idempotency)
        #expect(effects.framework == .xctest)
    }

    @Test("assertions: #expect, #require and every XCTAssert, nested closures included")
    func assertions() throws {
        let swiftTesting = try Self.facts("""
        @Test func checks() throws {
            let value = try #require(Int("1"))
            #expect(value == 1)
            [1].forEach { #expect($0 > 0) }
            print("not an assertion")
        }
        """)
        let xctest = try Self.facts("""
        func testChecks() {
            XCTAssertEqual(1, 1)
            XCTAssertTrue(true, "message")
            XCTFail("not counted")
        }
        """)

        #expect(swiftTesting.assertions == 3)
        #expect(swiftTesting.framework == .swiftTesting)
        #expect(xctest.assertions == 2)
    }
}
