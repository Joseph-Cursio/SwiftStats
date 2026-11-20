//
//  ValueShapeTests.swift
//  SwiftStatsCoreTests
//
//  Whether a function is value-shaped, and its shape (PRD §7.10), on the
//  Effects fixture's visitors and builders and on small sources.
//

@testable import SwiftStatsCore
import Testing

@Suite("Value shape")
struct ValueShapeTests {
    /// The function facts of the record keyed `key` in `run`.
    private static func function(_ key: String, in run: EffectRun) throws -> EffectFacts.Function {
        try #require(run.facts[key]?.function, "no function facts for \(key)")
    }

    @Test("visitors appending to their issues, calling addIssue or a helper are not value-shaped")
    func visitors() throws {
        let run = try EffectHarness.runFixture()
        let keys = [
            "Effects::EnumRule::func visit(_: EnumDeclSyntax) -> SyntaxVisitorContinueKind",
            "Effects::StructRule::func visit(_: StructDeclSyntax) -> SyntaxVisitorContinueKind",
            "Effects::ClassRule::func visit(_: ClassDeclSyntax) -> SyntaxVisitorContinueKind"
        ]
        for key in keys {
            let facts = try Self.function(key, in: run)
            #expect(facts.valueShaped == false, "\(key)")
            #expect(facts.shape == nil, "\(key)")
        }
    }

    @Test("a builder appending to a local array is value-shaped")
    func localBuilder() throws {
        let evens = try Self.function("Effects::func evens(in: [Int]) -> [Int]", in: try EffectHarness.runFixture())

        #expect(evens.valueShaped)
        #expect(evens.shape == .endomorphism)
    }

    @Test("an override, and a signature matching no shape, have no shape")
    func noShape() throws {
        let run = try EffectHarness.runFixture()
        let token = try Self.function(
            "Effects::TokenRule::func visit(_: TokenSyntax) -> SyntaxVisitorContinueKind",
            in: run
        )
        let base = try Self.function("Effects::Outline::func merged(_: Outline) -> Outline", in: run)
        let override = try Self.function("Effects::Box::func merged(_: Outline) -> Outline", in: run)
        let convert = try Self.function("Effects::func convert(_: Foo) -> Bar", in: run)

        #expect(token.valueShaped)
        #expect(token.shape == nil)
        #expect(base.shape == .endomorphism)
        #expect(override.valueShaped)
        #expect(override.shape == nil)
        #expect(convert.valueShaped)
        #expect(convert.shape == nil)
    }

    @Test("binary operations, self-returning methods and predicates, reading Self as the enclosing type")
    func shapes() throws {
        let run = try EffectHarness.run(source: """
        struct Money {
            let cents: Int
            func adding(_ other: Self) -> Money { Money(cents: cents + other.cents) }
            func scaled(by factor: Int) -> Money { Money(cents: cents * factor) }
            static func make(cents: Int) -> Money { Money(cents: cents) }
            static func combined(_ lhs: Money, _ rhs: Money) -> Money { lhs.adding(rhs) }
            static func isLarger(_ lhs: Money, _ rhs: Money) -> Bool { lhs.cents > rhs.cents }
        }
        func isEven(_ value: Int) -> Bool { value.isMultiple(of: 2) }
        func matches(_ value: Int, _ name: String) -> Bool { name.count == value }
        """)
        let expected: [(key: String, shape: EffectFacts.Shape?)] = [
            ("Effects::Money::func adding(_: Self) -> Money", .endomorphism),
            ("Effects::Money::func scaled(by: Int) -> Money", .selfReturning),
            // A static factory is not a method of a value.
            ("Effects::Money::static func make(cents: Int) -> Money", nil),
            ("Effects::Money::static func combined(_: Money, _: Money) -> Money", .binary),
            ("Effects::Money::static func isLarger(_: Money, _: Money) -> Bool", .predicate),
            ("Effects::func isEven(_: Int) -> Bool", .predicate),
            ("Effects::func matches(_: Int, _: String) -> Bool", nil)
        ]
        for (key, shape) in expected {
            let facts = try Self.function(key, in: run)
            #expect(facts.valueShaped, "\(key)")
            #expect(facts.shape == shape, "\(key)")
        }
    }

    @Test("mutating, inout and valueless functions are not value-shaped")
    func signatures() throws {
        let run = try EffectHarness.run(source: """
        struct Counter {
            var count = 0
            mutating func bumped() -> Int { count += 1; return count }
        }
        func addOne(_ value: inout Int) -> Int { value += 1; return value }
        func nothing(_ value: Int) { _ = value }
        func never(_ value: Int) -> Never { fatalError("\\(value)") }
        func handler(_ apply: (inout Int) -> Void) -> Int { 0 }
        """)
        let expected = [
            ("Effects::Counter::func bumped() -> Int", false),
            ("Effects::func addOne(_: inout Int) -> Int", false),
            ("Effects::func nothing(_: Int)", false),
            ("Effects::func never(_: Int) -> Never", false),
            // An `inout` inside a closure parameter's type doesn't count.
            ("Effects::func handler(_: (inout Int) -> Void) -> Int", true)
        ]
        for (key, valueShaped) in expected {
            #expect(try Self.function(key, in: run).valueShaped == valueShaped, "\(key)")
        }
    }

    @Test("a thrown-away call or an outside assignment is a write; returned values, locals and checks aren't")
    func writes() throws {
        let run = try EffectHarness.run(source: """
        final class Tally {
            var total = 0
            func noisy(_ value: Int) -> Int { log(value); return value }
            func stored(_ value: Int) -> Int { self.total = value; return value }
            func counted(_ value: Int) -> Int { total += value; return total }
            func pick(_ flag: Bool) -> Int { if flag { compute(1) } else { compute(2) } }
            func summed(_ values: [Int]) -> Int {
                precondition(values.isEmpty == false)
                var sum = 0
                values.forEach { sum += $0 }
                _ = values.map { compute($0) }
                return sum
            }
            func awaited(_ value: Int) async throws -> Int { try await sender.send(value); return value }
        }
        """)
        let expected = [
            ("Effects::Tally::func noisy(_: Int) -> Int", false),
            ("Effects::Tally::func stored(_: Int) -> Int", false),
            ("Effects::Tally::func counted(_: Int) -> Int", false),
            ("Effects::Tally::func pick(_: Bool) -> Int", true),
            ("Effects::Tally::func summed(_: [Int]) -> Int", true),
            ("Effects::Tally::func awaited(_: Int) async throws -> Int", false)
        ]
        for (key, valueShaped) in expected {
            #expect(try Self.function(key, in: run).valueShaped == valueShaped, "\(key)")
        }
    }

    @Test("a call that is the only statement of a closure whose value is thrown away is a write")
    func closureStatements() throws {
        let run = try EffectHarness.run(source: """
        final class Merger {
            var overrides: Set<String> = []
            var issues: [Int] = []
            func merged(_ other: [String]) -> [String] { other.forEach { overrides.insert($0) }; return other }
            func flagged(_ values: [Int]) -> [Int] { values.forEach { if $0 > 0 { issues.append($0) } }; return values }
            func recorded(_ values: [Int]) throws -> [Int] { try values.forEach { try self.record($0) }; return values }
            func mapped(_ values: [Int]) -> [Int] { values.map { compute($0) } }
            func doubled(_ values: [Int]) -> [Int] { let result = values.map { self.twice($0) }; return result }
            func total(_ values: [Int]) -> Int { values.lazy.map { compute($0) }.reduce(0) { sum($0, $1) } }
        }
        """)
        let expected = [
            ("Effects::Merger::func merged(_: [String]) -> [String]", false),
            // The `if` is the closure's value, and the closure's value is thrown away.
            ("Effects::Merger::func flagged(_: [Int]) -> [Int]", false),
            ("Effects::Merger::func recorded(_: [Int]) throws -> [Int]", false),
            ("Effects::Merger::func mapped(_: [Int]) -> [Int]", true),
            ("Effects::Merger::func doubled(_: [Int]) -> [Int]", true),
            ("Effects::Merger::func total(_: [Int]) -> Int", true)
        ]
        for (key, valueShaped) in expected {
            #expect(try Self.function(key, in: run).valueShaped == valueShaped, "\(key)")
        }
    }

    @Test("the pattern-match operator ~= reads its left operand rather than assigning it")
    func patternMatch() throws {
        let run = try EffectHarness.run(source: """
        struct Status {
            static let validRange = 200...299
            let allowed: ClosedRange<Int>
            func accepts(_ code: Int) -> Bool { allowed ~= code }
            func isValid(_ code: Int) -> Bool { Self.validRange ~= code }
        }
        """)

        for key in ["Effects::Status::func accepts(_: Int) -> Bool", "Effects::Status::func isValid(_: Int) -> Bool"] {
            let facts = try Self.function(key, in: run)
            #expect(facts.valueShaped, "\(key)")
            #expect(facts.shape == .predicate, "\(key)")
        }
    }
}
