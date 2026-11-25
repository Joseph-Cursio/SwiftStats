//
//  DeadButTestedFixtureTests.swift
//  SwiftStatsCoreTests
//
//  Dead but tested (M7, design §8.2, §13 step 9b) on the Index fixture,
//  scanned with its recorded build, index and outskirts runs and given
//  hand-made mutants (`IndexHarness`): its nine production-dead functions
//  (`onlyTestsCall()` by USR, `Unused`'s methods by its type and its
//  extension, the unused computed property's getter by `property`, the
//  unused local function) listed when a mutant of theirs ran (killed,
//  survived or timed out; killed only in a run with coverage off), else
//  counted by why not, files without full mutation results apart; the
//  covering declaration, the run's coverage setting and the coverage in
//  the payloads. Serialized: each test scans a copy of the fixture on a
//  thread of its own, as the index collector's tests do.
//

import Foundation
@testable import SwiftStatsCore
import Testing

/// Dead but tested on the Index fixture's scan with hand-made mutants.
@Suite("Dead but tested on the Index fixture", .serialized)
struct DeadButTestedFixtureTests {
    /// The harness's shorthand.
    private typealias Harness = IndexHarness

    /// Checks dead but tested on `snapshot`, the fixture's stored scan
    /// with the harness's killed mutant on `onlyTestsCall()`.
    private static func expectFixture(_ snapshot: StoredSnapshot) throws {
        let signal = try Harness.signal(.deadButTested, of: snapshot)

        #expect(signal.leftOut == nil)
        #expect(signal.rule == Harness.deadButTestedRule(listed: 1, partial: 0, unrun: [0, 0, 8, 0]))
        #expect(MutationSignalHarness.unbalanced(signal.rule) == [Harness.coveredClause])
        #expect(signal.candidates == 96)
        let item = try #require(signal.items.first)
        #expect(signal.items.count == 1)
        #expect(item.subject == Harness.onlyTestsCall)
        #expect("\(item.file):\(item.line)" == "Sources/IndexCore/TestOnly.swift:7")
        #expect(item.score == 1 && item.rank == 1 && item.member)
        #expect(item.dead == SignalItem.Dead(
            kind: "function.free",
            name: "onlyTestsCall()",
            file: "Sources/IndexCore/TestOnly.swift",
            line: 7,
            via: .usr,
            accessibility: "internal",
            deadWithTestsAsRoots: false
        ))
        #expect(item.mutation?.coverage == .enabled)
        #expect(item.mutation?.killingTests == 1)
        #expect(item.mutation?.firstKillingTests == [Harness.onlyTests])
        #expect(item.coverage == nil && item.references == nil)
    }

    /// Checks the JSON of dead but tested's item and of test-only
    /// production code's item with mutation results on `snapshot`: only
    /// the first carries the covering declaration and the run's coverage
    /// setting.
    private static func expectJSON(_ snapshot: StoredSnapshot) throws {
        let item = try #require(try Harness.signal(.deadButTested, of: snapshot).items.first)
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(item)) as? [String: Any]
        #expect((json?["mutation"] as? [String: Any])?["coverage"] as? String == "on")
        #expect((json?["dead"] as? [String: Any])?["via"] as? String == "usr")
        let testOnly = try Harness.signal(.testOnlyProduction, of: snapshot)
        let other = try #require(testOnly.items.first { $0.mutation != nil })
        let otherJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(other)) as? [String: Any]
        #expect((otherJSON?["mutation"] as? [String: Any])?["coverage"] == nil)
        #expect(otherJSON?["dead"] == nil)
    }

    /// Checks dead but tested's items and verdicts on `snapshot`, given the
    /// mutants of `verdicts()`.
    private static func expectVerdicts(_ snapshot: StoredSnapshot) throws {
        let signal = try Harness.signal(.deadButTested, of: snapshot)
        let verdicts = try Harness.verdicts(snapshot)
        let dead = signal.items.compactMap(\.dead)

        #expect(signal.rule == Harness.deadButTestedRule(listed: 4, partial: 0, unrun: [3, 1, 1, 0]))
        #expect(signal.items.map(\.subject) == [
            Harness.unusedThird, Harness.parseLine, Harness.onlyTestsCall, Harness.unusedFirst
        ])
        #expect(signal.items.map(\.score) == [2, 2, 1, 1])
        #expect(signal.items.map(\.rank) == [1, 2, 3, 4])
        #expect(signal.items.compactMap(\.mutation?.killingTests) == [2, 0, 1, 0])
        #expect(dead.map { "\($0.kind) \($0.name) \($0.via.rawValue)" } == [
            "extension.struct Unused extension",
            "function.free parseLine(_:) usr",
            "function.free onlyTestsCall() usr",
            "struct Unused type"
        ])
        #expect(dead.map(\.deadWithTestsAsRoots) == [true, false, false, true])
        #expect(dead.map(\.accessibility) == ["internal", "public", "internal", "internal"])
        #expect(verdicts[Harness.neverCalled] == .notCovered)
        #expect(verdicts[Harness.unusedComputed] == .notCovered)
        #expect(verdicts[Harness.unusedSecond] == .notCovered)
        #expect(verdicts[Harness.relay] == .buildErrors)
        #expect(verdicts[Harness.unusedHelper] == .noMutant)
        #expect(verdicts.values.count { $0 == .used } == 87)
    }

    @Test("""
        the fixture lists onlyTestsCall() for the harness's killed mutant, covered by its unused function entry \
        by USR and not dead with tests as roots, with its run's coverage setting; the eight other \
        production-dead functions have no mutant; both funnels' parts sum
        """)
    func fixture() async throws {
        try await Harness.scan(indexed: true) { scanned in
            let made = try TemporaryStore("DeadButTestedFixture")
            defer { made.remove() }
            let results = Harness.Results(mutants: [Harness.onlyTestsCall: [Harness.killed(by: [Harness.onlyTests])]])
            let snapshot = try Harness.stored(Harness.with(results, on: scanned), in: made.store)

            try Self.expectFixture(snapshot)
            try Self.expectJSON(snapshot)
        }
    }

    @Test("""
        a production-dead function is listed when a mutant killed, survived or timed out, scored by those and \
        ordered by score, then by killing tests, then key; not covered and no coverage count only not covered \
        (before build errors), build errors alone count apart, none counts no mutant; the payload names the \
        covering type, extension or property, and whether tests as roots leave it dead too
        """)
    func verdicts() async throws {
        try await Harness.scan(indexed: true) { scanned in
            let made = try TemporaryStore("DeadButTestedVerdicts")
            defer { made.remove() }
            let results = Harness.Results(mutants: [
                Harness.onlyTestsCall: [Harness.killed(by: [Harness.onlyTests])],
                Harness.parseLine: Harness.planted(1, .survived) + Harness.planted(1, .timedOut),
                Harness.unusedThird: [Harness.killed(by: ["T.a()"]), Harness.killed(by: ["T.b()"])],
                Harness.unusedFirst: Harness.planted(1, .timedOut) + Harness.planted(2, .notCovered),
                Harness.neverCalled: Harness.planted(1, .notCovered) + Harness.planted(1, .noCoverage),
                Harness.unusedComputed: Harness.planted(1, .noCoverage),
                Harness.unusedSecond: Harness.planted(1, .buildError) + Harness.planted(1, .notCovered),
                Harness.relay: Harness.planted(2, .buildError)
            ])

            try Self.expectVerdicts(try Harness.stored(Harness.with(results, on: scanned), in: made.store))
        }
    }

    @Test("""
        in a run with coverage off only kills count: survived or timed out alone counts apart, before not \
        covered; the payload says coverage is off; when no file names its run, the mutants' run decides
        """)
    func coverageOff() async throws {
        try await Harness.scan(indexed: true) { scanned in
            let made = try TemporaryStore("DeadButTestedOff")
            defer { made.remove() }
            let mutants: [String: [MutationSignalHarness.Planted]] = [
                Harness.onlyTestsCall: [Harness.killed(by: [Harness.onlyTests])] + Harness.planted(1, .survived),
                Harness.parseLine: Harness.planted(1, .survived) + Harness.planted(1, .timedOut),
                Harness.unusedFirst: Harness.planted(1, .timedOut) + Harness.planted(1, .notCovered),
                Harness.neverCalled: Harness.planted(1, .notCovered)
            ]
            let signal = { (results: Harness.Results) in
                let snapshot = try Harness.stored(Harness.with(results, on: scanned), in: made.store)
                return (try Harness.signal(.deadButTested, of: snapshot), try Harness.verdicts(snapshot))
            }

            for filesNameRun in [true, false] {
                let (off, verdicts) = try signal(
                    Harness.Results(mutants: mutants, skipCoverage: true, filesNameRun: filesNameRun)
                )
                #expect(off.rule == Harness.deadButTestedRule(listed: 1, partial: 0, unrun: [1, 0, 5, 2]))
                #expect(off.items.map(\.subject) == [Harness.onlyTestsCall] && off.items.map(\.score) == [1])
                #expect(off.items.first?.mutation?.coverage == .disabled)
                #expect(verdicts[Harness.parseLine] == .unchecked && verdicts[Harness.unusedFirst] == .unchecked)
                #expect(verdicts[Harness.neverCalled] == .notCovered)
            }
            let (coverageOn, _) = try signal(Harness.Results(mutants: mutants, filesNameRun: false))
            #expect(coverageOn.items.map(\.subject) == [
                Harness.onlyTestsCall, Harness.parseLine, Harness.unusedFirst
            ])
            #expect(coverageOn.items.map(\.score) == [2, 2, 1])
            #expect(coverageOn.items.compactMap(\.mutation?.coverage) == [.enabled, .enabled, .enabled])
        }
    }

    @Test("""
        a production-dead function in a file without full mutation results (unresolved or unlisted) counts \
        apart unless a mutant of it ran; the coverage payload comes with the snapshot's coverage
        """)
    func partialResults() async throws {
        try await Harness.scan(indexed: true) { scanned in
            let made = try TemporaryStore("DeadButTestedPartial")
            defer { made.remove() }
            let results = Harness.Results(
                mutants: [Harness.parseLine: [Harness.killed(by: ["T.a()"])]],
                dispositions: [
                    "Sources/IndexCore/TestOnly.swift": .unlisted,
                    "Sources/Kits/Relay.swift": .unresolved,
                    "Sources/Kits/Support.swift": .unresolved
                ],
                withCoverage: true,
                covered: [Harness.parseLine]
            )
            let snapshot = try Harness.stored(Harness.with(results, on: scanned), in: made.store)

            let signal = try Harness.signal(.deadButTested, of: snapshot)
            let verdicts = try Harness.verdicts(snapshot)

            #expect(signal.rule == Harness.deadButTestedRule(listed: 1, partial: 3, unrun: [0, 0, 5, 0]))
            #expect(signal.items.map(\.subject) == [Harness.parseLine])
            let lines = try #require(scanned.report.records.first { $0.key == Harness.parseLine }).strippedLines
            let all = CoverageTally(covered: lines, total: lines)
            #expect(signal.items.first?.coverage == SignalItem.Coverage(lines: all, regions: all))
            #expect(verdicts[Harness.onlyTestsCall] == .partialResults)
            #expect(verdicts[Harness.neverCalled] == .partialResults)
            #expect(verdicts[Harness.relay] == .partialResults)
        }
    }
}
