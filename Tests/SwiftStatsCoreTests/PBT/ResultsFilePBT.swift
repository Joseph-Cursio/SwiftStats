import Foundation
import PropertyBased
@testable import SwiftStatsCore
import Testing

/// Properties of reading SwiftMutator's results.jsonl (M6, design §2,
/// `MutationResultsFile`'s header), over generated files
/// (`ResultsFileGen`) whose expected reading comes from
/// `ResultsFileModel`, stated from the reading rules: every line the
/// generator wrote as unreadable is skipped and no readable one is (P3.4);
/// the mutants are the model's (P3.5); the file is refused exactly when the
/// rules refuse it (P3.6); and appending a line that never reads, or
/// reordering `mutant` lines of different keys, changes only what the rules
/// say (P3.7). `MutationResultsTests` holds the fixed examples; each
/// property here has its own, calling its shared check, and meta-tests that
/// feed a planted defect's output to that check.
@Suite("Results file: properties", .tags(.pbt))
struct ResultsFilePBT {
    /// What reading a results file gives.
    typealias Read = Result<MutationResultsFile.Contents, MutationFailure>

    /// P3.4's base runs, over the engine's 100: one read of up to 17 lines
    /// costs well under a millisecond, and an `end` line whose only fault
    /// is a reason SwiftMutator doesn't write, the only input on which a
    /// reader that doesn't check the reason skips too few lines, comes in
    /// 37 of the meta-test's 1,000 files (design D14; 100 runs detected
    /// that defect in 19 of 20 calibration runs), so `(1 - 0.037)^300`,
    /// about 10^-5, is the most a run misses it.
    static let skippedRuns = 300
    /// What P3.4's tally counts when the model reads the file as results
    /// (design D14: `ResultsFileGenTests` counts 572 of 1,000 files).
    static let readsAsResults = "a file read as results"
    /// What it counts when such a file has a line skipped (500 of 1,000).
    static let skipsLines = "a file read as results with a line skipped"
    /// What it counts when such a file has a line with no bytes (159 of
    /// 1,000, so `(1 - 0.159)^300`, about 3 * 10^-23, is the most a run of
    /// `skippedRuns` misses it).
    static let hasBlank = "a file read as results with a line that isn't counted"
    /// The antecedents P3.4 must reach at least once each.
    static let skippedAntecedents = [readsAsResults, skipsLines, hasBlank]
    /// The recorded runs whose results files hold results: each fixture
    /// and case.
    static let recordedCases = [
        (MutationFixture.coverageDirectory, "full"), (MutationFixture.directory, "full"),
        (MutationFixture.directory, "since"), (MutationFixture.directory, "interrupted"),
        (MutationFixture.directory, "resumed")
    ]

    /// No flaw.
    static let intact = ResultsLineDraft.Flaw(kind: .intact, slot: 0)

    /// The results `read` holds; nil when it refused the file or found only
    /// a `stopped` line.
    static func results(of read: Read) -> MutationResults? {
        guard case let .success(.results(results)) = read else {
            return nil
        }
        return results
    }

    /// The bytes of each recorded run's results file that holds results.
    static func recordedFiles() throws -> [Data] {
        try recordedCases.map { fixture, name in
            try MutationFixture.data("results.jsonl", of: name, in: fixture)
        }
    }

    /// Records an issue naming `subject`, in ASCII, for each law in `laws`
    /// that fails; whether all hold.
    static func holds(_ laws: [(holds: Bool, law: String)], subject: String) -> Bool {
        for law in laws where law.holds == false {
            Issue.record(Comment(rawValue: PBTTrace.ascii("\(subject) fails: it \(law.law)")))
        }
        return laws.allSatisfy(\.holds)
    }

    /// A file of `drafts`, tagged in order, over the generator's fixed keys,
    /// each line ended by LF.
    static func draft(_ drafts: [ResultsLineDraft]) -> ResultsFileDraft {
        draft(drafts, crlf: false, finalBreak: true)
    }

    /// A file of `drafts`, tagged in order, over the generator's fixed keys,
    /// its lines ended by CRLF when `crlf`, the last one only when
    /// `finalBreak`.
    static func draft(_ drafts: [ResultsLineDraft], crlf: Bool, finalBreak: Bool) -> ResultsFileDraft {
        ResultsFileDraft(
            lines: drafts.enumerated().map { ResultsFileDraft.Line(tag: $0.offset, draft: $0.element) },
            keys: ResultsFileGen.fixedKeys,
            crlf: crlf,
            finalBreak: finalBreak
        )
    }

    /// A whole header of session `session` recording pool tree `tree`,
    /// listing the pool keys `notCovered` as not covered.
    static func header(session: Int, tree: Int, notCovered: [Int]) -> ResultsLineDraft {
        .header(ResultsLineDraft.HeaderDraft(
            session: session,
            formatVersion: ResultsFileModel.newestFormatVersion,
            tree: .whole(tree),
            listsNotCovered: true,
            notCovered: notCovered,
            flaw: intact
        ))
    }

    /// A whole `mutant` line of `session` for pool key `key`, failed by an
    /// exit.
    static func mutant(session: Int, key: Int) -> ResultsLineDraft {
        .mutant(ResultsLineDraft.MutantDraft(session: session, key: key, outcome: 0, ending: 0, flaw: intact))
    }

    /// What reading `draft` gives.
    static func read(_ draft: ResultsFileDraft) -> Read {
        Read { () throws(MutationFailure) in try MutationResultsFile.read(draft.data) }
    }

    /// `results` with `lines` as its skipped lines: a planted defect's
    /// reading of the same file.
    static func skipping(_ lines: [Int], _ results: MutationResults) -> MutationResults {
        MutationResults(
            mutants: results.mutants,
            facts: results.facts,
            sessions: results.sessions,
            formatVersions: results.formatVersions,
            tree: results.tree,
            listsNotCovered: results.listsNotCovered,
            controlRuns: results.controlRuns,
            controlFailures: results.controlFailures,
            end: results.end,
            tested: results.tested,
            skippedLines: lines,
            sha256: results.sha256
        )
    }

    /// Whether `results`, what a reader read (nil when it didn't read the
    /// file as results), skips `expected`, the lines the model labels
    /// unreadable, in order. Records an issue for each law that fails.
    static func checkSkipped(_ expected: [Int], results: MutationResults?) -> Bool {
        guard let results else {
            return holds([(false, "reads as results")], subject: "reading the file")
        }
        return holds(
            [(results.skippedLines == expected, "skips lines \(results.skippedLines), expected \(expected)")],
            subject: "reading the file"
        )
    }

    // MARK: P3.4

    /// Invariant: every line the generator wrote as unreadable is in
    /// `skippedLines`, and no readable one is.
    /// Why it holds: `MutationResultsFile`'s header and `read(_:)` (a line
    /// that doesn't read is skipped and counted; a line of a session no
    /// readable header started is skipped; unknown kinds are ignored), and
    /// `MutationResults.skippedLines` ("the 1-based numbers of the lines
    /// skipped"); a line with no bytes isn't a line, but under CRLF breaks
    /// it is a lone CR, which doesn't read.
    /// Why it might not: only files the model reads as results say which
    /// lines were skipped; a refused or `stopped`-only file is P3.6's.
    /// "Increasing and 1-based" holds by construction and isn't stated.
    /// Oracle: the generating model (`ResultsFileModel`); planted defects:
    /// line numbers counted from 0, a lone CR not counted, unknown kinds
    /// skipped, empty lines counted, a `mutant` line read without its
    /// session's header, an `end` line's reason not checked, and a
    /// `projectDelta`'s tree hash not checked, each detected.
    /// Tier: Strict (stop-ship).
    @Test(
        "every line written unreadable is skipped and counted, and no readable line is",
        .timeLimit(PBTBudget.timeLimit)
    )
    func unreadableLinesSkipped() async {
        let latch = FirstFailureLatch()
        let tally = AntecedentTally()
        await propertyCheck(count: PBTBudget.runs(Self.skippedRuns), input: ResultsFileGen.file) { file in
            PBTTrace.note(file)
            let expected = ResultsFileModel.expected(of: file.draft)
            guard expected.outcome == .results else {
                return
            }
            tally.fire(Self.readsAsResults)
            if expected.unreadable.isEmpty == false {
                tally.fire(Self.skipsLines)
            }
            if expected.labels.contains(.notCounted) {
                tally.fire(Self.hasBlank)
            }
            let read = Read { () throws(MutationFailure) in try MutationResultsFile.read(file.data) }
            if Self.checkSkipped(expected.unreadable, results: Self.results(of: read)) == false {
                PBTTrace.firstFailure(file, latch: latch)
            }
        }
        tally.report()
        tally.requireFired(Self.skippedAntecedents, unlessFailed: latch, sourceLocation: #_sourceLocation)
    }

    @Test("each recorded results file skips no line")
    func recordedFilesSkipNothing() throws {
        for data in try Self.recordedFiles() {
            let read = Read { () throws(MutationFailure) in try MutationResultsFile.read(data) }

            #expect(Self.checkSkipped([], results: Self.results(of: read)))
        }
    }

    @Test("""
        a recorded results file with a lone CR, a cut-off line, an empty line and a line of an unknown kind \
        appended skips the CR and the cut-off line only
        """)
    func recordedFileWithBrokenLines() throws {
        let recorded = try MutationFixture.data("results.jsonl", of: "full", in: MutationFixture.directory)
        let count = recorded.split(separator: ResultsLineRenderer.lineFeed).count
        let lastMutant = try #require(String(data: recorded, encoding: .utf8)?
            .split(separator: "\n")
            .last { $0.contains(#""kind":"mutant""#) })
        let broken = "\r\n" + lastMutant.prefix(lastMutant.count / 2) + "\n\n" + #"{"kind":"someday"}"# + "\n"
        let data = recorded + Data(broken.utf8)

        let read = Read { () throws(MutationFailure) in try MutationResultsFile.read(data) }

        #expect(Self.checkSkipped([count + 1, count + 2], results: Self.results(of: read)))
    }

    @Test("""
        under CRLF line breaks an empty line is a lone CR and is skipped, and a mutant line of a session no \
        header started is skipped; with no final break the last empty line isn't counted
        """)
    func crlfBlankLinesSkipped() {
        let lines = [
            Self.header(session: 1, tree: 0, notCovered: []), .blank, Self.mutant(session: 2, key: 0),
            Self.mutant(session: 1, key: 1), .blank
        ]
        let draft = Self.draft(lines, crlf: true, finalBreak: false)
        let expected = ResultsFileModel.expected(of: draft)

        let read = Read { () throws(MutationFailure) in try MutationResultsFile.read(draft.data) }

        #expect(expected.unreadable == [2, 3])
        #expect(expected.labels == [.readable, .unreadable, .unreadable, .readable, .notCounted])
        #expect(Self.checkSkipped(expected.unreadable, results: Self.results(of: read)))
    }

    @Test("a planted defect's skipped lines, for the input it is about, fail P3.4's law")
    func skippedDefectsDetected() throws {
        let header = Self.header(session: 1, tree: 0, notCovered: [])
        let fromZero = Self.draft([header, .garbage(0), Self.mutant(session: 1, key: 0), .garbage(1)])
        let loneCR = Self.draft([header, .blank, Self.mutant(session: 1, key: 0)], crlf: true, finalBreak: true)
        let unknown = Self.draft([header, .unknown(0), .garbage(0)])
        let whole = Self.draft([header, Self.mutant(session: 1, key: 0)])
        let fromZeroRead = try #require(Self.results(of: Self.read(fromZero)))
        let loneCRRead = try #require(Self.results(of: Self.read(loneCR)))
        let unknownRead = try #require(Self.results(of: Self.read(unknown)))
        let expected = [fromZero, loneCR, unknown, whole].map { ResultsFileModel.expected(of: $0).unreadable }

        // Each input holds what its defect is about, and the reader as built
        // passes on it. Each defect's reading is the reader's, changed as the
        // defect would change it: every number one less; line 2, the lone CR,
        // left out; line 2, the unknown kind, added.
        let countedFromZero = Self.skipping(fromZeroRead.skippedLines.map { $0 - 1 }, fromZeroRead)
        let crNotCounted = Self.skipping(loneCRRead.skippedLines.filter { $0 != 2 }, loneCRRead)
        let unknownSkipped = Self.skipping((unknownRead.skippedLines + [2]).sorted(), unknownRead)

        #expect(expected == [[2, 4], [2], [3], []])
        #expect(Self.checkSkipped(expected[0], results: fromZeroRead))
        #expect(Self.checkSkipped(expected[1], results: loneCRRead))
        #expect(Self.checkSkipped(expected[2], results: unknownRead))
        PlantedDefect.expectDetected("line numbers counted from 0", sourceLocation: #_sourceLocation) {
            Self.checkSkipped(expected[0], results: countedFromZero)
        }
        PlantedDefect.expectDetected("a lone CR not counted", sourceLocation: #_sourceLocation) {
            Self.checkSkipped(expected[1], results: crNotCounted)
        }
        PlantedDefect.expectDetected("a line of an unknown kind skipped", sourceLocation: #_sourceLocation) {
            Self.checkSkipped(expected[2], results: unknownSkipped)
        }
        PlantedDefect.expectDetected("a file with results refused", sourceLocation: #_sourceLocation) {
            Self.checkSkipped(expected[3], results: nil)
        }
    }
}
