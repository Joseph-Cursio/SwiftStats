//
//  MutationResultsFile.swift
//  SwiftStatsCore
//
//  Reads SwiftMutator's results.jsonl (M6, design §2) line by line, as
//  SwiftMutator's own reader does (`RecordedResults.swift`,
//  `Docs/results-file.md` "Reading it"): a line that doesn't read is
//  skipped and counted; unknown kinds and keys are ignored; each `header`
//  opens a session, read on its own (formats 1 to 4; a newer one refuses
//  the file), a resumed one rebuilding its tree from an earlier session's
//  through `projectDelta`; a line of a session no readable header started
//  is skipped; the last `mutant` line of a key wins and a `retired` line
//  drops the earlier ones. The last readable header's `mutantsNotCovered`
//  entries that no line tested become not-covered mutants. A file without
//  a readable header holds only a `stopped` line, or isn't a results file.
//

import Foundation

/// SwiftMutator's results file.
enum MutationResultsFile {
    /// What a results file holds.
    enum Contents: Equatable, Sendable {
        /// Results, from at least one readable session.
        case results(MutationResults)
        /// Only a `stopped` line: the run stopped before its first mutant.
        case stopped(MutationStop)
    }

    /// The newest header format this reads.
    static let newestFormatVersion = 4
    /// The reasons an `end` line gives.
    static let endReasons: Set<String> = ["aborted", "finished", "interrupted"]
    /// The endings a `mutant` line records.
    static let endings: Set<String> = [
        "cancelled", "couldNotRun", "exited", "stoppedAtCrash", "stoppedAtFailedTest", "timedOut"
    ]
    /// Why a file with neither a readable header nor a `stopped` line
    /// isn't read.
    static let noHeaderReason = "the results file has no header SwiftStats can read, so it holds no results"

    /// What `data`, a results file's bytes, holds; a `MutationFailure`
    /// when a header is in a newer format, or the file has neither a
    /// readable header nor a `stopped` line.
    static func read(_ data: Data) throws(MutationFailure) -> Contents {
        var reader = MutationResultsReader()
        let lines = data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: false)
        for (index, line) in lines.enumerated() where line.isEmpty == false {
            if try reader.add(Data(line)) == false {
                reader.skipped.append(index + 1)
            }
        }
        if let results = reader.results(sha256: ContentHash.sha256(data)) {
            return .results(results)
        }
        if let stopped = reader.stopped {
            return .stopped(stopped)
        }
        throw MutationFailure(description: noHeaderReason)
    }

    /// Why a header in format `version` refuses the file.
    static func newerFormatReason(_ version: Int) -> String {
        "the results file has formatVersion \(version); this SwiftStats reads 1 to \(newestFormatVersion)"
    }

    /// The tested mutant `line` records.
    static func mutant(of line: MutantLine) -> RecordedMutant {
        RecordedMutant(
            key: line.key,
            verdict: MutationVerdict.of(
                outcome: line.outcome,
                activated: line.activated,
                endedBy: line.endedBy,
                leftOutWithOthers: line.leftOutWithOthers
            ) ?? .buildError,
            outcome: line.outcome,
            activated: line.activated,
            endedBy: line.endedBy,
            exitStatus: line.exitStatus,
            killedBy: line.killedBy,
            failedTestCount: line.failedTestCount,
            killedByComplete: line.completeness,
            fileSHA256: line.fileSHA256,
            before: line.snapshot.before,
            after: line.snapshot.after,
            description: line.snapshot.description,
            session: line.session,
            durationSeconds: line.durationSeconds,
            rerunBecause: line.rerun?.because,
            reused: line.reused
        )
    }

    /// The not-covered mutant `entry` lists, its file hash `tree`'s.
    static func notCovered(_ entry: NotCoveredLine, tree: [String: String]) -> RecordedMutant {
        RecordedMutant(
            key: entry.key,
            verdict: .notCovered,
            outcome: nil,
            activated: .unknown,
            endedBy: nil,
            exitStatus: nil,
            killedBy: [],
            failedTestCount: nil,
            killedByComplete: .notRecorded,
            fileSHA256: tree[entry.key.path],
            before: entry.snapshot.before,
            after: entry.snapshot.after,
            description: entry.snapshot.description,
            session: nil,
            durationSeconds: nil,
            rerunBecause: nil,
            reused: false
        )
    }

    /// The run's facts from `headers`, its readable sessions' headers in
    /// order; nil when there are none. The build, toolchain and settings
    /// come from the first, and from the last the ones a resume can change,
    /// but for the workers and time limit: those are the last session's
    /// that tested a mutant (`workers` above 0 and `timeoutSeconds`
    /// written), or else the first's, since a resumed session with nothing
    /// left to test writes `workers` 0 and no `timeoutSeconds`.
    static func facts(of headers: [HeaderLine]) -> MutationRunFacts? {
        guard let first = headers.first, let last = headers.last else {
            return nil
        }
        let tested = headers.last { $0.workers > 0 && $0.timeoutSeconds != nil } ?? first
        return MutationRunFacts(
            startedAt: first.startedAt,
            executableSHA256: first.provenance.executableSHA256,
            version: first.provenance.version,
            testCommandVersion: first.provenance.testCommandVersion,
            testExecutableSHA256: first.provenance.testExecutableSHA256,
            sdkEnvironment: first.provenance.environment,
            operators: first.operators,
            skipCoverage: first.skipCoverage,
            workers: tested.workers,
            timeoutSeconds: tested.timeoutSeconds,
            stopsAtFirstFailure: last.stopsAtFirstFailure,
            mutantsDiscovered: last.mutantsDiscovered,
            mutantsDropped: last.mutantsDropped,
            since: first.since
        )
    }
}
