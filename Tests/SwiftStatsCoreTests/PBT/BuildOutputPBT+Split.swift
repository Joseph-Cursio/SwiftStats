//
//  BuildOutputPBT+Split.swift
//  SwiftStatsCoreTests
//
//  P1.8: splitting the standard error between two lines, where no message
//  takes the line after and it is no origin note, gives the entries, the
//  counts and the diagnostics (kept once across both files) of the two
//  halves and the log read apart, concatenated; and moving one valid
//  timing line from the standard error into the task log leaves its entry
//  out and every count as it was (the diagnostics may change: the moved
//  line ended any message above it, and ends one where it goes).
//

import Foundation
import PropertyBased
@testable import SwiftStatsCore
import Testing

/// P1.8, its split and its move.
extension BuildOutputPBT {
    /// The three readings P1.8's split compares the whole with.
    struct SplitReadings {
        /// The standard error's first half, read alone.
        let first: BuildOutput
        /// Its second half, read alone.
        let second: BuildOutput
        /// The task log, read alone.
        let log: BuildOutput
    }

    /// P1.8's base runs for each of its two properties: the engine's
    /// default.
    static let splitRuns = 100
    /// What the split's tally counts when the standard error splits.
    static let splitDone = "a split"
    /// What the split's tally counts when it goes right after a header or a
    /// line its message took (design D14: the split generator's meta-test
    /// counts it in more than 0.3 of inputs).
    static let splitAfterMessage = "a split right after a message"
    /// What the move's tally counts when a timing line moves.
    static let moveDone = "a timing line moved"
    /// What the move's tally counts when the moved line ended a message.
    static let moveEndedMessage = "a moved line that ended a message"
    /// The antecedents the split must reach at least once each.
    static let splitAntecedents = [splitDone, splitAfterMessage]
    /// The antecedents the move must reach at least once each.
    static let moveAntecedents = [moveDone, moveEndedMessage]

    /// Whether `whole`, the reading of `split`'s files, is its `parts`
    /// concatenated: the entries and the counts of the two halves and the
    /// log, and their diagnostics kept once each, in that order. Records an
    /// issue for each law that fails.
    static func checkSplit(_ split: BuildOutputSplitGen.Split, whole: BuildOutput, parts: SplitReadings) -> Bool {
        let all = [parts.first, parts.second, parts.log]
        let diagnostics = keptOnce(all.flatMap(\.diagnostics))
        return holds(
            [
                (whole.entries == parts.first.entries + parts.second.entries, "reads the halves' entries, in order"),
                (
                    whole.diagnostics == diagnostics,
                    "reads the halves' and the log's diagnostics, kept once "
                        + "(\(firstDifference(whole.diagnostics, diagnostics)))"
                ),
                (
                    whole.unparsedTimingLines == parts.first.unparsedTimingLines + parts.second.unparsedTimingLines,
                    "counts the halves' refused timing lines"
                ),
                (whole.escapedLines == all.map(\.escapedLines).reduce(0, +), "counts the parts' escaped lines"),
                (
                    whole.otherWarningLines == all.map(\.otherWarningLines).reduce(0, +),
                    "counts the parts' other warning lines"
                )
            ],
            subject: "reading a standard error split before line \(split.index.map(String.init) ?? "none")"
        )
    }

    /// Whether `moved`, the reading of `move`'s files after its move, is
    /// `whole`, the reading before, without the moved line's entry and
    /// with every count as it was. Records an issue for each law that
    /// fails.
    static func checkMove(_ move: BuildOutputSplitGen.Move, whole: BuildOutput, moved: BuildOutput) -> Bool {
        var entries = whole.entries
        if let index = move.entryIndex, entries.indices.contains(index) {
            entries.remove(at: index)
        }
        return holds(
            [
                (
                    moved.entries == entries,
                    "reads the entries but the moved line's (\(moved.entries.count) of \(whole.entries.count))"
                ),
                (
                    moved.unparsedTimingLines == whole.unparsedTimingLines,
                    "counts the refused timing lines it counted before"
                ),
                (moved.escapedLines == whole.escapedLines, "counts the escaped lines it counted before"),
                (
                    moved.otherWarningLines == whole.otherWarningLines,
                    "counts the other warning lines it counted before"
                )
            ],
            subject: "reading a timing line moved from standard error line "
                + "\(move.index.map(String.init) ?? "none") into the log"
        )
    }

    /// The readings of `split`'s halves and log, each alone.
    static func parts(of split: BuildOutputSplitGen.Split) -> SplitReadings {
        SplitReadings(
            first: BuildOutputReader.read(stderr: split.first, log: Data()),
            second: BuildOutputReader.read(stderr: split.second, log: Data()),
            log: BuildOutputReader.read(stderr: Data(), log: split.sample.log)
        )
    }

    // MARK: P1.8, split

    /// Invariant: splitting the standard error between two lines, where no
    /// message takes the line after and it is no origin note, gives the
    /// entries, counts and diagnostics of the two halves and the log read
    /// apart, concatenated, the diagnostics kept once each.
    /// Why it holds: `BuildOutputReader`'s header (lines are read one by one,
    /// a diagnostic taking only the lines its message takes and reading only
    /// the origin note right after them; the two files' diagnostics kept
    /// once each, standard error first) and `read(stderr:log:)` (the counts
    /// add both files').
    /// Why it might not: a split before a line a message takes, or before
    /// an origin note a macro diagnostic reads, changes what the first half
    /// reads, so none is drawn there; the line before may be a header or a
    /// line its message took, and half the splits go there when they can,
    /// so that comes in some run (the tally).
    /// Oracle: metamorphic (each part read alone); planted defects: the
    /// line after a message skipped, and diagnostics not kept once each,
    /// each detected in 20 of 20 calibration runs.
    /// Tier: Strict (stop-ship).
    @Test(
        "splitting the standard error between two lines no message joins reads as its halves, concatenated",
        .timeLimit(PBTBudget.timeLimit)
    )
    func splitReadsAsHalves() async {
        let latch = FirstFailureLatch()
        let tally = AntecedentTally()
        await propertyCheck(count: PBTBudget.runs(Self.splitRuns), input: BuildOutputSplitGen.split) { split in
            PBTTrace.note(split)
            if split.index != nil {
                tally.fire(Self.splitDone)
            }
            if split.isAfterMessage {
                tally.fire(Self.splitAfterMessage)
            }
            let whole = BuildOutputReader.read(stderr: split.sample.stderr, log: split.sample.log)
            let parts = SplitReadings(
                first: BuildOutputReader.read(stderr: split.first, log: Data()),
                second: BuildOutputReader.read(stderr: split.second, log: Data()),
                log: BuildOutputReader.read(stderr: Data(), log: split.sample.log)
            )
            if Self.checkSplit(split, whole: whole, parts: parts) == false {
                PBTTrace.firstFailure(split, latch: latch)
            }
        }
        tally.report()
        tally.requireFired(Self.splitAntecedents, unlessFailed: latch, sourceLocation: #_sourceLocation)
    }

    @Test("""
        the recorded lines read as their halves, split before each line no message takes and that is no origin \
        note, right after the recorded warning first
        """)
    func recordedSplits() {
        let sample = GeneratedBuildOutput(
            rules: .decided,
            stderr: BuildFileDraft(
                blocks: BuildOutputGen.recordedGroups + BuildOutputGen.recordedTimings,
                decorations: [],
                terminated: true
            ),
            log: BuildFileDraft(blocks: [BuildOutputGen.recordedGroups[1]], decorations: [], terminated: true)
        )
        let whole = BuildOutputReader.read(stderr: sample.stderr, log: sample.log)

        #expect(BuildOutputSplitGen.Split(sample: sample, afterMessage: true, choice: 0).index == 1)
        for choice in sample.stderrLines.indices {
            for afterMessage in [false, true] {
                let split = BuildOutputSplitGen.Split(sample: sample, afterMessage: afterMessage, choice: choice)
                let index = split.index ?? 0

                #expect(sample.stderrLines[index].reading != .continuation)
                #expect(BuildOutputSplitGen.isOrigin(sample.stderrLines[index].shape) == false)
                #expect(Self.checkSplit(split, whole: whole, parts: Self.parts(of: split)))
            }
        }
    }

    @Test("a split between a message with no ID and the stopper after it reads as its halves (decided U10)")
    func unidentifiedSplit() {
        let sample = Self.output(
            [
                Self.plainWarning("w"),
                BuildLineDraft(.plain(SuffixedText("second")), text: "second", traits: []),
                BuildLineDraft(.stopper, text: "info: done", traits: []),
                Self.plainWarning("w")
            ],
            log: []
        )
        let split = BuildOutputSplitGen.Split(sample: sample, afterMessage: true, choice: 0)
        let whole = BuildOutputReader.read(stderr: sample.stderr, log: sample.log)

        #expect(split.index == 2)
        #expect(Self.checkSplit(split, whole: whole, parts: Self.parts(of: split)))
        #expect(whole.diagnostics.map(\.message) == ["w\nsecond", "w"])
    }

    // MARK: P1.8, move

    /// Invariant: moving one valid timing line from the standard error into
    /// the task log leaves out its entry and every count as it was.
    /// Why it holds: `BuildOutputReader`'s header (timing lines are read on
    /// the standard error only; a line holding `ms<TAB>` never continues a
    /// message, in either file; escapes are counted in both files) and
    /// `read(stderr:log:)` (only the standard error's refused timing lines
    /// are counted).
    /// Why it might not: the diagnostics may change, since the moved line
    /// ended any message above it and ends one where it goes, so they are
    /// left out of the law; a moved line with no line break gets one, and
    /// so does the log's last line when the moved line goes after it. Half
    /// the moves take a line that ended a message when there is one, so
    /// that comes in some run (the tally).
    /// Oracle: metamorphic (the reading before the move); planted defects:
    /// the log's timing lines read as entries, and only the standard
    /// error's escaped lines counted, each detected in 20 of 20
    /// calibration runs.
    /// Tier: Strict (stop-ship).
    @Test(
        "moving a valid timing line from the standard error into the log leaves its entry out and every count",
        .timeLimit(PBTBudget.timeLimit)
    )
    func moveLeavesEntryOut() async {
        let latch = FirstFailureLatch()
        let tally = AntecedentTally()
        await propertyCheck(count: PBTBudget.runs(Self.splitRuns), input: BuildOutputSplitGen.move) { move in
            PBTTrace.note(move)
            if move.index != nil {
                tally.fire(Self.moveDone)
            }
            if move.endsMessage {
                tally.fire(Self.moveEndedMessage)
            }
            let whole = BuildOutputReader.read(stderr: move.sample.stderr, log: move.sample.log)
            let moved = BuildOutputReader.read(stderr: move.stderr, log: move.log)
            if Self.checkMove(move, whole: whole, moved: moved) == false {
                PBTTrace.firstFailure(move, latch: latch)
            }
        }
        tally.report()
        tally.requireFired(Self.moveAntecedents, unlessFailed: latch, sourceLocation: #_sourceLocation)
    }

    @Test("the recorded function body's timing line moved into the log reads as no entry, and every count stays")
    func recordedMove() {
        let sample = GeneratedBuildOutput(
            rules: .decided,
            stderr: BuildFileDraft(blocks: BuildOutputGen.recordedTimings, decorations: [], terminated: true),
            log: BuildFileDraft(blocks: BuildOutputGen.recordedGroups, decorations: [], terminated: false)
        )
        let move = BuildOutputSplitGen.Move(sample: sample, afterMessage: false, choice: 1, position: Int.max)
        let whole = BuildOutputReader.read(stderr: sample.stderr, log: sample.log)
        let moved = BuildOutputReader.read(stderr: move.stderr, log: move.log)

        #expect(Self.checkMove(move, whole: whole, moved: moved))
        #expect(moved.entries.map(\.hundredths) == [1, BuildOutputGen.ringHundredths, BuildOutputGen.bufferHundredths])
    }

    @Test("a timing line that ended a message with no ID, moved into the log, lets the message go on (decided U10)")
    func movedLineEndedMessage() {
        let sample = Self.output(
            [
                Self.plainWarning("w"),
                Self.timing("1.00", hundredths: 100, place: nil),
                BuildLineDraft(.plain(SuffixedText("second")), text: "second", traits: [])
            ],
            log: [Self.plainWarning("v")]
        )
        let move = BuildOutputSplitGen.Move(sample: sample, afterMessage: true, choice: 0, position: 1)
        let whole = BuildOutputReader.read(stderr: sample.stderr, log: sample.log)
        let moved = BuildOutputReader.read(stderr: move.stderr, log: move.log)

        #expect(move.endsMessage)
        #expect(Self.checkMove(move, whole: whole, moved: moved))
        #expect(moved.diagnostics.map(\.message) == ["w\nsecond", "v"])
    }

    @Test("a planted defect's reading fails P1.8's laws")
    func splitDefectsDetected() {
        let sample = Self.output(
            [Self.plainWarning("w"), Self.timing("1.00", hundredths: 100, place: nil)],
            log: [Self.plainWarning("w")]
        )
        let split = BuildOutputSplitGen.Split(sample: sample, afterMessage: true, choice: 0)
        let whole = BuildOutputReader.read(stderr: sample.stderr, log: sample.log)
        let skipped = Self.output(whole, entries: [])
        let twice = BuildOutput(
            entries: whole.entries,
            diagnostics: whole.diagnostics + whole.diagnostics,
            escapedLines: 0,
            unparsedTimingLines: 0,
            otherWarningLines: 0
        )
        let move = BuildOutputSplitGen.Move(sample: sample, afterMessage: false, choice: 0, position: 0)

        PlantedDefect.expectDetected("the line after a message skipped", sourceLocation: #_sourceLocation) {
            Self.checkSplit(split, whole: skipped, parts: Self.parts(of: split))
        }
        PlantedDefect.expectDetected("diagnostics not kept once each", sourceLocation: #_sourceLocation) {
            Self.checkSplit(split, whole: twice, parts: Self.parts(of: split))
        }
        PlantedDefect.expectDetected("the log's timing lines read as entries", sourceLocation: #_sourceLocation) {
            Self.checkMove(move, whole: whole, moved: whole)
        }
    }
}
