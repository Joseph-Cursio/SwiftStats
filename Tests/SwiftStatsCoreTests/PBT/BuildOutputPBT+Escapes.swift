//
//  BuildOutputPBT+Escapes.swift
//  SwiftStatsCoreTests
//
//  P1.6: writing ANSI or OSC-8 escape sequences into lines that hold none
//  changes nothing the reader returns but `escapedLines`, which grows by
//  the number of lines newly wrapped. Since B24's fix (decided U13) the
//  sequences go at any Unicode scalar boundary, inside a Character
//  included, so a sequence's last scalar may join the scalar after it.
//

import Foundation
import PropertyBased
@testable import SwiftStatsCore
import Testing

/// P1.6.
extension BuildOutputPBT {
    /// P1.6's base runs: the engine's default.
    static let escapeRuns = 100
    /// What P1.6's tally counts when a wrap writes sequences into a line.
    static let wrappedLine = "a line newly wrapped"
    /// What P1.6's tally counts when a sequence goes inside a Character.
    static let insideCharacter = "a sequence inside a Character"
    /// What P1.6's tally counts when a sequence's last scalar joins the
    /// scalar after it into one Character (B24's shape; design D14: the
    /// wrap generator's meta-test counts it in more than 0.3 of inputs).
    static let joiningSequence = "a sequence joining the scalar after it"
    /// What P1.6's tally counts when a backslash follows an OSC-8 link
    /// ended by BEL, where it is text (design D14: counted by the wrap
    /// generator's meta-test).
    static let bellBeforeBackslash = "a BEL-ended sequence before a backslash"
    /// The antecedents P1.6 must reach at least once each.
    static let escapeAntecedents = [wrappedLine, insideCharacter, joiningSequence, bellBeforeBackslash]
    /// How far apart the colour resets of the recorded example's lines are,
    /// in scalars, so each line's reset goes somewhere else.
    static let colourStep = 7

    /// Whether `read`, the reading of `wrapped`'s files, is `original`, the
    /// reading of its files without the wraps' sequences, but for
    /// `escapedLines`, which grows by the lines newly wrapped. Records an
    /// issue for each law that fails.
    static func checkEscapes(_ wrapped: EscapeWrapGen.Wrapped, original: BuildOutput, read: BuildOutput) -> Bool {
        let added = wrapped.newlyWrapped
        return holds(
            [
                (read.entries == original.entries, "reads the entries it read before the wrap"),
                (
                    read.diagnostics == original.diagnostics,
                    "reads the diagnostics it read before the wrap "
                        + "(\(firstDifference(read.diagnostics, original.diagnostics)))"
                ),
                (
                    read.unparsedTimingLines == original.unparsedTimingLines,
                    "counts the refused timing lines it counted before"
                ),
                (
                    read.otherWarningLines == original.otherWarningLines,
                    "counts the other warning lines it counted before"
                ),
                (
                    read.escapedLines == original.escapedLines + added,
                    "counts \(original.escapedLines) escaped lines and the \(added) newly wrapped "
                        + "(counted \(read.escapedLines))"
                )
            ],
            subject: "reading \(added) newly wrapped lines"
        )
    }

    /// The wrapped output of `stderr` and `log`, each line wrapped by the
    /// wrap at its index in `wraps` (standard error's first), whatever
    /// line that wrap names.
    static func wrapped(
        _ stderr: [BuildLineDraft],
        log: [BuildLineDraft],
        wraps: [EscapeWrapGen.Wrap]
    ) -> EscapeWrapGen.Wrapped {
        let placed = wraps.indices.map { index in
            let wrap = wraps[index]
            return EscapeWrapGen.Wrap(
                line: index,
                kind: wrap.kind,
                start: wrap.start,
                end: wrap.end,
                beforeJoiner: wrap.beforeJoiner,
                joiner: wrap.joiner,
                backslash: wrap.backslash
            )
        }
        return EscapeWrapGen.Wrapped(original: output(stderr, log: log), wraps: placed)
    }

    /// A wrap of `kind` from `start` to `end`, before joining scalars when
    /// `joining`, of the first line until `wrapped(_:log:wraps:)` places it.
    static func wrap(_ kind: EscapeWrapGen.Kind, _ start: Int, _ end: Int, joining: Bool) -> EscapeWrapGen.Wrap {
        EscapeWrapGen.Wrap(
            line: 0,
            kind: kind,
            start: start,
            end: end,
            beforeJoiner: joining,
            joiner: nil,
            backslash: false
        )
    }

    // MARK: P1.6

    /// Invariant: writing ANSI or OSC-8 escape sequences into lines that
    /// hold none changes nothing the reader returns but `escapedLines`,
    /// which grows by the number of lines newly wrapped.
    /// Why it holds: `BuildOutputReader`'s header (each line loses its
    /// escapes first, counted) and `BuildLineEscapes`' (CSI, OSC by BEL or
    /// `ESC \` and two-character escapes are taken out, read on Unicode
    /// scalars, so a combining mark after a sequence's last scalar isn't
    /// part of it; design B24, decided U13).
    /// Why it might not: a line that holds an escape, or isn't UTF-8, isn't
    /// wrapped (its escapes are already counted, or it is read as Latin-1);
    /// a cut-off sequence goes only at a line's end, where it swallows no
    /// text; no sequence goes before a byte order mark that starts a line,
    /// which the reader's UTF-8 decoding drops there and nowhere else. The
    /// sequences go at any scalar boundary since U13, inside Characters
    /// included, so half the wraps go before a joining scalar, and a third
    /// first write one into the line (in both files compared), so a
    /// sequence joins the next scalar in some run (the tally); a quarter
    /// write a backslash after their last sequence, which is text after a
    /// BEL and would end the OSC only after `ESC`.
    /// Oracle: metamorphic (the reading of the same lines without the
    /// sequences);
    /// planted defects: escapes read on Characters again (B24's fix
    /// undone), a two-character escape taking two scalars after it, and the
    /// log's escaped lines not counted, each detected in 20 of 20
    /// calibration runs.
    /// Tier: Strict (stop-ship).
    @Test(
        "writing escapes into lines that hold none changes nothing read but the escaped lines, by those wrapped",
        .timeLimit(PBTBudget.timeLimit)
    )
    func escapesChangeNothing() async {
        let latch = FirstFailureLatch()
        let tally = AntecedentTally()
        await propertyCheck(count: PBTBudget.runs(Self.escapeRuns), input: EscapeWrapGen.wrapped) { wrapped in
            PBTTrace.note(wrapped)
            let lines = wrapped.stderrLines + wrapped.logLines
            let fired = [
                (lines.contains(where: \.isWrapped), Self.wrappedLine),
                (lines.contains(where: \.isInsideCharacter), Self.insideCharacter),
                (lines.contains(where: \.joins), Self.joiningSequence),
                (wrapped.bellBeforeBackslash, Self.bellBeforeBackslash)
            ]
            for (didFire, label) in fired where didFire {
                tally.fire(label)
            }
            let original = BuildOutputReader.read(stderr: wrapped.plainStderr, log: wrapped.plainLog)
            let read = BuildOutputReader.read(stderr: wrapped.stderr, log: wrapped.log)
            if Self.checkEscapes(wrapped, original: original, read: read) == false {
                PBTTrace.firstFailure(wrapped, latch: latch)
            }
        }
        tally.report()
        tally.requireFired(Self.escapeAntecedents, unlessFailed: latch, sourceLocation: #_sourceLocation)
    }

    @Test("the recorded warning and its excerpt, each line given a colour, read as before, six more lines escaped")
    func recordedLinesColoured() {
        let group = BuildOutputGen.recordedGroups[0]
        let wraps = group.indices.map { Self.wrap(.csi, 0, $0 * Self.colourStep, joining: false) }
        let wrapped = Self.wrapped(group, log: [], wraps: wraps)
        let original = BuildOutputReader.read(stderr: wrapped.plainStderr, log: wrapped.plainLog)
        let read = BuildOutputReader.read(stderr: wrapped.stderr, log: wrapped.log)

        #expect(Self.checkEscapes(wrapped, original: original, read: read))
        #expect(read.escapedLines == group.count)
    }

    @Test(
        "B24: a sequence just before a combining mark or a joiner keeps it, so the message reads as before",
        arguments: [EscapeWrapGen.Kind.csi, .oscTerminated, .twoCharacter]
    )
    func joiningSequenceKeepsMark(kind: EscapeWrapGen.Kind) {
        let message = SuffixedText(
            body: "use cafe\u{301} or \u{1F469}\u{200D}\u{1F4BB}",
            identifier: .valid("bridged_warning"),
            group: .absent
        )
        let header = BuildLineDraft(
            .header(
                location: .file(BuildPlace(path: "/p/a.swift", line: 1, column: 2)),
                severity: .warning,
                message: message
            ),
            text: "/p/a.swift:1:2: warning: " + message.rendered,
            traits: []
        )
        let wraps = [Self.wrap(kind, 0, 1, joining: true), Self.wrap(kind, 1, 1, joining: true)]
        let wrapped = Self.wrapped([header, header], log: [], wraps: wraps)
        let original = BuildOutputReader.read(stderr: wrapped.plainStderr, log: wrapped.plainLog)
        let read = BuildOutputReader.read(stderr: wrapped.stderr, log: wrapped.log)

        #expect(wrapped.stderrLines.map(\.joins) == [true, true])
        #expect(Self.checkEscapes(wrapped, original: original, read: read))
        #expect(read.diagnostics.map(\.message) == [message.body])
    }

    @Test("a timing line wrapped in an OSC-8 link ended by BEL, and one cut off at its end, read as the same entries")
    func timingLinesWrapped() {
        let first = Self.timing("1.23", hundredths: 123, place: BuildPlace(path: "/p/a b:c.swift", line: 3, column: 4))
        let second = Self.timing("0.01", hundredths: 1, place: nil)
        let wraps = [Self.wrap(.oscBell, 2, 9, joining: false), Self.wrap(.truncated, 3, 0, joining: false)]
        let wrapped = Self.wrapped([first, second], log: [], wraps: wraps)
        let original = BuildOutputReader.read(stderr: wrapped.plainStderr, log: wrapped.plainLog)
        let read = BuildOutputReader.read(stderr: wrapped.stderr, log: wrapped.log)

        #expect(Self.checkEscapes(wrapped, original: original, read: read))
        #expect(read.entries.count == 2)
    }

    /// The generator's byte order marks start only lines whose reading
    /// they don't change (calibration: with the guard removed, P1.6 passed
    /// 20 of 20 runs), so this example is what shows the guard works.
    @Test("a warning starting with a byte order mark is wrapped after the mark, so it reads as before")
    func byteOrderMarkKeptFirst() {
        let text = "/p/a.swift:1:2: warning: x [bridged_warning]"
        let header = BuildLineDraft(
            .header(
                location: .file(BuildPlace(path: "/p/a.swift", line: 1, column: 2)),
                severity: .warning,
                message: SuffixedText(body: "x", identifier: .valid("bridged_warning"), group: .absent)
            ),
            text: String(EscapeWrapGen.byteOrderMark) + text,
            traits: []
        )
        let wrapped = Self.wrapped([header], log: [], wraps: [Self.wrap(.csi, 0, Self.colourStep, joining: false)])
        let original = BuildOutputReader.read(stderr: wrapped.plainStderr, log: wrapped.plainLog)
        let read = BuildOutputReader.read(stderr: wrapped.stderr, log: wrapped.log)

        #expect(wrapped.stderrLines.map(\.plain) == [Data((String(EscapeWrapGen.byteOrderMark) + text + "\n").utf8)])
        #expect(Self.checkEscapes(wrapped, original: original, read: read))
        #expect(read.diagnostics.map(\.location) == [.file(BuildPlace(path: "/p/a.swift", line: 1, column: 2))])
    }

    @Test("a planted defect's reading fails P1.6's laws")
    func escapeDefectsDetected() {
        let wraps = [Self.wrap(.csi, 0, 0, joining: true)]
        let wrapped = Self.wrapped([Self.plainWarning("cafe\u{301}")], log: [], wraps: wraps)
        let original = BuildOutputReader.read(stderr: wrapped.plainStderr, log: wrapped.plainLog)
        let markLost = BuildOutput(
            entries: [],
            diagnostics: [
                BuildDiagnostic(
                    severity: .warning,
                    location: .file(BuildPlace(path: "/p/a.swift", line: 1, column: 2)),
                    message: "cafe",
                    identifier: nil,
                    group: nil,
                    origin: nil
                )
            ],
            escapedLines: 1,
            unparsedTimingLines: 0,
            otherWarningLines: 0
        )

        PlantedDefect.expectDetected(
            "B24's fix undone: a mark after a sequence lost",
            sourceLocation: #_sourceLocation
        ) {
            Self.checkEscapes(wrapped, original: original, read: markLost)
        }
        PlantedDefect.expectDetected("an escaped line not counted", sourceLocation: #_sourceLocation) {
            Self.checkEscapes(wrapped, original: original, read: original)
        }
    }
}
