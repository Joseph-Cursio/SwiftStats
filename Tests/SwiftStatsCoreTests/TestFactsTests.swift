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
        ("zip([1, 2, 3], [4, 5])", 2), ("[1, 2], [true, false, true]", 6), ("([1, 2])", 2), ("3...1", 0),
        ("0...9_223_372_036_854_775_806", Int.max)
    ])
    func literalCases(arguments: String, expected: Int) throws {
        let facts = try Self.facts("@Test(arguments: \(arguments)) func check(value: Int) { }")
        #expect(facts.kind == .parameterized)
        #expect(facts.cases == expected)
    }

    @Test("arguments it can't size leave the count unknown", arguments: [
        "Mode.allCases", "1...count", "zip(names, [1])", "stride(from: 0, to: 9, by: 3)",
        // Counts past Int.max are unknown rather than a crash.
        "0...9_223_372_036_854_775_807", "-9_000_000_000_000_000_000..<9_000_000_000_000_000_000",
        "0..<4_294_967_296, 0..<4_294_967_296"
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

    @Test("""
        every test keeps the names its body refers to (identifiers, members, key paths, types) and the names it \
        calls, a type's for T(…), T<U>(…), T.init(…) and T<U>.init(…); operators are neither
        """)
    func references() throws {
        let facts = try Self.facts("""
        @Test func shelf() {
            var shelf = Shelf(size: 2)
            let other: Bin<Int> = Bin<Int>(items: [])
            let made = Kit.Crate.init(count: 1)
            let tray = Tray<Int>.init(size: 3)
            shelf.grow()
            #expect(shelf.count + other.total + tray.size == made[0])
            #expect([shelf].map(\\.label).isEmpty == false)
        }
        """)

        #expect(facts.kind == .example)
        #expect(facts.references.names == [
            "Shelf", "shelf", "other", "Bin", "Int", "made", "Kit", "Crate", "tray", "Tray", "grow", "count", "total",
            "size", "label", "map", "isEmpty"
        ])
        #expect(facts.references.calls == ["Shelf", "Bin", "Crate", "Tray", "grow", "map"])
        #expect(facts.callees.isEmpty)
    }

    @Test("""
        names are kept without backticks; an implicit `.init(…)` calls the annotated type of the binding it \
        initialises, and nothing otherwise
        """)
    func escapedAndImplicitNames() throws {
        let facts = try Self.facts("""
        @Test func gauges() {
            let gauge: Gauge = .init(scale: 1)
            let spare: Kit.Meter? = .init()
            let `default` = Config.`default`
            take(.init(x: 1))
        }
        """)

        // `default` is `Config`'s member, written with backticks.
        #expect(facts.references.names == ["Gauge", "Kit", "Meter", "default", "Config", "take"])
        #expect(facts.references.calls == ["Gauge", "Meter", "take"])
        #expect(TestReferences.unescaped("`default`") == "default")
        #expect(TestReferences.unescaped("plain") == "plain")
    }

    @Test("""
        a test's references include what its parameter clause and its `@Test` `arguments:` collections name and \
        call, which add no assertions, but not its display name or traits
        """)
    func declarationReferences() throws {
        let facts = try Self.facts("""
        @Test(\"reads\", .tags(.slow), .timeLimit(.minutes(1)), arguments: [Gauge(scale: 1)], [Dial.low])
        func reads(gauge: Gauge, dial: Dial, limit: Limit = .standard) {
            #expect(gauge.read() == 1)
        }
        """)

        #expect(facts.kind == .parameterized)
        #expect(facts.cases == 1)
        #expect(facts.assertions == 1)
        // The traits name no subject, so `tags`, `slow`, `timeLimit` and
        // `minutes` are not references.
        #expect(facts.references.names == ["Gauge", "Dial", "low", "Limit", "standard", "gauge", "read"])
        #expect(facts.references.calls == ["Gauge", "read"])
    }
}
