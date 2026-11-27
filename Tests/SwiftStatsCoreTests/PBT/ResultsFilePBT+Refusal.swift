//
//  ResultsFilePBT+Refusal.swift
//  SwiftStatsCoreTests
//
//  P3.6: a results file is refused exactly when some header-kind line's
//  `formatVersion` decodes as an integer above 4, wherever it is and
//  whatever else in it fails, or when no header and no `stopped` line
//  reads; a file with no readable header but a readable `stopped` line is
//  that line. Over files whose headers may be in a newer format
//  (`ResultsFileGen.anyFile`), with its examples (the recorded files; a
//  newer header with a key missing still refuses, where an unknown kind's
//  `formatVersion` doesn't), an example pinning that formats 0 and -1
//  read, as the reader is built, awaiting a decision, and the meta-test
//  feeding planted defects' readings to its check.
//

import Foundation
import PropertyBased
@testable import SwiftStatsCore
import Testing

/// P3.6, its examples and its planted defects.
extension ResultsFilePBT {
    /// P3.6's base runs, over the engine's 100: each outcome comes in 19
    /// to 35 files in a hundred, but a newer header that doesn't otherwise
    /// read, the only input on which a reader checking the format only of
    /// readable headers fails, comes in about 8 (design D14: 82 of the
    /// meta-test's 1,000), and 200 runs miss it with odds below 10^-7.
    static let refusalRuns = 200
    /// What P3.6's tally counts when the model expects a refusal by a newer
    /// format.
    static let refusedNewer = "refused by a newer format"
    /// What it counts when the model expects a refusal for want of a header.
    static let refusedNoHeader = "refused: no header"
    /// What it counts when the model expects a `stopped` line.
    static let stoppedOnly = "stopped"
    /// What it counts when the model expects results.
    static let resultsRead = "results"
    /// The antecedents P3.6 must reach at least once each.
    static let refusalAntecedents = [refusedNewer, refusedNoHeader, stoppedOnly, resultsRead]

    /// The tally label of `outcome`.
    static func label(of outcome: ResultsFileModel.Outcome) -> String {
        switch outcome {
        case .newer:
            refusedNewer
        case .noHeader:
            refusedNoHeader
        case .stopped:
            stoppedOnly
        case .results:
            resultsRead
        }
    }

    /// Whether `read` is what `expected` says: refused naming the newer
    /// format, refused for having no header, the `stopped` line the model
    /// names, or results. Each reason is written out from the reading
    /// rules' text, not taken from the reader. Records an issue for each
    /// law that fails.
    static func checkContents(_ expected: ResultsFileModel.Outcome, read: Read) -> Bool {
        let law: (holds: Bool, law: String)
        switch (expected, read) {
        case let (.newer(version), .failure(failure)):
            let reason = "the results file has formatVersion \(version); this SwiftStats reads 1 to 4"
            law = (failure.description == reason, "is refused as \(failure.description.debugDescription)")
        case let (.noHeader, .failure(failure)):
            let reason = "the results file has no header SwiftStats can read, so it holds no results"
            law = (failure.description == reason, "is refused as \(failure.description.debugDescription)")
        case let (.stopped(tag), .success(.stopped(stop))):
            let step = stop.step.debugDescription
            law = (stop.step == ResultsLineObjects.marker(tag), "is the stopped line of \(step)")
        case (.results, .success(.results)):
            law = (true, "reads as results")
        default:
            law = (false, "reads as \(read), expected " + expected.testDescription)
        }
        return holds([law], subject: "reading the file")
    }

    /// Invariant: the file is refused exactly when some header-kind line's
    /// `formatVersion` decodes as an integer above 4, wherever it is, or
    /// when there is no readable header and no readable `stopped` line;
    /// with no readable header, the last readable `stopped` line is the
    /// file.
    /// Why it holds: `MutationResultsFile`'s header (each header is read
    /// on its own, formats 1 to 4, a newer one refusing the file; a file
    /// without a readable header holds only a `stopped` line, or isn't a
    /// results file) and `MutationResultsReader.add(_:)`, which reads the
    /// format alone before the header, so a newer header refuses even when
    /// the rest of it doesn't read.
    /// Why it might not: a newer header whose `kind` or `formatVersion`
    /// doesn't decode, or that is cut off, refuses nothing; a line of an
    /// unknown kind (`Header`, `someday`) holding `formatVersion` 9 refuses
    /// nothing. No format below 1 is drawn: the reader reads one, which is
    /// its code's rule, where SwiftMutator's docs say a reader refuses a
    /// format it doesn't know; that awaits a decision
    /// (`formatsBelowOneRead`). Each of the four outcomes must be expected
    /// at least once (the tally).
    /// Oracle: the generating model (`ResultsFileModel`); planted defects:
    /// format 4 refused, the format checked only on headers that read,
    /// only the first header's format checked, a `stopped` line taken
    /// over results, and the first `stopped` line kept, each detected in
    /// 20 of 20 calibration runs.
    /// Tier: Strict (stop-ship).
    @Test(
        "a file is refused exactly when a header's format is newer than 4, or no header and no stopped line reads",
        .timeLimit(PBTBudget.timeLimit)
    )
    func refusedExactlyByTheRules() async {
        let latch = FirstFailureLatch()
        let tally = AntecedentTally()
        await propertyCheck(count: PBTBudget.runs(Self.refusalRuns), input: ResultsFileGen.anyFile) { file in
            PBTTrace.note(file)
            let expected = ResultsFileModel.expected(of: file.draft)
            tally.fire(Self.label(of: expected.outcome))
            let read = Read { () throws(MutationFailure) in try MutationResultsFile.read(file.data) }
            if Self.checkContents(expected.outcome, read: read) == false {
                PBTTrace.firstFailure(file, latch: latch)
            }
        }
        tally.report()
        tally.requireFired(Self.refusalAntecedents, unlessFailed: latch, sourceLocation: #_sourceLocation)
    }

    @Test("the recorded results files read as results, and the recorded stopped run as its stopped line")
    func recordedFilesRead() throws {
        for data in try Self.recordedFiles() {
            let read = Read { () throws(MutationFailure) in try MutationResultsFile.read(data) }

            #expect(Self.checkContents(.results, read: read))
        }
        let stopped = try MutationFixture.data("results.jsonl", of: "stopped", in: MutationFixture.directory)
        let read = Read { () throws(MutationFailure) in try MutationResultsFile.read(stopped) }

        guard case .success(.stopped) = read else {
            Issue.record("the recorded stopped run reads as \(read)")
            return
        }
    }

    @Test("""
        a newer header with a key missing still refuses, after results too; a newer header cut off, or a line \
        of kind Header with formatVersion 9, refuses nothing
        """)
    func newerHeaderRefusesWherever() {
        let newer = ResultsLineDraft.HeaderDraft(
            session: 2,
            formatVersion: 5,
            tree: .noTree,
            listsNotCovered: false,
            notCovered: [],
            flaw: ResultsLineDraft.Flaw(kind: .absent, slot: 2)
        )
        let cut = ResultsLineDraft.HeaderDraft(
            session: 2,
            formatVersion: 5,
            tree: .noTree,
            listsNotCovered: false,
            notCovered: [],
            flaw: ResultsLineDraft.Flaw(kind: .cut, slot: 30)
        )
        let header = Self.header(session: 1, tree: 0, notCovered: [])
        let refusing = Self.draft([header, Self.mutant(session: 1, key: 0), .header(newer)])
        let reading = Self.draft([header, .header(cut), .unknown(2), Self.mutant(session: 1, key: 0)])

        let refused = Read { () throws(MutationFailure) in try MutationResultsFile.read(refusing.data) }
        let read = Read { () throws(MutationFailure) in try MutationResultsFile.read(reading.data) }

        #expect(ResultsFileModel.expected(of: refusing).outcome == .newer(5))
        #expect(Self.checkContents(.newer(5), read: refused))
        #expect(ResultsFileModel.expected(of: reading).outcome == .results)
        #expect(Self.checkContents(.results, read: read))
    }

    /// Pins what the reader does with a header in a format below 1, which
    /// the generators don't draw: it reads it, as `MutationResultsReader`
    /// is built (it refuses only newer formats, as SwiftMutator's own
    /// reader does). SwiftMutator's `Docs/results-file.md` "Compatibility"
    /// says a reader should refuse a format it doesn't know, and names only
    /// formats 1 to 4. Awaiting the user's decision: if formats below 1 are
    /// to be refused, this example flips with that change, and the
    /// generators draw them as refusing.
    @Test(
        "a header in format 0 or -1 reads, as the reader is built, awaiting a decision on refusing formats below 1",
        arguments: [0, -1]
    )
    func formatsBelowOneRead(version: Int) {
        let header = ResultsLineDraft.HeaderDraft(
            session: 1,
            formatVersion: version,
            tree: .noTree,
            listsNotCovered: true,
            notCovered: [],
            flaw: Self.intact
        )
        let draft = Self.draft([.header(header), Self.mutant(session: 1, key: 0)])

        let read = Read { () throws(MutationFailure) in try MutationResultsFile.read(draft.data) }

        #expect(Self.checkContents(.results, read: read))
        #expect(Self.results(of: read)?.formatVersions == [version])
    }

    @Test("a planted defect's reading fails P3.6's law")
    func refusalDefectsDetected() {
        let noHeader = MutationFailure(description: MutationResultsFile.noHeaderReason)
        let stop = MutationStop(step: "draft 1", reason: "failed", detail: nil, failedTests: [], failedTestCount: nil)

        let formatFour = MutationFailure(description: MutationResultsFile.newerFormatReason(4))

        PlantedDefect.expectDetected("format 4 refused", sourceLocation: #_sourceLocation) {
            Self.checkContents(.results, read: .failure(formatFour))
        }
        PlantedDefect.expectDetected("a newer header that doesn't read skipped", sourceLocation: #_sourceLocation) {
            Self.checkContents(.newer(5), read: .failure(noHeader))
        }
        PlantedDefect.expectDetected("a stopped line taken over results", sourceLocation: #_sourceLocation) {
            Self.checkContents(.results, read: .success(.stopped(stop)))
        }
        PlantedDefect.expectDetected("the first stopped line kept", sourceLocation: #_sourceLocation) {
            Self.checkContents(.stopped(tag: 4), read: .success(.stopped(stop)))
        }
    }
}
