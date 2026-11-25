//
//  IndexHarness.swift
//  SwiftStatsCoreTests
//
//  The Index fixture's scan for M7's signals (design §13 step 9b): a copy
//  scanned with `--index`, its recorded build and index and the fake
//  outskirts answering with the recorded runs, then given hand-made
//  mutation results (each record's mutants by verdict, placed on it as a
//  scan maps them, from one run with coverage on or off, each file tested
//  unless a disposition says otherwise) and, when asked, hand-made
//  coverage, as `PropertyTargetHarness` made suggestions; stored and read
//  back, so the signals read what `report` reads. The scan can leave the
//  index out (disabled by the configuration, so outskirts' results are
//  mapped by position).
//

import Foundation
@testable import SwiftStatsCore
import Testing

/// The Index fixture's scan with hand-made mutation results.
enum IndexHarness {
    /// The hand-made mutation results (and coverage) given to the scan.
    struct Results {
        /// Each record's mutants, by key.
        var mutants: [String: [MutationSignalHarness.Planted]] = [:]
        /// Whether the run had coverage off.
        var skipCoverage = false
        /// Each file's disposition, by path; tested when absent.
        var dispositions: [String: MutationFileDisposition] = [:]
        /// Whether each file names the run that tested it; when false, a
        /// record's mutants' run decides its coverage setting.
        var filesNameRun = true
        /// Whether the snapshot holds coverage, rather than being a scan
        /// without `--coverage`.
        var withCoverage = false
        /// With coverage, the records with every line covered, by key; the
        /// others have none covered.
        var covered: Set<String> = []
    }

    /// `onlyTestsCall()`: only a test calls it, so it is production-dead
    /// and dead with tests as roots isn't.
    static let onlyTestsCall = "IndexCore::func onlyTestsCall() -> Int"
    /// `neverCalled()`, in the same file: nothing calls it.
    static let neverCalled = "IndexCore::func neverCalled() -> Int"
    /// `index-support`'s public `parseLine(_:)`: only tests call it, and it
    /// is in no library product.
    static let parseLine = "index-support::func parseLine(_: String) -> [String]"
    /// `index-kit`'s `relay()`: nothing calls it.
    static let relay = "index-kit::func relay() -> Int"
    /// The getter of the unused computed property (`property`).
    static let unusedComputed = "IndexCore::Storage::var unusedComputed: Int { get }"
    /// A method in the braces of the unused type `Unused` (`type`).
    static let unusedFirst = "IndexCore::Unused::func first() -> Int"
    /// The other method in its braces.
    static let unusedSecond = "IndexCore::Unused::func second() -> Int"
    /// Its method in an extension in another file (`extension`).
    static let unusedThird = "IndexCore::Unused::func third() -> Int"
    /// The unused local function inside a used function.
    static let unusedHelper = "IndexCore::func summarize(_: [Int]) -> Int / func unusedHelper() -> Int"
    /// The test that calls `onlyTestsCall()`.
    static let onlyTests = "IndexCoreTests.onlyTests()"
    /// The run's start, as SwiftMutator writes it.
    private static let startedAt = "2026-11-24T09:00:00.000Z"
    /// The results file format the run's header names.
    private static let newestFormat = 4

    /// A kill by the tests named `tests`.
    static func killed(by tests: [String]) -> MutationSignalHarness.Planted {
        MutationSignalHarness.Planted(verdict: .killed, killedBy: tests)
    }

    /// `count` mutants with `verdict`.
    static func planted(_ count: Int, _ verdict: MutationVerdict) -> [MutationSignalHarness.Planted] {
        MutationSignalHarness.planted(count, verdict)
    }

    /// Scans a copy of the Index fixture with `--index`, the fake outskirts
    /// answering with the recorded runs and the index read when `indexed`
    /// (else disabled), and passes the scan to `check`.
    static func scan(indexed: Bool, check: (ScannedSnapshot) throws -> Void) async throws {
        let fake = try FakePeriphery.make(try FakePeriphery.recorded())
        defer { fake.remove() }
        var scan = try IndexFixtureScan()
        scan.extra = fake.configuration + (indexed ? "" : "  index:\n    enabled: false\n")
        try await scan.run { _, outcome in
            try check(outcome.snapshot)
        }
    }

    /// `scanned` given `results`: its mutation results from one SwiftMutator
    /// run, and its coverage when `results.withCoverage`.
    static func with(_ results: Results, on scanned: ScannedSnapshot) -> ScannedSnapshot {
        var snapshot = scanned
        if results.withCoverage {
            snapshot = withCoverage(results.covered, on: snapshot)
        }
        let records = Dictionary(snapshot.report.records.map { ($0.key, $0) }) { first, _ in first }
        let mutants = results.mutants.keys.sorted().flatMap { key -> [Mutant] in
            guard let record = records[key] else {
                return []
            }
            return (results.mutants[key] ?? []).enumerated().map { offset, planted in
                MutationSignalHarness.mutant(
                    planted,
                    path: record.file,
                    line: record.range.start.line,
                    column: record.range.start.column + offset,
                    owner: key
                )
            }
        }
        let report = MutationReport(
            collectedAt: startedAt,
            complete: true,
            listsNotCovered: true,
            mode: .full,
            base: nil,
            files: snapshot.report.files.map { file in
                MutationFile(
                    path: file.path,
                    sha256: file.sha256,
                    disposition: results.dispositions[file.path] ?? .tested,
                    changedTest: false,
                    run: results.filesNameRun ? 0 : nil
                )
            },
            runs: [run(0, skipCoverage: results.skipCoverage)],
            suspectTests: [],
            mutants: mutants
        )
        let ran = MutationSnapshots.ran(identity: MutationSnapshots.identity)
        return ScannedSnapshot(
            info: snapshot.info.with(run: ran),
            report: snapshot.report.with(mutation: MutationRows.normalized(report), status: ran.status, warnings: [])
        )
    }

    /// `scanned` holding coverage of every production record, those keyed
    /// in `covered` with every line covered and the rest with none.
    private static func withCoverage(_ covered: Set<String>, on scanned: ScannedSnapshot) -> ScannedSnapshot {
        let records = scanned.report.records.filter { $0.role == .production }.map { record in
            let lines = record.strippedLines
            return MutationSignalHarness.record(
                record.key,
                lines: CoverageTally(covered: covered.contains(record.key) ? lines : 0, total: lines)
            )
        }
        let ran = CoverageSnapshots.ran(options: [])
        return ScannedSnapshot(
            info: scanned.info.with(run: ran),
            report: scanned.report.with(
                coverage: MutationSignalHarness.coverage(records),
                status: ran.status,
                warnings: []
            )
        )
    }

    /// `scanned` with `declarations` added to its dead-code results, which
    /// are rolled up again as a scan rolls them up.
    static func adding(_ declarations: [DeadCodeDeclaration], to scanned: ScannedSnapshot) throws -> ScannedSnapshot {
        let dead = try #require(scanned.report.deadCode)
        let report = DeadCodeReport(
            version: dead.version,
            runs: dead.runs,
            declarations: dead.declarations + declarations,
            records: dead.records,
            dropped: dead.dropped,
            deadLines: dead.deadLines
        )
        let status = try #require(scanned.report.collectors.first { $0.name == PeripheryAdapter.name })
        return ScannedSnapshot(
            info: scanned.info,
            report: scanned.report.with(deadCode: DeadCodeRows.normalized(report), status: status)
        )
    }

    /// `snapshot` stored in `store` and read back.
    static func stored(_ snapshot: ScannedSnapshot, in store: SnapshotStore) throws -> StoredSnapshot {
        try store.load(id: try store.save(snapshot))
    }

    /// The signal `name` of `snapshot`, with the default thresholds.
    static func signal(_ name: SignalName, of snapshot: StoredSnapshot) throws -> SignalResult {
        try MutationSignalHarness.signal(name, of: snapshot)
    }

    /// What dead but tested decides of each of `snapshot`'s production
    /// functions, by key.
    static func verdicts(_ snapshot: StoredSnapshot) throws -> [String: DeadButTested.Verdict] {
        let dead = try #require(snapshot.deadCode?.report)
        let mutation = try #require(snapshot.mutation?.report)
        let judged = DeadButTested.judged(
            SignalInputs(snapshot: snapshot),
            declarations: DeadButTested.declarations(dead, index: snapshot.index?.report),
            mutation: mutation
        )
        return Dictionary(judged.map { ($0.row.key, $0.verdict) }) { first, _ in first }
    }

    /// The run numbered `ordinal`, with coverage off when `skipCoverage`:
    /// the one the harness's results come from is run 0.
    static func run(_ ordinal: Int, skipCoverage: Bool) -> MutationRunRecord {
        MutationRunRecord(
            ordinal: ordinal,
            identity: MutationSnapshots.identity,
            version: "0.1.0",
            startedAt: startedAt,
            endedAt: "2026-11-24T10:00:00.000Z",
            endReason: "finished",
            commit: "c1",
            dirty: false,
            mode: .full,
            sessions: 1,
            since: nil,
            carriedFrom: nil,
            resultsFile: ".swiftstats/mutation/runs/0/results.jsonl",
            resultsSHA256: "0",
            formatVersions: [newestFormat],
            operators: ["RelationalOperatorReplacement"],
            skipCoverage: skipCoverage,
            listsNotCovered: true,
            workers: 1,
            timeoutSeconds: nil,
            stopsAtFirstFailure: true,
            suspectsJudged: JSONFlag(true),
            mutantsDiscovered: 1,
            mutantsDropped: nil,
            controlRuns: 1,
            controlFailures: 0,
            toolchain: nil,
            testExecutableSHA256: nil,
            sdkEnvironment: nil
        )
    }
}
