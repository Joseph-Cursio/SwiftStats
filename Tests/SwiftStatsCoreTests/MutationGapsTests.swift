import Foundation
@testable import SwiftStatsCore
import Testing

/// Mutation results that leave files out in `diff` and `trend` (M6,
/// review finding 9): a `--since` merge drops the rows of the changed files
/// it leaves unlisted or unresolved, while their scopes' counts are still
/// stored, so those counts fall by mutants no run looked at. A side with
/// such files, or otherwise incomplete results, has its mutation counts
/// above records left out of the diff, with a warning saying so, and of
/// the trend, its break saying why; the scores and the records' own
/// figures still compare.
@Suite("Mutation gaps in diff and trend")
struct MutationGapsTests {
    /// The fixture's executable helper, whose two mutants are killed.
    private static let helper = "Exe::func exeHelper(_: Int) -> Int"

    /// The warning a diff gives when `sides` (`the older snapshot (…)`)
    /// leave files out.
    private static func warning(_ sides: String) -> String {
        "swiftmutator: mutation counts above records aren't compared, since files' mutants are missing from the "
            + "results of \(sides); scores still are"
    }

    /// `report` as a merge's results whose changed file `path` is
    /// unresolved: its rows dropped, the results incomplete.
    private static func unresolving(_ path: String, in report: MutationReport) -> MutationReport {
        MutationReport(
            collectedAt: report.collectedAt,
            complete: false,
            listsNotCovered: report.listsNotCovered,
            mode: .since,
            base: MutationSource(commit: "c0", collectedAt: report.collectedAt),
            files: report.files.map { file in
                guard file.path == path else {
                    return file
                }
                return MutationFile(
                    path: file.path,
                    sha256: file.sha256,
                    disposition: .unresolved,
                    changedTest: false,
                    run: nil
                )
            },
            runs: report.runs,
            suspectTests: report.suspectTests,
            mutants: report.mutants.filter { $0.path != path }
        )
    }

    @Test("""
        a merge leaving a changed file unlisted gives no better not-covered count, nor any other mutation count \
        above records, but a warning saying why; its score still compares; and the trend of a count has no value \
        there, its break saying why
        """)
    func unlistedMerge() throws {
        let harness = try SinceHarness()
        defer { harness.remove() }
        let base = try harness.base()
        let since = try harness.since("since-unlisted", acting: "since-unlisted")
        let older = try harness.workspace.store.load(id: base.id)
        let newer = try harness.workspace.store.load(id: since.id)

        let diff = SnapshotDiff.diff(older, newer)
        let notCovered = try harness.workspace.trend(metric: "mutation.notCovered", scope: .module, name: "Core")
        let score = try harness.workspace.trend(metric: "mutation.score.percent", scope: .module, name: "Core")

        let stored = { (snapshot: StoredSnapshot) in
            snapshot.rollups.first { $0.scope == .module && $0.name == "Core" && $0.metric == "mutation.notCovered" }
        }
        #expect(stored(older)?.value == 7 && stored(newer)?.value == 0)
        #expect(diff.collectors.first { $0.name == MutationAdapter.name }?.outcome == .compared)
        #expect(diff.rollups.contains { MutationGaps.affects($0.delta.metric) } == false)
        #expect(diff.warnings == [Self.warning("the newer snapshot (1 unlisted)")])
        let markdown = MarkdownDiff.render(diff)
        #expect(markdown.contains("## Warnings\n\n- \(Self.warning("the newer snapshot (1 unlisted)"))"))
        #expect(markdown.contains("mutation.notCovered") == false)
        #expect(notCovered.points.map(\.value) == [7, nil])
        #expect(notCovered.points.last?.breakReason == "swiftmutator: files' mutants are missing from this "
            + "snapshot's results (1 unlisted), so its count isn't compared")
        #expect(score.points.allSatisfy { $0.value != nil && $0.breakReason == nil })
    }

    @Test("""
        an older side whose results are incomplete, a changed file unresolved, gives no mutation count deltas above \
        records, but a warning naming it; its score left out reads as missing, and records' figures still compare
        """)
    func unresolvedOlderSide() throws {
        let full = try MutationSnapshots.snapshot(commit: "c1")
        let report = try #require(full.report.mutation)
        let helperFile = try #require(report.mutants.first { $0.owner == Self.helper }?.path)
        let dropped = try #require(report.files.first { file in
            file.path != helperFile && report.mutants.contains { $0.path == file.path && $0.verdict == .survived }
        })
        let incomplete = Self.unresolving(dropped.path, in: report)
        let old = MutationSnapshots.replacing(
            full,
            git: SnapshotHarness.git(commit: "c1"),
            mutation: incomplete,
            run: MutationSnapshots.ran(identity: MutationSnapshots.identity)
        )
        let survivor = try MutationSnapshots.changing(report, mode: .full, base: nil) { mutant in
            guard mutant.owner == Self.helper, mutant.verdict == .killed else {
                return mutant
            }
            return try MutationSnapshots.changing(mutant, verdict: .survived, carried: false)
        }
        let new = MutationSnapshots.replacing(
            full,
            git: SnapshotHarness.git(commit: "c2"),
            mutation: survivor,
            run: MutationSnapshots.ran(identity: MutationSnapshots.identity)
        )
        let directory = try SnapshotHarness.temporaryDirectory("MutationGaps")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SnapshotStore(at: directory.appendingPathComponent("stats.sqlite"))

        let diff = SnapshotDiff.diff(try store.load(id: try store.save(old)), try store.load(id: try store.save(new)))

        #expect(diff.rollups.contains { MutationGaps.affects($0.delta.metric) } == false)
        #expect(diff.warnings == [Self.warning("the older snapshot (1 unresolved)")])
        let production = diff.rollups.first { $0.name == "production" && $0.delta.metric == "mutation.score.percent" }
        #expect(production?.delta.before == nil && production?.delta.after != nil)
        #expect(production?.delta.verdict == .neutral)
        #expect(diff.functions.contains { $0.key == Self.helper })
        #expect(MutationGaps(incomplete)?.description == "1 unresolved")
        #expect(MutationGaps(unlisted: 0, unresolved: 0, complete: false).description == "mutants without a result")
        #expect(MutationGaps(report) == nil)
    }
}
