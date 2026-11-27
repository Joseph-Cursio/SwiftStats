//
//  ResultsFilePBT+Mutants.swift
//  SwiftStatsCoreTests
//
//  P3.5: the mutants a results file reads as are the model's: the last
//  readable `mutant` line of each key wins, a readable `retired` line drops
//  the key, a line of a session with no readable header is skipped, and
//  the last readable header's not-covered entries add every key absent
//  from the winning set, with their file hash from that header's tree;
//  each mutant keeps its line's snapshot, before and after.
//  With its examples (a key tested then retired comes back not covered;
//  the two spellings of an accented path are one key, the later line
//  winning) and the meta-test feeding planted defects' readings to its
//  check.
//

import Foundation
import PropertyBased
@testable import SwiftStatsCore
import Testing

/// P3.5, its examples and its planted defects.
extension ResultsFilePBT {
    /// P3.5's base runs, over the engine's 100: its rarest antecedent, a
    /// tested key retired, fires in 64 of the meta-test's 1,000 files
    /// (design D14; `ResultsFileGenTests`), and `(1 - 0.064)^220`, about
    /// 5 * 10^-7, is the most a run misses it (200 runs, enough at 78 of
    /// 1,000, fell short once more headers were drawn mistyped).
    static let mutantRuns = 220
    /// What P3.5's tally counts when a key's later line replaces an
    /// earlier readable one (92 of 1,000 files).
    static let replaced = "a key tested twice"
    /// What it counts when a readable `retired` line drops a winning key
    /// (64 of 1,000).
    static let retiredKey = "a tested key retired"
    /// What it counts when a not-covered entry adds a key (317 of 1,000).
    static let addedNotCovered = "a not-covered mutant added"
    /// The antecedents P3.5 must reach at least once each.
    static let mutantAntecedents = [readsAsResults, replaced, retiredKey, addedNotCovered]

    /// The mutant `recorded` as the model names one.
    static func observed(_ recorded: RecordedMutant) -> ResultsFileModel.Mutant {
        ResultsFileModel.Mutant(
            marker: recorded.description,
            session: recorded.session,
            notCoveredFileSHA256: recorded.session == nil ? recorded.fileSHA256 : nil,
            before: recorded.before,
            after: recorded.after
        )
    }

    /// `mutant` with its snapshot's `after` read as its `before` too: a
    /// planted defect's reading.
    static func beforeFromAfter(_ mutant: RecordedMutant) -> RecordedMutant {
        RecordedMutant(
            key: mutant.key,
            verdict: mutant.verdict,
            outcome: mutant.outcome,
            activated: mutant.activated,
            endedBy: mutant.endedBy,
            exitStatus: mutant.exitStatus,
            killedBy: mutant.killedBy,
            failedTestCount: mutant.failedTestCount,
            killedByComplete: mutant.killedByComplete,
            fileSHA256: mutant.fileSHA256,
            before: mutant.after,
            after: mutant.after,
            description: mutant.description,
            session: mutant.session,
            durationSeconds: mutant.durationSeconds,
            rerunBecause: mutant.rerunBecause,
            reused: mutant.reused
        )
    }

    /// `results` with `mutants` and `tested` in place of its own: a planted
    /// defect's reading.
    static func results(_ results: MutationResults, mutants: [RecordedMutant], tested: Int) -> MutationResults {
        MutationResults(
            mutants: mutants,
            facts: results.facts,
            sessions: results.sessions,
            formatVersions: results.formatVersions,
            tree: results.tree,
            listsNotCovered: results.listsNotCovered,
            controlRuns: results.controlRuns,
            controlFailures: results.controlFailures,
            end: results.end,
            tested: tested,
            skippedLines: results.skippedLines,
            sha256: results.sha256
        )
    }

    /// Whether `results`, what a reader read (nil when it didn't read the
    /// file as results), holds `expected`'s mutants: each key once, each
    /// named by the line the model says wins, and as many tested. Records
    /// an issue for each law that fails.
    static func checkMutants(_ expected: ResultsFileModel.Expected, results: MutationResults?) -> Bool {
        guard let results else {
            return holds([(false, "reads as results")], subject: "reading the file")
        }
        let tested = results.tested
        var read: [MutantKey: ResultsFileModel.Mutant] = [:]
        var repeated: [MutantKey] = []
        for mutant in results.mutants where read.updateValue(observed(mutant), forKey: mutant.key) != nil {
            repeated.append(mutant.key)
        }
        let wrong = Set(expected.mutants.keys).union(read.keys)
            .filter { expected.mutants[$0] != read[$0] }
            .sorted()
            .map { key in
                MutantKeyGen.parts(of: key) + ": read " + (read[key]?.testDescription ?? "nothing")
                    + ", expected " + (expected.mutants[key]?.testDescription ?? "nothing")
            }
        return holds(
            [
                (repeated.isEmpty, "lists \(repeated.map(\.description)) twice"),
                (wrong.isEmpty, "reads mutants otherwise: " + wrong.joined(separator: "; ")),
                (tested == expected.tested, "counts \(tested) tested, expected \(expected.tested)")
            ],
            subject: "reading the file"
        )
    }

    /// The antecedents of P3.5 that `draft`, read by the model as
    /// `expected`, reaches.
    static func mutantLabels(of draft: ResultsFileDraft, expected: ResultsFileModel.Expected) -> [String] {
        var labels = [readsAsResults]
        var tested: Set<MutantKey> = []
        for (index, line) in draft.lines.enumerated() where index < expected.labels.count {
            guard expected.labels[index] == .readable else {
                continue
            }
            switch line.draft {
            case let .mutant(mutant):
                if tested.insert(ResultsLineObjects.key(at: mutant.key, in: draft.keys)).inserted == false {
                    labels.append(replaced)
                }
            case let .retired(_, keys, _):
                for key in keys where tested.remove(ResultsLineObjects.key(at: key, in: draft.keys)) != nil {
                    labels.append(retiredKey)
                }
            default:
                break
            }
        }
        if expected.mutants.values.contains(where: { $0.session == nil }) {
            labels.append(addedNotCovered)
        }
        return labels
    }

    /// Invariant: the mutants equal the model's: the last readable `mutant`
    /// line per key wins, `retired` removes a key, a line of a session with
    /// no readable header is skipped, and the last readable header's
    /// not-covered entries add every key absent from the final winning
    /// set, with that header's tree's file hash; each keeps its line's
    /// snapshot, before and after; as many tested as winning keys.
    /// Why it holds: `MutationResultsFile`'s header (the last `mutant` line
    /// of a key wins and a `retired` line drops the earlier ones; the last
    /// readable header's `mutantsNotCovered` entries that no line tested
    /// become not-covered mutants), `MutationResults.tested`.
    /// Why it might not: keys compare as `MutantKey` compares them, so the
    /// composed and decomposed spellings of a path are one key; a key
    /// tested then retired comes back not covered when the last header
    /// lists it (`MutationResultsReader.results(sha256:)`). The replaced,
    /// retired and added antecedents must each fire (the tally).
    /// Oracle: the generating model (`ResultsFileModel`); planted defects:
    /// the first line of a key winning, `retired` ignored, not-covered
    /// entries taken from the first header, a tested key listed again as
    /// not covered, a `projectDelta`'s base not checked, and lines keyed
    /// without the occurrence, each detected in 20 of 20 calibration runs;
    /// the delta's tree hash not checked, in 18 of 20 (P3.4 detects that
    /// one in 20 of 20); since the review, a tested mutant's `before` read
    /// from its `after`, in 20 of 20.
    /// Tier: Strict (stop-ship).
    @Test(
        "the mutants are the model's: the last readable line of a key wins, retired drops it, not-covered fills in",
        .timeLimit(PBTBudget.timeLimit)
    )
    func mutantsAreTheModels() async {
        let latch = FirstFailureLatch()
        let tally = AntecedentTally()
        await propertyCheck(count: PBTBudget.runs(Self.mutantRuns), input: ResultsFileGen.file) { file in
            PBTTrace.note(file)
            let expected = ResultsFileModel.expected(of: file.draft)
            guard expected.outcome == .results else {
                return
            }
            for label in Self.mutantLabels(of: file.draft, expected: expected) {
                tally.fire(label)
            }
            let read = Read { () throws(MutationFailure) in try MutationResultsFile.read(file.data) }
            if Self.checkMutants(expected, results: Self.results(of: read)) == false {
                PBTTrace.firstFailure(file, latch: latch)
            }
        }
        tally.report()
        tally.requireFired(Self.mutantAntecedents, unlessFailed: latch, sourceLocation: #_sourceLocation)
    }

    @Test("""
        a key tested, then retired by a resumed session that tests nothing, comes back not covered with the \
        resumed session's file hash
        """)
    func retiredKeyComesBackNotCovered() {
        let draft = Self.draft([
            Self.header(session: 1, tree: 0, notCovered: [0]),
            Self.mutant(session: 1, key: 0),
            Self.mutant(session: 1, key: 2),
            .header(ResultsLineDraft.HeaderDraft(
                session: 2,
                formatVersion: ResultsFileModel.newestFormatVersion,
                tree: .delta(base: 0, target: 1, honest: true),
                listsNotCovered: true,
                notCovered: [0],
                flaw: Self.intact
            )),
            .retired(session: 2, keys: [0], flaw: Self.intact)
        ])
        let expected = ResultsFileModel.expected(of: draft)

        let read = Read { () throws(MutationFailure) in try MutationResultsFile.read(draft.data) }
        let results = Self.results(of: read)

        #expect(expected.mutants == [
            ResultsFileGen.fixedKeys[0]: ResultsFileModel.Mutant(
                marker: "listed by draft 3",
                session: nil,
                notCoveredFileSHA256: ResultsLineRenderer.hashB,
                before: "3 + 1",
                after: "3 - 1"
            ),
            ResultsFileGen.fixedKeys[2]: ResultsFileModel.Mutant(
                marker: "draft 2",
                session: 1,
                notCoveredFileSHA256: nil,
                before: "x > 2",
                after: "x >= 2"
            )
        ])
        #expect(Self.checkMutants(expected, results: results))
    }

    @Test("""
        the composed and decomposed spellings of a path are one key: the later line wins, and a not-covered \
        entry in the other spelling adds nothing
        """)
    func spellingsAreOneKey() {
        let draft = Self.draft([
            Self.header(session: 1, tree: 1, notCovered: [3, 1]),
            Self.mutant(session: 1, key: 4),
            Self.mutant(session: 1, key: 3),
            Self.mutant(session: 1, key: 0)
        ])
        let expected = ResultsFileModel.expected(of: draft)

        let read = Read { () throws(MutationFailure) in try MutationResultsFile.read(draft.data) }
        let results = Self.results(of: read)

        #expect(expected.tested == 2)
        #expect(expected.mutants[ResultsFileGen.fixedKeys[4]]?.marker == "draft 2")
        #expect(expected.mutants[ResultsFileGen.fixedKeys[1]]?.marker == "listed by draft 0")
        #expect(results?.mutants.count == 3)
        #expect(Self.checkMutants(expected, results: results))
    }

    @Test("a planted defect's mutants fail P3.5's law")
    func mutantDefectsDetected() throws {
        let header = Self.header(session: 1, tree: 0, notCovered: [1])
        let tested = Self.mutant(session: 1, key: 0)
        let twice = Self.draft([header, tested, tested])
        let retired = Self.draft([header, tested, .retired(session: 1, keys: [0], flaw: Self.intact)])
        let expected = ResultsFileModel.expected(of: twice)
        let firstRead = try #require(Self.results(of: Self.read(Self.draft([header, tested]))))
        let retiredRead = try #require(Self.results(of: Self.read(retired)))
        let mutants = firstRead.mutants

        PlantedDefect.expectDetected("the first line of a key winning", sourceLocation: #_sourceLocation) {
            Self.checkMutants(expected, results: firstRead)
        }
        PlantedDefect.expectDetected("a not-covered mutant left out", sourceLocation: #_sourceLocation) {
            Self.checkMutants(expected, results: Self.results(firstRead, mutants: Array(mutants.prefix(1)), tested: 1))
        }
        PlantedDefect.expectDetected("a key listed twice", sourceLocation: #_sourceLocation) {
            Self.checkMutants(expected, results: Self.results(firstRead, mutants: mutants + mutants, tested: 1))
        }
        PlantedDefect.expectDetected("retired ignored", sourceLocation: #_sourceLocation) {
            Self.checkMutants(ResultsFileModel.expected(of: retired), results: firstRead)
        }
        PlantedDefect.expectDetected("tested counted wrong", sourceLocation: #_sourceLocation) {
            Self.checkMutants(
                ResultsFileModel.expected(of: retired),
                results: Self.results(retiredRead, mutants: retiredRead.mutants, tested: 1)
            )
        }
        PlantedDefect.expectDetected("a snapshot's before read from its after", sourceLocation: #_sourceLocation) {
            Self.checkMutants(
                ResultsFileModel.expected(of: Self.draft([header, tested])),
                results: Self.results(firstRead, mutants: mutants.map(Self.beforeFromAfter), tested: 1)
            )
        }
    }
}
