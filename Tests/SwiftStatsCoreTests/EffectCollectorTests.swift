//
//  EffectCollectorTests.swift
//  SwiftStatsCoreTests
//
//  The side-effect collector (PRD §7.10) on the Effects fixture: the pin,
//  each tier source, the conflict formula, purity and where each kind's
//  facts land. Expected values are worked out by hand from the fixture's
//  comments.
//

import Foundation
@testable import SwiftStatsCore
import Testing

@Suite("Effect collector")
struct EffectCollectorTests {
    /// The SwiftStats checkout these tests were built from.
    private static let checkout = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    @Test("the pinned revision is the one Package.resolved records")
    func pin() throws {
        let lockfile = try #require(PackageResolvedReader.lockfile(root: Self.checkout).lockfile)
        let pin = try #require(lockfile.pins.first { $0.identity == "swifteffectinference" })

        #expect(pin.revision == EffectInferenceRevision.pinned)
        #expect(pin.location == "https://github.com/Joseph-Cursio/SwiftEffectInference.git")
        #expect(EffectInferenceRevision.identity == "git:" + EffectInferenceRevision.pinned)
    }

    @Test("the source is the first of conflicting, unknown, declared, purity, body-inferred, none")
    func sources() throws {
        let run = try EffectHarness.runFixture()
        let expected: [String: (source: EffectFacts.Source, tier: EffectFacts.Tier?)] = [
            "Effects::func enqueueJob(_: JobQueue)": (.conflicting, nil),
            "Effects::func mystery() -> Int": (.unknown, nil),
            "Effects::func resetCounter(_: Counter)": (.declared, .idempotent),
            "Effects::func ticks() -> Int": (.purity, .pure),
            "Effects::Ledger::func record(_: Int)": (.bodyInferred, .nonIdempotent),
            "Effects::Ledger::func stamp() -> Date": (.unresolved, nil)
        ]
        for (key, (source, tier)) in expected {
            let facts = try EffectHarness.facts(key, in: run)
            #expect(facts.source == source, "\(key)")
            #expect(facts.tier == tier, "\(key)")
        }
        // A conflicting declaration is still body-inferred; the tier just isn't used.
        #expect(try EffectHarness.inferred("Effects::func enqueueJob(_: JobQueue)", in: run).tier == .nonIdempotent)
        #expect(try EffectHarness.facts("Effects::func mystery() -> Int", in: run).declaration?.unknown == true)
        let ticks = try EffectHarness.facts("Effects::func ticks() -> Int", in: run)
        #expect(ticks.declaration?.clockDeterministic == true)
        let chargeKey = "Effects::func charge(requestID: String, amount: Int, gateway: Gateway)"
        let charge = try EffectHarness.facts(chargeKey, in: run)
        #expect(charge.declaration == EffectFacts.Declaration(
            declared: .externallyIdempotent,
            keyParameter: "requestID",
            unknown: false,
            clockDeterministic: false
        ))
    }

    @Test("a conflict is an attribute and a doc comment that disagree; the first attribute wins")
    func conflictFormula() throws {
        let fixture = try EffectHarness.runFixture()
        let run = try EffectHarness.run(source: """
        @Pure @NonIdempotent
        func first() -> Int { 1 }
        """)
        let conflicting = try EffectHarness.facts("Effects::func enqueueJob(_: JobQueue)", in: fixture)
        let agreeing = try EffectHarness.facts("Effects::func resetCounter(_: Counter)", in: fixture)
        let twoAttributes = try EffectHarness.facts("Effects::func first() -> Int", in: run)

        #expect(conflicting.declaration?.declared == nil)
        #expect(conflicting.source == .conflicting)
        #expect(agreeing.declaration?.declared == .idempotent)
        #expect(agreeing.source == .declared)
        #expect(twoAttributes.declaration?.declared == .pure)
        #expect(twoAttributes.source == .declared)
    }

    @Test("a throwing function without `try` is pure_but_partial; one with `try` is refuted")
    func partialPurity() throws {
        let run = try EffectHarness.runFixture()
        let parse = try EffectHarness.facts("Effects::func parse(_: String) throws -> Int", in: run)
        let parseTwice = try EffectHarness.facts("Effects::func parseTwice(_: String) throws -> Int", in: run)

        #expect(parse.purity == .pureButPartial)
        #expect(parse.refutation == nil)
        #expect(parse.tier == nil)
        #expect(parseTwice.purity == .refuted)
        #expect(parseTwice.refutation == EffectFacts.Refutation(
            case: "propagatedTry",
            root: "propagatedTry",
            detail: "propagates an error out of a callee (`try`)"
        ))
    }

    @Test("a refutation keeps its outer case and its root cause; refuted types are listed")
    func refutationChains() throws {
        let run = try EffectHarness.runFixture()
        let receipt = try EffectHarness.facts("Effects::func makeReceipt() -> Receipt", in: run).refutation
        let stamped = try EffectHarness.facts("Effects::func stamped(at: Date) -> Date", in: run).refutation

        let construction = "constructs `Receipt`, and the default value of its stored property `issued` "
            + "references the nondeterminism marker `Date`"
        #expect(receipt == EffectFacts.Refutation(
            case: "refutingConstruction",
            root: "nondeterministicMarker",
            detail: construction
        ))
        #expect(stamped == EffectFacts.Refutation(
            case: "refutingDefaultArgument",
            root: "nondeterministicMarker",
            detail: "the default value of `date` references the nondeterminism marker `Date`"
        ))
        #expect(run.summary.refutedTypes == ["Receipt: " + construction])
    }

    @Test("getters, subscripts and functions get facts; setters, inits and deinits don't")
    func placement() throws {
        let run = try EffectHarness.runFixture()
        let count = try EffectHarness.facts("Effects::Grid::var count: Int { get }", in: run)
        let checksum = try EffectHarness.facts("Effects::Grid::var checksum: Int { get }", in: run)
        let first = try EffectHarness.facts("Effects::Grid::var first: Int { get }", in: run)
        let element = try EffectHarness.facts("Effects::Grid::subscript(_: Int) -> Int", in: run)

        #expect(count.purity == .pure)
        #expect(count.source == .purity)
        #expect(count.function == nil)
        #expect(checksum.declaration?.declared == .idempotent)
        #expect(checksum.source == .declared)
        // A block with a setter is not a derived value.
        #expect(first.refutation?.case == "notAGetter")
        #expect(first.source == .unresolved)
        #expect(element.purity == .pure)
        #expect(element.declaration == nil)
        #expect(element.function == nil)
        let absent = [
            "Effects::Grid::var first: Int { set }",
            "Effects::Grid::init(cells: [Int])",
            "Effects::Handle::deinit"
        ]
        for key in absent {
            #expect(run.facts[key] == nil, "\(key)")
        }
    }

    @Test("a pure function calling `insertRow` keeps source purity, with an inferred non_idempotent")
    func pureWithInferredTier() throws {
        let run = try EffectHarness.runFixture()
        let stage = try EffectHarness.facts("Effects::Ledger::func stage(_: Int) -> Int", in: run)

        #expect(stage.source == .purity)
        #expect(stage.tier == .pure)
        #expect(stage.function?.inferred == EffectFacts.Inferred(
            tier: .nonIdempotent,
            depth: 1,
            anchor: .heuristic,
            via: ["from the callee-name prefix `insert` (in `insertRow`)"]
        ))
    }

    @Test("a record on line 1 after a byte order mark still joins")
    func byteOrderMark() throws {
        let source = "func one() -> Int { 1 }\n"
        let file = ParsedFile(
            path: "Sources/Effects/File.swift",
            source: source,
            tree: EffectHarness.parsed(source, path: "Sources/Effects/File.swift").tree,
            hasByteOrderMark: true
        )
        let run = try EffectHarness.run([file])

        #expect(EffectHarness.records(of: [file]).first?.range.start == SourcePosition(line: 1, column: 4))
        #expect(run.facts["Effects::func one() -> Int"]?.tier == .pure)
    }
}
