import Foundation
@testable import SwiftStatsCore
import Testing

/// Mutation results in `diff` (M6, design §8): matched records' mutation
/// figures and the mutation roll-ups change only when SwiftMutator's
/// results compare; a record with no mutant on a side is not collected
/// there, never 0; another SwiftMutator build doesn't compare; and where a
/// side's results came from is a fact that never makes a diff non-empty.
@Suite("Mutation diff")
struct MutationDiffTests {
    /// The fixture's executable helper, whose two mutants are killed.
    private static let helper = "Exe::func exeHelper(_: Int) -> Int"

    /// `old` and `new` stored in a fresh store, read back and diffed.
    private static func diff(_ old: ScannedSnapshot, _ new: ScannedSnapshot) throws -> SnapshotDiffReport {
        let directory = try SnapshotHarness.temporaryDirectory("MutationDiff")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SnapshotStore(at: directory.appendingPathComponent("stats.sqlite"))
        let older = try store.load(id: try store.save(old))
        let newer = try store.load(id: try store.save(new))
        return SnapshotDiff.diff(older, newer)
    }

    /// `snapshot`'s results with the helper's first killed mutant made a
    /// survivor.
    private static func helperSurvives(_ snapshot: ScannedSnapshot) throws -> MutationReport {
        let report = try #require(snapshot.report.mutation)
        let first = try #require(report.mutants.first { $0.owner == helper && $0.verdict == .killed })
        return try MutationSnapshots.changing(report, mode: .full, base: nil) { mutant in
            guard mutant.key == first.key else {
                return mutant
            }
            return try MutationSnapshots.changing(mutant, verdict: .survived, carried: false)
        }
    }

    /// `snapshot` at commit `commit` holding `mutation`, made by build
    /// `identity`.
    private static func replacing(
        _ snapshot: ScannedSnapshot,
        commit: String,
        mutation: MutationReport?,
        identity: String = MutationSnapshots.identity
    ) -> ScannedSnapshot {
        MutationSnapshots.replacing(
            snapshot,
            git: SnapshotHarness.git(commit: commit),
            mutation: mutation,
            run: mutation == nil ? MutationSnapshots.skipped : MutationSnapshots.ran(identity: identity)
        )
    }

    @Test("""
        when SwiftMutator's results compare, a matched record's mutation score, function score and unkilled \
        mutants that moved are deltas, scores better higher and unkilled lower; mutation roll-up deltas come from \
        swiftmutator; and the diff's schema is 4
        """)
    func compared() throws {
        let old = try MutationSnapshots.snapshot(commit: "c1")
        let new = Self.replacing(old, commit: "c2", mutation: try Self.helperSurvives(old))

        let diff = try Self.diff(old, new)

        #expect(diff.schemaVersion == 4)
        #expect(diff.collectors.first { $0.name == MutationAdapter.name }?.outcome == .compared)
        let helperDelta = try #require(diff.functions.first { $0.key == Self.helper })
        #expect(helperDelta.metrics == [
            MetricDelta(metric: "mutation.functionScore.percent", before: 100, after: 50),
            MetricDelta(metric: "mutation.score.percent", before: 100, after: 50),
            MetricDelta(metric: "mutation.unkilled", before: 0, after: 1)
        ])
        #expect(helperDelta.metrics.allSatisfy { $0.verdict == .worse })
        #expect(diff.functions.count == 1)
        let rollups = diff.rollups.filter { $0.scope == .module && $0.name == "Exe" }
        #expect(rollups.allSatisfy { $0.collector == MutationAdapter.name })
        let byMetric = Dictionary(rollups.map { ($0.delta.metric, $0.delta) }) { first, _ in first }
        let score = MetricDelta(metric: "mutation.score.percent", before: 100, after: 50)
        #expect(byMetric["mutation.score.percent"] == score)
        #expect(byMetric["mutation.score.percent"]?.verdict == .worse)
        #expect(byMetric["mutation.survived"]?.verdict == .worse)
        #expect(byMetric["mutation.killed"]?.verdict == .neutral)
        let production = try #require(diff.rollups.first { delta in
            delta.name == "production" && delta.delta.metric == "mutation.score.percent"
        })
        #expect(production.delta.before == 93.55 && production.delta.after == 90.32)
        #expect(diff.older.mutation?.mode == .full && diff.newer.mutation?.carried == 0)
        #expect(diff.isEmpty == false)
        let markdown = MarkdownDiff.render(diff)
        #expect(markdown.contains("| \(Self.helper) | mutation.score.percent | 100 | 50 |"))
        #expect(markdown.contains("Mutation results:") == false)
    }

    @Test("""
        a record with no mutant on one side is not collected there, never 0; a function only code no test ran \
        reaches has a function score of 0 and no mutation score; and a side without results gives no mutation deltas
        """)
    func notCollected() throws {
        let old = try MutationSnapshots.snapshot(commit: "c1")
        let report = try #require(old.report.mutation)
        let withoutHelper = MutationSnapshots.changing(report, mode: .full, base: nil) { mutant in
            mutant.owner == Self.helper ? nil : mutant
        }
        let gone = Self.replacing(old, commit: "c2", mutation: withoutHelper)
        let plain = Self.replacing(old, commit: "c3", mutation: nil)

        let removed = try Self.diff(old, gone)
        let unscanned = try Self.diff(old, plain)

        let helperDelta = try #require(removed.functions.first { $0.key == Self.helper })
        #expect(helperDelta.metrics == [
            MetricDelta(metric: "mutation.functionScore.percent", before: 100, after: nil),
            MetricDelta(metric: "mutation.score.percent", before: 100, after: nil),
            MetricDelta(metric: "mutation.scored", before: 2, after: nil),
            MetricDelta(metric: "mutation.unkilled", before: 0, after: nil)
        ])
        #expect(removed.functions.count == 1)
        let metrics = MutationMetrics(
            old: StoredMutation(report: report),
            new: nil,
            compared: [MutationAdapter.name]
        )
        let untested = try #require(report.records.first { $0.counts.notCovered > 0 && $0.counts.killed == 0 })
        #expect(metrics.old[untested.key]?[MutationMetrics.score] == nil)
        #expect(metrics.old[untested.key]?[MutationMetrics.functionScore] == 0)
        #expect(metrics.old[untested.key]?[MutationMetrics.unkilled] == Double(untested.counts.notCovered))
        #expect(metrics.new.isEmpty)
        #expect(unscanned.collectors.first { $0.name == MutationAdapter.name }?.outcome == .notCollected)
        #expect(unscanned.functions.allSatisfy { $0.metrics.allSatisfy { $0.metric.hasPrefix("mutation.") == false } })
        #expect(unscanned.rollups.allSatisfy { $0.delta.metric.hasPrefix("mutation.") == false })
        #expect(unscanned.newer.mutation == nil && unscanned.older.mutation?.mutants == 43)
    }

    @Test("results from another SwiftMutator build don't compare, so no mutation delta appears")
    func otherBuild() throws {
        let old = try MutationSnapshots.snapshot(commit: "c1")
        let new = Self.replacing(old, commit: "c2", mutation: try Self.helperSurvives(old), identity: "sha256:other")

        let diff = try Self.diff(old, new)

        let comparison = try #require(diff.collectors.first { $0.name == MutationAdapter.name })
        #expect(comparison.outcome == .notComparable && comparison.reason == "different builds")
        #expect(diff.functions.isEmpty)
        #expect(diff.rollups.allSatisfy { $0.delta.metric.hasPrefix("mutation.") == false })
    }

    @Test("""
        a merged side's results compare like any others; where they came from is listed as a fact, never a \
        change, so equal verdicts give an empty diff
        """)
    func mergedSide() throws {
        let old = try MutationSnapshots.snapshot(commit: "c1")
        let report = try #require(old.report.mutation)
        let base = MutationSource(commit: "c1aaaaaaaaaaaaaa", collectedAt: report.collectedAt)
        let merged = try MutationSnapshots.changing(report, mode: .since, base: base) { mutant in
            try MutationSnapshots.changing(mutant, verdict: mutant.verdict, carried: true)
        }
        let new = Self.replacing(old, commit: "c2", mutation: merged)

        let diff = try Self.diff(old, new)

        #expect(diff.collectors.first { $0.name == MutationAdapter.name }?.outcome == .compared)
        #expect(diff.newer.mutation?.mode == .since && diff.newer.mutation?.base == base)
        #expect(diff.newer.mutation?.carried == 43 && diff.newer.mutation?.mutants == 43)
        #expect(diff.newer.mutation?.runs.map(\.commit) == report.runs.map(\.commit))
        #expect(diff.isEmpty)
        #expect(MarkdownDiff.render(diff).contains("""
            No changes.

            Mutation results: older a full run; newer merged with the results of c1aaaaaaaa (43 of 43 mutants carried).
            """))
    }

    @Test("""
        mutation scores are better higher, unkilled, survived, no-coverage, timed-out, not-covered and unmapped \
        mutants better lower, other mutation counts neutral, and none of them reads a missing value as 0
        """)
    func directions() {
        for higher in ["mutation.score.percent", "mutation.functionScore.percent"] {
            #expect(MetricDirection.of(higher) == .higherIsBetter, "\(higher)")
        }
        let lower = [
            "mutation.unkilled", "mutation.survived", "mutation.noCoverage", "mutation.timedOut",
            "mutation.notCovered", "mutation.unmapped"
        ]
        for name in lower {
            #expect(MetricDirection.of(name) == .lowerIsBetter, "\(name)")
        }
        let neutral = [
            "mutation.killed", "mutation.crashKills", "mutation.buildErrors", "mutation.scored",
            "mutation.score.killed", "mutation.score.scored", "mutation.suspectOnly", "mutation.carried",
            "mutation.functions.notCoveredOnly"
        ]
        for name in neutral {
            #expect(MetricDirection.of(name) == .neutral, "\(name)")
        }
        for name in lower + neutral {
            #expect(CountedMetrics.value(nil, metric: name) == nil, "\(name)")
        }
    }
}
