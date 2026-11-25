import Foundation
@testable import SwiftStatsCore
import Testing

/// Test-only production code (M7, design §8.3) on a small package with
/// hand-made index results: each production function counted out by the
/// first exclusion that applies (no USR by reason, public API of a
/// library-product target by target name, witness, `@objc`, entry point
/// of an executable target, deinitializer), the candidates split into
/// listed, production-referenced and unreferenced, the funnel's parts
/// summing, the items ordered by test referrers then key with their
/// references, and the left-out reasons in order.
@Suite("Test-only production code")
struct TestOnlyProductionTests {
    /// The harness's shorthand.
    private typealias Harness = TestOnlyHarness

    /// The funnel the harness's cases give.
    private static let funnel = "20 production functions = 3 without a USR (1 inactive #if branch, 1 top-level "
        + "code, 1 no reason stored) + 17 with one; 17 = 2 public API of a library product + 2 witnesses or "
        + "overrides + 1 @objc + 1 entry points + 1 deinitializers + 10 "
        + "candidates; 10 = 6 listed + 2 with a production reference + 2 with no reference at all (not listed: "
        + "fan-in 0 isn't dead, PRD §7.6a)"

    @Test("""
        each function is counted out by the first exclusion that applies, in order: no USR by reason, public API \
        of a library-product target only, a witness, @objc, a parameterless static main() of an executable target \
        only, a deinitializer; the rest are listed, production-referenced or unreferenced
        """)
    func exclusions() throws {
        let made = try TemporaryStore("TestOnly")
        defer { made.remove() }
        let snapshot = try Harness.stored(Harness.cases, in: made.store)

        let verdicts = try Harness.verdicts(snapshot)

        #expect(snapshot.executableTargets == ["Tool"])
        #expect(verdicts == [
            "Lib::func api() -> Int": .excluded(.publicAPI),
            "Lib::func conformingAPI() -> Int": .excluded(.publicAPI),
            "Lib::func conform() -> Int": .excluded(.witness),
            "Lib::func objcThing() -> Int": .excluded(.objc),
            "Lib::func objcWitness() -> Int": .excluded(.witness),
            "Lib::Fake::static func main()": .listed,
            "Lib::Box::deinit": .excluded(.deinitializer),
            "Lib::func onlyTests() -> Int": .listed,
            "Lib::func alsoTests() -> Int": .listed,
            "Lib::func fewTests() -> Int": .listed,
            "Lib::func used() -> Int": .production,
            "Lib::func crossUsed() -> Int": .production,
            "Lib::func unused() -> Int": .unreferenced,
            "Lib::func flagged() -> Int": .withoutUSR(.inactiveIfBranch),
            "Lib::func topLevel() -> Int": .withoutUSR(.topLevelCode),
            "Lib::func unjoined() -> Int": .withoutUSR(nil),
            "Inner::func helper() -> Int": .listed,
            "Tool::Tool::static func main()": .excluded(.entryPoint),
            "Tool::Tool::static func main(_: [String])": .listed,
            "Tool::Tool::func main()": .unreferenced
        ])
    }

    @Test("""
        the rule states the design's text and a funnel whose parts sum; items sort by test referrers, highest \
        first, then key, each a member scored by its test referrers with its references and no other payload
        """)
    func listed() throws {
        let made = try TemporaryStore("TestOnly")
        defer { made.remove() }
        let snapshot = try Harness.stored(Harness.cases, in: made.store)

        let signal = try Harness.signal(snapshot)

        #expect(signal.leftOut == nil)
        #expect(signal.rule == TestOnlyProduction.rule + "; " + Self.funnel)
        #expect(signal.candidates == 20)
        #expect(signal.items.map(\.subject) == [
            "Lib::func alsoTests() -> Int",
            "Lib::func onlyTests() -> Int",
            "Inner::func helper() -> Int",
            "Lib::Fake::static func main()",
            "Lib::func fewTests() -> Int",
            "Tool::Tool::static func main(_: [String])"
        ])
        #expect(signal.items.map(\.score) == [2, 2, 1, 1, 1, 1])
        #expect(signal.items.map(\.rank) == [1, 2, 3, 4, 5, 6])
        #expect(signal.items.map(\.member) == [true, true, true, true, true, true])
        let first = try #require(signal.items.first)
        #expect(first.file == "Sources/Lib/Lib.swift" && first.line == 13)
        #expect(first.references == SignalItem.References(
            tests: 2,
            testReferrers: ["LibTests::func test0()", "LibTests::func test1()"],
            module: "Lib"
        ))
        #expect(signal.items[2].references?.module == "Inner")
        #expect(signal.items.allSatisfy { $0.coverage == nil && $0.mutation == nil && $0.history == nil })
        let json = String(bytes: try ScanReportEncoder.encode(first), encoding: .utf8) ?? ""
        #expect(json.contains("\"references\""))
        #expect(json.contains("\"coverage\"") == false && json.contains("\"mutation\"") == false)
    }

    @Test("""
        the functions without a USR are counted by reason, and the funnel breaks them down in USRReason's order, \
        the stored reason missing last
        """)
    func withoutUSRByReason() {
        let verdicts: [TestOnlyProduction.Verdict] = [
            .withoutUSR(nil), .withoutUSR(.topLevelCode), .withoutUSR(.inactiveIfBranch), .listed,
            .withoutUSR(.inactiveIfBranch), .withoutUSR(.disagreement)
        ]

        let tally = TestOnlyProduction.Tally(verdicts)

        #expect(tally.withoutUSR == 5)
        #expect(tally.count(USRReason.inactiveIfBranch) == 2)
        #expect(tally.count(USRReason.topLevelCode) == 1)
        #expect(tally.count(USRReason.disagreement) == 1)
        #expect(tally.count(nil as USRReason?) == 1)
        #expect(tally.count(USRReason.pluginTarget) == 0)
        #expect(TestOnlyProduction.byReason(tally)
            == " (1 disagreement, 2 inactive #if branch, 1 top-level code, 1 no reason stored)")
        #expect(TestOnlyProduction.funnel(tally).hasPrefix("6 production functions = 5 without a USR (1 "
            + "disagreement, 2 inactive #if branch, 1 top-level code, 1 no reason stored) + 1 with one; "))
        #expect(TestOnlyProduction.byReason(TestOnlyProduction.Tally([.listed])).isEmpty)
    }

    @Test("""
        a left-out hidden coupling states the design's rule with the support and confidence limits set; dead but \
        tested states its own rule
        """)
    func leftOutRules() {
        let tuned = SignalThresholds(limits: ["hidden-coupling": ["support": 5, "confidence": 62.5]])

        #expect(HiddenCoupling.rule(thresholds: SignalThresholds()).hasPrefix("pairs of production families changed "
            + "together by at least 3 commits in the window (confidence at least 50%: support ÷ the less-changed "
            + "family's changes) with no static dependency: "))
        #expect(HiddenCoupling.rule(thresholds: tuned).hasPrefix("pairs of production families changed together by "
            + "at least 5 commits in the window (confidence at least 62.5%: "))
        #expect(HiddenCoupling.rule(thresholds: tuned).hasSuffix("; same file or module isn't a dependency; "
            + "candidates for an explicit abstraction"))
        #expect(DeadButTested.rule.hasPrefix("production functions no production code uses (outskirts with test "
            + "targets not counted as roots; "))
        #expect(DeadButTested.rule.hasSuffix("; types and properties aren't judged"))
    }

    @Test("an empty pool states the funnel with every part zero")
    func emptyFunnel() {
        #expect(TestOnlyProduction.funnel(TestOnlyProduction.Tally([])) == "0 production functions = 0 without a "
            + "USR + 0 with one; 0 = 0 public API of a library product + 0 witnesses or overrides + 0 @objc + 0 "
            + "entry points + 0 deinitializers + 0 candidates; 0 = 0 listed + 0 with a production reference + 0 with "
            + "no reference at all (not listed: fan-in 0 isn't dead, PRD §7.6a)")
    }

    @Test("""
        an entry point is a parameterless static main() by its key's last segment, its collision suffix and \
        effects aside, in an executable target
        """)
    func entryPoints() throws {
        let made = try TemporaryStore("TestOnly")
        defer { made.remove() }
        let snapshot = try Harness.stored(Harness.cases, in: made.store)
        let main = try #require(snapshot.functions.first { $0.key == "Tool::Tool::static func main()" })
        var suffixed = main
        suffixed.key = "Tool::Tool::static func main() @ Sources/Tool/Tool.swift:3"
        var throwing = main
        throwing.key = "Tool::Tool::static func main() async throws"
        var instance = main
        instance.key = "Tool::Tool::func main()"
        var renamed = main
        renamed.name = "start"
        var library = main
        library.module = "Lib"

        #expect(TestOnlyProduction.isEntryPoint(main, executables: ["Tool"]))
        #expect(TestOnlyProduction.isEntryPoint(suffixed, executables: ["Tool"]))
        #expect(TestOnlyProduction.isEntryPoint(throwing, executables: ["Tool"]))
        #expect(TestOnlyProduction.isEntryPoint(instance, executables: ["Tool"]) == false)
        #expect(TestOnlyProduction.isEntryPoint(renamed, executables: ["Tool"]) == false)
        #expect(TestOnlyProduction.isEntryPoint(library, executables: ["Tool"]) == false)
        #expect(TestOnlyProduction.isEntryPoint(main, executables: []) == false)
    }

    @Test("""
        the left-out reasons come in order: predates M7 (schema 8, or no index run), needs index with its state \
        and reason, then no index rows; a left-out signal states the rule alone, lists nothing and counts no \
        candidates
        """)
    func leftOut() throws {
        let made = try TemporaryStore("TestOnly")
        defer { made.remove() }
        let full = try Harness.stored(Harness.cases, in: made.store)
        let reload = { try Harness.signal(try made.store.load(id: full.id)) }
        let predates = "the snapshot predates M7"

        #expect(try reload().leftOut == nil)
        try SnapshotHarness.sqlite(made.url, "DELETE FROM indexScan")
        let noRows = try reload()
        #expect(noRows.leftOut == "the snapshot holds no index rows")
        #expect(noRows.rule == TestOnlyProduction.rule && noRows.items.isEmpty && noRows.candidates == 0)
        try SnapshotHarness.sqlite(made.url, "UPDATE collectorRun SET state = 'skipped', reason = 'not requested; "
            + "scan --index runs it' WHERE name = 'index'")
        #expect(try reload().leftOut == "needs index: skipped, not requested; scan --index runs it")
        try SnapshotHarness.sqlite(made.url, "UPDATE collectorRun SET state = 'failed', reason = NULL WHERE name = "
            + "'index'")
        #expect(try reload().leftOut == "needs index: failed")
        try SnapshotHarness.sqlite(made.url, "UPDATE snapshot SET reportSchemaVersion = 8")
        #expect(try reload().leftOut == predates)
        try SnapshotHarness.sqlite(made.url, "UPDATE snapshot SET reportSchemaVersion = 9")
        try SnapshotHarness.sqlite(made.url, "DELETE FROM collectorRun WHERE name = 'index'")
        #expect(try reload().leftOut == predates)
        #expect(SignalEngine.leftOut([.m7Snapshot], in: try made.store.load(id: full.id)) == predates)
    }

    @Test("""
        M7's three signals come last in report order with their titles and requirements; hidden coupling is \
        computed once its requirements hold, and dead but tested is left out for its requirements, then for the \
        mutation rows it reads, stating its own rule
        """)
    func names() throws {
        let made = try TemporaryStore("TestOnly")
        defer { made.remove() }
        let id = try made.store.save(try IndexStoreSamples.snapshot(commit: "c1"))
        let reasons = {
            let signals = SignalEngine.signals(
                of: SignalInputs(snapshot: try made.store.load(id: id)),
                thresholds: SignalThresholds()
            )
            return [SignalName.hiddenCoupling, .deadButTested].map { name in
                signals.first { $0.name == name }?.leftOut
            }
        }
        let rules = {
            let signals = SignalEngine.signals(
                of: SignalInputs(snapshot: try made.store.load(id: id)),
                thresholds: SignalThresholds()
            )
            return [SignalName.hiddenCoupling, .deadButTested].map { name in
                signals.first { $0.name == name }?.rule
            }
        }

        #expect(SignalName.reportOrder.suffix(4) == [
            .unevenCloneMutation, .hiddenCoupling, .deadButTested, .testOnlyProduction
        ])
        #expect(Set(SignalName.reportOrder) == Set(SignalName.allCases))
        #expect(SignalName.reportOrder.count == SignalName.allCases.count)
        #expect([SignalName.hiddenCoupling, .deadButTested, .testOnlyProduction].map(\.title) == [
            "Hidden coupling", "Dead but tested", "Test-only production code"
        ])
        #expect(SignalName.hiddenCoupling.requirements == [.history, .m7Snapshot, .collector(IndexAdapter.name)])
        #expect(SignalName.deadButTested.requirements == [
            .m7Snapshot, .collector(PeripheryAdapter.name), .collector(MutationAdapter.name)
        ])
        #expect(SignalName.testOnlyProduction.requirements == [.m7Snapshot, .collector(IndexAdapter.name)])
        let computed = HiddenCoupling.rule(thresholds: SignalThresholds()) + "; "
        #expect(try reasons() == [nil, "needs swiftmutator: skipped, not requested; scan --mutation runs it"])
        #expect(try rules()[0]?.hasPrefix(computed) == true)
        #expect(try rules()[1] == DeadButTested.rule)
        try SnapshotHarness.sqlite(made.url, "UPDATE collectorRun SET state = 'ran', reason = NULL WHERE name = "
            + "'swiftmutator'")
        #expect(try reasons() == [nil, "the snapshot holds no mutation rows"])
        #expect(try rules()[1] == DeadButTested.rule)
        try SnapshotHarness.sqlite(made.url, "UPDATE snapshot SET reportSchemaVersion = 8")
        #expect(try reasons() == ["the snapshot predates M7", "the snapshot predates M7"])
        #expect(SignalName(rawValue: "test-only-production") == .testOnlyProduction)
        #expect(SignalName(rawValue: "hidden-coupling") == .hiddenCoupling)
        #expect(SignalName(rawValue: "dead-but-tested") == .deadButTested)
    }
}
