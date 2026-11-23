import Foundation
@testable import SwiftStatsCore
import Testing

/// Mutation roll-ups (M6, design §4): each production module's and the
/// project's production part's mapped mutants by verdict, SwiftMutator's
/// score over them (its percentage null over incomplete results), how
/// many were carried, functions by mutation state, and the project's
/// unmapped and dropped mutants; and every mutant's score as
/// SwiftMutator's own report gives it.
@Suite("Mutation roll-ups")
struct MutationRollupTests {
    /// The Coverage fixture's production records outside its generated
    /// file that its recorded run placed no mutant on, checked by hand
    /// against the source: setters, observers and initialisers with
    /// nothing SwiftMutator mutates, the subscript's container (its
    /// accessors hold the mutants), the `#if !(DEBUG)` branch the build
    /// leaves out, `main.swift`'s top-level code, and the function of the
    /// target no test builds.
    private static let unplacedKeys = [
        "Exe::<top-level code> @ Sources/Exe/main.swift",
        "Probe::Box::init()",
        "Probe::Box::subscript(_: Int) -> Int",
        "Probe::Box::var both: Int { set }",
        "Probe::Box::var watched { willSet }",
        "Probe::Clamped::init(wrappedValue: Int)",
        "Probe::Clamped::var wrappedValue: Int { set }",
        "Probe::Counter::init()",
        "Probe::Settings::init()",
        "Probe::func mode() -> String #if !(DEBUG)",
        "Unlinked::func unlinked() -> Int"
    ]

    /// `mutant` with the JSON fields in `changes` set, or left out where
    /// the change is nil.
    private static func altered(_ mutant: Mutant, _ changes: [String: Any?]) throws -> Mutant {
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(mutant))
        var object = try #require(encoded as? [String: Any])
        for (key, value) in changes {
            object[key] = value
        }
        return try JSONDecoder().decode(Mutant.self, from: JSONSerialization.data(withJSONObject: object))
    }

    /// Counts with the verdicts given.
    private static func counts(
        killed: Int,
        crashKills: Int = 0,
        survived: Int = 0,
        notCovered: Int = 0,
        buildErrors: Int = 0,
        judgedKills: Int = 0
    ) -> MutationCounts {
        MutationCounts(
            killed: killed,
            crashKills: crashKills,
            survived: survived,
            noCoverage: 0,
            timedOut: 0,
            notCovered: notCovered,
            buildErrors: buildErrors,
            suspectOnly: 0,
            judgedKills: judgedKills
        )
    }

    @Test("""
        the Coverage fixture's modules count their records' and attachments' mutants, a generated record's too, \
        and their functions outside generated files by state; the production part adds the unmapped and dropped \
        mutants, test modules have none, and every mutant scores as SwiftMutator's report says
        """)
    func coverageFixture() throws {
        let harness = try MappingHarness.coverage()
        defer { harness.remove() }
        let (results, suspects) = try MappingHarness.coverageRun()
        let report = harness.report(results, suspects: suspects)
        let builder = harness.rollupBuilder(report)

        let probe = builder.rollup(of: ["Probe"], isProject: false)
        #expect(probe.counts == Self.counts(killed: 27, survived: 2, notCovered: 10, judgedKills: 27))
        #expect(probe.score == MutationScore(killed: 27, scored: 29) && probe.score.percent == 93.1)
        #expect(probe.functions.scored == 21 && probe.functions.notCoveredOnly == 6 && probe.functions.noMutant == 9)
        #expect(probe.carried == 0 && probe.unmapped == nil && probe.dropped == nil)
        let exe = builder.rollup(of: ["Exe"], isProject: false)
        #expect(exe.counts == Self.counts(killed: 2, judgedKills: 2) && exe.score.percent == 100)
        #expect(exe.functions.scored == 1 && exe.functions.noMutant == 1)
        let unlinked = builder.rollup(of: ["Unlinked"], isProject: false)
        #expect(unlinked.counts == Self.counts(killed: 0) && unlinked.score.percent == nil)
        #expect(unlinked.functions.scored == 0 && unlinked.functions.noMutant == 1)
        let production = builder.rollup(of: ["Exe", "Probe", "Unlinked"], isProject: true)
        #expect(production.counts == Self.counts(killed: 29, survived: 2, notCovered: 10, judgedKills: 29))
        #expect(production.score.percent == 93.55 && production.score.truncatedPercent == 93)
        #expect(production.unmapped == 1 && production.dropped == 1)
        #expect(production.functions.scored == 22 && production.functions.noMutant == 11)

        let recorded = try MutationFixture.data("report.json", of: "full", in: MutationFixture.coverageDirectory)
        let swiftMutator = try #require(try JSONSerialization.jsonObject(with: recorded) as? [String: Any])
        let every = report.everyMutant.counts
        let outcomes = try #require(swiftMutator["mutantsByOutcome"] as? [String: Int])
        #expect(MutationFigures(every).score.truncatedPercent == swiftMutator["globalMutationScore"] as? Int)
        #expect(outcomes == [
            "killed": every.killed, "survived": every.survived, "timedOut": every.timedOut,
            "buildErrors": every.buildErrors, "notCovered": every.noCoverage
        ])
    }

    @Test("""
        the Coverage fixture's functions with no mutant are its production records outside the generated file \
        that no mutant was placed on: setters, initialisers, a subscript's container, an inactive `#if` branch, \
        top-level code and a target no test builds
        """)
    func noMutant() throws {
        let harness = try MappingHarness.coverage()
        defer { harness.remove() }
        let (results, suspects) = try MappingHarness.coverageRun()
        let report = harness.report(results, suspects: suspects)
        let generated = Set(harness.measured.files.filter(\.generated).map(\.path))
        let placed = Set(report.records.map(\.key))

        let unplaced = harness.measured.records.filter { record in
            record.role == .production && generated.contains(record.file) == false
                && placed.contains(record.key) == false
        }

        #expect(generated == ["Sources/Probe/Generated.swift"])
        #expect(unplaced.map(\.key).sorted() == Self.unplacedKeys)
        let rollups = harness.rollupBuilder(report)
        for module in ["Exe", "Probe", "Unlinked"] {
            let expected = unplaced.count { $0.module == module }
            #expect(rollups.rollup(of: [module], isProject: false).functions.noMutant == expected, "\(module)")
        }
    }

    @Test("""
        the Mutation fixture's two modules count crash kills among the kills, functions no test ran as only not \
        covered, and the production part scores as SwiftMutator's report does, nothing dropped or unmapped
        """)
    func mutationFixture() throws {
        let harness = try MappingHarness.mutation()
        defer { harness.remove() }
        let (results, suspects) = try MappingHarness.fullRun(of: MutationFixture.directory)
        let report = harness.report(results, suspects: suspects)
        let builder = harness.rollupBuilder(report)

        let core = builder.rollup(of: ["Core"], isProject: false)
        #expect(core.counts == Self.counts(killed: 24, crashKills: 2, survived: 9, notCovered: 7))
        #expect(core.score.percent == 72.73)
        #expect(core.functions.scored == 4 && core.functions.notCoveredOnly == 1 && core.functions.noMutant == 0)
        let extras = builder.rollup(of: ["Extras"], isProject: false)
        #expect(extras.counts == Self.counts(killed: 2, notCovered: 14) && extras.score.percent == 100)
        #expect(extras.functions.scored == 1 && extras.functions.notCoveredOnly == 2)
        let production = builder.rollup(of: ["Core", "Extras"], isProject: true)
        #expect(production.counts == Self.counts(killed: 26, crashKills: 2, survived: 9, notCovered: 21))
        #expect(production.score.percent == 74.29 && production.score.truncatedPercent == 74)
        #expect(production.unmapped == 0 && production.dropped == 0)
        #expect(MutationFigures(report.everyMutant.counts).score == production.score)
    }

    @Test("""
        over incomplete results the scores keep their counts but lose their percentages; functions in \
        unresolved and unlisted files have no results and aren't listed, a function with only build errors is \
        counted apart, carried mutants are counted, and a crash kill's flag isn't a judged kill
        """)
    func mergedShapes() throws {
        let harness = try MappingHarness.mutation()
        defer { harness.remove() }
        let (results, suspects) = try MappingHarness.fullRun(of: MutationFixture.directory)
        let full = harness.report(results, suspects: suspects)
        let unresolved = "Sources/Extras/Unused.swift"
        let unlisted = "Sources/Core/Dormant.swift"
        let mutants = try full.mutants.filter { $0.path != unresolved && $0.path != unlisted }.map { mutant in
            switch mutant.path {
            case "Sources/Core/Signs.swift":
                try Self.altered(mutant, ["carried": true])

            case "Sources/Extras/Scale.swift":
                try Self.altered(mutant, ["verdict": "buildError", "outcome": "buildError", "killedBy": []])

            default:
                mutant.isCrashKill ? try Self.altered(mutant, ["suspectOnly": false]) : mutant
            }
        }
        let dispositions: [String: MutationFileDisposition] = [unresolved: .unresolved, unlisted: .unlisted]
        let files = full.files.map { file in
            MutationFile(
                path: file.path,
                sha256: file.sha256,
                disposition: dispositions[file.path] ?? file.disposition,
                changedTest: false,
                run: 0
            )
        }

        let merged = MappingHarness.rebuilt(full, complete: false, files: files, mutants: mutants)
        let builder = harness.rollupBuilder(merged)

        let core = builder.rollup(of: ["Core"], isProject: false)
        #expect(core.counts == Self.counts(killed: 24, crashKills: 2, survived: 9))
        #expect(core.score == MutationScore(killed: 24, scored: 33).withoutPercent())
        #expect(core.carried == 8 && core.functions.scored == 4 && core.functions.notListed == 1)
        let extras = builder.rollup(of: ["Extras"], isProject: false)
        #expect(extras.counts == Self.counts(killed: 0, notCovered: 7, buildErrors: 2))
        #expect(extras.score.scored == 0 && extras.score.percent == nil)
        #expect(extras.functions.noResults == 1 && extras.functions.buildErrorsOnly == 1)
        #expect(extras.functions.notCoveredOnly == 1 && extras.functions.scored == 0)
        let production = builder.rollup(of: ["Core", "Extras"], isProject: true)
        #expect(production.score.killed == 24 && production.score.percent == nil && production.carried == 8)
        #expect(merged.everyMutant.counts.judgedKills == 0)
    }
}
