import Foundation
@testable import SwiftStatsCore
import Testing

/// Suspect-only kills from `swift-mutator report -f json` (M6, design §2):
/// keys joined on all five parts, keyless placeholders skipped, the flag a
/// tri-state (present is suspect-only whatever `suspectsChecked` says;
/// absent is judged only when suspects were checked), only kills by a
/// failed test judged, and each suspect test's reason.
@Suite("Suspect report")
struct SuspectReportTests {
    /// The keys of the hand-written report.
    private static let flaggedKey = MutantKey(
        path: "My Sources/a:b.swift", operatorID: "RelationalBoundary", line: 7, column: 41, occurrence: 1
    )
    /// A key the hand-written report doesn't flag.
    private static let plainKey = MutantKey(
        path: "Sources/Lib.swift", operatorID: "SwapTernary", line: 3, column: 9, occurrence: 0
    )

    /// A report whose applied operators are `applied` and whose summary is
    /// `summary`, or none.
    private static func report(applied: [String], summary: String?) -> Data {
        let operators = applied.joined(separator: ",")
        let summaryKey = summary.map { #","killingTestSummary":\#($0)"# } ?? ""
        return Data(#"{"fileReports":[{"appliedOperators":[\#(operators)]}]\#(summaryKey)}"#.utf8)
    }

    /// An applied operator spelled `key`, flagged when `flagged`.
    private static func applied(_ key: String, flagged: Bool = false) -> String {
        #"{"key":"\#(key)","testSuiteOutcome":"failed"\#(flagged ? #","killedOnlyBySuspectTests":true"# : "")}"#
    }

    /// The killing-test summary with `suspectsChecked` and `tests`.
    private static func summary(checked: Bool, tests: [String] = []) -> String {
        #"{"suspectsChecked":\#(checked),"filesWithKills":12,"tests":[\#(tests.joined(separator: ","))]}"#
    }

    /// A recorded mutant with `key`, `verdict` and `outcome`.
    private static func mutant(_ key: MutantKey, verdict: MutationVerdict, outcome: String) -> RecordedMutant {
        RecordedMutant(
            key: key,
            verdict: verdict,
            outcome: outcome,
            activated: .ran,
            endedBy: "exited",
            exitStatus: 1,
            killedBy: ["checks()"],
            failedTestCount: 1,
            killedByComplete: .complete,
            fileSHA256: nil,
            before: ">",
            after: ">=",
            description: "changed > to >=",
            session: 1,
            durationSeconds: 1,
            rerunBecause: nil,
            reused: false
        )
    }

    /// The report of the two keys, flagging `flaggedKey`, with `summary`.
    private static func twoKeys(summary: String?) throws -> SuspectReport {
        try SuspectReport.decode(report(
            applied: [
                applied("My Sources/a:b.swift:7:41 RelationalBoundary (#2)", flagged: true),
                applied("Sources/Lib.swift:3:9 SwapTernary"),
                #"{"mutationPoint":{"filePath":""},"testSuiteOutcome":"noCoverage"}"#
            ],
            summary: summary
        ))
    }

    @Test("a flag present is suspect-only even when suspects weren't checked; absent, it is judged only when they were")
    func triState() throws {
        let checked = try Self.twoKeys(summary: Self.summary(checked: true))
        let unchecked = try Self.twoKeys(summary: Self.summary(checked: false))
        let noSummary = try Self.twoKeys(summary: nil)
        let flagged = Self.mutant(Self.flaggedKey, verdict: .killed, outcome: "failed")
        let plain = Self.mutant(Self.plainKey, verdict: .killed, outcome: "failed")

        #expect([checked, unchecked, noSummary].map { $0.judgement(of: flagged) }
            == [.suspectOnly, .suspectOnly, .suspectOnly])
        #expect([checked, unchecked, noSummary].map { $0.judgement(of: plain) }
            == [.notSuspectOnly, .unjudged, .unjudged])
        #expect(checked.flagged == [Self.flaggedKey])
        #expect(checked.unreadableKeys == 0 && noSummary.suspectsChecked == false)
    }

    @Test("""
        a run's suspectsJudged is false for a report read without a summary, which judged no reach, as for one whose \
        summary says so; null only when no report was read; its absent flags are null either way
        """)
    func suspectsJudgedWithoutSummary() throws {
        let results = try ResultsLines.results([
            ResultsLines.header(.init(discovered: 1)),
            ResultsLines.mutant(.init(path: "Sources/Lib.swift", line: 3, column: 9, operatorID: "SwapTernary")),
            ResultsLines.end(.init())
        ])
        let run = { (suspects: SuspectReport) in
            MutationMapper.run(results, ordinal: 0, resultsFile: "results.jsonl", git: nil, suspects: suspects)
        }
        let noSummary = try Self.twoKeys(summary: nil)
        let unchecked = try Self.twoKeys(summary: Self.summary(checked: false))
        let checked = try Self.twoKeys(summary: Self.summary(checked: true))

        #expect([noSummary, unchecked, checked, .unjudged].map { run($0).suspectsJudged }
            == [JSONFlag(false), JSONFlag(false), JSONFlag(true), nil])
        #expect(results.mutants.map(noSummary.judgement(of:)) == [.unjudged])
    }

    @Test("only a kill by a failed test is judged: a crash kill, a survivor and a not-covered mutant aren't")
    func onlyFailedKills() throws {
        let report = try Self.twoKeys(summary: Self.summary(checked: true))

        let crash = Self.mutant(Self.flaggedKey, verdict: .killed, outcome: "runtimeError")
        let survivor = Self.mutant(Self.flaggedKey, verdict: .survived, outcome: "passed")
        let notCovered = Self.mutant(Self.plainKey, verdict: .notCovered, outcome: "failed")
        let plain = Self.mutant(Self.plainKey, verdict: .killed, outcome: "failed")

        #expect([crash, survivor, notCovered].map(report.judgement(of:)) == [.unjudged, .unjudged, .unjudged])
        #expect(SuspectReport.unjudged.judgement(of: plain) == .unjudged)
    }

    @Test("a key that doesn't read is counted, not joined, and the kill it was for isn't judged")
    func unreadableKey() throws {
        let report = try SuspectReport.decode(Self.report(
            applied: [Self.applied("Sources/Lib.swift:3:x SwapTernary", flagged: true)],
            summary: Self.summary(checked: true)
        ))
        let plain = Self.mutant(Self.plainKey, verdict: .killed, outcome: "failed")

        #expect(report.flagged.isEmpty && report.reported.isEmpty && report.unreadableKeys == 1)
        #expect(report.judgement(of: plain) == .unjudged)
        #expect(report.unreported(among: [plain]) == 1)
    }

    @Test("""
        the join is one to one: with suspects checked, a kill no entry has is unjudged, not judged not suspect-only, \
        and counted; a survivor without one isn't counted, nor is anything when no report was read
        """)
    func missingEntry() throws {
        let report = try SuspectReport.decode(Self.report(
            applied: [Self.applied("Sources/Lib.swift:3:9 SwapTernary")],
            summary: Self.summary(checked: true)
        ))
        let listed = Self.mutant(Self.plainKey, verdict: .killed, outcome: "failed")
        let missing = Self.mutant(Self.flaggedKey, verdict: .killed, outcome: "failed")
        let survivor = Self.mutant(Self.flaggedKey, verdict: .survived, outcome: "passed")

        #expect([listed, missing].map(report.judgement(of:)) == [.notSuspectOnly, .unjudged])
        #expect(report.unreported(among: [listed, missing, survivor]) == 1)
        #expect(SuspectReport.unjudged.unreported(among: [listed, missing]) == 0)
    }

    @Test("each suspect test says why: a failed control run, flakiness alone, or reach over files with kills")
    func suspectReasons() throws {
        let tests = [
            #"{"name":"reaches()","file":"A.swift","suspect":true,"files":10,"failedControlRuns":0}"#,
            #"{"name":"controlled()","file":"B.swift","suspect":true,"failedControlRuns":1,"files":12}"#,
            #"{"name":"flaky()","suspect":true,"notReproducedAlone":1,"failedAgainAlone":3,"files":2}"#,
            #"{"name":"cleared()","suspect":false,"files":11}"#,
            #"{"name":"steady()","suspect":true,"notReproducedAlone":1,"failedAgainAlone":4,"files":11}"#
        ]

        let summary = Self.summary(checked: true, tests: tests)

        let report = try SuspectReport.decode(Self.report(applied: [], summary: summary))

        #expect(report.suspectTests == [
            .init(name: "controlled()", file: "B.swift", reason: .controlRun, files: nil, filesWithKills: nil),
            .init(name: "flaky()", file: nil, reason: .flaky, files: nil, filesWithKills: nil),
            .init(name: "reaches()", file: "A.swift", reason: .reach, files: 10, filesWithKills: 12),
            .init(name: "steady()", file: nil, reason: .reach, files: 11, filesWithKills: 12)
        ])
    }

    @Test("a report that doesn't decode fails with a reason")
    func undecodable() {
        #expect(throws: MutationFailure(description: "`swift-mutator report`'s JSON doesn't read")) {
            try SuspectReport.decode(Data("[]".utf8))
        }
    }
}
