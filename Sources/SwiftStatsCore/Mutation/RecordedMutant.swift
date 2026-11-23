//
//  RecordedMutant.swift
//  SwiftStatsCore
//
//  One mutant of a results file (M6, design §2 item 7): the last `mutant`
//  line of its key, or an entry of the last header's `mutantsNotCovered`
//  that no line tested, with what SwiftStats keeps of it.
//

/// A mutant as a results file records it.
struct RecordedMutant: Equatable, Sendable {
    /// Its key.
    let key: MutantKey
    /// Its verdict.
    let verdict: MutationVerdict
    /// The line's raw `outcome`; nil for a not-covered entry.
    let outcome: String?
    /// Whether its block ran; `.unknown` for a not-covered entry.
    let activated: MutantActivation
    /// How its run ended (`exited`, `timedOut`, …); nil for a not-covered
    /// entry.
    let endedBy: String?
    /// The exit status of an `exited` run.
    let exitStatus: Int?
    /// The tests its log showed failing, by name, in the order SwiftMutator
    /// wrote them; at most 20.
    let killedBy: [String]
    /// How many distinct tests its log showed failing, uncapped.
    let failedTestCount: Int?
    /// Whether `killedBy` names every failing test: complete when the run
    /// exited by itself and `failedTestCount` is its length; not recorded
    /// for a not-covered entry or a line with no `killedBy` (a survivor, a
    /// build error), which a store or JSON writes as null.
    let killedByComplete: KillListCompleteness
    /// The SHA-256 of its file's raw bytes as the run tested it: the line's
    /// `fileSHA256`, or for a not-covered entry the last header's tree hash
    /// of its path; nil when neither is recorded.
    let fileSHA256: String?
    /// The code it replaces.
    let before: String
    /// The code it puts in its place.
    let after: String
    /// What it does, in SwiftMutator's words.
    let description: String
    /// The session that tested it; nil for a not-covered entry.
    let session: Int?
    /// How long its run took, in seconds.
    let durationSeconds: Double?
    /// Why the session tested it again (`rerun.because`), when it did.
    let rerunBecause: String?
    /// Whether its result was copied from an earlier run (`reusedFrom`).
    let reused: Bool

    /// Whether a test process crashed for it, a kill counted apart.
    var isCrash: Bool {
        outcome == "runtimeError"
    }
}
