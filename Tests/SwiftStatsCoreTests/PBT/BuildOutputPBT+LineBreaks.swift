//
//  BuildOutputPBT+LineBreaks.swift
//  SwiftStatsCoreTests
//
//  P1.7: ending with CRLF every line of both files that doesn't already
//  end in a carriage return, the last one included when it had no line
//  break, changes nothing the reader returns: it drops one carriage return
//  from the end of each line, and a final line break only ends the last
//  line.
//

import Foundation
import PropertyBased
@testable import SwiftStatsCore
import Testing

/// P1.7.
extension BuildOutputPBT {
    /// P1.7's base runs: the engine's default.
    static let lineBreakRuns = 100
    /// What P1.7's tally counts when a line ended with LF now ends with
    /// CRLF.
    static let lineFeedChanged = "a line feed made CRLF"
    /// What P1.7's tally counts when a last line with no line break now
    /// ends with CRLF.
    static let unterminatedChanged = "an unterminated last line ended with CRLF"
    /// The antecedents P1.7 must reach at least once each.
    static let lineBreakAntecedents = [lineFeedChanged, unterminatedChanged]
    /// A carriage return's byte.
    static let carriageReturn = UInt8(ascii: "\r")
    /// CRLF.
    static let crlf = "\r\n"

    /// `lines` written with CRLF after each that doesn't already end in a
    /// carriage return; a line that does keeps its own line break.
    static func withCRLF(_ lines: [GeneratedBuildLine]) -> Data {
        Data(
            lines.flatMap { line in
                line.written.last == carriageReturn ? line.data : Data(line.written) + Data(crlf.utf8)
            }
        )
    }

    /// Whether `read`, the reading of `sample`'s files with CRLF line
    /// breaks, is `original`, the reading of the files as generated.
    /// Records an issue for each part that differs.
    static func checkLineBreaks(_ sample: GeneratedBuildOutput, original: BuildOutput, read: BuildOutput) -> Bool {
        holds(
            [
                (read.entries == original.entries, "reads the entries it read before"),
                (
                    read.diagnostics == original.diagnostics,
                    "reads the diagnostics it read before (\(firstDifference(read.diagnostics, original.diagnostics)))"
                ),
                (read.escapedLines == original.escapedLines, "counts the escaped lines it counted before"),
                (
                    read.unparsedTimingLines == original.unparsedTimingLines,
                    "counts the refused timing lines it counted before"
                ),
                (
                    read.otherWarningLines == original.otherWarningLines,
                    "counts the other warning lines it counted before"
                )
            ],
            subject: "reading \(sample.lines.count) lines ended with CRLF"
        )
    }

    // MARK: P1.7

    /// Invariant: ending with CRLF every line that doesn't already end in a
    /// carriage return changes nothing the reader returns.
    /// Why it holds: `BuildOutputReader.lines(of:)`'s doc comment (a final
    /// newline ends the last line; each line is read without a trailing
    /// carriage return).
    /// Why it might not: only one carriage return is dropped, so a line
    /// already ending in one is outside the law and keeps its line break
    /// (the generator writes none). A last line with no line break gains
    /// CRLF too, which makes it no different. Each run has lines to change
    /// and, in some run, an unterminated last line (the tally).
    /// Oracle: metamorphic (the reading of the files as generated);
    /// planted defect: the trailing carriage return kept, detected in 20
    /// of 20 calibration runs.
    /// Tier: Strict (stop-ship).
    @Test(
        "ending with CRLF every line that doesn't already end in a carriage return changes nothing read",
        .timeLimit(PBTBudget.timeLimit)
    )
    func lineBreaksChangeNothing() async {
        let latch = FirstFailureLatch()
        let tally = AntecedentTally()
        let input = BuildOutputGen.output(.decided)
        await propertyCheck(count: PBTBudget.runs(Self.lineBreakRuns), input: input) { sample in
            PBTTrace.note(sample)
            if sample.lines.contains(where: { $0.lineBreak == "\n" }) {
                tally.fire(Self.lineFeedChanged)
            }
            if sample.traits.contains(.unterminated) {
                tally.fire(Self.unterminatedChanged)
            }
            let original = BuildOutputReader.read(stderr: sample.stderr, log: sample.log)
            let read = BuildOutputReader.read(
                stderr: Self.withCRLF(sample.stderrLines),
                log: Self.withCRLF(sample.logLines)
            )
            if Self.checkLineBreaks(sample, original: original, read: read) == false {
                PBTTrace.firstFailure(sample, latch: latch)
            }
        }
        tally.report()
        tally.requireFired(Self.lineBreakAntecedents, unlessFailed: latch, sourceLocation: #_sourceLocation)
    }

    @Test("the recorded lines, in both files, read the same with CRLF line breaks")
    func recordedLinesWithCRLF() {
        let sample = GeneratedBuildOutput(
            rules: .decided,
            stderr: BuildFileDraft(
                blocks: BuildOutputGen.recordedTimings + BuildOutputGen.recordedGroups,
                decorations: [],
                terminated: true
            ),
            log: BuildFileDraft(blocks: BuildOutputGen.recordedGroups, decorations: [], terminated: false)
        )
        let original = BuildOutputReader.read(stderr: sample.stderr, log: sample.log)
        let read = BuildOutputReader.read(
            stderr: Self.withCRLF(sample.stderrLines),
            log: Self.withCRLF(sample.logLines)
        )

        #expect(Self.checkLineBreaks(sample, original: original, read: read))
        #expect(read.entries.count == BuildOutputGen.recordedTimings.count)
    }

    @Test("a function body's timing line and a warning, the last with no line break, read the same with CRLF")
    func unterminatedWithCRLF() {
        let place = BuildPlace(path: "/p/a.swift", line: 2, column: 13)
        let sample = GeneratedBuildOutput(
            rules: .decided,
            stderr: BuildFileDraft(
                blocks: [[Self.timing("0.59", hundredths: 59, place: place)], [Self.plainWarning("w")]],
                decorations: [],
                terminated: false
            ),
            log: BuildFileDraft(blocks: [], decorations: [], terminated: true)
        )
        let original = BuildOutputReader.read(stderr: sample.stderr, log: sample.log)
        let read = BuildOutputReader.read(
            stderr: Self.withCRLF(sample.stderrLines),
            log: Self.withCRLF(sample.logLines)
        )

        #expect(sample.traits.contains(.unterminated))
        #expect(Self.checkLineBreaks(sample, original: original, read: read))
        #expect(read.entries.map(\.declaration) == ["global function f()"])
    }

    @Test("a planted defect's reading fails P1.7's law")
    func lineBreakDefectsDetected() {
        let place = BuildPlace(path: "/p/a.swift", line: 2, column: 13)
        let line = Self.timing("0.59", hundredths: 59, place: place)
        let sample = Self.output([line], log: [])
        let original = BuildOutputReader.read(stderr: sample.stderr, log: sample.log)
        let kept = TimingEntry(kind: .function, hundredths: 59, place: place, declaration: "global function f()\r")
        let carriageReturnKept = Self.output(original, entries: [kept])

        PlantedDefect.expectDetected("the carriage return kept", sourceLocation: #_sourceLocation) {
            Self.checkLineBreaks(sample, original: original, read: carriageReturnKept)
        }
    }
}
