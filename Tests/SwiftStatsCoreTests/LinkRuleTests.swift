@testable import SwiftStatsCore
import Testing

/// Tests per public function's tightened link rules (M5): calls whose
/// labels fit, member reads, qualified type names, test helpers and
/// skipped tests, each on a small package whose counted test target ran
/// every public function.
@Suite("Link rules")
struct LinkRuleTests {
    /// `--skip` regexes and the count of `compute()` they leave: a test the
    /// coverage run's regexes match counts for nothing.
    private static let skipCases: [([String], Int)] = [
        ([String](), 6),
        (["MeasuredSuite"], 5),
        (["LibTests.ComputeXCTests/testMeasured"], 5),
        (["^LibTests\\.ComputeXCTests/testCompute$"], 5),
        (["^LibTests\\.fastCompute\\(\\)/SkipTests\\.swift:4:2$"], 5),
        (["SkipTests\\.swift:4:1"], 6),
        (["^LibTests\\.MeasuredSuite/slowCompute\\(_:\\)/SkipTests\\.swift:7:6$"], 5),
        (["^LibTests\\.TaggedSuite/Deep/deepCompute\\(\\)/SkipTests\\.swift:17:21$"], 5),
        (["slowCompute\\(_:\\)"], 5),
        (["Measured"], 4),
        (["SkipTests\\.swift:"], 2),
        (["fastCompute", "testCompute$"], 4),
        // `deepCompute` and `farCompute`, whose IDs pass through the
        // `@Suite` type's; a type without `@Suite` is never matched alone.
        (["^LibTests\\.TaggedSuite$"], 4),
        (["^LibTests\\.MeasuredSuite$"], 6),
        (["tag:slow"], 4),
        (["tag:fast"], 6),
        (["id:^LibTests\\.TaggedSuite$"], 4),
        (["`fastCompute`"], 5),
        (["("], 6)
    ]

    @Test("""
        a function counts the calls whose labels fit it, defaults passed over, the trailing closure filling the \
        next parameter, variadic and unlabelled parameters matched, and labelled references; a protocol extension's \
        accessor counts member reads; tuple labels, locals and local functions named like a member, and a free \
        function's name called on a value, count for nothing
        """)
    func overloads() throws {
        let counts = try LinkRuleHarness.counts(LinkRuleSources.overloads)

        #expect(counts == [
            // `separators`, and `closures`: types aren't read, so `splitUp { … }`'s
            // closure may fill `separator:`, as for any overload with a
            // first parameter that has no default.
            "Lib::Sequence::func splitUp(separator: Int, maxSplits: Int) -> Int": 2,
            // `closures` and `closuresWithMax`, not `separators`.
            "Lib::Sequence::func splitUp(maxSplits: Int, whereSeparator: (Element) -> Bool) -> Int": 2,
            // `leastCount` alone: `leastSorted` has a trailing closure,
            // `leastTuple` a tuple label, `leastLocal` a local, and
            // `leastLocalFunction` calls its local function bare.
            "Lib::Sequence::func least(count: Int) -> Int": 1,
            // `leastSorted` and the labelled reference in `leastReference`.
            "Lib::Sequence::func least(count: Int, sortedBy: (Element, Element) -> Bool) -> Int": 2,
            "Lib::Sequence::var firstOrZero: Int { get }": 1,
            "Lib::func total(_: Int...) -> Int": 1,
            // `totalsOf`, not `totalsOnValue`'s `box.total(of:)`.
            "Lib::func total(of: [Int]) -> Int": 1,
            "Lib::func label(_: Int) -> String": 1,
            // Qualified by the module, `Lib.label(value:)`.
            "Lib::func label(value: Int) -> String": 1
        ])
    }

    @Test("""
        a concrete type's initialiser counts its calls in every form with fitting labels, an accessor member reads, \
        key paths and calls of the closure it holds but no bare local, a member function no local named like it; a \
        qualified type must be qualified by a suffix of the module and parents, an unqualified one names any type \
        of that simple name; a free variable counts bare and module-qualified reads
        """)
    func members() throws {
        let counts = try LinkRuleHarness.counts(LinkRuleSources.members)

        #expect(counts == [
            // `sizes`, `qualified` (`Lib.Shelf`), `bareArea`, `keyPaths`,
            // `roots`, `localRoot` and `makers`.
            "Lib::Shelf::init(size: Int)": 7,
            // `Shelf.init(width:)` passes over the default, and the
            // implicit `.init(width:height:)` builds the annotated type.
            "Lib::Shelf::init(width: Int, height: Int)": 2,
            // `areas` and `keyPaths`, not `bareArea`'s local.
            "Lib::Shelf::var area: Int { get }": 2,
            "Lib::Shelf::static var standard: Shelf { get }": 1,
            // `roots`, not `localRoot`'s local.
            "Lib::Shelf::func root(forScanOf: String) -> String": 1,
            // `makers` calls the closure it holds.
            "Lib::Shelf::var maker: () -> Int { get }": 1,
            // `harvested` and `harvestedRun`, not `commanded`'s
            // `Command.Corpus()`.
            "Lib::Harvester.Corpus::init()": 2,
            "Lib::Command.Corpus::init()": 1,
            // `commanded`, and `unqualifiedCorpus`, which writes `Corpus`
            // alone; not `harvestedRun`, whose `Corpus` is `Harvester`'s.
            "Lib::Command.Corpus::func run() -> Int": 2,
            // A free variable is read bare, or qualified by its module.
            "Lib::var counter: Int { get }": 2
        ])
    }

    @Test("""
        a test counts what the helpers of its target that it calls write, transitively and through a cycle, each \
        reached only by calls whose labels fit it, initialisers included and qualified only by their type's path, \
        where it is visible: a file-scoped one in its file, a member called bare from its own type or a subclass; \
        never a function nested in another test, nor another test target's helper
        """)
    func helpers() throws {
        let counts = try LinkRuleHarness.counts(LinkRuleSources.helpers)

        #expect(counts == [
            // `starts`, through `startEngine` and `warmUp`; no call fits
            // `Rig(label:)`.
            "Lib::Engine::func start() -> Int": 1,
            // `starts` and `pings`, through the `ping` / `pong(_:)` cycle,
            // and `testRevs`, through its base class's `revUp()`.
            "Lib::Engine::func stop() -> Int": 3,
            // `rigs`, through `Rig(engine:)`, `benches`, through its own
            // type's `spin()`, and `hosts`, through the function nested in
            // it. No call fits `pong(label:)`; `otherRigs`' `Other.Rig` is
            // no `Rig` of the target; `starts` can't see the other file's
            // private `startEngine()`, nor `stands` `Bench`'s `spin()`, nor
            // `borrows` the function nested in `hosts`; `OtherTests`'
            // `warmUp(_:)` is another target's.
            "Lib::Engine::func idle() -> Int": 3
        ])
    }

    // A test the coverage run's `--skip` regexes match counts for nothing:
    // an XCTest test by `<module>.<class>/<method>`, a Swift Testing one by
    // `<module>.<suite>/<function>(<labels>)/<file>:<line>:<column>`, where
    // the location is the `@Test` attribute's name, or by the ID of an
    // enclosing `@Suite` type, a regex found anywhere; `tag:` matches Swift
    // Testing tags, `id:` and backticks are dropped; a regex that doesn't
    // compile skips nothing.
    @Test("skipped tests count for nothing", arguments: skipCases)
    func skipped(patterns: [String], expected: Int) throws {
        let counts = try LinkRuleHarness.counts(LinkRuleSources.skips, skipPatterns: patterns)

        #expect(counts == ["Lib::func compute() -> Int": expected])
    }

    @Test("""
        a helper is reached through `Self` only from its own type, through a type or typealias only of that type, \
        never through a type outside the target, and no free helper through a qualified call; a test-target \
        extension of a production type calls its members bare and delegates to its initialiser; a nested type \
        calls its enclosing type's static helper bare
        """)
    func receivers() throws {
        let counts = try LinkRuleHarness.counts(LinkRuleSources.receivers)

        #expect(counts == [
            // `alpha` and `beta` each reach only their own type's helper,
            // and neither reaches the free `detect(in:)`.
            "Lib::AlphaDetector::static func detect(in: String) -> Int": 1,
            "Lib::BetaDetector::static func detect(in: String) -> Int": 1,
            // `recordsGamma` and `recordsAlias`; `Issue.record` reaches no
            // helper.
            "Lib::Gamma::init()": 2,
            "Lib::Gamma::func scan(_: String) -> Int": 2,
            // `origins` through `self.init(x:y:)`, and `doubles`.
            "Lib::Point::init(x: Int, y: Int)": 2,
            // A bare read in the extension may be a local, so it counts
            // for nothing.
            "Lib::Point::var area: Int { get }": 0,
            "Lib::Point::func grow(by: Int) -> Int": 1,
            "Lib::Shared::static func run() -> Int": 1
        ])
    }

    @Test("""
        a module is written by its C99 name, in a qualified call, read or type, and in the identifiers --skip \
        regexes match
        """)
    func moduleNames() throws {
        let counts = try LinkRuleHarness.counts(LinkRuleSources.moduleNames, skipPatterns: [], ran: ["my-lib-tests"])
        let skipped = try LinkRuleHarness.counts(
            LinkRuleSources.moduleNames,
            skipPatterns: ["^my_lib_tests\\.qualifiedCall\\(\\)/"],
            ran: ["my-lib-tests"]
        )

        let expected = [
            "my-lib::func compute() -> Int": 1,
            "my-lib::var limit: Int { get }": 1,
            "my-lib::Gauge::init()": 1,
            "my-lib::Gauge::func read() -> Int": 1
        ]
        #expect(counts == expected)
        #expect(skipped == expected.merging(["my-lib::func compute() -> Int": 0]) { _, new in new })
    }
}
