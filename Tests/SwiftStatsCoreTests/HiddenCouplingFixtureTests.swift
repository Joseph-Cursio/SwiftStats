//
//  HiddenCouplingFixtureTests.swift
//  SwiftStatsCoreTests
//
//  Hidden coupling on the Index fixture (M7, design §8.1, §13 step 9c):
//  the fixture scanned with `--index`, its recorded build and index, and
//  `IndexHarness`' deterministic history, stored and read back. Each pair
//  of the history is made for one term of the funnel; `formatLine` with
//  `parseLine` is the one listed, and the `Array` pair counts below the
//  confidence limit.
//

import Foundation
@testable import SwiftStatsCore
import Testing

/// Hidden coupling on the Index fixture's history.
@Suite("Hidden coupling on the Index fixture")
struct HiddenCouplingFixtureTests {
    /// The funnel of the fixture's nine pairs with the default limits.
    static let funnel = "9 pairs = 0 with a family not in this snapshot + 0 with a generated family + 1 with a test "
        + "or helper family + 8 with both families in production code; 8 = 7 judged + 1 with a family the index "
        + "didn't see; 7 = 1 referencing each other + 1 calling through a protocol the other implements + 2 sharing "
        + "or nesting a type + 1 referencing the other's type or members + 2 without a static dependency; 2 = 1 "
        + "listed + 1 below the limits"

    /// The key of the family the history calls `name`, in `snapshot`.
    private static func key(_ name: String, in snapshot: StoredSnapshot) throws -> String {
        let row = name == "topLevel"
            ? snapshot.functions.first { $0.kind == .topLevelCode }
            : snapshot.functions.first { $0.name == name && $0.parentKey == nil }
        return try #require(row, "no record \(name)").key
    }

    /// Expects each of `snapshot`'s pairs to have the verdict its case is
    /// made for.
    private static func expectVerdicts(_ snapshot: StoredSnapshot) throws {
        let index = try #require(snapshot.index?.report)
        let judged = HiddenCoupling.judged(
            snapshot,
            pairs: snapshot.couplingPairs,
            index: index,
            limits: HiddenCoupling.Limits(SignalThresholds())
        )
        let verdicts = Dictionary(judged.map { entry in
            (Set([entry.pair.familyA, entry.pair.familyB]), entry.verdict)
        }) { first, _ in first }
        let expected: [([String], HiddenCoupling.Verdict)] = [
            (["formatLine", "parseLine"], .listed), (["open", "close"], .sharedType),
            (["index", "entry"], .sharedType), (["cycle", "make"], .references),
            (["totalArea", "area"], .requirement), (["unitTile", "area"], .typeReference),
            (["topLevel", "welcome"], .unjudged), (["writesLevel", "arrayUse"], .nonProduction),
            (["doubledAll", "secondItem"], .belowLimits)
        ]
        for (names, verdict) in expected {
            let keys = Set(try names.map { try key($0, in: snapshot) })
            #expect(verdicts[keys] == verdict, "\(names)")
        }
    }

    @Test("""
        the history couples the nine pairs it changes together, each with its support and both families' changes, \
        and the stored pairs equal the history block's
        """)
    func pairs() async throws {
        try await IndexHarness.scanWithHistory { scanned in
            let made = try TemporaryStore("HiddenCouplingFixture")
            defer { made.remove() }
            let snapshot = try IndexHarness.stored(scanned, in: made.store)
            let history = try #require(scanned.report.history)
            let found = Set(snapshot.couplingPairs.map { pair in
                [pair.familyA, pair.familyB, "\(pair.support)", "\(pair.changesA)/\(pair.changesB)"]
            })
            let changed = IndexHarness.historyCommits.flatMap(\.self)
            let changes = try changed.reduce(into: [String: Int]()) { counts, name in
                counts[try Self.key(name, in: snapshot), default: 0] += 1
            }
            let expected = try Set(IndexHarness.coupled.map { names in
                let keys = try names.map { try Self.key($0, in: snapshot) }.sorted()
                return keys + ["\(IndexHarness.rounds)", keys.map { "\(changes[$0] ?? 0)" }.joined(separator: "/")]
            })

            #expect(history.windowCommits == IndexHarness.historyCommits.count)
            #expect(snapshot.couplingPairs == history.coupling)
            #expect(found == expected)
            #expect(snapshot.couplingPairs.count == IndexHarness.coupled.count)
        }
    }

    @Test("""
        each pair is classed as the case it is made for, and only formatLine with parseLine is listed, with its \
        support, changes, confidence, modules and the root's line; the rule states the funnel
        """)
    func endToEnd() async throws {
        try await IndexHarness.scanWithHistory { scanned in
            let made = try TemporaryStore("HiddenCouplingFixture")
            defer { made.remove() }
            let snapshot = try IndexHarness.stored(scanned, in: made.store)
            try Self.expectVerdicts(snapshot)
            let signal = try IndexHarness.signal(.hiddenCoupling, of: snapshot)
            let formatLine = try #require(snapshot.functions.first { $0.name == "formatLine" })
            let item = try #require(signal.items.first)

            #expect(signal.leftOut == nil)
            #expect(signal.rule == HiddenCoupling.rule(thresholds: SignalThresholds()) + "; " + Self.funnel)
            #expect(signal.candidates == IndexHarness.coupled.count)
            #expect(signal.items.count == 1)
            #expect(item.subject == formatLine.key && item.file == formatLine.file)
            #expect(item.line == formatLine.startLine && item.rank == 1 && item.member && item.score == 3)
            #expect(item.coupling == SignalItem.Coupling(
                partner: IndexHarness.parseLine,
                partnerFile: "Sources/Kits/Support.swift",
                support: 3,
                changesA: 3,
                changesB: 3,
                confidence: SignalItem.CouplingConfidence(support: 3, smaller: 3),
                modules: ["IndexCore", "index-support"],
                sameFile: false,
                sameModule: false
            ))
            #expect(item.history == nil && item.references == nil && item.mutation == nil && item.dead == nil)
        }
    }

    @Test("""
        the item's JSON holds the coupling payload alone, with the confidence's two integers, and a support limit \
        of 4 lists nothing
        """)
    func payloadJSON() async throws {
        try await IndexHarness.scanWithHistory { scanned in
            let made = try TemporaryStore("HiddenCouplingFixture")
            defer { made.remove() }
            let snapshot = try IndexHarness.stored(scanned, in: made.store)
            let signal = try IndexHarness.signal(.hiddenCoupling, of: snapshot)
            let item = try #require(signal.items.first)
            let object = try #require(
                try JSONSerialization.jsonObject(with: JSONEncoder().encode(item)) as? [String: Any]
            )
            let coupling = try #require(object["coupling"] as? [String: Any])
            let confidence = try #require(coupling["confidence"] as? [String: Int])
            let stricter = SignalThresholds(limits: ["hidden-coupling": ["support": 4]])
            let none = try #require(
                SignalEngine.signals(of: SignalInputs(snapshot: snapshot), thresholds: stricter)
                    .first { $0.name == .hiddenCoupling }
            )

            #expect(Set(object.keys) == ["rank", "subject", "file", "line", "score", "member", "coupling"])
            #expect(confidence == ["support": 3, "smaller": 3])
            #expect(coupling["modules"] as? [String] == ["IndexCore", "index-support"])
            #expect(none.items.isEmpty && none.candidates == IndexHarness.coupled.count)
            #expect(none.rule.contains("; 7 = 1 referencing each other + 1 calling through a protocol the other "
                + "implements + 2 sharing or nesting a type + 1 referencing the other's type or members + 2 without "
                + "a static dependency; 2 = 0 listed + 2 below the limits"))
            #expect(none.rule.contains("min_support") == false)
        }
    }
}
