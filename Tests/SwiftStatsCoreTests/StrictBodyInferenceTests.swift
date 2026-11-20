//
//  StrictBodyInferenceTests.swift
//  SwiftStatsCoreTests
//
//  Strict body inference (PRD §7.10) on the Effects fixture: convergence
//  and the pass limit, file-order independence and the collector's sort,
//  declared tiers on shared signatures, a package callee's body deciding
//  its tier where its name would guess another (cycles and recursion too),
//  `via`, anchors and the inference states.
//

import Foundation
@testable import SwiftStatsCore
import Testing

@Suite("Strict body inference")
struct StrictBodyInferenceTests {
    @Test("body inference converges on the fixture in four passes, the last confirming")
    func convergence() throws {
        let run = try EffectHarness.runFixture()

        // syncAll → refresh → updateTotals → upsert: pass 1 infers
        // updateTotals() from `upsert`, pass 2 gives refresh its tier, pass 3
        // gives syncAll its tier, pass 4 changes nothing.
        #expect(run.summary.passes == 4)
        #expect(run.summary.revision == EffectInferenceRevision.pinned)
    }

    @Test("a pass limit too low to converge fails the collector")
    func passLimit() throws {
        let files = try EffectHarness.fixtureFiles()
        let records = EffectHarness.records(of: files)

        #expect(throws: EffectInferenceError.didNotConverge(maxPasses: 1)) {
            try EffectCollector.run(files: files, records: records, maxPasses: 1)
        }
        #expect(throws: EffectInferenceError.didNotConverge(maxPasses: 3)) {
            try EffectCollector.run(files: files, records: records, maxPasses: 3)
        }
        #expect(EffectInferenceError.didNotConverge(maxPasses: 3).description
            == "body inference did not converge in 3 passes")
    }

    @Test("inference over the files in reverse order changes no tier, depth, anchor, via or fact")
    func fileOrder() throws {
        let files = try EffectHarness.fixtureFiles()
        let forward = StrictBodyInference(trees: files.map(\.tree))
        let backward = StrictBodyInference(trees: files.reversed().map(\.tree))
        let forwardMap = try forward.converge(maxPasses: StrictBodyInference.defaultMaxPasses)
        let backwardMap = try backward.converge(maxPasses: StrictBodyInference.defaultMaxPasses)

        #expect(forwardMap.passes == backwardMap.passes)
        #expect(forward.explain(map: forwardMap.map).results == backward.explain(map: backwardMap.map).results)
        // The unsorted entry, so the order really is reversed all the way to each fact.
        let records = EffectHarness.records(of: files)
        let maxPasses = StrictBodyInference.defaultMaxPasses
        let inOrder = try EffectCollector.run(universe: files, records: records, maxPasses: maxPasses)
        let reversed = try EffectCollector.run(universe: files.reversed(), records: records, maxPasses: maxPasses)
        #expect(reversed.facts == inOrder.facts)
        #expect(reversed.summary == inOrder.summary)
        #expect(inOrder.facts.values.contains { $0.function?.inferred?.via.isEmpty == false })
    }

    @Test("the collector sorts its files, so which of two same-named types refutes first doesn't depend on input order")
    func collectorSorts() throws {
        let first = """
        struct Clock {
            let now: Double
            init() { now = Double.random(in: 0...1) }
        }
        func reading() -> Double { Clock().now }
        """
        let second = """
        import Foundation
        struct Clock {
            let now: Double
            init() { now = Date().timeIntervalSince1970 }
        }
        """
        let files = [
            EffectHarness.parsed(first, path: "Sources/Effects/A.swift"),
            EffectHarness.parsed(second, path: "Sources/Effects/B.swift")
        ]
        let records = EffectHarness.records(of: files)
        let sorted = try EffectCollector.run(files: files, records: records)
        let reversed = try EffectCollector.run(files: files.reversed(), records: records)
        let unsorted = try EffectCollector.run(
            universe: files.reversed(),
            records: records,
            maxPasses: StrictBodyInference.defaultMaxPasses
        )

        #expect(reversed.facts == sorted.facts)
        #expect(reversed.summary == sorted.summary)
        // Taken in the order given, the other declaration's witness comes first.
        #expect(unsorted.summary.refutedTypes != sorted.summary.refutedTypes)
    }

    @Test("an annotated requirement with several bodied conformers gives callers its tier; two annotations withdraw it")
    func declaredSharedSignature() throws {
        let run = try EffectHarness.run(source: """
        protocol Persisting {
            /// @lint.effect idempotent
            func persist()
        }
        struct Draft: Persisting {
            let log: Log
            func persist() { log.upsert(1) }
        }
        struct Note: Persisting {
            let log: Log
            func persist() { log.insert(1) }
        }
        struct Store {
            /// @lint.effect idempotent
            func save() {}
        }
        struct Cache {
            /// @lint.effect idempotent
            func save() {}
        }
        func flush(_ draft: Draft) { draft.persist() }
        func keep(_ cache: Cache) { cache.save() }
        """)
        let flush = try EffectHarness.inferred("Effects::func flush(_: Draft)", in: run)

        #expect(flush == EffectFacts.Inferred(
            tier: .idempotent,
            depth: 1,
            anchor: .declared,
            via: ["calls `persist()`"]
        ))
        // Each conformer's own body is still not inferred.
        #expect(try EffectHarness.facts("Effects::Draft::func persist()", in: run).function?.inference == .ambiguous)
        // Two annotations of one signature are a collision even when they
        // agree, as in SwiftEffectInference's own resolver: no tier, no guess.
        let keep = try EffectHarness.facts("Effects::func keep(_: Cache)", in: run)
        #expect(keep.function?.inference == .unique)
        #expect(keep.function?.inferred == nil)
    }

    @Test("a callee's own body, never its name, gives a call to it a tier")
    func calleeBodyWins() throws {
        let run = try EffectHarness.runFixture()
        let updateTotals = try EffectHarness.inferred("Effects::Ledger::func updateTotals()", in: run)
        let refresh = try EffectHarness.inferred("Effects::Ledger::func refresh()", in: run)

        #expect(updateTotals == EffectFacts.Inferred(
            tier: .idempotent,
            depth: 1,
            anchor: .heuristic,
            via: ["from the callee name `upsert`"]
        ))
        #expect(refresh == EffectFacts.Inferred(
            tier: .idempotent,
            depth: 2,
            anchor: .heuristic,
            via: ["calls `updateTotals()`"]
        ))
    }

    @Test("a call cycle through a name the heuristic matches converges on its bodies' tier")
    func heuristicNamedCycle() throws {
        // `logger` is outside the package, so `logger.info` takes the
        // logger-shaped receiver heuristic.
        let run = try EffectHarness.run(source: """
        func insertNode(_ value: Int) { logger.info("insert"); walk(value - 1) }
        func walk(_ value: Int) { logger.info("walk"); if value > 0 { insertNode(value) } }
        func appendLeaf(_ value: Int) { logger.info("append"); descend(value) }
        func descend(_ value: Int) { logger.info("descend"); climb(value - 1) }
        func climb(_ value: Int) { logger.info("climb"); if value > 0 { appendLeaf(value) } }
        """)
        let keys = [
            "Effects::func insertNode(_: Int)",
            "Effects::func walk(_: Int)",
            "Effects::func appendLeaf(_: Int)",
            "Effects::func descend(_: Int)",
            "Effects::func climb(_: Int)"
        ]

        // A name guess seeding the cycle would swap between its members
        // every pass and never settle.
        #expect(run.summary.passes <= 3)
        for key in keys {
            let inferred = try EffectHarness.inferred(key, in: run)
            #expect(inferred.tier == .observational, "\(key)")
            #expect(inferred.via.contains { $0.hasPrefix("from logger-shaped receiver") }, "\(key)")
        }
        // With the package's own `Logger`, whose `info` does nothing, the
        // loop still settles. A signature can't tell `logger.info` from an
        // external logger's, so the receiver-qualified call keeps its guess,
        // while the unqualified calls in the cycle still guess nothing.
        let stubbed = try EffectHarness.run(source: """
        struct Logger { func info(_ text: String) {} }
        let logger = Logger()
        func insertNode(_ value: Int) { logger.info("insert"); walk(value - 1) }
        func walk(_ value: Int) { logger.info("walk"); if value > 0 { insertNode(value) } }
        """)
        #expect(stubbed.summary.passes <= 3)
        for key in ["Effects::func insertNode(_: Int)", "Effects::func walk(_: Int)"] {
            let function = try EffectHarness.facts(key, in: stubbed).function
            #expect(function?.inference == .unique, "\(key)")
            #expect(function?.inferred?.tier == .observational, "\(key)")
        }
    }

    @Test("a recursive function, or a cycle of lexicon names, takes its bodies' tier, not its names'")
    func recursiveLexiconName() throws {
        let run = try EffectHarness.run(source: """
        func updateTree(_ depth: Int) { logger.info("visit"); if depth > 0 { updateTree(depth - 1) } }
        func refreshTree(_ depth: Int) { logger.info("visit"); if depth > 0 { refreshTree(depth - 1) } }
        func updatePing(_ depth: Int) { logger.info("ping"); if depth > 0 { insertPong(depth - 1) } }
        func insertPong(_ depth: Int) { logger.info("pong"); if depth > 0 { updatePing(depth - 1) } }
        """)
        let update = try EffectHarness.inferred("Effects::func updateTree(_: Int)", in: run)
        let refresh = try EffectHarness.inferred("Effects::func refreshTree(_: Int)", in: run)

        // The two bodies differ only in the name, which is in the
        // non-idempotent lexicon for one of them.
        #expect(update.tier == .observational)
        #expect(update == refresh.renamingVia(from: "refreshTree", to: "updateTree"))
        #expect(update.via.contains("from logger-shaped receiver `logger.info`"))
        for key in ["Effects::func updatePing(_: Int)", "Effects::func insertPong(_: Int)"] {
            #expect(try EffectHarness.inferred(key, in: run).tier == .observational, "\(key)")
        }
    }

    @Test("a package function whose body gives no tier is never guessed from its name")
    func bodiedCalleeWithoutTier() throws {
        let run = try EffectHarness.run(source: """
        func insertRow(_ value: Int) {}
        func stage(_ value: Int) { insertRow(value) }
        """)

        #expect(try EffectHarness.facts("Effects::func stage(_: Int)", in: run).function?.inferred == nil)
    }

    @Test("a tier two hops from its anchor names the callee it took it from")
    func twoHops() throws {
        let syncAll = try EffectHarness.inferred("Effects::Ledger::func syncAll()", in: try EffectHarness.runFixture())

        #expect(syncAll == EffectFacts.Inferred(
            tier: .idempotent,
            depth: 3,
            anchor: .heuristic,
            via: ["calls `refresh()`"]
        ))
    }

    @Test("a callee annotated elsewhere gives a declared anchor")
    func declaredAnchor() throws {
        let run = try EffectHarness.runFixture()
        let flush = try EffectHarness.inferred("Effects::Ledger::func flush(_: Draft)", in: run)

        #expect(flush == EffectFacts.Inferred(
            tier: .idempotent,
            depth: 1,
            anchor: .declared,
            via: ["calls `persist()`"]
        ))
    }

    @Test("#if twins are ambiguous, an annotated namesake shadows, an annotation is its own")
    func inferenceStates() throws {
        let run = try EffectHarness.runFixture()
        let twinKeys = [
            "Effects::func platformName() -> String #if os(macOS)",
            "Effects::func platformName() -> String #if !(os(macOS))"
        ]
        let twins = try twinKeys.map { key in
            try EffectHarness.facts(key, in: run).function
        }
        let persist = try EffectHarness.facts("Effects::Draft::func persist()", in: run).function
        let reset = try EffectHarness.facts("Effects::func resetCounter(_: Counter)", in: run).function

        #expect(twins.map { $0?.inference } == [.ambiguous, .ambiguous])
        #expect(twins.allSatisfy { $0?.inferred == nil })
        // Its body calls `upsert`, but the protocol requirement declares the signature.
        #expect(persist?.inference == .shadowed)
        #expect(persist?.inferred == nil)
        #expect(reset?.inference == .annotated)
        #expect(reset?.inferred == nil)
    }

    @Test("a function declared inside a closure, which inference never visits, has no inference state")
    func closureLocalFunction() throws {
        let run = try EffectHarness.run(source: """
        func outer() -> Int {
            let make = { () -> Int in
                func inner() -> Int { 1 }
                return inner()
            }
            return make()
        }
        """)

        #expect(try EffectHarness.facts("Effects::func outer() -> Int", in: run).function?.inference == .unique)
        let inner = try EffectHarness.facts("Effects::func outer() -> Int / func inner() -> Int", in: run)
        #expect(inner.function?.inference == nil)
    }
}

private extension EffectFacts.Inferred {
    /// This tier with `old` replaced by `new` in each reason.
    func renamingVia(from old: String, to new: String) -> Self {
        Self(
            tier: tier,
            depth: depth,
            anchor: anchor,
            via: via.map { $0.replacingOccurrences(of: old, with: new) }
        )
    }
}
