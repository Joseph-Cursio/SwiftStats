//
//  DeadButTestedInputsTests.swift
//  SwiftStatsCoreTests
//
//  What dead but tested reads (M7, design §8.2, §13 step 9b), on the Index
//  fixture's scan with hand-made mutants (`IndexHarness`): the
//  declarations funnel over the `production` run's unused production
//  entries alone (a function entry matching no record, one matching a
//  record by USR alone, parameters and stored properties as others);
//  outskirts' results mapped by position when the index is disabled,
//  which the signal doesn't need; and the left-out reasons in order.
//  Serialized: each test scans a copy of the fixture on a thread of its
//  own, as the index collector's tests do.
//

import Foundation
@testable import SwiftStatsCore
import Testing

/// Dead but tested's inputs on the Index fixture's scan.
@Suite("Dead but tested's inputs on the Index fixture", .serialized)
struct DeadButTestedInputsTests {
    /// The harness's shorthand.
    private typealias Harness = IndexHarness

    /// The rule without the index: eight production-dead functions (the
    /// unused computed property covers no accessor), one listed, and the
    /// computed property's entry among the others.
    private static let positionRule = DeadButTested.rule + "; "
        + Harness.functionsFunnel(listed: 1, partial: 0, unrun: [0, 0, 7, 0], dead: 8, nested: 0)
        + "; 8 unused production declarations = 5 function entries matching a record + 0 function entries "
        + "matching no record + 1 type entries + 1 extension entries + 0 property entries with accessor records + "
        + "1 others (parameters, imports, enum cases, stored properties, typealiases); 8 = the distinct records F, T, "
        + "E and V cover"

    /// The entries the declarations funnel test adds, `usr` being
    /// `onlyTestsCall()`'s USR: a function matching no record, one matching
    /// a record by USR alone (the record's cover is a lower entry's), a
    /// parameter, a stored property, and two it doesn't count (another
    /// hint, a test target's).
    private static func added(usr: String) -> [DeadCodeDeclaration] {
        [
            Harness.deadEntry(13, kind: "function.free", name: "ghost()", ids: ["s:ghost"]),
            Harness.deadEntry(14, kind: "function.free", name: "onlyTestsCall()", ids: [usr]),
            Harness.deadEntry(15, kind: "var.parameter", name: "value", ids: ["param-value-f-s:x"]),
            Harness.deadEntry(16, kind: "var.instance", name: "stored", ids: ["s:stored"]),
            Harness.retagged(
                Harness.deadEntry(17, kind: "function.free", name: "loud()", ids: ["s:loud"]),
                hint: "redundantPublicAccessibility",
                entryClass: .production
            ),
            Harness.retagged(
                Harness.deadEntry(18, kind: "function.free", name: "inTests()", ids: ["s:inTests"]),
                hint: DeadCodeMapper.unusedHint,
                entryClass: .test
            )
        ]
    }

    @Test("""
        the declarations funnel counts the production run's unused production entries only: a function entry \
        matching no record, one matching a record by USR alone, a parameter and a stored property apart; other \
        hints and classes aren't counted, and D stays the distinct records F, T, E and V cover
        """)
    func declarationsFunnel() async throws {
        try await Harness.scan(indexed: true) { scanned in
            let made = try TemporaryStore("DeadButTestedDeclarations")
            defer { made.remove() }
            let usr = try #require(scanned.report.index?.records.first { $0.key == Harness.onlyTestsCall }?.usr)
            let snapshot = try Harness.stored(
                Harness.with(Harness.Results(), on: try Harness.adding(Self.added(usr: usr), to: scanned)),
                in: made.store
            )

            let signal = try Harness.signal(.deadButTested, of: snapshot)

            #expect(signal.rule.hasSuffix("; 12 unused production declarations = 6 function entries matching a "
                + "record + 1 function entries matching no record + 1 type entries + 1 extension entries + 1 "
                + "property entries with accessor records + 2 others (parameters, imports, enum cases, stored "
                + "properties, typealiases); 9 = the distinct records F, T, E and V cover"))
            #expect(MutationSignalHarness.unbalanced(signal.rule) == [Harness.coveredClause])
            #expect(signal.items.isEmpty)
        }
    }

    @Test("""
        without the index outskirts' function entries are mapped by position, so onlyTestsCall() is listed via \
        location, and the unused computed property covers no accessor; the signal needs no index, while \
        test-only production code is left out
        """)
    func byLocation() async throws {
        try await Harness.scan(indexed: false) { scanned in
            let made = try TemporaryStore("DeadButTestedLocation")
            defer { made.remove() }
            let results = Harness.Results(mutants: [Harness.onlyTestsCall: [Harness.killed(by: [Harness.onlyTests])]])
            let snapshot = try Harness.stored(Harness.with(results, on: scanned), in: made.store)

            let signal = try Harness.signal(.deadButTested, of: snapshot)

            #expect(snapshot.info.collectors.first { $0.name == IndexAdapter.name }?.state == .skipped)
            #expect(signal.leftOut == nil)
            #expect(signal.rule == Self.positionRule)
            #expect(signal.items.map(\.subject) == [Harness.onlyTestsCall])
            #expect(signal.items.first?.dead?.via == .location)
            #expect(signal.items.first?.dead?.kind == "function.free")
            #expect(try Harness.verdicts(snapshot)[Harness.unusedComputed] == .used)
            let testOnly = try Harness.signal(.testOnlyProduction, of: snapshot)
            #expect(testOnly.leftOut?.hasPrefix("needs index: skipped") == true)
        }
    }

    @Test("""
        the left-out reasons come in order: predates M7, needs periphery, needs swiftmutator, no dead-code rows, \
        then no mutation rows; the index isn't required; a left-out signal states the rule alone and lists \
        nothing
        """)
    func leftOut() async throws {
        try await Harness.scan(indexed: true) { scanned in
            let made = try TemporaryStore("DeadButTestedLeftOut")
            defer { made.remove() }
            let mutated = Harness.with(Harness.Results(), on: scanned)
            let reason = { (snapshot: ScannedSnapshot) in
                try Harness.signal(.deadButTested, of: try Harness.stored(snapshot, in: made.store)).leftOut
            }
            let noPeriphery = "needs periphery: skipped, " + BuildAdapter.notRequestedReason

            #expect(try reason(mutated) == nil)
            #expect(try reason(scanned) == "needs swiftmutator: skipped, " + MutationAdapter.notRequestedReason)
            #expect(try reason(IndexStoreSamples.plain(mutated)) == noPeriphery)
            #expect(try reason(IndexStoreSamples.plain(scanned)) == noPeriphery)

            let id = try made.store.save(mutated)
            let reload = { try Harness.signal(.deadButTested, of: try made.store.load(id: id)) }
            try SnapshotHarness.sqlite(made.url, "UPDATE collectorRun SET state = 'skipped', reason = 'not "
                + "requested; scan --index runs it' WHERE name = 'index' AND snapshotId = \(id)")
            #expect(try reload().leftOut == nil)
            try SnapshotHarness.sqlite(made.url, "DELETE FROM mutationScan WHERE snapshotId = \(id)")
            #expect(try reload().leftOut == "the snapshot holds no mutation rows")
            try SnapshotHarness.sqlite(made.url, "DELETE FROM deadScan WHERE snapshotId = \(id)")
            let noRows = try reload()
            #expect(noRows.leftOut == "the snapshot holds no dead-code rows")
            #expect(noRows.rule == DeadButTested.rule && noRows.items.isEmpty && noRows.candidates == 0)
            try SnapshotHarness.sqlite(made.url, "UPDATE snapshot SET reportSchemaVersion = 8 WHERE id = \(id)")
            #expect(try reload().leftOut == "the snapshot predates M7")
        }
    }
}
