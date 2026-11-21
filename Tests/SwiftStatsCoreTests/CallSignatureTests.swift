import SwiftParser
@testable import SwiftStatsCore
import SwiftSyntax
import Testing

/// Whether a call's labels fit a declaration's parameters (M5, tests per
/// public function), Swift's forward-scan rule approximated without types.
@Suite("Call signatures")
struct CallSignatureTests {
    /// A declaration with two defaulted parameters before a closure.
    private static let splitter = "func split(maxSplits: Int = 0, omitting: Bool = true, where test: (Int) -> Bool) {}"

    /// The signature of the declaration `source` holds.
    private static func signature(_ source: String) throws -> CallSignature {
        let item = try #require(Parser.parse(source: source).statements.first?.item)
        return try #require(CallSignature(of: Syntax(item)))
    }

    /// The call or labelled reference the expression `source` writes.
    private static func call(_ source: String) throws -> CallReference {
        let item = try #require(Parser.parse(source: source).statements.first?.item.as(ExprSyntax.self))
        if let call = item.as(FunctionCallExprSyntax.self) {
            return try #require(CallReferenceBuilder.call(call))
        }
        if let member = item.as(MemberAccessExprSyntax.self) {
            return try #require(CallReferenceBuilder.reference(member))
        }
        let reference = try #require(item.as(DeclReferenceExprSyntax.self))
        return try #require(CallReferenceBuilder.reference(reference))
    }

    /// Whether the call `call` fits the declaration `declaration`.
    private static func fits(_ declaration: String, _ call: String) throws -> Bool {
        try Self.call(call).fits(try signature(declaration))
    }

    @Test("overloads sharing a base name are told apart by their labels", arguments: [
        ("func split(separator: Int, maxSplits: Int = 0) {}", "x.split(separator: 1)", true),
        ("func split(maxSplits: Int = 0, whereSeparator: (Int) -> Bool) {}", "x.split(separator: 1)", false),
        ("func ends(with other: [Int]) {}", "x.ends(with: [1])", true),
        ("func ends(with other: [Int], by same: (Int, Int) -> Bool) {}", "x.ends(with: [1])", false),
        ("func suggest(for pair: Int, seed: Int = 0) {}", "T.suggest(forLifted: 1)", false)
    ])
    func overloadLabels(declaration: String, call: String, expected: Bool) throws {
        #expect(try Self.fits(declaration, call) == expected)
    }

    // Only a parameter with a default may be passed over, and arguments
    // keep the parameters' order.
    @Test("defaults may be passed over", arguments: [
        ("func bucket(accepted: Int = 0, rejected: Int = 0) {}", "bucket()", true),
        ("func bucket(accepted: Int = 0, rejected: Int = 0) {}", "bucket(rejected: 1)", true),
        ("func bucket(accepted: Int = 0, rejected: Int = 0) {}", "bucket(rejected: 1, accepted: 2)", false),
        ("func bucket(accepted: Int = 0, rejected: Int = 0) {}", "bucket(skipped: 1)", false),
        ("func max(count: Int, sortedBy: (Int, Int) -> Bool) {}", "x.max(count: 2)", false),
        ("func max(count: Int, sortedBy: (Int, Int) -> Bool) {}", "x.max(count: 2, sortedBy: <)", true),
        ("func sample(count: Int, using rng: Int = 0) {}", "x.sample(count: 2)", true)
    ])
    func defaults(declaration: String, call: String, expected: Bool) throws {
        #expect(try Self.fits(declaration, call) == expected)
    }

    // The unlabelled trailing closure fills the next parameter whatever its
    // label, passing over defaulted ones; labelled trailing closures are
    // labelled arguments.
    @Test("trailing closures fill parameters in order", arguments: [
        (splitter, "x.split { $0 == 0 }", true),
        (splitter, "x.split(maxSplits: 1) { _ in true }", true),
        ("func max(count: Int, sortedBy: (Int, Int) -> Bool) {}", "x.max(count: 2) { $0 < $1 }", true),
        ("func reductions(_ initial: Int, _ next: (Int, Int) -> Int) {}", "x.reductions(0) { $0 + $1 }", true),
        ("func reductions(_ initial: Int, _ next: (Int, Int) -> Int) {}", "x.reductions { $0 + $1 }", false),
        ("func run(body: () -> Void, done: () -> Void = {}) {}", "run {} done: {}", true),
        ("func run(body: () -> Void, done: () -> Void = {}) {}", "run {} other: {}", false)
    ])
    func trailingClosures(declaration: String, call: String, expected: Bool) throws {
        #expect(try Self.fits(declaration, call) == expected)
    }

    @Test("a variadic parameter takes any number of arguments, the first labelled as declared", arguments: [
        ("func sum(_ values: Int...) {}", "sum()", true),
        ("func sum(_ values: Int...) {}", "sum(1, 2, 3)", true),
        ("func sum(_ values: Int...) {}", "sum(values: 1)", false),
        ("func pack(values: Int..., tag: String) {}", "pack(values: 1, 2, tag: \"a\")", true),
        ("func pack(values: Int..., tag: String) {}", "pack(tag: \"a\")", true),
        ("func pack(values: Int..., tag: String) {}", "pack(values: 1, 2)", false),
        // The further arguments a variadic parameter takes are unlabelled.
        ("func pick(_ values: Int..., limit: Int = 0) {}", "pick(1, other: 2)", false),
        ("func pick(_ values: Int..., limit: Int = 0) {}", "pick(1, 2, limit: 3)", true)
    ])
    func variadics(declaration: String, call: String, expected: Bool) throws {
        #expect(try Self.fits(declaration, call) == expected)
    }

    @Test("a parameter declared `_` takes an unlabelled argument and no other", arguments: [
        ("func describe(_ value: Int) {}", "describe(1)", true),
        ("func describe(_ value: Int) {}", "describe(value: 1)", false),
        ("func describe(value: Int) {}", "describe(1)", false),
        ("func `default`(`in` scope: Int) {}", "x.default(in: 1)", true)
    ])
    func unlabelledParameters(declaration: String, call: String, expected: Bool) throws {
        #expect(try Self.fits(declaration, call) == expected)
    }

    // An initialiser's labels are fitted as a function's; an unapplied
    // reference names a declaration only with every label, `_` for an
    // unlabelled parameter.
    @Test("initialisers and labelled references", arguments: [
        ("init(items: [Int]) {}", "Bag(items: [])", true),
        ("init(items: [Int]) {}", "Bag.init(items: [])", true),
        ("init(items: [Int]) {}", "Bag()", false),
        ("func max(count: Int, sortedBy: (Int, Int) -> Bool) {}", "x.max(count:sortedBy:)", true),
        ("func max(count: Int, sortedBy: (Int, Int) -> Bool) {}", "x.max(count:)", false),
        ("func describe(_ value: Int, style: Int = 0) {}", "describe(_:style:)", true),
        ("init(items: [Int]) {}", "Bag.init(items:)", true),
        // A labelled reference names defaulted parameters too.
        ("func bucket(accepted: Int = 0, rejected: Int = 0) {}", "bucket(rejected:)", false),
        ("func bucket(accepted: Int = 0, rejected: Int = 0) {}", "bucket(accepted:rejected:)", true)
    ])
    func initialisersAndReferences(declaration: String, call: String, expected: Bool) throws {
        #expect(try Self.fits(declaration, call) == expected)
    }

    @Test("an operator has no signature: calls never write its labels")
    func operators() throws {
        let source = "static func + (lhs: Int, rhs: Int) -> Int { 0 }"
        let item = try #require(Parser.parse(source: source).statements.first)
        #expect(CallSignature(of: Syntax(item.item)) == nil)
    }
}
