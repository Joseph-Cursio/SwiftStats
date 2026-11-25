//
//  HiddenCouplingTests.swift
//  SwiftStatsCoreTests
//
//  Hidden coupling's judgement (M7, design §8.1) on `CouplingSignalHarness`'
//  small package, with hand-made index results and history pairs: the
//  classes in order (a family not in the snapshot, a generated family, a
//  test family, a family without a USR), the static dependencies in order
//  (a direct reference either way, one through a requirement, a shared or
//  nested type, a reference to the other's type), the owning type of an
//  extension's member by its USR, the order with its partner tie-break,
//  and the left-out wordings in order; the limits are in
//  `HiddenCouplingTests+Limits`.
//

@testable import SwiftStatsCore
import Testing

/// Hidden coupling on hand-made pairs.
@Suite("Hidden coupling judgement")
struct HiddenCouplingTests {
    /// The harness.
    typealias Harness = CouplingSignalHarness

    /// The thresholds with hidden coupling's limits `support` and
    /// `confidence`.
    static func limits(support: Double, confidence: Double) -> SignalThresholds {
        SignalThresholds(limits: ["hidden-coupling": ["support": support, "confidence": confidence]])
    }

    /// The pairs `names` give, each listed by default (support 3 of 3
    /// changes each), named over `snapshot`'s records.
    private static func pairs(_ names: [(String, String)], in snapshot: StoredSnapshot) throws -> [CouplingPair] {
        try names.map { first, second in
            try Harness.pair(first, second, support: 3, changes: (3, 3), in: snapshot)
        }
    }

    @Test("""
        a pair is classed by the first that applies: a family not in the snapshot, a generated family, a test or \
        helper family, a family without a USR, else both in production and judged; the funnel's parts sum
        """)
    func classes() throws {
        let made = try TemporaryStore("HiddenCoupling")
        defer { made.remove() }
        let plain = try Harness.plain(in: made.store)
        let gone = CouplingPair(
            familyA: "Lib::func gone() -> Int",
            fileA: "Sources/Lib/Lib.swift",
            familyB: try #require(plain.functions.first { $0.name == "made" }).key,
            fileB: "Sources/Lib/Made.generated.swift",
            support: 3,
            changesA: 3,
            changesB: 3
        )
        var facts = Harness.Facts()
        facts.pairs = [gone] + (try Self.pairs([
            ("made", "loneOne"), ("made", "testIt"), ("testIt", "loneOne"), ("testIt", "unseen"),
            ("unseen", "callee"), ("loneOne", "loneTwo")
        ], in: plain))
        facts.references = [Harness.reference("unseen", "callee", .direct)]
        let snapshot = try Harness.stored(facts, in: made.store)
        let signal = try Harness.signal(snapshot, thresholds: SignalThresholds())

        #expect(try Harness.verdicts(snapshot, thresholds: SignalThresholds()) == [
            .unknownFamily, .generated, .generated, .nonProduction, .nonProduction, .unjudged, .listed
        ])
        #expect(signal.rule == HiddenCoupling.rule(thresholds: SignalThresholds()) + "; 7 pairs = 1 with a family "
            + "not in this snapshot + 2 with a generated family + 2 with a test or helper family + 2 with both "
            + "families in production code; 2 = 1 judged + 1 with a family the index didn't see; 1 = 0 referencing "
            + "each other + 0 calling through a protocol the other implements + 0 sharing or nesting a type + 0 "
            + "referencing the other's type or members + 1 without a static dependency; 1 = 1 listed + 0 below the "
            + "limits")
        #expect(signal.candidates == facts.pairs.count)
        #expect(signal.items.map(\.subject) == [facts.pairs[6].familyA])
        #expect(HiddenCoupling.funnel(HiddenCoupling.Tally([])) == "0 pairs = 0 with a family not in this snapshot "
            + "+ 0 with a generated family + 0 with a test or helper family + 0 with both families in production "
            + "code; 0 = 0 judged + 0 with a family the index didn't see; 0 = 0 referencing each other + 0 calling "
            + "through a protocol the other implements + 0 sharing or nesting a type + 0 referencing the other's "
            + "type or members + 0 without a static dependency; 0 = 0 listed + 0 below the limits")
    }

    @Test("""
        the static dependencies count a pair out in order: a direct reference either way before a requirement, a \
        requirement before a shared type, a shared or nested type before a type reference, and a reference to the \
        other root's type either way
        """)
    func dependencies() throws {
        let made = try TemporaryStore("HiddenCoupling")
        defer { made.remove() }
        let plain = try Harness.plain(in: made.store)
        var facts = Harness.Facts()
        facts.pairs = try Self.pairs([
            ("callee", "caller"), ("throughProtocol", "witnessing"), ("alpha", "beta"), ("alpha", "gamma"),
            ("theta", "beta"), ("theta", "zeta"), ("theta", "typeUser")
        ], in: plain)
        facts.references = [
            Harness.reference("caller", "callee", .direct), Harness.reference("caller", "callee", .requirement),
            Harness.reference("witnessing", "throughProtocol", .requirement),
            Harness.reference("alpha", "beta", .requirement)
        ]
        facts.typeReferences = [
            Harness.typeReference("alpha", "Lib", "Shared.Nested"), Harness.typeReference("beta", "Lib", "Box"),
            Harness.typeReference("theta", "Lib", "Holder"), Harness.typeReference("typeUser", "Lib", "Box")
        ]
        let snapshot = try Harness.stored(facts, in: made.store)

        #expect(try Harness.verdicts(snapshot, thresholds: SignalThresholds()) == [
            .references, .requirement, .requirement, .sharedType, .typeReference, .typeReference, .typeReference
        ])
        facts.references = []
        facts.typeReferences = []
        #expect(try Harness.verdicts(try Harness.stored(facts, in: made.store), thresholds: SignalThresholds()) == [
            .listed, .listed, .sharedType, .sharedType, .listed, .listed, .listed
        ])
    }

    @Test("""
        a shared or nested type is one target's: equal type paths in two targets and a path nested in another \
        target's type aren't shared; an extension's member is owned by the package type its USR names, by a \
        plain, qualified or typealias head and whichever target declares it, and by none when it extends \
        another module's type of a name one target declares; a root without a Swift USR is owned by its own \
        target's type; Array extension methods share none; a private type nested in a plain one shares it
        """)
    func owners() throws {
        let made = try TemporaryStore("HiddenCoupling")
        defer { made.remove() }
        let plain = try Harness.plain(in: made.store)
        var facts = Harness.Facts()
        facts.pairs = try Self.pairs([
            ("alpha", "delta"), ("epsilon", "zeta"), ("eta", "theta"), ("iota", "kappa"), ("kappa", "lambda"),
            ("firstPart", "secondPart"), ("audit", "theta"), ("mu", "theta"), ("nu", "eta"), ("bridged", "alpha"),
            ("alpha", "omega")
        ], in: plain)
        facts.typeReferences = [
            Harness.typeReference("delta", "Lib", "Holder"), Harness.typeReference("lambda", "Other", "Holder.Inside")
        ]
        let snapshot = try Harness.stored(facts, in: made.store)
        let index = try #require(snapshot.index?.report)
        let owners = CouplingOwners(index: index)
        let roots = FunctionFamily.families(snapshot.functions).map { ($0.root?.name ?? "", $0) }
        let families = Dictionary(roots) { first, _ in first }
        let owner = { (name: String) in
            owners.owner(of: try #require(families[name])).map { "\($0.module)::\($0.typePath)" }
        }

        #expect(try owner("eta") == "Lib::Box")
        #expect(try owner("kappa") == "Lib::Twin")
        #expect(try owner("lambda") == "Third::Twin")
        #expect(try owner("epsilon") == "Other::Holder.Inside")
        #expect(try owner("mu") == "Lib::Box")
        #expect(try owner("nu") == "Lib::Box")
        #expect(try owner("audit") == nil)
        #expect(try owner("bridged") == "Lib::Shared")
        #expect(try owner("firstPart") == nil)
        #expect(try owner("loneOne") == nil)
        #expect(try owner("unseen") == nil)
        #expect(try owner("omega") == "Lib::Shared.Hidden")
        #expect(snapshot.functions.first { $0.name == "mu" }?.typePath == "Lib.Box")
        #expect(snapshot.functions.first { $0.name == "nu" }?.typePath == "Crate")
        #expect(try Harness.verdicts(snapshot, thresholds: SignalThresholds()) == [
            .listed, .listed, .sharedType, .sharedType, .listed, .listed, .listed, .sharedType, .sharedType,
            .sharedType, .sharedType
        ])
    }

    @Test("""
        one type is nested in another of its target when its path continues the other's: a private type nested in \
        a plain one counts, though only the inner one is file-scoped; one in another file's private type, or \
        whose name merely starts with the other's, doesn't
        """)
    func nesting() {
        #expect(CouplingOwners.isNested(
            TypeIdentity(module: "Lib", typePath: "Shared.Nested", typeFile: ""),
            TypeIdentity(module: "Lib", typePath: "Shared", typeFile: "")
        ))
        #expect(CouplingOwners.isNested(
            TypeIdentity(module: "Lib", typePath: "Shared", typeFile: ""),
            TypeIdentity(module: "Lib", typePath: "Shared.Hidden", typeFile: "Sources/Lib/Lib.swift")
        ))
        #expect(CouplingOwners.isNested(
            TypeIdentity(module: "Lib", typePath: "Shared.Hidden", typeFile: "Sources/Lib/Lib.swift"),
            TypeIdentity(module: "Lib", typePath: "Shared", typeFile: "Sources/Lib/Other.swift")
        ) == false)
        #expect(CouplingOwners.isNested(
            TypeIdentity(module: "Lib", typePath: "SharedMore", typeFile: ""),
            TypeIdentity(module: "Lib", typePath: "Shared", typeFile: "")
        ) == false)
    }

    @Test("""
        listed pairs sort by support, then confidence, both highest first, then subject, file and line, then \
        partner; each scores its support and names its partner, both changes, the confidence, the modules and \
        whether they share a file or a module
        """)
    func order() throws {
        let made = try TemporaryStore("HiddenCoupling")
        defer { made.remove() }
        let plain = try Harness.plain(in: made.store)
        var facts = Harness.Facts()
        facts.pairs = [
            try Harness.pair("firstPart", "secondPart", support: 3, changes: (6, 6), in: plain),
            try Harness.pair("loneOne", "loneTwo", support: 3, changes: (3, 4), in: plain),
            try Harness.pair("loneOne", "loneThree", support: 3, changes: (4, 3), in: plain),
            try Harness.pair("alpha", "delta", support: 4, changes: (8, 8), in: plain)
        ]
        let snapshot = try Harness.stored(facts, in: made.store)
        let signal = try Harness.signal(snapshot, thresholds: SignalThresholds())
        let alpha = try #require(snapshot.functions.first { $0.name == "alpha" })

        #expect(signal.items.map(\.subject) == [3, 2, 1, 0].map { facts.pairs[$0].familyA })
        #expect(signal.items.map { $0.coupling?.partner } == [3, 2, 1, 0].map { facts.pairs[$0].familyB })
        #expect(signal.items.map(\.rank) == [1, 2, 3, 4])
        #expect(signal.items.map(\.score) == [4, 3, 3, 3])
        #expect(signal.items.map(\.member) == [true, true, true, true])
        #expect(signal.items.first?.line == alpha.startLine)
        #expect(signal.items.first?.coupling == SignalItem.Coupling(
            partner: facts.pairs[3].familyB,
            partnerFile: "Sources/Other/Other.swift",
            support: 4,
            changesA: 8,
            changesB: 8,
            confidence: SignalItem.CouplingConfidence(support: 4, smaller: 8),
            modules: ["Lib", "Other"],
            sameFile: false,
            sameModule: false
        ))
        #expect(signal.items[1].coupling?.confidence == SignalItem.CouplingConfidence(support: 3, smaller: 3))
        #expect(signal.items[1].coupling?.sameFile == true && signal.items[1].coupling?.sameModule == true)
        #expect(signal.items[1].coupling?.modules == ["Lib", "Lib"])
    }

    @Test("""
        the left-out reasons come in order: no history (M3's wording), predates M7, needs index with its state and \
        reason, then no index rows; a left-out signal states the rule alone, lists nothing and counts no candidates
        """)
    func leftOut() throws {
        let made = try TemporaryStore("HiddenCoupling")
        defer { made.remove() }
        let plain = try Harness.plain(in: made.store)
        var facts = Harness.Facts()
        facts.pairs = try Self.pairs([("loneOne", "loneTwo")], in: plain)
        let full = try Harness.stored(facts, in: made.store)
        let reload = { try Harness.signal(try made.store.load(id: full.id), thresholds: SignalThresholds()) }

        #expect(try reload().leftOut == nil)
        try SnapshotHarness.sqlite(made.url, "DELETE FROM indexScan")
        let noRows = try reload()
        #expect(noRows.leftOut == "the snapshot holds no index rows")
        #expect(noRows.rule == HiddenCoupling.rule(thresholds: SignalThresholds()))
        #expect(noRows.items.isEmpty && noRows.candidates == 0)
        try SnapshotHarness.sqlite(made.url, "UPDATE collectorRun SET state = 'skipped', reason = 'not requested; "
            + "scan --index runs it' WHERE name = 'index'")
        #expect(try reload().leftOut == "needs index: skipped, not requested; scan --index runs it")
        try SnapshotHarness.sqlite(made.url, "UPDATE snapshot SET reportSchemaVersion = 8")
        #expect(try reload().leftOut == "the snapshot predates M7")
        try SnapshotHarness.sqlite(made.url, "DELETE FROM historyRun")
        #expect(try reload().leftOut == "history was not collected: ran")
        try SnapshotHarness.sqlite(made.url, "DELETE FROM collectorRun WHERE name = 'history'")
        #expect(try reload().leftOut == "history was not collected (the snapshot predates M3)")
        facts.missing = HistoryCollector.name
        let unread = try Harness.signal(try Harness.stored(facts, in: made.store), thresholds: SignalThresholds())
        #expect(unread.leftOut == "history was not collected: skipped, not in a git repository with commits")
        facts.missing = IndexAdapter.name
        let unindexed = try Harness.signal(try Harness.stored(facts, in: made.store), thresholds: SignalThresholds())
        #expect(unindexed.leftOut == "needs index: skipped, not requested; scan --index runs it")
    }
}
