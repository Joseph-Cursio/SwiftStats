import Foundation
@testable import SwiftStatsCore
import Testing

/// Held results decided before the slow runs (M6, design §6.4, as built;
/// review findings 4 and 16): a scan asking for SwiftMutator or coverage
/// over a snapshot holding results it doesn't collect and can't keep is
/// refused before the run, with the words a plain rescan's save gives,
/// rather than after an hour-long run whose results it would throw away.
/// The fake tools count the runs that didn't happen.
@Suite("Held results decided before the slow runs")
struct HeldResultsUpFrontTests {
    @Test("""
        scan --mutation over held coverage of other uncommitted changes is refused before SwiftMutator starts, in \
        the save's words, leaving nothing pending; --drop-coverage runs and stores it
        """)
    func otherChangesBeforeMutation() throws {
        let harness = try HeldResultsHarness()
        defer { harness.remove() }
        try harness.edit("Edit A.")
        try harness.storeCoverage()
        try harness.edit("Edit B.")
        let expected = try #require(try harness.plainRefusal())
        guard case let .coverageNotKept(_, _, reason) = expected else {
            Issue.record("expected the coverage refusal, got \(expected)")
            return
        }

        let refused = try harness.storeError { _ = try harness.scan(RequestedTiers(mutation: .full), drop: []) }

        #expect(reason == "the uncommitted changes differ")
        #expect(refused == expected)
        #expect(harness.since.runs() == 0)
        #expect(try harness.pending() == nil)

        let stored = try harness.scan(RequestedTiers(mutation: .full), drop: .coverage)
        #expect(harness.since.runs() == 1)
        #expect(stored.snapshot.report.mutation != nil)
        #expect(try harness.workspace.store.holdsCoverage(id: stored.id) == false)
        #expect(try harness.pending() == nil)
    }

    @Test(
        """
        the check made before any collector runs refuses scan --mutation and scan --mutation --resume over held \
        coverage of other uncommitted changes on its own, in the save's words, without the gate before \
        SwiftMutator; --drop-coverage passes it
        """,
        arguments: [MutationRequest.full, .resume]
    )
    func otherChangesBeforeCollectors(request: MutationRequest) throws {
        let harness = try HeldResultsHarness()
        defer { harness.remove() }
        try harness.edit("Edit A.")
        try harness.storeCoverage()
        try harness.edit("Edit B.")
        let expected = try #require(try harness.plainRefusal())
        let git = GitReader.read(packageRoot: harness.since.root, ignoring: harness.workspace.storeInPackage)
        let tiers = RequestedTiers(mutation: request)

        let refused = try harness.storeError {
            _ = try harness.workspace.heldResultsChecks(git: git, tiers: tiers, drop: [])
        }
        let dropped = try harness.workspace.heldResultsChecks(git: git, tiers: tiers, drop: .coverage)

        #expect(refused == expected)
        #expect(dropped != nil)
    }

    @Test("""
        scan --coverage over held mutation results of other uncommitted changes is refused before the coverage run, \
        in the save's words
        """)
    func otherChangesBeforeCoverage() throws {
        let harness = try HeldResultsHarness()
        defer { harness.remove() }
        try harness.edit("Edit A.")
        _ = try harness.scan(RequestedTiers(mutation: .full), drop: [])
        try harness.edit("Edit B.")
        let expected = try #require(try harness.plainRefusal())

        let refused = try harness.storeError { _ = try harness.scan(.coverage, drop: []) }

        #expect(refused == expected)
        #expect(refused.map { error in
            guard case let .mutationNotKept(_, _, reason) = error else {
                return false
            }
            return reason == "the uncommitted changes differ"
        } == true)
        #expect(harness.coverageRuns() == 0)
    }

    @Test("""
        held coverage of the same tree whose records the scan refuses stops scan --mutation once the other \
        collectors have run, before SwiftMutator starts; with --coverage whose run fails, the refusal names the \
        failed run, as the save's does
        """)
    func recordsBeforeMutation() throws {
        let harness = try HeldResultsHarness()
        defer { harness.remove() }
        try harness.storeCoverage()
        let expected = try #require(try harness.plainRefusal())
        guard case let .coverageNotKept(snapshot, collectedAt, reason) = expected else {
            Issue.record("expected the coverage refusal, got \(expected)")
            return
        }

        let refused = try harness.storeError { _ = try harness.scan(RequestedTiers(mutation: .full), drop: []) }
        let both = RequestedTiers(coverage: true, mutation: .full)
        let failed = try harness.storeError { _ = try harness.scan(both, drop: []) }

        #expect(reason.hasSuffix("names no record now"))
        #expect(refused == expected)
        #expect(harness.coverageRuns() == 1)
        guard case let .coverageNotKept(failedSnapshot, failedAt, failedReason) = failed else {
            Issue.record("expected the coverage refusal, got \(String(describing: failed))")
            return
        }
        #expect(failedSnapshot == snapshot && failedAt == collectedAt)
        #expect(failedReason.hasPrefix(reason + "; this scan's coverage run failed ("))
        #expect(harness.since.runs() == 0)
    }
}
