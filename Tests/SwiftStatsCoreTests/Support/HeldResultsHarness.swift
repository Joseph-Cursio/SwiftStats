//
//  HeldResultsHarness.swift
//  SwiftStatsCoreTests
//
//  What the tests of held results decided before the slow runs, and of a
//  SwiftMutator run's results kept until its snapshot is stored, share (M6,
//  design §6.4, as built): the Mutation fixture's repository with its fake
//  tools (`SinceHarness`), edits to one of its test files that keep the
//  tree dirty on the same commit, the refusal a plain rescan's save gives,
//  and the mutation folder's pending record.
//

import Foundation
@testable import SwiftStatsCore

/// The `--since` harness with edits, refusals and the pending record.
struct HeldResultsHarness {
    /// The repository, tools and store.
    let since: SinceHarness

    /// The workspace.
    var workspace: SnapshotWorkspace {
        since.workspace
    }

    /// The test file the edits change.
    private var edited: URL {
        since.root.appendingPathComponent("Tests/CoreTests/SignTests.swift")
    }

    /// A harness on `main`, removed again if it can't be checked out.
    init() throws {
        since = try SinceHarness()
        do {
            try since.repository.checkOut("main")
        } catch {
            since.remove()
            throw error
        }
    }

    /// Ends the test file with `comment`, after its committed text.
    func edit(_ comment: String) throws {
        try since.repository.checkOut("main")
        let original = try String(contentsOf: edited, encoding: .utf8)
        try (original + "// \(comment)\n").write(to: edited, atomically: true, encoding: .utf8)
    }

    /// Puts the test file back as committed.
    func revert() throws {
        _ = try MutationFixture.git(
            ["checkout", "--quiet", "--", "Tests/CoreTests/SignTests.swift"],
            in: since.root,
            day: 0
        )
    }

    /// Scans the working tree asking for `tiers`, letting `drop` go, the
    /// fake tools acting out the recorded full run.
    func scan(_ tiers: RequestedTiers, drop: DropOptions) throws -> (snapshot: ScannedSnapshot, id: Int64) {
        try since.fake.act(SinceHarness.scenario("full"))
        return try workspace.scanWorkingTree(history: .skipped("test"), tiers: tiers, drop: drop)
    }

    /// Stores a plain scan of the working tree holding the shapes coverage,
    /// whose stored records name no record of the fixture.
    func storeCoverage() throws {
        let plain = try workspace.scanWorkingTree(history: .skipped("test")).snapshot
        try workspace.save(try CarrySamples.covered(plain), drop: [])
    }

    /// Stores a plain scan of the working tree holding the hand-made
    /// mutation results, recorded on the Coverage fixture, whose mutants
    /// name no record of this one.
    func storeMutation() throws {
        let plain = try workspace.scanWorkingTree(history: .skipped("test")).snapshot
        try workspace.save(try MutationCarrySamples.held(plain), drop: [])
    }

    /// Stores a plain scan of the working tree holding the hand-made T1
    /// results, its build, index and periphery runs ran (M7, design §9.1).
    func storeIndex() throws {
        let plain = try workspace.scanWorkingTree(history: .skipped("test")).snapshot
        try workspace.save(try IndexStoreSamples.indexed(plain), drop: [])
    }

    /// The error a plain rescan's save gives now, which scans asking for
    /// the slow collectors must give before they run; nil when it stores
    /// the rescan (a refused save writes nothing).
    func plainRefusal() throws -> StoreError? {
        try storeError { _ = try workspace.scanWorkingTree(history: .skipped("test")) }
    }

    /// The error `body` throws as a store error; nil when it throws none.
    func storeError(_ body: () throws -> Void) throws -> StoreError? {
        do {
            try body()
            return nil
        } catch let error as StoreError {
            return error
        }
    }

    /// Scans the working tree asking for `tiers`, merging with `base`, the
    /// fake tools acting out the recorded case `name`, without the checks
    /// a storing scan makes before SwiftMutator starts but keeping a run
    /// that ran until it is stored: the scan a save refuses only after its
    /// run, as when the snapshot it replaces changed during the run.
    func unchecked(_ tiers: RequestedTiers, base: MutationBase?, acting name: String) throws -> ScannedSnapshot {
        try since.fake.act(SinceHarness.scenario(name))
        let saving = MutationSaving { _, _, _ in
            // No check: the save is left to refuse after the run.
        }
        return try workspace.scanner.saving(saving, index: nil).scan(
            packageAt: since.root,
            configurationFile: workspace.configurationFile,
            ignoring: workspace.storeInPackage,
            history: .skipped("test"),
            tiers: tiers.merging(with: base)
        )
    }

    /// The mutation folder's pending record; nil when there is none.
    func pending() throws -> PendingMutationRun? {
        try PendingMutationRun.read(in: MutationDirectory(lookingIn: since.root))
    }

    /// How many coverage runs started: each asks the fake `swift` for its
    /// target info first (which fails it, since the fake prints none).
    func coverageRuns() -> Int {
        since.fake.calls(of: "swift").count { $0.first == "-print-target-info" }
    }

    /// Removes the repository, the tools and the store.
    func remove() {
        since.remove()
    }
}
