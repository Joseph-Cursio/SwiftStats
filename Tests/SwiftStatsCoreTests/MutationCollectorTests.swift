import Foundation
@testable import SwiftStatsCore
import Testing

/// The SwiftMutator collector's place in a scan (M6, design §1): every
/// scan lists its status, it runs only when the scan asks for it, a
/// requested run is skipped for the usual reasons, `--since` and
/// `--resume` are refused before anything runs until they are built,
/// `--drop-mutation` lets no coverage go, and it compares only when
/// SwiftStats' own build does.
@Suite("Mutation collector")
struct MutationCollectorTests {
    private static let files = ["Sources/Lib/Lib.swift": "public func one() -> Int { 1 }\n"]

    /// The swiftmutator status of `files` (with `Self.files`) scanned with
    /// no tools on PATH, the tools skipped for `toolSkipReason` when given,
    /// making `request`.
    private static func status(
        _ files: [String: String],
        toolSkipReason: String?,
        request: MutationRequest?
    ) throws -> CollectorStatus? {
        let package = try TemporaryPackage(Self.files.merging(files) { $1 })
        defer { package.remove() }
        let scanner = PackageScanner(
            describer: package.describer,
            tools: SnapshotHarness.noTools,
            toolSkipReason: toolSkipReason
        )
        return try scanner.scan(packageAt: package.root, tiers: RequestedTiers(mutation: request)).collectors
            .first { $0.name == MutationAdapter.name }
    }

    /// A workspace on a package holding `Self.files` and `files`, storing
    /// in the package's default store.
    private static func workspace(_ files: [String: String]) throws -> (TemporaryPackage, SnapshotWorkspace) {
        let package = try TemporaryPackage(Self.files.merging(files) { $1 })
        let workspace = try SnapshotWorkspace(
            packageRoot: package.root,
            configurationFile: nil,
            storeOverride: nil,
            build: SnapshotHarness.build,
            describer: package.describer,
            tools: SnapshotHarness.noTools
        )
        return (package, workspace)
    }

    /// A snapshot's record of a run of `name`: `ran` with `identity`.
    private static func run(_ name: String, identity: String) -> CollectorRunInfo {
        CollectorRunInfo(
            name: name,
            state: .ran,
            reason: nil,
            version: "0.1.0",
            identity: identity,
            identityLabel: nil,
            options: ["coverage: on"],
            durationMilliseconds: 1
        )
    }

    /// A snapshot whose SwiftStats build is `build` and whose SwiftMutator
    /// run is identified by `mutator`.
    private static func info(build: String, mutator: String) -> SnapshotInfo {
        SnapshotInfo(
            package: "Probe",
            git: SnapshotHarness.git(commit: "c1"),
            date: "2027-01-15T08:00:00Z",
            toolchain: SnapshotHarness.toolchain,
            collectors: [run(MutationAdapter.name, identity: mutator), run(SwiftStatsCollector.name, identity: build)]
        )
    }

    @Test("a scan that doesn't ask for mutation testing lists it skipped, saying how to run it, even in a backfill")
    func notRequested() throws {
        let plain = try Self.status([:], toolSkipReason: nil, request: nil)
        let backfill = try Self.status([:], toolSkipReason: "backfill runs SwiftStats only", request: nil)
        let disabled = try Self.status(
            [".swiftstats.yml": "collectors:\n  swiftmutator:\n    enabled: false\n"],
            toolSkipReason: nil,
            request: nil
        )

        let expected = CollectorStatus(
            name: "swiftmutator",
            state: .skipped,
            version: nil,
            reason: "not requested; scan --mutation runs it",
            options: []
        )
        #expect(plain == expected)
        #expect(backfill == expected)
        #expect(disabled == expected)
    }

    @Test("""
        asked for, mutation testing is skipped when collectors.swiftmutator.enabled is false, when no \
        swift-mutator is found, when its path isn't executable, and when the tools are skipped, each saying why
        """)
    func requestedSkips() throws {
        let disabled = try Self.status(
            [".swiftstats.yml": "collectors:\n  swiftmutator:\n    enabled: false\n"],
            toolSkipReason: nil,
            request: .full
        )
        let missing = try Self.status([:], toolSkipReason: nil, request: .full)
        let badPath = try Self.status(
            [".swiftstats.yml": "collectors:\n  swiftmutator:\n    path: tools/swift-mutator\n"],
            toolSkipReason: nil,
            request: .full
        )
        let toolsSkipped = try Self.status([:], toolSkipReason: "backfill runs SwiftStats only", request: .full)

        #expect(disabled?.reason == "disabled by collectors.swiftmutator.enabled")
        #expect(missing?.reason == "`swift-mutator` not found on PATH; set collectors.swiftmutator.path")
        #expect(badPath?.reason == "collectors.swiftmutator.path tools/swift-mutator is not an executable file")
        #expect(toolsSkipped?.reason == "backfill runs SwiftStats only")
        #expect([disabled, missing, badPath, toolsSkipped].allSatisfy { $0?.state == .skipped })
    }

    @Test("scanWorkingTree passes --mutation to the scan, and a skipped mutation run has no build identity")
    func workspaceThreading() throws {
        let (package, workspace) = try Self.workspace(
            [".swiftstats.yml": "collectors:\n  swiftmutator:\n    enabled: false\n"]
        )
        defer { package.remove() }

        let asked = try workspace.scanWorkingTree(history: .skipped("test"), tiers: RequestedTiers(mutation: .full))
        let storedRun = try workspace.store.info(id: asked.id).collectors.first { $0.name == MutationAdapter.name }
        let plain = try workspace.scanWorkingTree(history: .skipped("test"))

        let askedRun = asked.snapshot.info.collectors.first { $0.name == MutationAdapter.name }
        let plainRun = plain.snapshot.info.collectors.first { $0.name == MutationAdapter.name }
        #expect(askedRun?.reason == "disabled by collectors.swiftmutator.enabled")
        #expect(plainRun?.reason == "not requested; scan --mutation runs it")
        #expect(askedRun?.identity == nil && plainRun?.identity == nil)
        #expect(storedRun == askedRun)
    }

    @Test("""
        scan --mutation --since is refused until built, and --resume with no run pending, before anything is \
        scanned or stored
        """)
    func sinceAndResumeRefused() throws {
        let (package, workspace) = try Self.workspace([:])
        defer { package.remove() }
        let stored = try workspace.scanWorkingTree(history: .skipped("test")).id
        try "public func one() -> Int { 1 }\npublic func two() -> Int { 2 }\n".write(
            to: package.root.appendingPathComponent("Sources/Lib/Lib.swift"),
            atomically: true,
            encoding: .utf8
        )

        let since = ScanError.mutationRefused("--since is not built yet; run scan --mutation for a full run")
        let resume = ScanError.mutationRefused("no interrupted or failed SwiftMutator run to resume")
        #expect(throws: since) {
            try workspace.scanWorkingTree(tiers: RequestedTiers(mutation: .since("HEAD~1")))
        }
        #expect(throws: resume) {
            try workspace.scanWorkingTree(tiers: RequestedTiers(coverage: true, mutation: .resume))
        }
        #expect(since.description == "scan --mutation: --since is not built yet; run scan --mutation for a full run")
        let latest = try #require(try workspace.store.latestSnapshotID(package: "Probe", packagePath: ""))
        #expect(latest == stored)
        #expect(try workspace.store.report(id: latest).records.count == 1)
    }

    @Test("--drop-mutation alone lets no coverage go: held coverage too damaged to read still stops the rescan")
    func dropMutationKeepsCoverage() throws {
        let (package, workspace) = try CarrySamples.store()
        defer { package.remove() }
        let covered = try CarrySamples.covered(try CarrySamples.scan(git: CarrySamples.clean))
        let held = try workspace.save(covered, drop: [])
        try SnapshotHarness.sqlite(
            workspace.store.url,
            "UPDATE coverageLine SET lines = '1:5' WHERE snapshotId = \(held.id) AND file = 'Sources/Kit/Kit.swift'"
        )
        let rescan = try CarrySamples.scan(git: CarrySamples.clean, date: SnapshotHarness.date + CarrySamples.day)

        #expect(throws: StoreError.self) {
            try workspace.save(rescan, drop: .mutation)
        }
        #expect(try workspace.store.snapshotID(package: "Probe", packagePath: "", commit: "c1", isDirty: false)
            == held.id)
        let dropped = try workspace.save(rescan, drop: [.coverage, .mutation])

        #expect(try workspace.store.load(id: dropped.id).coverage == nil)
    }

    @Test("mutation results compare only when SwiftStats' own build does, since SwiftStats' own code maps them")
    func comparability() {
        let older = Self.info(build: "inputs:aaa", mutator: "sha256:aaa")
        let otherBuild = Self.info(build: "inputs:bbb", mutator: "sha256:aaa")
        let otherMutator = Self.info(build: "inputs:aaa", mutator: "sha256:bbb")

        let mutation = { (new: SnapshotInfo) in
            Comparability.compare(older, new).first { $0.name == MutationAdapter.name }
        }

        #expect(mutation(older)?.outcome == .compared)
        #expect(mutation(otherBuild)?.outcome == .notComparable)
        #expect(mutation(otherBuild)?.reason == "SwiftStats' build differs, and its own code maps the mutants")
        #expect(mutation(otherMutator)?.outcome == .notComparable)
        #expect(mutation(otherMutator)?.reason == "different builds")
    }
}
