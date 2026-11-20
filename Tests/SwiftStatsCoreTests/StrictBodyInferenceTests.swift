//
//  StrictBodyInferenceTests.swift
//  SwiftStatsCoreTests
//
//  Strict body inference (PRD §7.10) on the Effects fixture: convergence
//  and the pass limit, file-order independence and the collector's sort,
//  declared tiers on shared signatures, a callee's body beating a name
//  guess, `via`, anchors and the inference states.
//

@testable import SwiftStatsCore
import Testing

@Suite("Strict body inference")
struct StrictBodyInferenceTests {
    @Test("body inference converges on the fixture in four passes, the last confirming")
    func convergence() throws {
        let run = try EffectHarness.runFixture()

        // syncAll → refresh → updateTotals → upsert: pass 1 guesses
        // updateTotals() from its name, pass 2 corrects refresh, pass 3
        // corrects syncAll, pass 4 changes nothing.
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

    @Test("a callee's own body beats the guess its name gave on the first pass")
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
