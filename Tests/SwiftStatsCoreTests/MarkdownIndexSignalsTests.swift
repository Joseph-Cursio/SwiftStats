//
//  MarkdownIndexSignalsTests.swift
//  SwiftStatsCoreTests
//
//  M7's signal tables (design §10.1): test-only production code shows,
//  after the function and its score, the test referrers counted with the
//  first three named, then the lines covered and the function score, a
//  dash when the snapshot holds no coverage or the function has no
//  mutants; on `TestOnlyHarness`' package and on hand-made items. Dead but
//  tested shows the mutants killed of scored (the run's coverage setting
//  when off), the killing tests, the covering declaration with its rule
//  and whether tests as roots leave the function dead too, on hand-made
//  items. Hidden coupling shows, after the pair's first family and its
//  support, the partner with its place, both families' changes, the
//  confidence with its percentage and whether the two share a file and a
//  module, on hand-made items.
//

import Foundation
@testable import SwiftStatsCore
import Testing

@Suite("Markdown index signals")
struct MarkdownIndexSignalsTests {
    /// The function the hand-made items are about.
    private static let subject = "Lib::func f(_: Int) -> Int"
    /// Its file.
    private static let file = "Sources/Lib/F.swift"
    /// The table's header and separator.
    private static let header = [
        "| # | Function | Score | Test referrers | Lines covered | Function score |",
        "| --- | --- | --- | --- | --- | --- |"
    ]

    /// A function's results: two kills of seven scored.
    private static let mutationJSON = """
        {
          "counts": {"killed": 2, "crashKills": 0, "survived": 5, "noCoverage": 0, "timedOut": 0, "notCovered": 0,
                     "buildErrors": 0, "suspectOnly": 0, "judgedKills": 2},
          "score": {"killed": 2, "scored": 7, "percent": 28.57},
          "functionScore": {"killed": 2, "scored": 7, "percent": 28.57},
          "killingTests": 1,
          "firstKillingTests": ["a()"],
          "survivors": [],
          "suspects": []
        }
        """

    /// The table lines a report shows for `signal`.
    private static func table(_ signal: SignalResult) -> [String] {
        MarkdownSignals.render([signal], history: nil).filter { $0.hasPrefix("|") }
    }

    /// The table row of a test-only item scored `score` with `references`,
    /// `coverage` and `mutation`.
    private static func row(
        score: Double,
        references: SignalItem.References,
        coverage: SignalItem.Coverage? = nil,
        mutation: SignalItem.Mutation? = nil
    ) throws -> String {
        let item = SignalItem(
            SignalItem.Draft(
                subject: subject,
                file: file,
                line: 3,
                coverage: coverage,
                mutation: mutation,
                references: references
            ),
            rank: 1,
            score: score,
            member: true
        )
        let signal = SignalResult(name: .testOnlyProduction, leftOut: nil, rule: "", candidates: 1, items: [item])
        return try #require(table(signal).last)
    }

    /// The table row of a dead but tested item scored `score` with `dead`
    /// and `mutation`.
    private static func deadRow(
        score: Double,
        dead: SignalItem.Dead?,
        mutation: SignalItem.Mutation?
    ) throws -> String {
        let item = SignalItem(
            SignalItem.Draft(subject: subject, file: file, line: 3, mutation: mutation, dead: dead),
            rank: 1,
            score: score,
            member: true
        )
        let signal = SignalResult(name: .deadButTested, leftOut: nil, rule: "", candidates: 1, items: [item])
        let lines = table(signal)
        #expect(lines.prefix(2) == [
            "| # | Function | Score | Killed / scored | Killing tests | Covering declaration | Dead with tests as "
                + "roots |",
            "| --- | --- | --- | --- | --- | --- | --- |"
        ])
        return try #require(lines.last)
    }

    @Test("""
        dead but tested shows the mutants killed of scored with the run's coverage setting when off, the killing \
        tests, the covering declaration with its rule and whether tests as roots leave it dead; a dash when a \
        payload is absent
        """)
    func deadButTested() throws {
        let mutation = try JSONDecoder().decode(SignalItem.Mutation.self, from: Data(Self.mutationJSON.utf8))
        let byType = SignalItem.Dead(
            kind: "struct",
            name: "Unused",
            file: "Sources/Lib/Unused.swift",
            line: 3,
            via: .type,
            accessibility: "internal",
            deadWithTestsAsRoots: true
        )
        let byLocation = SignalItem.Dead(
            kind: "function.free",
            name: "f(_:)",
            file: Self.file,
            line: 3,
            via: .location,
            accessibility: "internal",
            deadWithTestsAsRoots: false
        )
        let place = "`func f(_: Int) -> Int` (Sources/Lib/F.swift:3)"

        #expect(mutation.coverage == nil)
        #expect(try Self.deadRow(score: 7, dead: byType, mutation: mutation.with(coverage: .disabled))
            == "| 1 | \(place) | 7 | 2/7 (28.57%), coverage off | 1: a() | `struct Unused` via type | yes |")
        #expect(try Self.deadRow(score: 7, dead: byLocation, mutation: mutation.with(coverage: .enabled))
            == "| 1 | \(place) | 7 | 2/7 (28.57%) | 1: a() | `function.free f(_:)` via location | no |")
        #expect(try Self.deadRow(score: 1, dead: nil, mutation: nil) == "| 1 | \(place) | 1 | — | — | — | — |")
    }

    @Test("""
        test-only production code shows each listed function's test referrers, and a dash for coverage and \
        function score when the snapshot holds neither
        """)
    func harness() throws {
        let made = try TemporaryStore("TestOnlyMarkdown")
        defer { made.remove() }
        let snapshot = try TestOnlyHarness.stored(TestOnlyHarness.cases, in: made.store)

        let signal = try TestOnlyHarness.signal(snapshot)

        #expect(Self.table(signal) == Self.header + [
            "| 1 | `func alsoTests() -> Int` (Sources/Lib/Lib.swift:13) | 2 | 2: LibTests::func test0(); "
                + "LibTests::func test1() | — | — |",
            "| 2 | `func onlyTests() -> Int` (Sources/Lib/Lib.swift:12) | 2 | 2: LibTests::func test0(); "
                + "LibTests::func test1() | — | — |",
            "| 3 | `func helper() -> Int` (Sources/Inner/Inner.swift:1) | 1 | 1: LibTests::func test0() | — | — |",
            "| 4 | `Fake::static func main()` (Sources/Lib/Lib.swift:7) | 1 | 1: LibTests::func test0() | — | — |",
            "| 5 | `func fewTests() -> Int` (Sources/Lib/Lib.swift:14) | 1 | 1: LibTests::func test0() | — | — |",
            "| 6 | `Tool::static func main(_: [String])` (Sources/Tool/Tool.swift:4) | 1 | 1: LibTests::func "
                + "test0() | — | — |"
        ])
    }

    @Test("""
        a test-referrers cell names the first three and counts the rest, or gives the count alone when none is \
        named; lines covered and the function score show when present
        """)
    func cells() throws {
        let mutation = try JSONDecoder().decode(SignalItem.Mutation.self, from: Data(Self.mutationJSON.utf8))
        let many = SignalItem.References(
            tests: 7,
            testReferrers: ["T::a()", "T::b()", "T::c()", "T::d()", "T::e()"],
            module: "Lib"
        )
        let three = SignalItem.References(tests: 3, testReferrers: ["T::a()", "T::b()", "T::c()"], module: "Lib")
        let unnamed = SignalItem.References(tests: 2, testReferrers: [], module: "Lib")
        let covered = SignalItem.Coverage(lines: CoverageTally(covered: 3, total: 4), regions: nil)
        let place = "`func f(_: Int) -> Int` (Sources/Lib/F.swift:3)"

        #expect(try Self.row(score: 7, references: many, coverage: covered, mutation: mutation)
            == "| 1 | \(place) | 7 | 7: T::a(); T::b(); T::c() (+4 more) | 3/4 (75%) | 2/7 (28.57%) |")
        #expect(try Self.row(score: 3, references: three, coverage: covered)
            == "| 1 | \(place) | 3 | 3: T::a(); T::b(); T::c() | 3/4 (75%) | — |")
        #expect(try Self.row(score: 2, references: unnamed)
            == "| 1 | \(place) | 2 | 2 | — | — |")
        #expect(try Self.row(score: 2, references: unnamed, coverage: SignalItem.Coverage(lines: nil, regions: nil))
            == "| 1 | \(place) | 2 | 2 | — | — |")
    }

    @Test("""
        hidden coupling heads its subject column Family and shows the partner, both families' changes, the \
        confidence with its percentage, and whether the two share a file and a module; a dash without a payload
        """)
    func hiddenCoupling() {
        let coupling = SignalItem.Coupling(
            partner: "Other::func g() -> Int",
            partnerFile: "Sources/Other/G.swift",
            support: 3,
            changesA: 4,
            changesB: 9,
            confidence: SignalItem.CouplingConfidence(support: 3, smaller: 4),
            modules: ["Lib", "Other"],
            sameFile: false,
            sameModule: false
        )
        let rows = [coupling, nil].map { payload in
            SignalItem(
                SignalItem.Draft(subject: Self.subject, file: Self.file, line: 3, coupling: payload),
                rank: 1,
                score: 3,
                member: true
            )
        }
        let lines = Self.table(SignalResult(name: .hiddenCoupling, leftOut: nil, rule: "", candidates: 2, items: rows))
        let place = "`func f(_: Int) -> Int` (Sources/Lib/F.swift:3)"

        #expect(lines == [
            "| # | Family | Score | Partner | Changes | Confidence | Same file / module |",
            "| --- | --- | --- | --- | --- | --- | --- |",
            "| 1 | \(place) | 3 | `func g() -> Int` (Sources/Other/G.swift) | 4/9 | 3/4 (75%) | no / no |",
            "| 1 | \(place) | 3 | — | — | — | — |"
        ])
    }
}
