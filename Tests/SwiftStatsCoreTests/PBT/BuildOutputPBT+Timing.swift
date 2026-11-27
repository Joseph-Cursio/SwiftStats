//
//  BuildOutputPBT+Timing.swift
//  SwiftStatsCoreTests
//
//  P1.2: every standard error line holding `ms<TAB>` is an entry or is
//  counted unparsed, and no diagnostic's message takes one, wherever it
//  stands, since B10's fix (decided U10) a message open above it included.
//  P1.4: every timing entry the grammar can state reads back from the line
//  `BuildLineRenderer` writes for it, paired with P1.3, which states the
//  time's value.
//

import Foundation
import PropertyBased
@testable import SwiftStatsCore
import Testing

/// P1.2 and P1.4.
extension BuildOutputPBT {
    /// P1.2's base runs: the engine's default.
    static let timingLineRuns = 100
    /// P1.4's base runs, over the engine's 100: one `timingEntry` call
    /// costs microseconds and the domain is flat, so more draws cost
    /// nothing and reach more path and number classes.
    static let renderedRuns = 300
    /// What P1.2's tally counts when the standard error holds a timing line
    /// the grammar refuses.
    static let refusedLine = "a refused timing line"
    /// What P1.2's tally counts when a refused timing line comes right after
    /// a header or a line its message took (design D14: the generator's
    /// meta-test counts it in 262 of 1,000 outputs, and `(1 - 0.262)^100`,
    /// about 6 * 10^-14, is below 10^-6, so 100 runs suffice).
    static let refusedInMessage = "a refused timing line right after a message's line"
    /// The antecedents P1.2 must reach at least once each.
    static let timingLineAntecedents = [refusedLine, refusedInMessage]
    /// The UTF-8 bytes of `ms<TAB>`, as the grammar's doc comment states
    /// the mark a timing line holds.
    static let timingMarkBytes = Array("ms\t".utf8)
    /// The column of the examples' plain warning.
    static let warningColumn = 2
    /// The place of the examples' plain warning.
    static let warningPlace = BuildPlace(path: "/p/a.swift", line: 1, column: warningColumn)

    /// Whether `text` holds `ms<TAB>`: its three bytes in a row.
    static func holdsMark(_ text: String) -> Bool {
        let bytes = Array(text.utf8)
        guard bytes.count >= timingMarkBytes.count else {
            return false
        }
        return (0...(bytes.count - timingMarkBytes.count)).contains { start in
            bytes[start..<(start + timingMarkBytes.count)].elementsEqual(timingMarkBytes)
        }
    }

    /// Whether `sample`'s files read as `read` as P1.2 states: each
    /// standard error line holding `ms<TAB>` an entry or counted unparsed,
    /// the count the labels state, and no diagnostic's message holding
    /// one. Records an issue for each law that fails.
    static func checkTimingLines(_ sample: GeneratedBuildOutput, read: BuildOutput) -> Bool {
        let marked = sample.stderrLines.count { holdsMark($0.text) }
        return holds(
            [
                (
                    read.entries.count + read.unparsedTimingLines == marked,
                    "reads each of its \(marked) standard error lines holding ms<TAB> as an entry or counts it "
                        + "(\(read.entries.count) entries, \(read.unparsedTimingLines) counted)"
                ),
                (
                    read.unparsedTimingLines == sample.unparsedTimingLines,
                    "counts the \(sample.unparsedTimingLines) refused timing lines its labels state "
                        + "(counted \(read.unparsedTimingLines))"
                ),
                (
                    read.diagnostics.allSatisfy { holdsMark($0.message) == false },
                    "takes no line holding ms<TAB> into a diagnostic's message"
                )
            ],
            subject: "reading \(marked) timing lines"
        )
    }

    /// Whether `read`, what the grammar read from `line`'s text, is the
    /// entry it was written from. Records an issue when it isn't.
    static func checkRendered(_ line: TimingEntryGen.Line, read: TimingEntry?) -> Bool {
        guard read == line.entry else {
            let readText = read.map { "\($0)" } ?? "none"
            let text = "\(line.text.debugDescription) reads as \(readText), expected \(line.entry)"
            Issue.record(Comment(rawValue: PBTTrace.ascii(text)))
            return false
        }
        return true
    }

    /// The plain warning `/p/a.swift:1:2: warning: <message>` with no
    /// ID.
    static func plainWarning(_ message: String) -> BuildLineDraft {
        BuildLineDraft(
            .header(
                location: .file(warningPlace),
                severity: .warning,
                message: SuffixedText(message)
            ),
            text: "/p/a.swift:1:2: warning: \(message)",
            traits: []
        )
    }

    // MARK: P1.2

    /// Invariant: every standard error line holding `ms<TAB>` reads as an
    /// entry or is counted unparsed, as many are counted as the labels
    /// state, and no diagnostic's message takes such a line.
    /// Why it holds: `BuildOutputReader`'s header (a line holding
    /// `ms<TAB>` that doesn't read is counted; a message takes only lines
    /// that can't be anything else, and a line holding `ms<TAB>` is never
    /// one, so a refused timing line ends the message and on the standard
    /// error is counted) and `BuildLineGrammar.continues` (design B10,
    /// decided U10: whether or not it reads as a timing entry).
    /// Why it might not: the mark is found in bytes, so a Prepend scalar
    /// before `ms` doesn't hide it (U13). No header line itself holds
    /// `ms<TAB>` (the generator writes none; such a line would be counted
    /// and read as a diagnostic). Lines of the task log are never counted.
    /// Since B10's fix the generator places refused timing lines anywhere,
    /// right after a header or a line its message took included, and draws
    /// that shape as a block of its own so that it comes in some run (the
    /// tally).
    /// Oracle: the generator's labels and the lines' own bytes;
    /// planted defects: B10's fix undone (a refused line continues a
    /// message), a refused line not counted, and the mark looked for among
    /// Characters (a Prepend scalar before `ms` hides it), each detected in
    /// 20 of 20 calibration runs.
    /// Tier: Strict (stop-ship).
    @Test(
        "every standard error line holding ms<TAB> is an entry or counted, and no message takes one",
        .timeLimit(PBTBudget.timeLimit)
    )
    func timingLinesAccounted() async {
        let latch = FirstFailureLatch()
        let tally = AntecedentTally()
        let input = BuildOutputGen.output(.decided)
        await propertyCheck(count: PBTBudget.runs(Self.timingLineRuns), input: input) { sample in
            PBTTrace.note(sample)
            if sample.unparsedTimingLines > 0 {
                tally.fire(Self.refusedLine)
            }
            if BuildOutputGen.refusesInMessage(sample.stderrLines) {
                tally.fire(Self.refusedInMessage)
            }
            let read = BuildOutputReader.read(stderr: sample.stderr, log: sample.log)
            if Self.checkTimingLines(sample, read: read) == false {
                PBTTrace.firstFailure(sample, latch: latch)
            }
        }
        tally.report()
        tally.requireFired(Self.timingLineAntecedents, unlessFailed: latch, sourceLocation: #_sourceLocation)
    }

    @Test("the recorded timing lines are entries, and the recorded diagnostics' messages hold no timing mark")
    func recordedTimingLines() {
        let sample = GeneratedBuildOutput(
            rules: .decided,
            stderr: BuildFileDraft(
                blocks: BuildOutputGen.recordedGroups + BuildOutputGen.recordedTimings,
                decorations: [],
                terminated: true
            ),
            log: BuildFileDraft(blocks: [], decorations: [], terminated: true)
        )
        let read = BuildOutputReader.read(stderr: sample.stderr, log: sample.log)

        #expect(Self.checkTimingLines(sample, read: read))
        #expect(read.entries.count == BuildOutputGen.recordedTimings.count)
    }

    @Test("""
        B10: a refused timing line inside a message with no ID ends it there and is counted, though a later \
        line ends with an ID (decided U10)
        """)
    func refusedLineEndsMessage() {
        let identified = SuffixedText(body: "third", identifier: .valid("deprecated_declaration"), group: .absent)
        let sample = Self.output(
            [
                Self.plainWarning("w"),
                BuildLineDraft(.plain(SuffixedText("second")), text: "second", traits: []),
                BuildLineDraft(.malformedTiming, text: "4.355ms\t/p/a.swift:1:2", traits: []),
                BuildLineDraft(.plain(identified), text: identified.rendered, traits: [])
            ],
            log: []
        )
        let read = BuildOutputReader.read(stderr: sample.stderr, log: sample.log)

        #expect(Self.checkTimingLines(sample, read: read))
        #expect(read.diagnostics.map(\.message) == ["w\nsecond"])
        #expect(read.diagnostics.map(\.identifier) == [nil])
        #expect(read.unparsedTimingLines == 1)
    }

    @Test("in the task log a refused timing line also ends a message, and isn't counted")
    func refusedLineInLog() {
        let sample = Self.output(
            [],
            log: [
                Self.plainWarning("w"),
                BuildLineDraft(.malformedTiming, text: "4.35\u{600}ms\t<invalid loc>", traits: [])
            ]
        )
        let read = BuildOutputReader.read(stderr: sample.stderr, log: sample.log)

        #expect(Self.checkTimingLines(sample, read: read))
        #expect(read.diagnostics.map(\.message) == ["w"])
        #expect(read.unparsedTimingLines == 0)
    }

    @Test("a planted defect's reading fails P1.2's laws")
    func timingLineDefectsDetected() {
        let refused = BuildLineDraft(.malformedTiming, text: "4.355ms\t/p/a.swift:1:2", traits: [])
        let sample = Self.output([Self.plainWarning("w"), refused], log: [])
        let read = BuildOutputReader.read(stderr: sample.stderr, log: sample.log)
        let absorbed = BuildDiagnostic(
            severity: .warning,
            location: .file(BuildPlace(path: "/p/a.swift", line: 1, column: 2)),
            message: "w\n" + refused.text,
            identifier: nil,
            group: nil,
            origin: nil
        )
        let continued = BuildOutput(
            entries: [],
            diagnostics: [absorbed],
            escapedLines: 0,
            unparsedTimingLines: 0,
            otherWarningLines: 0
        )
        let uncounted = BuildOutput(
            entries: [],
            diagnostics: read.diagnostics,
            escapedLines: 0,
            unparsedTimingLines: 0,
            otherWarningLines: 0
        )

        PlantedDefect.expectCaught("B10's fix undone: the refused line taken", sourceLocation: #_sourceLocation) {
            Self.checkTimingLines(sample, read: continued)
        }
        PlantedDefect.expectCaught("a refused line not counted", sourceLocation: #_sourceLocation) {
            Self.checkTimingLines(sample, read: uncounted)
        }
    }

    // MARK: P1.4

    /// Invariant: every timing entry the grammar can state reads back from
    /// the line written for it, whichever of its forms the time is written
    /// in.
    /// Why it holds: `BuildLineGrammar`'s header (a time with at most twelve
    /// whole digits, a tab, `<invalid loc>` or `<path>:<line>:<column>`
    /// split from the right, so a path may hold colons and spaces, and for
    /// a function body a tab and its declaration) and `timingEntry`'s and
    /// `splitPlace`'s doc comments (a path isn't empty and doesn't start
    /// with white space; its colons are found among scalars, B23).
    /// Why it might not: a path or declaration holding a tab, an empty
    /// one, or a path starting with white space is no entry the grammar
    /// states, so none is drawn; lines and columns go up to `Int.max`, and
    /// times up to twelve whole digits. The round trip is the grammar's
    /// own (`timingEntry`): line breaks and escapes in a path are the
    /// reader's business before it, not the grammar's, so they are drawn.
    /// Oracle: round trip through `BuildLineRenderer`, written from the
    /// grammar's header, paired with P1.3 (the time's value against a
    /// reference); planted defects: a place split at its first colon, a
    /// path refused for any white space, and a one-digit fraction read
    /// unscaled, each detected.
    /// Tier: Strict (stop-ship).
    @Test(
        "every timing entry the grammar can state reads back from its line, in each form",
        .timeLimit(PBTBudget.timeLimit)
    )
    func renderedEntriesReadBack() async {
        let latch = FirstFailureLatch()
        await propertyCheck(count: PBTBudget.runs(Self.renderedRuns), input: TimingEntryGen.line) { line in
            PBTTrace.note(line)
            if Self.checkRendered(line, read: BuildLineGrammar.timingEntry(line.text)) == false {
                PBTTrace.firstFailure(line, latch: latch)
            }
        }
    }

    @Test("the recorded timing lines are written back as recorded, and read back")
    func recordedEntriesWritten() {
        for block in BuildOutputGen.recordedTimings {
            for draft in block {
                guard case .timing(let entry) = draft.shape else {
                    Issue.record("recorded timing line \(draft.text.debugDescription) isn't labelled a timing line")
                    continue
                }
                let line = TimingEntryGen.Line(entry: entry, style: .plain)

                #expect(line.text == draft.text)
                #expect(Self.checkRendered(line, read: BuildLineGrammar.timingEntry(line.text)))
            }
        }
    }

    @Test(
        "a path with colons, spaces, a Prepend scalar and a line break, at the largest line and column, reads back",
        arguments: BuildLineRenderer.TimeForm.allCases
    )
    func oddEntryReadsBack(form: BuildLineRenderer.TimeForm) {
        let path = "/Volumes/x:y/a b:12:34/\u{1F1EF}\u{1F1F5}\n\u{600}"
        let place = BuildPlace(path: path, line: Int.max, column: Int.max)
        let entry = TimingEntry(kind: .function, hundredths: 99_999_999_999_900, place: place, declaration: " é ")
        let line = TimingEntryGen.Line(
            entry: entry,
            style: BuildLineRenderer.Style(form: form, padding: 0, paddedNumbers: true)
        )

        #expect(Self.checkRendered(line, read: BuildLineGrammar.timingEntry(line.text)))
    }

    @Test(
        "each form of a time reads back as the same hundredths",
        arguments: zip(
            [
                "4.3ms\t<invalid loc>",
                "4.30ms\t<invalid loc>",
                "004.3ms\t<invalid loc>",
                "000000000004.30ms\t<invalid loc>"
            ],
            [
                BuildLineRenderer.Style(form: .tenths, padding: 0, paddedNumbers: false),
                BuildLineRenderer.Style(form: .twoDigits, padding: 0, paddedNumbers: false),
                BuildLineRenderer.Style(form: .tenths, padding: 2, paddedNumbers: false),
                BuildLineRenderer.Style(form: .whole, padding: 20, paddedNumbers: false)
            ]
        )
    )
    func timeFormsReadBack(text: String, style: BuildLineRenderer.Style) {
        let entry = TimingEntry(kind: .expression, hundredths: 430, place: nil, declaration: nil)
        let line = TimingEntryGen.Line(entry: entry, style: style)

        #expect(line.text == text)
        #expect(Self.checkRendered(line, read: BuildLineGrammar.timingEntry(line.text)))
    }

    @Test("a planted defect's reading fails P1.4's law")
    func renderedDefectsDetected() {
        let place = BuildPlace(path: "/x:y/a b.swift", line: 3, column: 4)
        let line = TimingEntryGen.Line(
            entry: TimingEntry(kind: .function, hundredths: 430, place: place, declaration: "getter M.(file).v"),
            style: BuildLineRenderer.Style(form: .tenths, padding: 0, paddedNumbers: false)
        )
        let splitFirst = TimingEntry(
            kind: .function,
            hundredths: 430,
            place: BuildPlace(path: "/x", line: 0, column: 3),
            declaration: "getter M.(file).v"
        )
        let unscaled = TimingEntry(kind: .function, hundredths: 403, place: place, declaration: "getter M.(file).v")

        PlantedDefect.expectCaught("a place split at its first colon", sourceLocation: #_sourceLocation) {
            Self.checkRendered(line, read: splitFirst)
        }
        PlantedDefect.expectCaught("a path with a space refused", sourceLocation: #_sourceLocation) {
            Self.checkRendered(line, read: nil)
        }
        PlantedDefect.expectCaught("a one-digit fraction read unscaled", sourceLocation: #_sourceLocation) {
            Self.checkRendered(line, read: unscaled)
        }
    }
}
