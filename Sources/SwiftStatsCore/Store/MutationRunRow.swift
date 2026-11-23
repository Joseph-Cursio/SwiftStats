//
//  MutationRunRow.swift
//  SwiftStatsCore
//
//  The `mutationRun` table (M6, design §5): one row per SwiftMutator run a
//  snapshot's mutants refer to, by ordinal, with its build, the commit it
//  tested, how it ended and its header's facts. A `--since` run's revision
//  and a carried run's source are flattened into columns, null when
//  absent; format versions and operators are JSON arrays; whether reach
//  was judged is 1, 0 or null when no report was read.
//

import GRDB

/// One run of a snapshot's mutation results.
struct MutationRunRow: Codable, Equatable, FetchableRecord, PersistableRecord {
    /// The table name.
    static let databaseTableName = "mutationRun"

    /// The snapshot.
    var snapshotId: Int64
    /// The run's ordinal, from 0.
    var ordinal: Int
    /// The SwiftMutator build's identity; null when not recorded.
    var identity: String?
    /// SwiftMutator's version.
    var version: String
    /// When its first session started.
    var startedAt: String
    /// When its last session ended; null without an end.
    var endedAt: String?
    /// How its last session ended; null without an end.
    var endReason: String?
    /// The commit it tested; null outside git.
    var commit: String?
    /// Whether the tree it tested had uncommitted changes.
    var dirty: Bool
    /// `full` or `since`.
    var mode: MutationMode
    /// How many readable sessions its results file holds.
    var sessions: Int
    /// A `--since` run's revision as given.
    var sinceRef: String?
    /// The commit it names.
    var sinceCommit: String?
    /// Its merge base with HEAD.
    var mergeBase: String?
    /// Where its results file is kept, from the package root.
    var resultsFile: String
    /// The results file's SHA-256.
    var resultsSHA256: String
    /// Its headers' format versions, as a JSON array.
    var formatVersions: String
    /// Its operators, as a JSON array.
    var operators: String
    /// Whether coverage was off.
    var skipCoverage: Bool
    /// Whether its last header lists code no test ran.
    var listsNotCovered: Bool
    /// How many mutants it tested at once.
    var workers: Int
    /// Its time limit per mutant, in seconds.
    var timeoutSeconds: Double?
    /// Whether it stopped at the first failure.
    var stopsAtFirstFailure: Bool
    /// Whether reach was judged: 1, 0, or null when no report was read.
    var suspectsJudged: Int?
    /// How many mutants it discovered.
    var mutantsDiscovered: Int
    /// How many it couldn't test.
    var mutantsDropped: Int?
    /// How many control runs it made.
    var controlRuns: Int
    /// How many failed.
    var controlFailures: Int
    /// The test command's version line.
    var toolchain: String?
    /// The test command's SHA-256.
    var testExecutableSHA256: String?
    /// The SDK environment's hash.
    var sdkEnvironment: String?
    /// The commit of the snapshot its rows were carried from.
    var carriedFrom: String?
    /// When that snapshot's mutation results were collected.
    var carriedFromCollectedAt: String?

    /// The run this row records; it throws when its JSON columns don't
    /// read.
    var run: MutationRunRecord {
        get throws {
            MutationRunRecord(
                ordinal: ordinal,
                identity: identity,
                version: version,
                startedAt: startedAt,
                endedAt: endedAt,
                endReason: endReason,
                commit: commit,
                dirty: dirty,
                mode: mode,
                sessions: sessions,
                since: since,
                carriedFrom: carriedFromSource,
                resultsFile: resultsFile,
                resultsSHA256: resultsSHA256,
                formatVersions: try RowJSON.decoded([Int].self, from: formatVersions),
                operators: try RowJSON.decoded([String].self, from: operators),
                skipCoverage: skipCoverage,
                listsNotCovered: listsNotCovered,
                workers: workers,
                timeoutSeconds: timeoutSeconds,
                stopsAtFirstFailure: stopsAtFirstFailure,
                suspectsJudged: suspectsJudged.map { JSONFlag($0 != 0) },
                mutantsDiscovered: mutantsDiscovered,
                mutantsDropped: mutantsDropped,
                controlRuns: controlRuns,
                controlFailures: controlFailures,
                toolchain: toolchain,
                testExecutableSHA256: testExecutableSHA256,
                sdkEnvironment: sdkEnvironment
            )
        }
    }

    /// The `--since` revision these columns name; nil unless all are set.
    private var since: MutationSinceRevision? {
        guard let sinceRef, let sinceCommit, let mergeBase else {
            return nil
        }
        return MutationSinceRevision(ref: sinceRef, commit: sinceCommit, mergeBase: mergeBase)
    }

    /// The snapshot these columns say the run was carried from; nil
    /// unless both are set.
    private var carriedFromSource: MutationSource? {
        guard let carriedFrom, let carriedFromCollectedAt else {
            return nil
        }
        return MutationSource(commit: carriedFrom, collectedAt: carriedFromCollectedAt)
    }

    /// The row for `run` in snapshot `snapshotId`.
    init(_ run: MutationRunRecord, snapshotId: Int64) {
        self.snapshotId = snapshotId
        ordinal = run.ordinal
        identity = run.identity
        version = run.version
        startedAt = run.startedAt
        endedAt = run.endedAt
        endReason = run.endReason
        commit = run.commit
        dirty = run.dirty
        mode = run.mode
        sessions = run.sessions
        sinceRef = run.since?.ref
        sinceCommit = run.since?.commit
        mergeBase = run.since?.mergeBase
        resultsFile = run.resultsFile
        resultsSHA256 = run.resultsSHA256
        formatVersions = RowJSON.text(run.formatVersions)
        operators = RowJSON.text(run.operators)
        skipCoverage = run.skipCoverage
        listsNotCovered = run.listsNotCovered
        workers = run.workers
        timeoutSeconds = run.timeoutSeconds
        stopsAtFirstFailure = run.stopsAtFirstFailure
        suspectsJudged = run.suspectsJudged.map { $0.value ? 1 : 0 }
        mutantsDiscovered = run.mutantsDiscovered
        mutantsDropped = run.mutantsDropped
        controlRuns = run.controlRuns
        controlFailures = run.controlFailures
        toolchain = run.toolchain
        testExecutableSHA256 = run.testExecutableSHA256
        sdkEnvironment = run.sdkEnvironment
        carriedFrom = run.carriedFrom?.commit
        carriedFromCollectedAt = run.carriedFrom?.collectedAt
    }
}
