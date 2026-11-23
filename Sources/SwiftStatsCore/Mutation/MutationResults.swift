//
//  MutationResults.swift
//  SwiftStatsCore
//
//  What a results file with at least one readable header holds, read by
//  the rules of design §2: the winning line of each key and the last
//  header's not-covered mutants, the run's facts and tree, its control
//  runs and end, whether it is complete, and the lines skipped.
//

/// The results a SwiftMutator results file records.
struct MutationResults: Equatable, Sendable {
    /// A session's `end` line.
    struct End: Equatable, Sendable {
        /// `finished`, `aborted` or `interrupted`.
        let reason: String
        /// The abort's code or the signal's name.
        let detail: String?
        /// When the session ended, as SwiftMutator wrote it.
        let endedAt: String
    }

    /// The most skipped line numbers a warning lists.
    static let listedSkippedLines = 10
    /// What the warning about skipped lines says before the count.
    private static let skippedLinesLead = MutationAdapter.name + ": skipped "
    /// What it says between the count and the line numbers.
    private static let skippedLinesText = " of the results file that didn't read ("

    /// Every mutant, tested or not covered, sorted by key.
    let mutants: [RecordedMutant]
    /// The run's facts.
    let facts: MutationRunFacts
    /// How many readable sessions the file holds.
    let sessions: Int
    /// The readable headers' format versions, sorted, each once.
    let formatVersions: [Int]
    /// The last readable header's tree, rebuilt through `projectDelta`;
    /// empty when it records none.
    let tree: [String: String]
    /// Whether the last readable header lists the mutants of code no test
    /// ran (`mutantsNotCovered` present, or coverage off, which has none).
    let listsNotCovered: Bool
    /// How many control runs the file records, and how many didn't pass.
    let controlRuns: Int
    /// How many control runs failed, crashed or timed out.
    let controlFailures: Int
    /// The last session's end; nil when it wrote none (killed, crashed).
    let end: End?
    /// How many keys the winning `mutant` lines hold.
    let tested: Int
    /// The 1-based numbers of the lines skipped: those that don't read,
    /// and those of a session no readable header started.
    let skippedLines: [Int]
    /// The file's SHA-256.
    let sha256: String

    /// Whether the last session finished and every mutant its header
    /// discovered has a result.
    var complete: Bool {
        end?.reason == "finished" && tested == facts.mutantsDiscovered
    }

    /// Why the results are incomplete; nil when they are complete.
    var incompleteReason: String? {
        guard complete == false else {
            return nil
        }
        let ending = end.map { "ended \($0.reason)" } ?? "with no end line"
        return "the results file is incomplete (\(tested) of \(facts.mutantsDiscovered) mutants, \(ending))"
    }

    /// The warning about skipped lines, naming the first ten; nil when
    /// none was skipped.
    var skippedLinesWarning: String? {
        guard skippedLines.isEmpty == false else {
            return nil
        }
        let listed = skippedLines.prefix(Self.listedSkippedLines).map(String.init).joined(separator: ", ")
        let more = skippedLines.count > Self.listedSkippedLines ? ", …" : ""
        let count = skippedLines.count == 1 ? "1 line" : "\(skippedLines.count) lines"
        return Self.skippedLinesLead + count + Self.skippedLinesText + listed + more + ")"
    }

    /// Whether `warning` is one `skippedLinesWarning` gives.
    static func isSkippedLinesWarning(_ warning: ScanWarning) -> Bool {
        warning.file == nil && warning.message.hasPrefix(skippedLinesLead)
            && warning.message.contains(skippedLinesText) && warning.message.hasSuffix(")")
    }
}
