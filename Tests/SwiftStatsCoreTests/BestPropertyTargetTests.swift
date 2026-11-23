//
//  BestPropertyTargetTests.swift
//  SwiftStatsCoreTests
//
//  Best property-test target (M6, design §7.3): suggestions of every tier
//  in the pool with blocked Advisory rows flagged, rejected, disproven,
//  test-site, generated and interaction rows not; one item per function
//  with an unkilled mutant of its own; a resolved partner's unkilled
//  mutants added once per item and counted again where the partner has
//  its own item; a function linked to a property test kept and flagged;
//  the order, the funnel, the rule's advice, and when it is left out.
//

import Foundation
@testable import SwiftStatsCore
import Testing

@Suite("Best property-test target")
struct BestPropertyTargetTests {
    private typealias Harness = PropertyTargetHarness
    private typealias Samples = PropertyTargetSamples

    /// The signal over the package `setup` describes.
    private static func signal(_ setup: Harness.Setup) throws -> SignalResult {
        try MutationSignalHarness.signal(.bestPropertyTarget, of: try Harness.stored(setup))
    }

    @Test("suggestions of every tier are read, blocked Advisory rows flagged; rejected, disproven and others aren't")
    func tiers() throws {
        let signal = try Self.signal(Samples.setup())
        let target = signal.items.map(\.propertyTarget)

        #expect(signal.leftOut == nil)
        #expect(signal.items.map(\.subject) == [Samples.encoded, Samples.decoded, Samples.doubled, Samples.clamped])
        #expect(target.map { $0?.suggestions.map(\.identity) ?? [] } == [
            ["0x00000000000000A1", "0x00000000000000A2"], ["0x00000000000000B1"], ["0x00000000000000C1"],
            ["0x00000000000000E1"]
        ])
        #expect(target.map { $0?.suggestions.map(\.tier) ?? [] } == [
            ["Likely", "Possible"], ["Possible"], ["Strong"], ["Advisory"]
        ])
        #expect(target.map { $0?.suggestions.map(\.blocked) ?? [] } == [[false, false], [false], [false], [true]])
        #expect(target.map { $0?.suggestions.map(\.verified) ?? [] } == [[false, false], [true], [false], [false]])
        // halved, built, bare, moved and fresh carry suggestions but aren't listed;
        // hidden's are rejected or disproven, so it isn't counted at all.
        #expect(signal.candidates == 5)
        #expect(signal.members.count == 4)
    }

    @Test("a function linked to a property test stays in, flagged by its suggestion's testedBy")
    func tested() throws {
        let signal = try Self.signal(Samples.setup())
        let item = try #require(signal.items.first { $0.subject == Samples.doubled })
        let suggestion = try #require(item.propertyTarget?.suggestions.first)

        #expect(suggestion.testedBy == .generated)
        #expect(item.score == 2)
        #expect(item.propertyTarget?.unkilled.map(\.verdict) == ["timedOut", "noCoverage"])
    }

    @Test("a resolved partner's unkilled mutants count once per item, again in its own item, and in the funnel")
    func partners() throws {
        let signal = try Self.signal(Samples.setup())
        let encodedItem = try #require(signal.items.first { $0.subject == Samples.encoded })
        let decodedItem = try #require(signal.items.first { $0.subject == Samples.decoded })
        let added = try #require(encodedItem.propertyTarget?.partners.first)

        // Two round trips name decoded: it is added once.
        #expect(encodedItem.propertyTarget?.partners.count == 1)
        #expect(added.key == Samples.decoded)
        #expect(added.counts?.survived == 1)
        #expect(added.counts?.notCovered == 1)
        #expect(added.unkilled.map(\.verdict) == ["survived", "notCovered"])
        // Its own two survivors, then decoded's two unkilled mutants.
        #expect(encodedItem.score == 4)
        #expect(encodedItem.propertyTarget?.unkilled.map(\.verdict) == ["survived", "survived"])
        #expect(encodedItem.mutation?.counts.killed == 1)
        #expect(encodedItem.mutation?.firstKillingTests == ["roundTrips()"])
        // decoded's own item counts them too: the funnel says so.
        #expect(decodedItem.score == 2)
        #expect(decodedItem.propertyTarget?.partners.isEmpty == true)
        #expect(signal.rule.hasSuffix("; 1 partner added, 2 mutants counted by more than one item"))
    }

    /// The mapper never resolves a partner to the suggestion's own function,
    /// so a stored row is edited to carry one.
    @Test("a stored suggestion naming its own function as partner adds no partner and counts no mutant twice")
    func selfPartner() throws {
        let directory = try SnapshotHarness.temporaryDirectory("PropertyTargetSelfPartner")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("stats.sqlite")
        let store = try SnapshotStore(at: url)
        let stored = try Harness.stored(Samples.setup { $0.store = store })
        let owner = Samples.doubled.replacingOccurrences(of: "'", with: "''")
        try SnapshotHarness.sqlite(url, "UPDATE propertyCandidate SET partnerKey = '\(owner)' WHERE owner = '\(owner)'")
        let reloaded = try store.load(id: stored.id)

        #expect(reloaded.candidates.contains { $0.partnerKey == Samples.doubled })
        let signal = try MutationSignalHarness.signal(.bestPropertyTarget, of: reloaded)
        let item = try #require(signal.items.first { $0.subject == Samples.doubled })
        #expect(item.propertyTarget?.partners.isEmpty == true)
        #expect(item.score == 2)
        #expect(signal.rule.hasSuffix("; 1 partner added, 2 mutants counted by more than one item"))
    }

    @Test("items order by score, then their best suggestion's score with Verified's 50, then subject")
    func order() throws {
        let signal = try Self.signal(Samples.setup())
        let unverified = try Self.signal(Samples.setup { setup in
            setup.files[".swiftinfer/verify-evidence.json"] = Samples.evidenceWithoutVerified
        })

        // decoded's Possible 35 is Verified (85), so it comes before
        // doubled's Strong 80 at the same score; clamped's blocked 95 scores 1.
        #expect(signal.items.map(\.score) == [4, 2, 2, 1])
        #expect(signal.items.map(\.subject) == [Samples.encoded, Samples.decoded, Samples.doubled, Samples.clamped])
        #expect(signal.items.map(\.rank) == [1, 2, 3, 4])
        // Without Verified, decoded's 35 is below doubled's 80: doubled comes
        // first, though decoded sorts first by subject.
        #expect(unverified.items.map(\.score) == [4, 2, 2, 1])
        #expect(unverified.items.map(\.subject) == [
            Samples.encoded, Samples.doubled, Samples.decoded, Samples.clamped
        ])
    }

    @Test("a function's suggestions rank by weight, not identity or row order, and the best sets its tie-break")
    func ranking() throws {
        let signal = try Self.signal(Samples.setup { $0.rows.append(Samples.strongerDoubled) })
        let item = try #require(signal.items.first { $0.subject == Samples.doubled })

        // C2's 90 outranks C1's 80, though C2's identity is larger and its
        // row comes later.
        #expect(item.propertyTarget?.suggestions.map(\.identity) == ["0x00000000000000C2", "0x00000000000000C1"])
        // doubled's best is now 90, above decoded's Verified 85.
        #expect(signal.items.map(\.subject) == [Samples.encoded, Samples.doubled, Samples.decoded, Samples.clamped])
    }

    @Test("the funnel counts every function carrying a suggestion, each part summing to its whole")
    func funnel() throws {
        let signal = try Self.signal(Samples.setup())
        let funnel = "9 production functions holding 10 suggestions = 5 with mutation results + 1 with only "
            + "build errors + 1 with none + 2 without results (1 unresolved, 1 unlisted); 5 = 4 listed + 1 with "
            + "every mutant killed; 1 partner added, 2 mutants counted by more than one item"

        #expect(signal.rule == BestPropertyTarget.rule + "; " + funnel)
        #expect(MutationSignalHarness.unbalanced(signal.rule).isEmpty)
    }

    @Test("the rule's advice is a full scan or SwiftMutator on the file, since a --since run retests nothing")
    func advice() {
        let rule = BestPropertyTarget.rule

        #expect(rule.contains(
            "after writing the property test, run scan --mutation, or SwiftMutator on the file (swift-mutator run "
                + "--files-to-mutate <file>), and read the former survivors' killedBy"
        ))
        #expect(rule.hasSuffix("(a --since run retests nothing when only tests changed)"))
        #expect(rule.contains("blocked Advisory rows flagged"))
    }

    @Test("an item's JSON carries its suggestions, unkilled mutants and partners under propertyTarget")
    func json() throws {
        let signal = try Self.signal(Samples.setup())
        let item = try #require(signal.items.first)
        let object = try JSONSerialization.jsonObject(with: try JSONEncoder().encode(item)) as? [String: Any]
        let target = object?["propertyTarget"] as? [String: Any]

        #expect(Set(target?.keys.map(\.self) ?? []) == ["partners", "suggestions", "unkilled"])
        #expect(object?["property"] == nil)
        #expect(object?["mutation"] != nil)
        #expect(object?["coverage"] == nil)
    }

    @Test("results that don't list code no test ran add the note that functions no test ran aren't judged")
    func notListed() throws {
        let signal = try Self.signal(Samples.setup { setup in
            setup.listsNotCovered = false
            setup.mutants[Samples.decoded] = [.init(verdict: .survived)]
        })

        #expect(signal.leftOut == nil)
        #expect(signal.rule.hasSuffix("; " + WeakTests.notListedNote))
    }

    @Test("predates M6 at schema 7, then no mutation rows; coverage isn't needed")
    func requirements() throws {
        let directory = try SnapshotHarness.temporaryDirectory("PropertyTargetRequirements")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("stats.sqlite")
        let store = try SnapshotStore(at: url)
        let stored = try Harness.stored(Samples.setup { $0.store = store })
        let reason = {
            try MutationSignalHarness.signal(.bestPropertyTarget, of: try store.load(id: stored.id)).leftOut
        }

        try SnapshotHarness.sqlite(url, "DELETE FROM coverageRun")
        try SnapshotHarness.sqlite(url, "UPDATE collectorRun SET state = 'skipped' WHERE name = 'coverage'")
        #expect(try reason() == nil)
        try SnapshotHarness.sqlite(url, "UPDATE snapshot SET reportSchemaVersion = 7")
        #expect(try reason() == "the snapshot predates M6")
        try SnapshotHarness.sqlite(url, "UPDATE snapshot SET reportSchemaVersion = 8")
        try SnapshotHarness.sqlite(url, "DELETE FROM mutationScan")
        #expect(try reason() == "the snapshot holds no mutation rows")
    }

    @Test("left out without swift-infer, and without a mutation run, which is named first")
    func leftOut() throws {
        let noIndex = try Self.signal(Samples.setup { $0.indexed = false })
        let neither = try Self.signal(Samples.setup { setup in
            setup.indexed = false
            setup.withMutation = false
        })

        #expect(noIndex.leftOut?.hasPrefix("needs swiftinferproperties: skipped") == true)
        #expect(noIndex.items.isEmpty)
        #expect(noIndex.rule == BestPropertyTarget.rule)
        #expect(neither.leftOut == "needs swiftmutator: skipped, " + MutationAdapter.notRequestedReason)
    }
}
