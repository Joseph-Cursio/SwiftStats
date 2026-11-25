//
//  DeadButTestedNestingTests.swift
//  SwiftStatsCoreTests
//
//  Dead but tested over records nested in a production-dead one (M7,
//  design §8.2 as built, review C23), on the Index fixture's scan with
//  hand-made outskirts entries and mutants (`IndexHarness`): outskirts
//  lists only the outermost unused declaration and the mutation mapper
//  puts each mutant on the innermost record, so a dead subscript's
//  explicit accessors and a dead function's local function and local
//  type's method hold its mutants. Such a record is dead too, inheriting
//  the nearest covered ancestor's cover; only the outermost is judged and
//  listed, with the mutants of all of them; the others count as nested in
//  it. Serialized: each test scans a copy of the fixture on a thread of
//  its own, as the index collector's tests do.
//

@testable import SwiftStatsCore
import Testing

/// Dead but tested over nested records, on the Index fixture's scan.
@Suite("Dead but tested over nested records", .serialized)
struct DeadButTestedNestingTests {
    /// The harness's shorthand.
    private typealias Harness = IndexHarness

    /// The subscript with explicit `get` and `set` accessors.
    private static let subscriptKey = "IndexCore::Storage::subscript(slot: Int) -> Int"
    /// Its getter.
    private static let getter = subscriptKey + " / { get }"
    /// Its setter.
    private static let setter = subscriptKey + " / { set }"
    /// `layout(_:)`, a function with a local function and a local type.
    private static let layout = "IndexCore::func layout(_: Int) -> Int"
    /// Its local function.
    private static let padded = layout + " / func padded(_: Int) -> Int"
    /// Its local type's method.
    private static let area = layout + " / Square::func area() -> Int"

    /// The rule with the fixture's nine production-dead functions and the
    /// three of the added entry's nest, one listed and two nested, the rest
    /// with no mutant; the declarations funnel with the added function
    /// entry.
    private static let nestRule = DeadButTested.rule + "; "
        + Harness.functionsFunnel(listed: 1, partial: 0, unrun: [0, 0, 9, 0], dead: 12, nested: 2)
        + "; 9 unused production declarations = 6 function entries matching a record + 0 function entries "
        + "matching no record + 1 type entries + 1 extension entries + 1 property entries with accessor records + "
        + "0 others (parameters, imports, enum cases, stored properties, typealiases); 10 = the distinct records F, "
        + "T, E and V cover"

    @Test("""
        a production-dead subscript with explicit get and set is listed for its getter's killed mutant, its \
        accessors dead with it and counted as nested in it, its mutation results those of all three
        """)
    func deadSubscript() async throws {
        try await Harness.scan(indexed: true) { scanned in
            let made = try TemporaryStore("DeadButTestedSubscript")
            defer { made.remove() }
            let covered = try Harness.covering(
                Self.subscriptKey,
                run: .production,
                ordinal: 20,
                kind: "function.subscript",
                in: scanned
            )
            let results = Harness.Results(mutants: [
                Self.getter: [Harness.killed(by: ["T.slot()"])],
                Self.setter: Harness.planted(1, .notCovered)
            ])
            let snapshot = try Harness.stored(Harness.with(results, on: covered), in: made.store)

            let signal = try Harness.signal(.deadButTested, of: snapshot)
            let verdicts = try Harness.verdicts(snapshot)

            #expect(signal.rule == Self.nestRule)
            #expect(signal.items.map(\.subject) == [Self.subscriptKey])
            let item = try #require(signal.items.first)
            #expect(item.score == 1)
            #expect(item.dead?.kind == "function.subscript" && item.dead?.via == .usr)
            #expect(item.dead?.deadWithTestsAsRoots == false)
            #expect(item.mutation?.counts.killed == 1 && item.mutation?.counts.notCovered == 1)
            #expect(item.mutation?.firstKillingTests == ["T.slot()"] && item.mutation?.coverage == .enabled)
            #expect(verdicts[Self.subscriptKey] == .listed)
            #expect(verdicts[Self.getter] == .nested && verdicts[Self.setter] == .nested)
        }
    }

    @Test("""
        a production-dead function whose mutants all sit in its local function and its local type's method is \
        listed, scored by all of them; a nested record outskirts covers too is still nested in the outermost; \
        with only the local function covered it is listed alone, dead with tests as roots when the roots run \
        covers the function holding it
        """)
    func deadFunctionWithLocals() async throws {
        try await Harness.scan(indexed: true) { scanned in
            let made = try TemporaryStore("DeadButTestedLocals")
            defer { made.remove() }
            let results = Harness.Results(mutants: [
                Self.padded: [Harness.killed(by: ["T.a()"]), Harness.killed(by: ["T.b()"])],
                Self.area: Harness.planted(1, .survived)
            ])
            let cover = { (key: String, run: DeadCodeRun, ordinal: Int, onto: ScannedSnapshot) in
                try Harness.covering(key, run: run, ordinal: ordinal, kind: "function.free", in: onto)
            }
            let both = try cover(Self.padded, .production, 21, try cover(Self.layout, .production, 20, scanned))
            let snapshot = try Harness.stored(Harness.with(results, on: both), in: made.store)

            let signal = try Harness.signal(.deadButTested, of: snapshot)
            let verdicts = try Harness.verdicts(snapshot)

            #expect(signal.items.map(\.subject) == [Self.layout])
            #expect(signal.items.map(\.score) == [3])
            #expect(signal.items.first?.mutation?.killingTests == 2)
            #expect(signal.items.first?.dead?.name == Self.layout)
            #expect(signal.rule.contains(
                Harness.functionsFunnel(listed: 1, partial: 0, unrun: [0, 0, 9, 0], dead: 12, nested: 2)
            ))
            #expect(verdicts[Self.padded] == .nested && verdicts[Self.area] == .nested)

            let roots = try cover(Self.layout, .roots, 20, try cover(Self.padded, .production, 20, scanned))
            let alone = try Harness.stored(Harness.with(results, on: roots), in: made.store)
            let single = try Harness.signal(.deadButTested, of: alone)
            #expect(single.items.map(\.subject) == [Self.padded] && single.items.map(\.score) == [2])
            #expect(single.items.first?.dead?.deadWithTestsAsRoots == true)
            #expect(try Harness.verdicts(alone)[Self.area] == .used)
        }
    }
}
