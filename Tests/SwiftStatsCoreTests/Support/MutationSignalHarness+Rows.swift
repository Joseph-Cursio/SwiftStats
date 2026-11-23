//
//  MutationSignalHarness+Rows.swift
//  SwiftStatsCoreTests
//
//  The rows `MutationSignalHarness` gives its packages (M6): a function's
//  coverage record, coverage holding nothing but records, a planted
//  mutant as a scan maps it onto its record (or, for uneven clone
//  testing's mutation part, onto a type or file, or not at all, with an
//  anchor of its own), and the one run the results come from.
//

@testable import SwiftStatsCore

extension MutationSignalHarness {
    /// The results file format the run's header names.
    private static let newestFormat = 4

    /// `key`'s coverage record with `lines` (and as many regions).
    static func record(_ key: String, lines: CoverageTally?) -> CoverageRecord {
        CoverageRecord(
            key: key,
            lines: lines,
            regions: lines,
            testTargets: lines == nil ? [] : ["LibTests"],
            reason: lines == nil ? "no coverage data" : nil,
            link: nil,
            linkedTests: nil
        )
    }

    /// Coverage holding `records` and nothing else.
    static func coverage(_ records: [CoverageRecord]) -> CoverageReport {
        CoverageReport(
            records: records,
            attachments: [],
            unmapped: [],
            dropped: CoverageDropped(build: 0, outsideRoot: 0, testFiles: 0, otherPackage: 0, otherLanguage: 0),
            bundles: ["LibTests"],
            tests: "passed",
            saturated: [],
            files: []
        )
    }

    /// `planted` as a mutant of `owner` at `line` and `column` of `path`,
    /// placed on its record and anchored at its point.
    static func mutant(_ planted: Planted, path: String, line: Int, column: Int, owner: String) -> Mutant {
        let point = SourcePosition(line: line, column: column)
        return mutant(planted, path: path, at: point, placement: Placement(place: .record, owner: owner, anchor: point))
    }

    /// `planted` as a mutant at `point` of `path` (SwiftMutator's line and
    /// column), placed as `placement` says.
    static func mutant(_ planted: Planted, path: String, at point: SourcePosition, placement: Placement) -> Mutant {
        let mapped = placement.place == .record || placement.place == .type || placement.place == .file
        let verdict = planted.verdict
        let outcome: String? = switch verdict {
        case .killed:
            planted.crash ? "runtimeError" : "failed"

        case .survived, .noCoverage:
            "passed"

        case .timedOut:
            "timeout"

        case .buildError:
            "buildError"

        case .notCovered:
            nil
        }
        return Mutant(
            path: path,
            line: point.line,
            column: point.column,
            occurrence: 0,
            operatorID: planted.operatorID,
            anchor: mapped ? placement.anchor : nil,
            verdict: verdict,
            outcome: outcome,
            activated: verdict == .noCoverage ? JSONFlag(false) : nil,
            endedBy: outcome == nil ? nil : "exited",
            exitStatus: nil,
            killedBy: planted.killedBy,
            killedByComplete: nil,
            failedTestCount: planted.killedBy.isEmpty ? nil : planted.killedBy.count,
            suspectOnly: planted.suspectOnly,
            fileSHA256: "abc",
            before: "+",
            after: "-",
            description: "replaced + with -",
            run: 0,
            session: outcome == nil ? nil : 1,
            durationSeconds: nil,
            carried: false,
            reused: false,
            rerun: nil,
            place: placement.place,
            owner: mapped ? placement.owner : nil,
            reason: mapped ? nil : placement.place == .unmapped ? "file changed" : "testFiles"
        )
    }

    /// The one run the results come from.
    static func run(listsNotCovered: Bool) -> MutationRunRecord {
        MutationRunRecord(
            ordinal: 0,
            identity: MutationSnapshots.identity,
            version: "0.1.0",
            startedAt: "2026-11-21T09:00:00.000Z",
            endedAt: "2026-11-21T10:00:00.000Z",
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
            skipCoverage: false,
            listsNotCovered: listsNotCovered,
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
