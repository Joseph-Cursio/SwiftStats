import Foundation
@testable import SwiftStatsCore
import Testing

/// Mutation roll-ups in a scan's roll-ups (M6, design §4): only production
/// modules and the production part take them, their numbers are named
/// under `mutation`, the counts beside the score, they come from the
/// SwiftMutator collector, and a percentage left out over incomplete
/// results is no metric.
@Suite("Mutation roll-up metrics")
struct MutationRollupMetricsTests {
    /// The production modules and part of the Coverage fixture's scan.
    private static let coverageScopes: Set<String> = ["Exe", "Probe", "Unlinked", "production"]

    @Test("""
        a scan's roll-ups take the mutation results on production modules and the production part only, and the \
        numbers are named under mutation, counts beside the score, and come from the SwiftMutator collector
        """)
    func rollupsAndMetrics() throws {
        let harness = try MappingHarness.coverage()
        defer { harness.remove() }
        let (results, suspects) = try MappingHarness.coverageRun()
        let report = harness.report(results, suspects: suspects)
        let scanned = try PackageScanner(describer: harness.package.describer, tools: SnapshotHarness.noTools)
            .scan(packageAt: harness.package.root)

        let builder = MutationRollupBuilder(
            targets: scanned.targets,
            records: scanned.records,
            files: scanned.files,
            report: report
        )
        let rolled = builder.rollups(scanned.rollups)

        #expect(scanned.rollups.allSatisfy { $0.mutation == nil })
        for rollup in rolled {
            #expect((rollup.mutation != nil) == Self.coverageScopes.contains(rollup.name), "\(rollup.name)")
        }
        let production = try #require(rolled.first { $0.scope == .project && $0.name == "production" })
        #expect(production.mutation == builder.rollup(of: ["Exe", "Probe", "Unlinked"], isProject: true))
        #expect(rolled.first { $0.name == "Probe" }?.mutation == builder.rollup(of: ["Probe"], isProject: false))
        let numbers = try RollupMetrics.metrics(of: production).filter { $0.path.hasPrefix("mutation.") }
        #expect(numbers.allSatisfy { $0.collector == MutationAdapter.name })
        let values = Dictionary(numbers.map { ($0.path, $0.value) }) { first, _ in first }
        #expect(values["mutation.killed"] == 29 && values["mutation.notCovered"] == 10)
        #expect(values["mutation.score.percent"] == 93.55 && values["mutation.score.scored"] == 31)
        #expect(values["mutation.unmapped"] == 1 && values["mutation.dropped"] == 1)
        #expect(values["mutation.functions.scored"] == 22 && values["mutation.judgedKills"] == 29)
        #expect(numbers.contains { $0.path.hasPrefix("mutation.counts.") } == false)
        let probe = try #require(rolled.first { $0.name == "Probe" })
        let probeNumbers = try RollupMetrics.metrics(of: probe).map(\.path)
        #expect(probeNumbers.contains("mutation.unmapped") == false)
        #expect(probeNumbers.contains("mutation.dropped") == false)
        #expect(try JSONDecoder().decode(Rollup.self, from: JSONEncoder().encode(production)) == production)
    }

    @Test("a roll-up's score over incomplete results leaves its percentage out of the metrics, keeping the counts")
    func incompleteMetrics() throws {
        let harness = try MappingHarness.coverage()
        defer { harness.remove() }
        let (results, suspects) = try MappingHarness.coverageRun()
        let full = harness.report(results, suspects: suspects)
        let incomplete = MappingHarness.rebuilt(full, complete: false, files: full.files, mutants: full.mutants)

        let rollup = harness.rollupBuilder(incomplete).rollup(of: ["Probe"], isProject: false)
        let scanned = try PackageScanner(describer: harness.package.describer, tools: SnapshotHarness.noTools)
            .scan(packageAt: harness.package.root)
        let probe = try #require(scanned.rollups.first { $0.name == "Probe" }).with(mutation: rollup)
        let paths = try RollupMetrics.metrics(of: probe).map(\.path)

        #expect(rollup.counts == harness.rollupBuilder(full).rollup(of: ["Probe"], isProject: false).counts)
        #expect(paths.contains("mutation.score.scored") && paths.contains("mutation.score.percent") == false)
    }
}
