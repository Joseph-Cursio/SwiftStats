import Foundation
@testable import SwiftStatsCore
import Testing

/// M6's per-function signals on the Mutation fixture end to end (design
/// §11): its copy scanned with coverage through a `FakeToolchain` serving
/// the fixture's recorded coverage run, given its recorded SwiftMutator
/// run mapped as a scan maps it, stored and read back. `Core.clamp`, whose
/// tests run every line and check almost nothing, is weak tests' row;
/// `Extras.unused` and `Extras.normalizedB`, which no test runs, in a
/// module with little test code, are genuinely under-tested's, while
/// `Core.neverCalled`, also run by no test, is counted because `Core`'s
/// test code isn't low.
@Suite("Mutation signals on the fixture")
struct MutationSignalFixtureTests {
    /// The fixture's `clamp`.
    static let clamp = "Core::func clamp(_: Int, low: Int, high: Int) -> Int"
    /// The fixture's `unused`.
    static let unused = "Extras::func unused(_: Int, _: Int) -> Int"
    /// The fixture's `normalizedB`.
    static let normalizedB = "Extras::func normalizedB(_: [Int], log: inout[Int]) -> [Int]"

    /// The fixture scanned with its recorded coverage and mutation runs,
    /// stored and read back.
    private static func stored() throws -> StoredSnapshot {
        let recorded = MutationFixture.directory.appendingPathComponent("Recorded")
        let toolchain = try FakeToolchain.make(FakeToolchain.recorded(in: recorded))
        defer { toolchain.remove() }
        let package = try TemporaryPackage([:], targets: MappingHarness.mutationTargets)
        defer { package.remove() }
        for part in ["Sources", "Tests"] {
            try FileManager.default.copyItem(
                at: MutationFixture.directory.appendingPathComponent(part),
                to: package.root.appendingPathComponent(part)
            )
        }
        try "collectors:\n  coverage:\n    path: \(toolchain.proxy.path)\n".write(
            to: package.root.appendingPathComponent(SwiftStatsConfiguration.fileName),
            atomically: true,
            encoding: .utf8
        )
        let scanned = try SnapshotScanner(
            scanner: PackageScanner(describer: package.describer, tools: SnapshotHarness.noTools),
            build: SnapshotHarness.build
        )
        .scan(
            packageAt: package.root,
            configurationFile: StoreLocation.localConfiguration(packageRoot: package.root),
            git: SnapshotHarness.git(commit: "c1"),
            toolchain: SnapshotHarness.toolchain,
            date: SnapshotHarness.date,
            tiers: .coverage
        )
        let (results, suspects) = try MappingHarness.fullRun(of: MutationFixture.directory)
        let mapping = try MappingHarness(package)
        let snapshot = MutationSnapshots.replacing(
            scanned,
            git: scanned.info.git,
            mutation: MutationRows.normalized(mapping.report(results, suspects: suspects)),
            run: MutationSnapshots.ran(identity: MutationSnapshots.identity)
        )
        let directory = try SnapshotHarness.temporaryDirectory("MutationSignalFixture")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SnapshotStore(at: directory.appendingPathComponent("stats.sqlite"))
        return try store.load(id: try store.save(snapshot))
    }

    @Test("""
        weak tests lists clamp, whose covered lines hide surviving mutants, and genuinely under-tested lists \
        Extras' untested functions, not Core's, each funnel summing
        """)
    func rows() throws {
        let snapshot = try Self.stored()
        let weak = try MutationSignalHarness.signal(.weakTests, of: snapshot)
        let under = try MutationSignalHarness.signal(.genuinelyUnderTested, of: snapshot)

        #expect(snapshot.coverage != nil && snapshot.mutation?.report.listsNotCovered == true)
        #expect(weak.leftOut == nil && under.leftOut == nil)
        #expect(weak.items.map(\.subject) == [Self.clamp])
        let listed = try #require(weak.items.first)
        #expect(listed.file == "Sources/Core/Bounds.swift" && listed.line == 4)
        #expect(listed.coverage?.lines.map { $0.covered == $0.total } == true)
        #expect(under.items.map(\.subject) == [Self.normalizedB, Self.unused])
        #expect(under.items.map { $0.ratio?.module } == ["Extras", "Extras"])
        #expect(under.rule.contains("2 production modules = 1 with low test code + 1 without; 1 = 0 with no test "
            + "code + 1 below the project's ratio"))
        #expect(weak.items.map(\.score) == [9] && under.items.map(\.score) == [7, 7])
        #expect(listed.mutation?.functionScore == MutationScore(killed: 0, scored: 9))
        #expect(listed.mutation?.survivors.count == 9 && listed.mutation?.suspects.isEmpty == true)
        #expect(under.items.map { $0.mutation?.counts.notCovered } == [7, 7])
        #expect(weak.rule.hasSuffix(
            "8 production functions = 8 with coverage data + 0 without; 8 = 7 with at least 3 scored mutants + 1 "
                + "with fewer + 0 with only build errors + 0 with none + 0 without results (0 unresolved, 0 unlisted); "
                + "7 = 4 at least 80% covered + 3 less; 4 = 1 listed + 0 under 50% only through code no test ran + 3 "
                + "not under 50% and with no suspect-only kill; 1 = 1 by score + 0 by suspect-only kills alone; "
                + "suspects judged for 0 of 22 kills by a failing test among the 4 (a run whose kills name tests in "
                + "fewer than 10 files judges only control-run and flaky suspects); " + WeakTests.killingTestLimits
        ))
        #expect(under.rule.hasSuffix(
            "; 7 = 3 at most 20% covered + 4 more; 3 = 2 listed + 1 under 20% in a module whose test code isn't low "
                + "+ 0 not under 20%"
        ))
        #expect(MutationSignalHarness.unbalanced(weak.rule).isEmpty)
        #expect(MutationSignalHarness.unbalanced(under.rule).isEmpty)
    }
}
