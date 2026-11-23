import Foundation
@testable import SwiftStatsCore
import Testing

/// A mutation report as the store's rows (M6, design §3, §5): the rows
/// hold it whole, so it reads back unchanged and a scan's JSON is what a
/// stored copy gives; list columns are JSON arrays whatever their names
/// hold; columns that don't read throw; the scan JSON writes counts beside
/// what they count and leaves out what wasn't recorded.
@Suite("Mutation rows")
struct MutationRowsTests {
    /// A mutant's tri-states.
    private struct Flags {
        /// Whether its block ran.
        let activated: JSONFlag?
        /// Whether its kill list is whole.
        let complete: JSONFlag?
        /// Whether only suspect tests killed it.
        let suspect: JSONFlag?
    }

    /// A killing test's name holding a line break, a comma and quotes.
    private static let oddName = "kills \"this\",\nand that()"
    /// When the base snapshot's results were collected.
    private static let baseDate = "2026-11-20T09:00:00.000Z"
    /// A run's suspect tests, out of order: two sharing a name in different
    /// files, and one with no file.
    private static let suspectTests = [
        MutationSuspectTest(
            name: "reaches()",
            file: "BTests.swift",
            run: 1,
            why: .controlRun,
            files: nil,
            filesWithKills: nil
        ),
        MutationSuspectTest(
            name: "reaches()",
            file: "ATests.swift",
            run: 1,
            why: .reach,
            files: 3,
            filesWithKills: 4
        ),
        MutationSuspectTest(name: "flaky()", file: nil, run: 1, why: .flaky, files: nil, filesWithKills: nil)
    ]

    /// A mutant of `Lib.swift` at `line` with `verdict`, tested by run
    /// `run`, with `flags` and `killedBy`; line 1's is unmapped with no
    /// hash or anchor.
    private static func mutant(
        line: Int,
        verdict: MutationVerdict,
        run: Int,
        flags: Flags,
        killedBy: [String]
    ) -> Mutant {
        let listed = verdict != .notCovered
        let mapped = line != 1
        return Mutant(
            path: "Sources/Lib/Lib.swift",
            line: line,
            column: 5,
            occurrence: 0,
            operatorID: "ReplaceReturnValue",
            anchor: mapped ? SourcePosition(line: line, column: 5) : nil,
            verdict: verdict,
            outcome: listed ? "failed" : nil,
            activated: flags.activated,
            endedBy: listed ? "exited" : nil,
            exitStatus: listed ? 1 : nil,
            killedBy: killedBy,
            killedByComplete: flags.complete,
            failedTestCount: killedBy.isEmpty ? nil : killedBy.count,
            suspectOnly: flags.suspect,
            fileSHA256: mapped ? "abc" : nil,
            before: "1",
            after: "0",
            description: "replaced the return value with 0",
            run: run,
            session: listed ? 1 : nil,
            durationSeconds: listed ? ResultsLines.durationSeconds : nil,
            carried: run == 0,
            reused: run == 0,
            rerun: killedBy.isEmpty ? nil : "onlySuspectTestsFailed",
            place: mapped ? .record : .unmapped,
            owner: mapped ? "Lib::func one() -> Int" : nil,
            reason: mapped ? nil : "no file hash"
        )
    }

    /// A run with ordinal `ordinal`, chosen by `since` or carried from
    /// `carriedFrom`; run 0 leaves every optional fact null.
    private static func run(
        _ ordinal: Int,
        since: MutationSinceRevision?,
        carriedFrom: MutationSource?,
        judged: JSONFlag?
    ) -> MutationRunRecord {
        let recorded = ordinal != 0
        return MutationRunRecord(
            ordinal: ordinal,
            identity: recorded ? "sha256:abc" : nil,
            version: "0.1.0",
            startedAt: "2026-11-2\(ordinal)T09:00:00.000Z",
            endedAt: recorded ? "2026-11-21T10:00:00.000Z" : nil,
            endReason: recorded ? "finished" : nil,
            commit: recorded ? "c1" : "b1",
            dirty: recorded,
            mode: since == nil ? .full : .since,
            sessions: ordinal + 1,
            since: since,
            carriedFrom: carriedFrom,
            resultsFile: ".swiftstats/mutation/runs/\(ordinal)/results.jsonl",
            resultsSHA256: "\(ordinal)",
            formatVersions: [1, 4],
            operators: ["RelationalBoundary", "SwapTernary"],
            skipCoverage: false,
            listsNotCovered: recorded,
            workers: 2,
            timeoutSeconds: recorded ? 2.5 : nil,
            stopsAtFirstFailure: true,
            suspectsJudged: judged,
            mutantsDiscovered: 3,
            mutantsDropped: recorded ? 1 : nil,
            controlRuns: 2,
            controlFailures: 1,
            toolchain: recorded ? "Swift 6.4" : nil,
            testExecutableSHA256: recorded ? "def" : nil,
            sdkEnvironment: recorded ? "sha256:123" : nil
        )
    }

    /// A merged report filling every optional column, and leaving each
    /// empty somewhere.
    private static func merged() -> MutationReport {
        let base = MutationSource(commit: "b1", collectedAt: baseDate)
        let since = MutationSinceRevision(ref: "main", commit: "b1", mergeBase: "b1")
        let unflagged = Flags(activated: nil, complete: nil, suspect: nil)
        return MutationReport(
            collectedAt: "2026-11-21T09:00:00.000Z",
            complete: false,
            listsNotCovered: false,
            mode: .since,
            base: base,
            files: [
                MutationFile(path: "Old.swift", sha256: nil, disposition: .deleted, changedTest: false, run: nil),
                MutationFile(path: "Tests/T.swift", sha256: "t", disposition: .untested, changedTest: true, run: nil),
                MutationFile(path: "Lib.swift", sha256: "abc", disposition: .tested, changedTest: false, run: 1)
            ],
            runs: [
                run(1, since: since, carriedFrom: nil, judged: JSONFlag(false)),
                run(0, since: nil, carriedFrom: base, judged: nil)
            ],
            suspectTests: suspectTests,
            mutants: [
                mutant(
                    line: 3,
                    verdict: .killed,
                    run: 1,
                    flags: Flags(activated: JSONFlag(true), complete: JSONFlag(false), suspect: JSONFlag(true)),
                    killedBy: [oddName, "b()"]
                ),
                mutant(line: 2, verdict: .notCovered, run: 0, flags: unflagged, killedBy: []),
                mutant(
                    line: 1,
                    verdict: .survived,
                    run: 1,
                    flags: Flags(activated: JSONFlag(false), complete: nil, suspect: JSONFlag(false)),
                    killedBy: []
                )
            ]
        )
    }

    /// `report` as the scan JSON writes it, read back.
    private static func decoded(_ report: MutationReport) throws -> MutationReport {
        try JSONDecoder().decode(MutationReport.self, from: ScanReportEncoder.encode(report))
    }

    /// `report` as the scan JSON writes it, as JSON objects.
    private static func object(_ report: MutationReport) throws -> [String: Any] {
        let value = try JSONSerialization.jsonObject(with: ScanReportEncoder.encode(report))
        return try #require(value as? [String: Any])
    }

    @Test("the Coverage fixture's report reads back from its rows unchanged, its mutants in key order")
    func fixtureRoundTrip() throws {
        let harness = try MappingHarness.coverage()
        defer { harness.remove() }
        let (results, suspects) = try MappingHarness.coverageRun()
        let report = harness.report(results, suspects: suspects)

        let rows = MutationRows(report, snapshotId: 7)

        #expect(try rows.report() == report)
        #expect(MutationRows.normalized(report) == report)
        #expect(try Self.decoded(report) == report)
        #expect(rows.scan.snapshotId == 7 && rows.runs.count == 1 && rows.files.count == 20)
        #expect(rows.mutants.map(\.ordinal) == Array(0..<report.mutants.count))
        #expect(rows.mutants.count == 43)
        #expect(report.mutants.map(\.key) == report.mutants.map(\.key).sorted())
    }

    @Test("""
        every optional column reads back: a merge's base, a since run's revision, a carried run's source and its \
        unrecorded facts, a deleted path, suspect tests sharing a name, tri-states of every value, and killing \
        tests' names holding line breaks, commas and quotes
        """)
    func optionalColumns() throws {
        let report = Self.merged()

        let rows = MutationRows(report, snapshotId: 1)

        #expect(try rows.report() == report)
        #expect(try Self.decoded(report) == report)
        #expect(report.runs.map(\.ordinal) == [0, 1])
        #expect(report.files.map(\.path) == ["Lib.swift", "Old.swift", "Tests/T.swift"])
        #expect(report.suspectTests.map(\.name) == ["flaky()", "reaches()", "reaches()"])
        #expect(report.suspectTests.map(\.file) == [nil, "ATests.swift", "BTests.swift"])
        #expect(rows.suspects.map(\.file) == [nil, "ATests.swift", "BTests.swift"])
        #expect(report.mutants.map(\.line) == [1, 2, 3])
        #expect(rows.mutants.last?.killedBy == RowJSON.text([Self.oddName, "b()"]))
        #expect(rows.mutants.map(\.suspectOnly) == [0, nil, 1])
        #expect(rows.runs.map(\.suspectsJudged) == [nil, 0])
        #expect(report.records.first?.killingTests == ["b()", Self.oddName])
        #expect(report.records.first?.counts.suspectOnly == 1)
    }

    @Test("""
        the scan JSON writes counts beside what they count, verdicts and reasons by name, the operator as \
        `operator`, and leaves out what wasn't recorded or judged
        """)
    func jsonShape() throws {
        let object = try Self.object(Self.merged())

        let records = try #require(object["records"] as? [[String: Any]])
        let totals = try #require(object["everyMutant"] as? [String: Any])
        let mutants = try #require(object["mutants"] as? [[String: Any]])
        let suspects = try #require(object["suspectTests"] as? [[String: Any]])
        #expect(records.first?["killed"] as? Int == 1 && records.first?["counts"] == nil)
        #expect(totals["unmapped"] as? Int == 1 && totals["survived"] as? Int == 1 && totals["counts"] == nil)
        let notCovered = try #require(mutants.first { $0["verdict"] as? String == "notCovered" })
        for key in ["activated", "killedByComplete", "suspectOnly", "outcome", "session", "rerun", "reason"] {
            #expect(notCovered[key] == nil, "\(key)")
        }
        #expect(notCovered["operator"] as? String == "ReplaceReturnValue")
        let survived = try #require(mutants.first { $0["verdict"] as? String == "survived" })
        #expect(survived["suspectOnly"] as? Bool == false && survived["anchor"] == nil)
        #expect(suspects.map { $0["why"] as? String } == ["flaky", "reach", "controlRun"])
        #expect(suspects.map { $0["file"] as? String } == [nil, "ATests.swift", "BTests.swift"])
        #expect(suspects.first?["files"] == nil && suspects.first?.keys.contains("file") == false)
    }

    @Test("""
        rows whose JSON or named columns don't read throw, normalizing keeps a report whose rows can't read back, \
        and the scan JSON refuses a verdict SwiftStats doesn't write
        """)
    func unreadable() throws {
        let rows = MutationRows(Self.merged(), snapshotId: 1)
        var killedBy = rows.mutants
        killedBy[0].killedBy = "[\"open"
        var verdict = rows.mutants
        verdict[0].verdict = "exploded"
        var versions = rows.runs
        versions[0].formatVersions = "four"
        var why = rows.suspects
        why[0].why = "guess"
        let damaged = { (runs: [MutationRunRow], suspects: [MutationSuspectRow], mutants: [MutantRow]) in
            MutationRows(scan: rows.scan, runs: runs, files: rows.files, suspects: suspects, mutants: mutants)
        }

        #expect(throws: DecodingError.self) { try damaged(rows.runs, rows.suspects, killedBy).report() }
        #expect(throws: RowJSON.Unreadable(text: "exploded")) {
            try damaged(rows.runs, rows.suspects, verdict).report()
        }
        #expect(throws: DecodingError.self) { try damaged(versions, rows.suspects, rows.mutants).report() }
        #expect(throws: RowJSON.Unreadable(text: "guess")) { try damaged(rows.runs, why, rows.mutants).report() }
        let json = try String(bytes: ScanReportEncoder.encode(Self.merged()), encoding: .utf8) ?? ""
        let named = "\"verdict\" : \"notCovered\""
        #expect(json.contains(named))
        let corrupted = Data(json.replacingOccurrences(of: named, with: "\"verdict\" : \"exploded\"").utf8)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(MutationReport.self, from: corrupted) }
    }
}
