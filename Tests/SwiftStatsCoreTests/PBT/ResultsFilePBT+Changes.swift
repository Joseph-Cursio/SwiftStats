//
//  ResultsFilePBT+Changes.swift
//  SwiftStatsCoreTests
//
//  P3.7, two metamorphic laws: appending a line that never reads only
//  grows `skippedLines`, by that line; and interleaving runs of `mutant`
//  lines otherwise, each key's lines in their order, changes neither the
//  mutants nor the count tested. Over `ResultsFileGen.appended` and
//  `.reordered`, with examples on the recorded files and the meta-test
//  feeding planted defects' readings to the checks.
//

import Foundation
import PropertyBased
@testable import SwiftStatsCore
import Testing

/// P3.7, its examples and its planted defects.
extension ResultsFilePBT {
    /// The appending law's base runs, over the engine's 100: one read of
    /// two files costs well under a millisecond, and the input on which a
    /// reader that lets a line that doesn't read reopen the last session
    /// fails comes in 471 of 10,000 inputs (design D14, measured with that
    /// defect planted; 100 runs detected it in 19 of 20 calibration runs),
    /// so `(1 - 0.0471)^300`, about 5 * 10^-7, is the most a run misses it.
    static let appendedRuns = 300
    /// The reordering law's base runs: the input on which a reader where
    /// the last line of a session wins whatever its key fails comes in 337
    /// of 10,000 inputs (measured so; 100 runs detected it in 17 of 20
    /// calibration runs), so `(1 - 0.0337)^400`, about 10^-6, is the most
    /// a run misses it.
    static let reorderedRuns = 400
    /// What the appending law's tally counts when the file reads as
    /// results (design D14: 562 of the meta-test's 1,000 inputs).
    static let appendedResults = "an appended file read as results"
    /// What the reordering law's tally counts when a line moved in a file
    /// read as results (175 of 1,000, so even 100 runs miss it with odds
    /// of about 4 * 10^-9).
    static let movedResults = "a moved line in a file read as results"

    /// Whether the results of `original` and `appended` agree but for the
    /// skipped lines, grown by `line`, and the file's hash.
    static func agreeButSkipped(_ original: MutationResults, _ appended: MutationResults, line: Int) -> Bool {
        original.mutants == appended.mutants && original.facts == appended.facts
            && original.sessions == appended.sessions && original.formatVersions == appended.formatVersions
            && original.tree == appended.tree && original.listsNotCovered == appended.listsNotCovered
            && original.controlRuns == appended.controlRuns && original.controlFailures == appended.controlFailures
            && original.end == appended.end && original.tested == appended.tested
            && appended.skippedLines == original.skippedLines + [line]
    }

    /// Whether `appended`, the reading of a file with an unreadable line
    /// appended as line `line`, is `original`'s but for that line skipped:
    /// the same refusal or `stopped` line, or the same results with `line`
    /// added to the skipped lines. Records an issue for each law that
    /// fails.
    static func checkAppended(_ original: Read, appended: Read, line: Int) -> Bool {
        let agrees = switch (original, appended) {
        case let (.success(.results(before)), .success(.results(after))):
            agreeButSkipped(before, after, line: line)
        default:
            original == appended
        }
        return holds(
            [(agrees, "reads as \(appended), not as before but for line \(line) skipped")],
            subject: "appending"
        )
    }

    /// Whether `reordered`, the reading of a file with its `mutant` lines
    /// reordered, has `original`'s mutants and count tested, or the same
    /// refusal or `stopped` line. Records an issue for each law that fails.
    static func checkReordered(_ original: Read, reordered: Read) -> Bool {
        let agrees = switch (original, reordered) {
        case let (.success(.results(before)), .success(.results(after))):
            before.mutants == after.mutants && before.tested == after.tested
        default:
            original == reordered
        }
        return holds([(agrees, "reads as \(reordered), not as before")], subject: "reordering")
    }

    /// The key of `line` when it is a `mutant` line; nil otherwise.
    static func mutantKey(of line: Data) throws -> MutantKey? {
        guard let object = try JSONSerialization.jsonObject(with: line) as? [String: Any],
              object["kind"] as? String == "mutant",
              let path = object["path"] as? String, let operatorID = object["mutationOperatorId"] as? String,
              let number = object["line"] as? Int, let column = object["column"] as? Int,
              let occurrence = object["occurrence"] as? Int
        else {
            return nil
        }
        return MutantKey(path: path, operatorID: operatorID, line: number, column: column, occurrence: occurrence)
    }

    /// Invariant: appending a line that never reads only grows
    /// `skippedLines`, by that line's number; a refused or `stopped`-only
    /// file stays as it was.
    /// Why it holds: `MutationResultsFile`'s header (a line that doesn't
    /// read is skipped and counted) and `read(_:)`, which reads each line
    /// on its own; the appended line is no header, so it opens nothing.
    /// Why it might not: the file's hash changes with its bytes and isn't
    /// compared. The appended lines never read in any state: not JSON, a
    /// lone CR, blanks, NULs, a top-level array, no kind or a kind that
    /// isn't a string, junk after an object, a byte that isn't UTF-8. The
    /// results antecedent must fire (the tally).
    /// Oracle: metamorphic; planted defects: a last line that doesn't
    /// read taken as a torn write and not counted, and a line that
    /// doesn't read reopening the last session, each detected in 20 of 20
    /// calibration runs at 300 runs.
    /// Tier: Strict (stop-ship).
    @Test(
        "appending a line that never reads only adds its number to the lines skipped",
        .timeLimit(PBTBudget.timeLimit)
    )
    func appendedGarbageOnlySkipped() async {
        let latch = FirstFailureLatch()
        let tally = AntecedentTally()
        await propertyCheck(count: PBTBudget.runs(Self.appendedRuns), input: ResultsFileGen.appended) { input in
            PBTTrace.note(input)
            if ResultsFileModel.expected(of: input.file.draft).outcome == .results {
                tally.fire(Self.appendedResults)
            }
            let original = Read { () throws(MutationFailure) in try MutationResultsFile.read(input.file.data) }
            let appended = Read { () throws(MutationFailure) in try MutationResultsFile.read(input.appended.data) }
            if Self.checkAppended(original, appended: appended, line: input.appended.draft.lines.count) == false {
                PBTTrace.firstFailure(input, latch: latch)
            }
        }
        tally.report()
        tally.requireFired([Self.appendedResults], unlessFailed: latch, sourceLocation: #_sourceLocation)
    }

    /// Invariant: reordering `mutant` lines of different keys within a run
    /// of consecutive `mutant` lines, each key's lines kept in their
    /// order, changes neither `mutants` nor `tested`.
    /// Why it holds: `MutationResultsFile`'s header (the last `mutant` line
    /// of a key wins); within such a run no header, `retired`, `end` or
    /// `control` line moves, so each key's winner is the same line.
    /// Why it might not: keys compare as `MutantKey` compares them, so the
    /// two spellings of a path are one key and keep their order; skipped
    /// line numbers move with the lines and aren't compared. A moved line
    /// in a file read as results must come up (the tally).
    /// Oracle: metamorphic; planted defect: the last line of a session
    /// winning whatever its key, detected in 20 of 20 calibration runs at
    /// 400 runs; lines keyed without the occurrence, only in 16 of 20, since
    /// two lines at one place must meet in one run and move (P3.5 detects
    /// it in 20 of 20).
    /// Tier: Strict (stop-ship).
    @Test(
        "reordering mutant lines of different keys changes neither the mutants nor the count tested",
        .timeLimit(PBTBudget.timeLimit)
    )
    func reorderedMutantsKept() async {
        let latch = FirstFailureLatch()
        let tally = AntecedentTally()
        await propertyCheck(count: PBTBudget.runs(Self.reorderedRuns), input: ResultsFileGen.reordered) { input in
            PBTTrace.note(input)
            if input.moved, ResultsFileModel.expected(of: input.file.draft).outcome == .results {
                tally.fire(Self.movedResults)
            }
            let original = Read { () throws(MutationFailure) in try MutationResultsFile.read(input.file.data) }
            let reordered = Read { () throws(MutationFailure) in try MutationResultsFile.read(input.reordered.data) }
            if Self.checkReordered(original, reordered: reordered) == false {
                PBTTrace.firstFailure(input, latch: latch)
            }
        }
        tally.report()
        tally.requireFired([Self.movedResults], unlessFailed: latch, sourceLocation: #_sourceLocation)
    }

    @Test("each recorded results file, and the recorded stopped run, with a line that never reads appended")
    func recordedFilesWithGarbage() throws {
        let stopped = try MutationFixture.data("results.jsonl", of: "stopped", in: MutationFixture.directory)
        for data in try Self.recordedFiles() + [stopped] {
            let count = data.split(separator: ResultsLineRenderer.lineFeed).count
            for garbage in ResultsLineRenderer.garbage {
                let appended = data + Data(garbage + [ResultsLineRenderer.lineFeed])

                let before = Read { () throws(MutationFailure) in try MutationResultsFile.read(data) }
                let after = Read { () throws(MutationFailure) in try MutationResultsFile.read(appended) }

                #expect(Self.checkAppended(before, appended: after, line: count + 1))
            }
        }
    }

    @Test("each recorded results file with every run of mutant lines reversed reads the same mutants")
    func recordedFilesReversed() throws {
        for data in try Self.recordedFiles() {
            let lines = data.split(separator: ResultsLineRenderer.lineFeed).map { Data($0) }
            var reversed: [Data] = []
            var run: [Data] = []
            var keys: [MutantKey] = []
            for line in lines {
                if let key = try Self.mutantKey(of: line) {
                    keys.append(key)
                    run.append(line)
                    continue
                }
                reversed += run.reversed() + [line]
                run = []
            }
            reversed += run.reversed()
            let reversedData = Data(reversed.map { $0 + [ResultsLineRenderer.lineFeed] }.joined())

            let before = Read { () throws(MutationFailure) in try MutationResultsFile.read(data) }
            let after = Read { () throws(MutationFailure) in try MutationResultsFile.read(reversedData) }

            // A recorded run tests each key once, so any order of a run keeps
            // each key's lines in order.
            #expect(Set(keys).count == keys.count)
            #expect(Self.checkReordered(before, reordered: after))
            #expect(reversedData != data)
        }
    }

    @Test("""
        a line appended to a CRLF file ending in an empty line with no line break, in that line's place, only \
        adds its own number to the lines skipped
        """)
    func appendedAfterUnbrokenBlank() {
        let lines = [Self.header(session: 1, tree: 0, notCovered: [2]), Self.mutant(session: 1, key: 0), .blank]
        let draft = Self.draft(lines, crlf: true, finalBreak: false)
        let appended = ResultsFileGen.appending(0, to: draft)

        let before = Self.read(draft)
        let after = Self.read(appended)

        #expect(Self.results(of: before)?.skippedLines.isEmpty == true)
        #expect(Self.checkAppended(before, appended: after, line: appended.lines.count))
    }

    @Test("""
        interleaving a run of mutant lines, a key twice and one path in both spellings among them, keeps the \
        mutants and the count tested
        """)
    func interleavedRunKept() {
        let draft = Self.draft([
            Self.header(session: 1, tree: 0, notCovered: []),
            Self.mutant(session: 1, key: 3),
            Self.mutant(session: 1, key: 0),
            Self.mutant(session: 1, key: 4),
            Self.mutant(session: 1, key: 1),
            Self.mutant(session: 1, key: 0),
            .blank,
            Self.mutant(session: 1, key: 2)
        ])
        let lines = ResultsFileGen.interleaved(draft.lines, keys: draft.keys, picks: [1, 2, 0])
        let reordered = draft.replacing(lines: lines)

        let before = Self.read(draft)
        let after = Self.read(reordered)

        // Keys 3 and 4 are one key, and draft 2 and draft 5 hold key 0: each
        // pair keeps its order, so drafts 3 and 5 still win.
        #expect(reordered.lines.map(\.tag) != draft.lines.map(\.tag))
        #expect(Self.results(of: before)?.tested == 4)
        #expect(Self.checkReordered(before, reordered: after))
    }

    @Test("a planted defect's reading fails P3.7's laws")
    func changeDefectsDetected() {
        let header = Self.header(session: 1, tree: 0, notCovered: [1])
        let file = Self.draft([header, Self.mutant(session: 1, key: 0), .garbage(0)])
        let shorter = Self.draft([header, Self.mutant(session: 1, key: 0)])
        let other = Self.draft([header, Self.mutant(session: 1, key: 2)])
        let read = Read { () throws(MutationFailure) in try MutationResultsFile.read(file.data) }
        let shorterRead = Read { () throws(MutationFailure) in try MutationResultsFile.read(shorter.data) }
        let otherRead = Read { () throws(MutationFailure) in try MutationResultsFile.read(other.data) }

        PlantedDefect.expectDetected("a last unreadable line not counted", sourceLocation: #_sourceLocation) {
            Self.checkAppended(shorterRead, appended: shorterRead, line: 3)
        }
        PlantedDefect.expectDetected("an unreadable line ending the file's results", sourceLocation: #_sourceLocation) {
            Self.checkAppended(shorterRead, appended: .failure(MutationFailure(description: "no results")), line: 3)
        }
        PlantedDefect.expectDetected("another key winning after a move", sourceLocation: #_sourceLocation) {
            Self.checkReordered(read, reordered: otherRead)
        }
    }
}
