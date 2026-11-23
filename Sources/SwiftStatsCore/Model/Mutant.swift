//
//  Mutant.swift
//  SwiftStatsCore
//
//  One mutant of a snapshot (M6, design §3, §5): its key as SwiftMutator
//  records it (`line` and `column` as SwiftMutator counts them, a byte
//  order mark's bytes not counted), its anchor in the scanned file
//  (counted as records' positions are, a byte order mark's bytes counted on
//  line 1), its verdict and what its results line said, the run that
//  tested it, and where the mapping put it. Every mutant is kept, dropped
//  and unmapped ones too: one per stored row. What wasn't recorded is
//  null, never zero or false.
//

/// A mutant and where it went.
public struct Mutant: Codable, Hashable, Sendable {
    /// The keys the scan JSON writes; `operator` is a keyword. The verdict
    /// is written by name.
    private enum CodingKeys: String, CodingKey {
        case path
        case line
        case column
        case occurrence
        case operatorID = "operator"
        case anchor
        case verdict
        case outcome
        case activated
        case endedBy
        case exitStatus
        case killedBy
        case killedByComplete
        case failedTestCount
        case suspectOnly
        case fileSHA256
        case before
        case after
        case description
        case run
        case session
        case durationSeconds
        case carried
        case reused
        case rerun
        case place
        case owner
        case reason
    }

    /// Its file's path, relative to the package, as SwiftMutator records it.
    public let path: String
    /// The 1-based line SwiftMutator gives.
    public let line: Int
    /// The 1-based UTF-8 byte column SwiftMutator gives, a byte order mark
    /// not counted.
    public let column: Int
    /// 0, or n for the nth repeat of the same place and operator in a run.
    public let occurrence: Int
    /// The operator's id, such as `RelationalBoundary`.
    public let operatorID: String
    /// A position inside a token of the scanned file that stands for the
    /// mutant, as records count positions; nil when the mutant isn't in a
    /// kept file whose bytes the run tested.
    public let anchor: SourcePosition?
    /// Its verdict.
    public let verdict: MutationVerdict
    /// The results line's raw `outcome`; nil for a not-covered mutant.
    public let outcome: String?
    /// Whether its block ran (`activated`); nil when the line doesn't say.
    public let activated: JSONFlag?
    /// How its run ended (`exited`, `timedOut`, …); nil for a not-covered
    /// mutant.
    public let endedBy: String?
    /// The exit status of an `exited` run.
    public let exitStatus: Int?
    /// The tests its log showed failing, as SwiftMutator wrote them; at
    /// most 20.
    public let killedBy: [String]
    /// Whether `killedBy` names every failing test; nil when no list was
    /// recorded.
    public let killedByComplete: JSONFlag?
    /// How many distinct tests its log showed failing, uncapped.
    public let failedTestCount: Int?
    /// Whether only suspect tests killed it; nil when not judged (only a
    /// kill by a failing test can be judged).
    public let suspectOnly: JSONFlag?
    /// The SHA-256 of its file as the run tested it; nil when not recorded.
    public let fileSHA256: String?
    /// The code it replaces.
    public let before: String
    /// The code it puts in its place.
    public let after: String
    /// What it does, in SwiftMutator's words.
    public let description: String
    /// The ordinal of the run that tested it (or, for a not-covered
    /// mutant, listed it).
    public let run: Int
    /// The session of that run that tested it; nil for a not-covered
    /// mutant.
    public let session: Int?
    /// How long its run took, in seconds.
    public let durationSeconds: Double?
    /// Whether it came from an earlier snapshot rather than this scan's run.
    public let carried: Bool
    /// Whether SwiftMutator copied its result from an earlier run
    /// (`reusedFrom`).
    public let reused: Bool
    /// Why its session tested it again (`rerun.because`), when it did.
    public let rerun: String?
    /// Where it went.
    public let place: MutationPlace
    /// What it went to: a record's key, a type's owner text, a file's
    /// path; nil when unmapped or dropped.
    public let owner: String?
    /// Why it is unmapped (`excluded`, `not parsed`, `file changed`,
    /// `symlink`, `no file hash`, …), or the class that dropped it
    /// (`build`, `outsideRoot`, `testFiles`, `otherLanguage`,
    /// `otherPackage`); nil when placed.
    public let reason: String?

    /// Whether a test process crashed for it: a kill counted apart.
    public var isCrashKill: Bool {
        verdict == .killed && outcome == "runtimeError"
    }

    /// Its key, as SwiftMutator's results and report name it.
    var key: MutantKey {
        MutantKey(path: path, operatorID: operatorID, line: line, column: column, occurrence: occurrence)
    }

    /// Creates a mutant. Fields are documented on their properties.
    public init(
        path: String,
        line: Int,
        column: Int,
        occurrence: Int,
        operatorID: String,
        anchor: SourcePosition?,
        verdict: MutationVerdict,
        outcome: String?,
        activated: JSONFlag?,
        endedBy: String?,
        exitStatus: Int?,
        killedBy: [String],
        killedByComplete: JSONFlag?,
        failedTestCount: Int?,
        suspectOnly: JSONFlag?,
        fileSHA256: String?,
        before: String,
        after: String,
        description: String,
        run: Int,
        session: Int?,
        durationSeconds: Double?,
        carried: Bool,
        reused: Bool,
        rerun: String?,
        place: MutationPlace,
        owner: String?,
        reason: String?
    ) {
        self.path = path
        self.line = line
        self.column = column
        self.occurrence = occurrence
        self.operatorID = operatorID
        self.anchor = anchor
        self.verdict = verdict
        self.outcome = outcome
        self.activated = activated
        self.endedBy = endedBy
        self.exitStatus = exitStatus
        self.killedBy = killedBy
        self.killedByComplete = killedByComplete
        self.failedTestCount = failedTestCount
        self.suspectOnly = suspectOnly
        self.fileSHA256 = fileSHA256
        self.before = before
        self.after = after
        self.description = description
        self.run = run
        self.session = session
        self.durationSeconds = durationSeconds
        self.carried = carried
        self.reused = reused
        self.rerun = rerun
        self.place = place
        self.owner = owner
        self.reason = reason
    }

    /// Reads a mutant; it throws for a verdict no SwiftStats writes.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let name = try container.decode(String.self, forKey: .verdict)
        guard let named = MutationVerdict(rawValue: name) else {
            throw DecodingError.dataCorruptedError(forKey: .verdict, in: container, debugDescription: name)
        }
        try self.init(
            path: container.decode(String.self, forKey: .path),
            line: container.decode(Int.self, forKey: .line),
            column: container.decode(Int.self, forKey: .column),
            occurrence: container.decode(Int.self, forKey: .occurrence),
            operatorID: container.decode(String.self, forKey: .operatorID),
            anchor: container.decodeIfPresent(SourcePosition.self, forKey: .anchor),
            verdict: named,
            outcome: container.decodeIfPresent(String.self, forKey: .outcome),
            activated: container.decodeIfPresent(JSONFlag.self, forKey: .activated),
            endedBy: container.decodeIfPresent(String.self, forKey: .endedBy),
            exitStatus: container.decodeIfPresent(Int.self, forKey: .exitStatus),
            killedBy: container.decode([String].self, forKey: .killedBy),
            killedByComplete: container.decodeIfPresent(JSONFlag.self, forKey: .killedByComplete),
            failedTestCount: container.decodeIfPresent(Int.self, forKey: .failedTestCount),
            suspectOnly: container.decodeIfPresent(JSONFlag.self, forKey: .suspectOnly),
            fileSHA256: container.decodeIfPresent(String.self, forKey: .fileSHA256),
            before: container.decode(String.self, forKey: .before),
            after: container.decode(String.self, forKey: .after),
            description: container.decode(String.self, forKey: .description),
            run: container.decode(Int.self, forKey: .run),
            session: container.decodeIfPresent(Int.self, forKey: .session),
            durationSeconds: container.decodeIfPresent(Double.self, forKey: .durationSeconds),
            carried: container.decode(Bool.self, forKey: .carried),
            reused: container.decode(Bool.self, forKey: .reused),
            rerun: container.decodeIfPresent(String.self, forKey: .rerun),
            place: container.decode(MutationPlace.self, forKey: .place),
            owner: container.decodeIfPresent(String.self, forKey: .owner),
            reason: container.decodeIfPresent(String.self, forKey: .reason)
        )
    }

    /// Writes the mutant, leaving out what wasn't recorded.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(path, forKey: .path)
        try container.encode(line, forKey: .line)
        try container.encode(column, forKey: .column)
        try container.encode(occurrence, forKey: .occurrence)
        try container.encode(operatorID, forKey: .operatorID)
        try container.encodeIfPresent(anchor, forKey: .anchor)
        try container.encode(verdict.rawValue, forKey: .verdict)
        try container.encodeIfPresent(outcome, forKey: .outcome)
        try container.encodeIfPresent(activated, forKey: .activated)
        try container.encodeIfPresent(endedBy, forKey: .endedBy)
        try container.encodeIfPresent(exitStatus, forKey: .exitStatus)
        try container.encode(killedBy, forKey: .killedBy)
        try container.encodeIfPresent(killedByComplete, forKey: .killedByComplete)
        try container.encodeIfPresent(failedTestCount, forKey: .failedTestCount)
        try container.encodeIfPresent(suspectOnly, forKey: .suspectOnly)
        try container.encodeIfPresent(fileSHA256, forKey: .fileSHA256)
        try container.encode(before, forKey: .before)
        try container.encode(after, forKey: .after)
        try container.encode(description, forKey: .description)
        try container.encode(run, forKey: .run)
        try container.encodeIfPresent(session, forKey: .session)
        try container.encodeIfPresent(durationSeconds, forKey: .durationSeconds)
        try container.encode(carried, forKey: .carried)
        try container.encode(reused, forKey: .reused)
        try container.encodeIfPresent(rerun, forKey: .rerun)
        try container.encode(place, forKey: .place)
        try container.encodeIfPresent(owner, forKey: .owner)
        try container.encodeIfPresent(reason, forKey: .reason)
    }
}
