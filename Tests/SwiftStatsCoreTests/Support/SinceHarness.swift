//
//  SinceHarness.swift
//  SwiftStatsCoreTests
//
//  What the `--since` merge tests share (M6, design §6.1, §11 step 6): the
//  Mutation fixture's repository built as the recording script builds it,
//  so its commits are the ones the recordings name, a `FakeMutator` acting
//  out its recorded cases as the build it names itself, a configuration
//  and a store outside the repository, and a workspace scanning the
//  branch checked out, described from its files on disk (the `since`
//  branch renames a file). A scan of `main` asking for a full run stores
//  the base; a scan of another branch asking for `--since main` merges
//  with it.
//

import Foundation
@testable import SwiftStatsCore

/// The Mutation fixture's repository, fake tools and a store, for `--since`.
struct SinceHarness {
    /// The fixture's repository.
    let repository: MutationFixture.Repository
    /// The fake tools.
    let fake: FakeMutator
    /// The folder holding the configuration and the store.
    let folder: URL
    /// The workspace, configured by `configuration.yml` in `folder`.
    let workspace: SnapshotWorkspace

    /// The package's root.
    var root: URL {
        repository.root
    }

    /// `main`'s commit, the base's.
    var mainCommit: String {
        repository.commits["main", default: ""]
    }

    /// A harness whose fake tools act out nothing yet; removed again if it
    /// can't be made.
    init() throws {
        repository = try MutationFixture.repository(of: MutationFixture.directory)
        do {
            fake = try FakeMutator.make(FakeMutator.Scenario())
            folder = try SnapshotHarness.temporaryDirectory("SinceHarness")
            workspace = try Self.workspace(root: repository.root, folder: folder, fake: fake, settings: "")
        } catch {
            repository.remove()
            throw error
        }
    }

    /// The recorded case `name` of the Mutation fixture, as the build the
    /// fake tools name themselves.
    static func scenario(_ name: String) throws -> FakeMutator.Scenario {
        var scenario = try FakeMutator.recorded(name)
        scenario.ownIdentity = true
        return scenario
    }

    /// A workspace on the package at `root`, its store in `folder`, its
    /// configuration pointing the collectors at `fake` with `settings`
    /// added under `collectors.swiftmutator`, written to a file in `folder`
    /// of its own.
    static func workspace(root: URL, folder: URL, fake: FakeMutator, settings: String) throws -> SnapshotWorkspace {
        let configuration = folder.appendingPathComponent("configuration-\(UUID().uuidString).yml")
        try (
            "collectors:\n  coverage:\n    path: \(fake.swift.path)\n"
                + "  swiftmutator:\n    path: \(fake.mutator.path)\n" + settings
        )
        .write(to: configuration, atomically: true, encoding: .utf8)
        return try SnapshotWorkspace(
            packageRoot: root,
            configurationFile: configuration,
            storeOverride: folder.appendingPathComponent("stats.sqlite").path,
            build: SnapshotHarness.build,
            describer: TreeDescriber(name: "Mutation", targets: MappingHarness.mutationTargets),
            tools: SnapshotHarness.noTools
        )
    }

    /// Another workspace on the same package and store, with `settings`
    /// added under `collectors.swiftmutator`.
    func workspace(adding settings: String) throws -> SnapshotWorkspace {
        try Self.workspace(root: root, folder: folder, fake: fake, settings: settings)
    }

    /// Checks out `branch` and scans it with `workspace`, the fake tools
    /// acting out `scenario`, asking for `request`: what was stored, with
    /// its id.
    func scan(
        _ branch: String,
        acting scenario: FakeMutator.Scenario,
        request: MutationRequest?,
        in workspace: SnapshotWorkspace
    ) throws -> (snapshot: ScannedSnapshot, id: Int64) {
        try repository.checkOut(branch)
        try fake.act(scenario)
        return try workspace.scanWorkingTree(history: .skipped("test"), tiers: RequestedTiers(mutation: request))
    }

    /// Scans `main` asking for a full run, the fake acting out the recorded
    /// full run: the base snapshot and its id.
    func base() throws -> (snapshot: ScannedSnapshot, id: Int64) {
        try scan("main", acting: Self.scenario("full"), request: .full, in: workspace)
    }

    /// Scans `branch` asking for `--since main`, the fake acting out the
    /// recorded case `name`.
    func since(_ branch: String, acting name: String) throws -> (snapshot: ScannedSnapshot, id: Int64) {
        try scan(branch, acting: Self.scenario(name), request: .since("main"), in: workspace)
    }

    /// How many times the fake `swift-mutator run` was called.
    func runs() -> Int {
        fake.calls(of: "swift-mutator").count { $0.first == "run" }
    }

    /// Removes the repository, the tools and the folder.
    func remove() {
        repository.remove()
        fake.remove()
        try? FileManager.default.removeItem(at: folder)
    }
}
