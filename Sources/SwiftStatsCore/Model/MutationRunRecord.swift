//
//  MutationRunRecord.swift
//  SwiftStatsCore
//
//  One SwiftMutator run whose results a snapshot holds (M6, design §3,
//  §5): the build that made them, the commit it tested, how it ended, and
//  the facts its results file's headers record. Its dates are stored facts
//  of the snapshot, so reports read from the store stay byte-identical. A
//  run carried from an earlier snapshot keeps the commit it tested and
//  names the snapshot it was carried from.
//

/// A SwiftMutator run a snapshot's mutants refer to.
public struct MutationRunRecord: Codable, Hashable, Sendable {
    /// Its ordinal among the snapshot's runs, from 0.
    public let ordinal: Int
    /// `sha256:` and the SHA-256 of the SwiftMutator build its header
    /// names; nil when the header records none.
    public let identity: String?
    /// SwiftMutator's version (`0.1.0` for every build; identifies
    /// nothing).
    public let version: String
    /// When its first session started, as SwiftMutator wrote it.
    public let startedAt: String
    /// When its last session ended; nil when that session wrote no end.
    public let endedAt: String?
    /// How its last session ended (`finished`, `aborted`,
    /// `interrupted`); nil when it wrote no end.
    public let endReason: String?
    /// The commit it tested; nil outside git.
    public let commit: String?
    /// Whether the tree it tested had uncommitted changes.
    public let dirty: Bool
    /// Whether it ran over every file or over those changed since a base.
    public let mode: MutationMode
    /// How many readable sessions its results file holds.
    public let sessions: Int
    /// What a `--since` run compared with; nil for a full run.
    public let since: MutationSinceRevision?
    /// The snapshot its rows were carried from; nil for this scan's run.
    public let carriedFrom: MutationSource?
    /// Where its results file is kept, relative to the package root.
    public let resultsFile: String
    /// The results file's SHA-256.
    public let resultsSHA256: String
    /// The format versions of its readable headers, sorted.
    public let formatVersions: [Int]
    /// The operators it asked for, sorted.
    public let operators: [String]
    /// Whether coverage was off.
    public let skipCoverage: Bool
    /// Whether its last header lists the mutants of code no test ran.
    public let listsNotCovered: Bool
    /// How many mutants it tested at once.
    public let workers: Int
    /// Its time limit per mutant, in seconds; nil when not recorded.
    public let timeoutSeconds: Double?
    /// Whether it stopped a mutant's tests at the first failure.
    public let stopsAtFirstFailure: Bool
    /// Whether `swift-mutator report` judged reach (enough files have kills
    /// naming tests); nil when the report wasn't read.
    public let suspectsJudged: JSONFlag?
    /// How many mutants its last session discovered.
    public let mutantsDiscovered: Int
    /// How many its last session couldn't test; nil when not recorded.
    public let mutantsDropped: Int?
    /// How many control runs it made.
    public let controlRuns: Int
    /// How many of them failed, crashed or timed out.
    public let controlFailures: Int
    /// The first line of what the test command printed for its version;
    /// nil when not recorded.
    public let toolchain: String?
    /// The SHA-256 of a test command that wraps `swift`; nil when not
    /// recorded.
    public let testExecutableSHA256: String?
    /// `sha256:` and the hash of the SDK environment the header records
    /// (`MutationAdapter.sdkEnvironment`); nil when it records none.
    public let sdkEnvironment: String?

    /// Creates a run's record. Fields are documented on their properties.
    public init(
        ordinal: Int,
        identity: String?,
        version: String,
        startedAt: String,
        endedAt: String?,
        endReason: String?,
        commit: String?,
        dirty: Bool,
        mode: MutationMode,
        sessions: Int,
        since: MutationSinceRevision?,
        carriedFrom: MutationSource?,
        resultsFile: String,
        resultsSHA256: String,
        formatVersions: [Int],
        operators: [String],
        skipCoverage: Bool,
        listsNotCovered: Bool,
        workers: Int,
        timeoutSeconds: Double?,
        stopsAtFirstFailure: Bool,
        suspectsJudged: JSONFlag?,
        mutantsDiscovered: Int,
        mutantsDropped: Int?,
        controlRuns: Int,
        controlFailures: Int,
        toolchain: String?,
        testExecutableSHA256: String?,
        sdkEnvironment: String?
    ) {
        self.ordinal = ordinal
        self.identity = identity
        self.version = version
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.endReason = endReason
        self.commit = commit
        self.dirty = dirty
        self.mode = mode
        self.sessions = sessions
        self.since = since
        self.carriedFrom = carriedFrom
        self.resultsFile = resultsFile
        self.resultsSHA256 = resultsSHA256
        self.formatVersions = formatVersions
        self.operators = operators
        self.skipCoverage = skipCoverage
        self.listsNotCovered = listsNotCovered
        self.workers = workers
        self.timeoutSeconds = timeoutSeconds
        self.stopsAtFirstFailure = stopsAtFirstFailure
        self.suspectsJudged = suspectsJudged
        self.mutantsDiscovered = mutantsDiscovered
        self.mutantsDropped = mutantsDropped
        self.controlRuns = controlRuns
        self.controlFailures = controlFailures
        self.toolchain = toolchain
        self.testExecutableSHA256 = testExecutableSHA256
        self.sdkEnvironment = sdkEnvironment
    }

    /// The record as the `ordinal`th run of another snapshot, carried from
    /// `source` (nil for this scan's own run): a carry keeps the commit
    /// it tested and names the snapshot it came from.
    func renumbered(_ ordinal: Int, carriedFrom source: MutationSource?) -> Self {
        Self(
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
            carriedFrom: source,
            resultsFile: resultsFile,
            resultsSHA256: resultsSHA256,
            formatVersions: formatVersions,
            operators: operators,
            skipCoverage: skipCoverage,
            listsNotCovered: listsNotCovered,
            workers: workers,
            timeoutSeconds: timeoutSeconds,
            stopsAtFirstFailure: stopsAtFirstFailure,
            suspectsJudged: suspectsJudged,
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
