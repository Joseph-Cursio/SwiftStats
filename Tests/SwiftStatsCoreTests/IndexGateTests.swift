import Foundation
@testable import SwiftStatsCore
import Testing

/// Held results decided before the T1 build and SwiftMutator (M7, design
/// §9.5), on the Mutation fixture's repository with its fake tools: held
/// coverage the scan won't keep stops `scan --index` before the build
/// starts, held T1 results stop `scan --mutation` before SwiftMutator
/// starts, and `scan --coverage` is refused up front over held T1 results
/// of other uncommitted changes, each with the words a plain rescan's save
/// gives. Held mutation results that don't carry stop `scan --index` before
/// the build starts too, and `scan --index` is refused up front over held
/// coverage of other uncommitted changes. The fake tools count the runs
/// that didn't happen.
@Suite("Held T1 results decided before the slow runs")
struct IndexGateTests {
    @Test("""
        held coverage of the same tree whose records the scan refuses stops scan --index once the other \
        collectors have run, before the build starts, in the save's words; --drop-coverage lets the build run
        """)
    func indexGate() throws {
        let harness = try HeldResultsHarness()
        defer { harness.remove() }
        try harness.storeCoverage()
        let expected = try #require(try harness.plainRefusal())

        let refused = try harness.storeError { _ = try harness.scan(RequestedTiers(index: true), drop: []) }

        guard case let .coverageNotKept(_, _, reason) = expected else {
            Issue.record("expected the coverage refusal, got \(expected)")
            return
        }
        #expect(reason.hasSuffix("names no record now"))
        #expect(refused == expected)
        #expect(harness.coverageRuns() == 0)

        let stored = try harness.scan(RequestedTiers(index: true), drop: .coverage)
        #expect(harness.coverageRuns() > 0)
        #expect(try harness.workspace.store.holdsCoverage(id: stored.id) == false)
    }

    @Test("""
        held T1 results that don't describe the files stop scan --mutation once the other collectors have run, \
        before SwiftMutator starts, in the save's words, leaving nothing pending; --drop-index runs and stores it
        """)
    func mutationGate() throws {
        let harness = try HeldResultsHarness()
        defer { harness.remove() }
        try harness.storeIndex()
        let expected = try #require(try harness.plainRefusal())

        let refused = try harness.storeError { _ = try harness.scan(RequestedTiers(mutation: .full), drop: []) }

        guard case let .indexNotKept(_, _, reason) = expected else {
            Issue.record("expected the index refusal, got \(expected)")
            return
        }
        #expect(reason.hasSuffix("is scanned now, but wasn't when the index was built"))
        #expect(refused == expected)
        #expect(harness.since.runs() == 0)
        #expect(try harness.pending() == nil)

        let stored = try harness.scan(RequestedTiers(mutation: .full), drop: .index)
        #expect(harness.since.runs() == 1)
        #expect(stored.snapshot.report.mutation != nil)
        #expect(try harness.workspace.store.holdsIndex(id: stored.id) == false)
    }

    @Test("""
        scan --coverage over held T1 results of other uncommitted changes is refused before the coverage run, in \
        the save's words
        """)
    func otherChangesBeforeCoverage() throws {
        let harness = try HeldResultsHarness()
        defer { harness.remove() }
        try harness.edit("Edit A.")
        try harness.storeIndex()
        try harness.edit("Edit B.")
        let expected = try #require(try harness.plainRefusal())

        let refused = try harness.storeError { _ = try harness.scan(.coverage, drop: []) }

        guard case let .indexNotKept(_, _, reason) = expected else {
            Issue.record("expected the index refusal, got \(expected)")
            return
        }
        #expect(reason == "the uncommitted changes differ")
        #expect(refused == expected)
        #expect(harness.coverageRuns() == 0)
    }

    @Test("""
        held mutation results whose records the scan refuses stop scan --index once the other collectors have \
        run, before the build starts, in the save's words; --drop-mutation lets the build run
        """)
    func mutationBeforeBuild() throws {
        let harness = try HeldResultsHarness()
        defer { harness.remove() }
        try harness.storeMutation()
        let expected = try #require(try harness.plainRefusal())

        let refused = try harness.storeError { _ = try harness.scan(RequestedTiers(index: true), drop: []) }

        guard case let .mutationNotKept(_, _, reason) = expected else {
            Issue.record("expected the mutation refusal, got \(expected)")
            return
        }
        #expect(reason.hasSuffix("names no record now"))
        #expect(refused == expected)
        #expect(harness.coverageRuns() == 0)

        let stored = try harness.scan(RequestedTiers(index: true), drop: .mutation)
        #expect(harness.coverageRuns() > 0)
        #expect(try harness.workspace.store.holdsMutation(id: stored.id) == false)
    }

    @Test("""
        scan --index over held coverage of other uncommitted changes is refused by the check made before any \
        collector runs, in the save's words, and never starts the build; --drop-coverage passes the check
        """)
    func otherChangesBeforeIndex() throws {
        let harness = try HeldResultsHarness()
        defer { harness.remove() }
        try harness.edit("Edit A.")
        try harness.storeCoverage()
        try harness.edit("Edit B.")
        let expected = try #require(try harness.plainRefusal())
        let git = GitReader.read(packageRoot: harness.since.root, ignoring: harness.workspace.storeInPackage)
        let tiers = RequestedTiers(index: true)

        let early = try harness.storeError {
            _ = try harness.workspace.heldResultsChecks(git: git, tiers: tiers, drop: [])
        }
        let dropped = try harness.workspace.heldResultsChecks(git: git, tiers: tiers, drop: .coverage)
        let refused = try harness.storeError { _ = try harness.scan(tiers, drop: []) }

        guard case let .coverageNotKept(_, _, reason) = expected else {
            Issue.record("expected the coverage refusal, got \(expected)")
            return
        }
        #expect(reason == "the uncommitted changes differ")
        #expect(early == expected && refused == expected)
        #expect(dropped.mutation == nil && dropped.index != nil)
        #expect(harness.coverageRuns() == 0)
    }
}
