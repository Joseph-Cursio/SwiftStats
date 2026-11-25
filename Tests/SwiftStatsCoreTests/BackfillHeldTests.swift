import Foundation
@testable import SwiftStatsCore
import Testing

/// `backfill --rerun` over snapshots holding results a backfill never
/// collects (M5–M7, PRD §7.13, design §9.6): coverage, mutation results
/// and T1 results keep their snapshot, which isn't even rescanned, with or
/// without tools.
@Suite("Backfill keeping held results")
struct BackfillHeldTests {
    /// A plan picking every `step`th commit.
    private static func every(_ step: Int, rerun: Bool, withTools: Bool) -> BackfillPlan {
        BackfillPlan(selection: .every(step), since: nil, maximumCommits: nil, rerun: rerun, withTools: withTools)
    }

    /// Backfills with `plan`.
    private static func backfill(_ workspace: SnapshotWorkspace, _ plan: BackfillPlan) throws -> [BackfillStep] {
        try workspace.backfill(plan) { _ in
            // Progress isn't checked here.
        }
    }

    /// A function `one` returning `value`.
    private static func one(_ value: Int) -> String {
        "func one() -> Int {\n    \(value)\n}\n"
    }

    @Test("--rerun, even with tools, keeps a snapshot holding coverage without rescanning it, history or not")
    func rerunKeepsHeldCoverage() throws {
        let repository = try HistoryRepository()
        defer { repository.remove() }
        try repository.write(["Sources/Lib/One.swift": Self.one(1)])
        try repository.commit("One", day: 0)
        let workspace = try repository.workspace()
        let plain = try workspace.scanWorkingTree(history: .skipped("test")).snapshot
        let covered = CoverageSnapshots.replacing(
            plain,
            git: plain.info.git,
            coverage: try CoverageSamples.stored(),
            run: CoverageSnapshots.ran(options: ["map: " + CoverageMapper.rule, "links: " + CoverageTestLinks.rule])
        )
        let id = try workspace.save(covered, drop: []).id
        // Fails any export scan, which would make the step fail, not keep it.
        let other = try SnapshotWorkspace(
            packageRoot: repository.root,
            configurationFile: nil,
            storeOverride: nil,
            build: SwiftStatsBuild(identity: "inputs:other", label: nil),
            describer: RootOnlyDescriber(root: repository.root),
            tools: SnapshotHarness.noTools
        )

        let steps = try Self.backfill(other, Self.every(1, rerun: true, withTools: true))

        #expect(steps.map(\.action) == [.kept])
        #expect(steps.first?.note == "its snapshot holds coverage; rescan it with `swiftstats scan`")
        #expect(try other.store.snapshotID(package: "Probe", packagePath: "", commit: steps[0].commit, isDirty: false)
            == id)
        #expect(try other.store.load(id: id).coverage?.report == covered.report.coverage)
    }

    @Test("--rerun, even with tools, keeps a snapshot holding mutation results without rescanning it")
    func rerunKeepsHeldMutation() throws {
        let repository = try HistoryRepository()
        defer { repository.remove() }
        try repository.write(["Sources/Lib/One.swift": Self.one(1)])
        try repository.commit("One", day: 0)
        let workspace = try repository.workspace()
        let plain = try workspace.scanWorkingTree(history: .skipped("test")).snapshot
        let mutated = MutationSnapshots.replacing(
            plain,
            git: plain.info.git,
            mutation: try MutationCarrySamples.results(),
            run: MutationSnapshots.ran(identity: MutationSnapshots.identity)
        )
        let id = try workspace.save(mutated, drop: []).id
        // Fails any export scan, which would make the step fail, not keep it.
        let other = try SnapshotWorkspace(
            packageRoot: repository.root,
            configurationFile: nil,
            storeOverride: nil,
            build: SwiftStatsBuild(identity: "inputs:other", label: nil),
            describer: RootOnlyDescriber(root: repository.root),
            tools: SnapshotHarness.noTools
        )

        let steps = try Self.backfill(other, Self.every(1, rerun: true, withTools: true))

        #expect(steps.map(\.action) == [.kept])
        #expect(steps.first?.note == "its snapshot holds swiftmutator; rescan it with `swiftstats scan`")
        #expect(try other.store.snapshotID(package: "Probe", packagePath: "", commit: steps[0].commit, isDirty: false)
            == id)
        #expect(try other.store.load(id: id).mutation?.report == mutated.report.mutation)
    }

    @Test("--rerun, even with tools, keeps a snapshot holding T1 results without rescanning it")
    func rerunKeepsHeldIndex() throws {
        let repository = try HistoryRepository()
        defer { repository.remove() }
        try repository.write(["Sources/Lib/One.swift": Self.one(1)])
        try repository.commit("One", day: 0)
        let workspace = try repository.workspace()
        let plain = try workspace.scanWorkingTree(history: .skipped("test")).snapshot
        let indexed = try IndexStoreSamples.indexed(plain)
        let id = try workspace.save(indexed, drop: []).id
        // Fails any export scan, which would make the step fail, not keep it.
        let other = try SnapshotWorkspace(
            packageRoot: repository.root,
            configurationFile: nil,
            storeOverride: nil,
            build: SwiftStatsBuild(identity: "inputs:other", label: nil),
            describer: RootOnlyDescriber(root: repository.root),
            tools: SnapshotHarness.noTools
        )

        let steps = try Self.backfill(other, Self.every(1, rerun: true, withTools: true))

        #expect(steps.map(\.action) == [.kept])
        #expect(steps.first?.note == "its snapshot holds build, index, periphery; rescan it with `swiftstats scan`")
        #expect(try other.store.snapshotID(package: "Probe", packagePath: "", commit: steps[0].commit, isDirty: false)
            == id)
        #expect(try other.store.load(id: id).index?.report == indexed.report.index)
    }
}
