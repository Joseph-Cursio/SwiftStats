//
//  IntegerEdgesPBT+Results.swift
//  SwiftStatsCoreTests
//
//  P15.1's results path: a results.jsonl file read as the collector reads
//  it (`MutationResultsFile.read(_:)`), each mutant's key spelled
//  (`MutantKey.description`, B25's 04a) and placed by `MutationMapper`,
//  every number a key, a session or a run's outcome holds an integer
//  edge. A `mutant` line of a session no header opened is skipped; the
//  header's not-covered mutant is added unless the line tested its key;
//  each mutant keeps its numbers, is spelled as SwiftMutator spells it
//  (an occurrence of `Int.max` as ` (#9223372036854775808)`, which reads
//  back as no key, as a line or column of 0 does), and is placed on `first()` at 1:1, the only edge
//  point the file holds, and unmapped as a position outside its file
//  anywhere else. Its examples, and a meta-test that feeds a planted
//  defect's spelling (04a undone as a wrapping add) to its check.
//

import Foundation
import PropertyBased
@testable import SwiftStatsCore
import Testing

/// P15.1's results path.
extension IntegerEdgesPBT {
    /// What reading a results file and mapping its mutants gave: the
    /// mutants, each placed, and each key's spelling; or the failure
    /// reading it gave.
    typealias ResultsOutcome = Result<ReadMutants, any Error>

    /// What reading a results file's mutants and mapping them gave.
    struct ReadMutants {
        /// The results read.
        let results: MutationResults
        /// The mutants, placed, in the results' order.
        let mutants: [Mutant]
        /// Each mutant's key, spelled, in the same order.
        let spellings: [String]
    }

    /// The results path's base runs, over the engine's 100: reading two
    /// lines and placing two mutants costs about a hundred microseconds.
    /// The rarest antecedent, a tested mutant read at 1:1, comes in 29 of
    /// the meta-test's 1,000 files (design D14: `(1 - 0.029)^500`, about
    /// 4 * 10^-7, is the most a run misses it; 100 runs would miss it
    /// about 5 * 10^-2 of the time). The not-covered key tested, 2 in
    /// 1,000, is tallied but not required.
    static let resultsRuns = 500
    /// What the results path's tally counts when the `mutant` line is read.
    static let testedRead = "a mutant line read"
    /// What it counts when a read mutant lies at 1:1 of the file.
    static let testedPlaced = "a mutant line read at 1:1"
    /// What it counts when an occurrence is `Int.max`.
    static let largestOccurrence = "an occurrence of Int.max"
    /// What it counts when the line tested the not-covered key.
    static let notCoveredTested = "the not-covered key tested"
    /// What it counts when the line's kill list is complete.
    static let completeList = "a complete kill list"
    /// The antecedents the results path must reach at least once each.
    static let resultsAntecedents = [
        mapped, failed, unknown, testedRead, testedPlaced, largestOccurrence, completeList, largest, zero
    ]
    /// The spelling of one past `Int.max`, a repeat number that doesn't fit
    /// an `Int`, as decimal digits.
    static let pastLargest = "9223372036854775808"

    /// A file whose `mutant` line tests 1:1 with the largest occurrence,
    /// killed by its one test, and whose header lists 1:Int.max as not
    /// covered; both sessions `Int.max`.
    static let largestResults = ResultsEdgeDraft(
        headerSession: Int.max,
        notCovered: ResultsEdgeDraft.KeyNumbers(line: 1, column: Int.max, occurrence: 0),
        mutantSession: Int.max,
        tested: ResultsEdgeDraft.KeyNumbers(line: 1, column: 1, occurrence: Int.max),
        exitStatus: Int.max,
        failedTestCount: 1
    )

    /// `numbers`' key as SwiftMutator spells it: `path:line:column
    /// Operator`, then ` (#k)` with k one past the occurrence when it is
    /// above 0, k written as decimal digits worked out apart from `Int`.
    static func spelling(_ numbers: ResultsEdgeDraft.KeyNumbers) -> String {
        let place = "\(IntegerEdgeGen.plainFile):\(numbers.line):\(numbers.column) \(ResultsEdgeDraft.operatorID)"
        guard numbers.occurrence > 0 else {
            return place
        }
        let repeatNumber = numbers.occurrence == Int.max ? pastLargest : String(numbers.occurrence + 1)
        return place + " (#\(repeatNumber))"
    }

    /// The keys `draft`'s file holds, in key order: the tested one when its
    /// session is the header's, then the not-covered one unless it was
    /// tested.
    static func expectedKeys(of draft: ResultsEdgeDraft) -> [MutantKey] {
        let tested = draft.mutantSession == draft.headerSession ? [draft.tested.key] : []
        let notCovered = tested.contains(draft.notCovered.key) ? [] : [draft.notCovered.key]
        return (tested + notCovered).sorted()
    }

    /// Whether `numbers` name the one edge point the file holds, 1:1.
    static func isPlaced(_ numbers: ResultsEdgeDraft.KeyNumbers) -> Bool {
        numbers.line == 1 && numbers.column == 1
    }

    /// The classes `draft` falls in, for the results path's tally and the
    /// generator's meta-test.
    static func resultsLabels(of draft: ResultsEdgeDraft) -> [String] {
        let read = draft.mutantSession == draft.headerSession
        let keys = [draft.tested, draft.notCovered]
        let placedKeys = keys.filter { key in key == draft.notCovered || read }
        let numbers = keys.flatMap { [$0.line, $0.column, $0.occurrence] }
            + [draft.headerSession, draft.mutantSession, draft.exitStatus, draft.failedTestCount]
        return [
            (read, testedRead),
            (read == false, failed),
            (read && isPlaced(draft.tested), testedPlaced),
            (placedKeys.contains(where: isPlaced), mapped),
            (placedKeys.contains { isPlaced($0) == false }, unknown),
            (keys.contains { $0.occurrence == Int.max }, largestOccurrence),
            (read && draft.tested.key == draft.notCovered.key, notCoveredTested),
            (read && draft.failedTestCount == 1, completeList)
        ]
        .filter(\.0)
        .map(\.1) + edgeLabels(numbers)
    }

    /// Whether `outcome`, what `draft`'s file gave on `library`, is what
    /// the reader's and the mapper's rules give: the expected keys (a
    /// skipped line counted), each keeping its numbers, spelled as
    /// SwiftMutator spells it and reading back unless a line or column is
    /// 0 (a spelled number is positive, decided U11) or its repeat number
    /// passes `Int`, and placed on `first()` at 1:1 or unmapped as outside
    /// its file elsewhere. Records an issue for each law that fails.
    static func checkResults(_ draft: ResultsEdgeDraft, outcome: ResultsOutcome, library: Library) -> Bool {
        let subject = "reading the results file"
        guard case .success(let read) = outcome else {
            return holds([(false, "fails to read it: \(outcome)")], subject: subject)
        }
        let keys = read.results.mutants.map(\.key)
        let expected = expectedKeys(of: draft)
        let skipped = draft.mutantSession == draft.headerSession ? [Int]() : [ResultsEdgeDraft.mutantLine]
        var laws = [
            (keys == expected, "reads the keys \(keys), expected \(expected)"),
            (read.results.skippedLines == skipped, "skips the lines \(read.results.skippedLines), expected \(skipped)"),
            (read.mutants.count == keys.count, "places \(read.mutants.count) mutants of \(keys.count)")
        ]
        for (index, key) in keys.enumerated() {
            let numbers = ResultsEdgeDraft.KeyNumbers(line: key.line, column: key.column, occurrence: key.occurrence)
            let spelled = read.spellings.indices.contains(index) ? read.spellings[index] : ""
            let back = key.line > 0 && key.column > 0 && key.occurrence < Int.max ? key : nil
            laws += [
                (spelled == spelling(numbers), "spells \(key) as \(spelled), expected \(spelling(numbers))"),
                (MutantKey(spelled: spelled) == back, "reads \(spelled) back as other than \(String(describing: back))")
            ]
            if read.mutants.indices.contains(index) {
                laws += checkMutant(read.mutants[index], numbers: numbers, draft: draft, library: library)
            }
        }
        return holds(laws, subject: subject)
    }

    /// The laws `mutant`, placed from `numbers` of `draft`'s file, must
    /// meet on `library`: its numbers kept, the tested one's exit status,
    /// failed-test count and completeness as written, and its place.
    static func checkMutant(
        _ mutant: Mutant,
        numbers: ResultsEdgeDraft.KeyNumbers,
        draft: ResultsEdgeDraft,
        library: Library
    ) -> [(holds: Bool, law: String)] {
        let kept = (mutant.line, mutant.column, mutant.occurrence) == (numbers.line, numbers.column, numbers.occurrence)
        var laws = [(kept, "keeps \(numbers) as \(mutant.line):\(mutant.column) #\(mutant.occurrence)")]
        if mutant.verdict != .notCovered {
            let complete = JSONFlag(draft.failedTestCount == 1)
            laws += [
                (
                    (mutant.exitStatus, mutant.failedTestCount) == (draft.exitStatus, draft.failedTestCount),
                    "keeps the exit status and failed tests as \(String(describing: mutant.exitStatus)), "
                        + "\(String(describing: mutant.failedTestCount))"
                ),
                (
                    mutant.killedByComplete == complete,
                    "calls the kill list complete: \(String(describing: mutant.killedByComplete))"
                )
            ]
        }
        if isPlaced(numbers) {
            laws.append((
                mutant.place == .record && mutant.owner == library.firstKey
                    && mutant.anchor == SourcePosition(line: 1, column: 1),
                "places the mutant at 1:1 as \(mutant.place) \(String(describing: mutant.owner)), "
                    + "anchored at \(String(describing: mutant.anchor))"
            ))
        } else {
            laws.append((
                mutant.place == .unmapped && mutant.reason == MutationMapper.noSuchPosition && mutant.anchor == nil,
                "places the mutant at \(numbers.line):\(numbers.column) as \(mutant.place) "
                    + "(\(String(describing: mutant.reason)))"
            ))
        }
        return laws
    }

    /// Counts in `tally` what `outcome` shows: a mutant placed on a record,
    /// and one unmapped.
    static func tallyResults(_ outcome: ResultsOutcome, in tally: AntecedentTally) {
        guard case .success(let read) = outcome else {
            return
        }
        if read.mutants.contains(where: { $0.place == .record }) {
            tally.fire(mapped)
        }
        if read.mutants.contains(where: { $0.place == .unmapped }) {
            tally.fire(unknown)
        }
    }

    /// The spellings of `read`'s keys as B25's 04a spelled them before its
    /// fix, but with a wrapping add instead of a trapping one: the planted
    /// defect.
    static func wrappingSpellings(_ read: ReadMutants) -> ReadMutants {
        let spellings = read.results.mutants.map { mutant in
            let key = mutant.key
            let place = "\(key.path):\(key.line):\(key.column) \(key.operatorID)"
            return key.occurrence > 0 ? place + " (#\(key.occurrence &+ 1))" : place
        }
        return ReadMutants(results: read.results, mutants: read.mutants, spellings: spellings)
    }

    // MARK: P15.1, results

    /// Invariant: a results file whose keys, sessions and outcome numbers
    /// are integer edges reads as the mutants of its header's session and
    /// its not-covered key, each keeping its numbers, spelled as
    /// SwiftMutator spells it, reading back as itself unless a number in
    /// it is 0 or its repeat number passes `Int`, and placed on the record
    /// at 1:1 or unmapped as outside its file, and nothing traps.
    /// Why it holds: `MutationResultsFile`'s header (a line of a session no
    /// header opened is skipped; not-covered keys no line tested are
    /// added), `KillListCompleteness`, `MutantKey.description`'s doc (the
    /// repeat counted in `UInt`, B25's 04a), `MutantAnchoring`'s (a point
    /// the file doesn't hold has no anchor) and `MutationMapper`'s header
    /// (M6 design §2, §3).
    /// Why it might not: one header and one line, of one operator, in the
    /// one file at its scanned hash; the file's first line starts with
    /// `first()`'s first token, as `libraryIsAsStated` pins, and holds
    /// fewer than `Int.max - 3` columns.
    /// Oracle: postconditions from the rules above, the spelling worked out
    /// apart from `Int`; planted defects: 04a undone (a trapping add,
    /// detected as a trap), the repeat spelled without its `+ 1`, a line
    /// of a session no header opened read, and (meta-test) 04a undone as a
    /// wrapping add, each detected.
    /// Tier: Strict (stop-ship).
    @Test(
        """
        a results file at the integer edges reads as its session's mutants, spelled and placed or unmapped, \
        and nothing traps
        """,
        .timeLimit(PBTBudget.timeLimit)
    )
    func resultsEdgesMap() async throws {
        let library = try Library()
        defer { library.remove() }
        let latch = FirstFailureLatch()
        let tally = AntecedentTally()
        await propertyCheck(count: PBTBudget.runs(Self.resultsRuns), input: IntegerEdgeGen.results) { draft in
            PBTTrace.note(draft)
            Self.resultsLabels(of: draft).filter { $0 != Self.mapped && $0 != Self.unknown }.forEach(tally.fire)
            let outcome = ResultsOutcome {
                let data = try draft.data(fileHash: library.plainHash)
                guard case .results(let results) = try MutationResultsFile.read(data) else {
                    throw MutationFailure(description: "the file holds only a stopped line")
                }
                let mutants = library.harness.mapper.mutants(of: results, run: 1, suspects: .unjudged)
                let spellings = results.mutants.map(\.key.description)
                return ReadMutants(results: results, mutants: mutants, spellings: spellings)
            }
            Self.tallyResults(outcome, in: tally)
            if Self.checkResults(draft, outcome: outcome, library: library) == false {
                PBTTrace.firstFailure(draft, latch: latch)
            }
        }
        tally.report()
        tally.requireFired(Self.resultsAntecedents, unlessFailed: latch, sourceLocation: #_sourceLocation)
    }

    @Test("""
        a mutant at 1:1 with the largest occurrence is placed on first() and spelled (#9223372036854775808), \
        which reads back as no key, beside its not-covered key at 1:Int.max, unmapped
        """)
    func largestOccurrenceSpelled() throws {
        let library = try Library()
        defer { library.remove() }
        let draft = Self.largestResults

        let outcome = ResultsOutcome {
            let data = try draft.data(fileHash: library.plainHash)
            guard case .results(let results) = try MutationResultsFile.read(data) else {
                throw MutationFailure(description: "the file holds only a stopped line")
            }
            let mutants = library.harness.mapper.mutants(of: results, run: 1, suspects: .unjudged)
            let spellings = results.mutants.map(\.key.description)
            return ReadMutants(results: results, mutants: mutants, spellings: spellings)
        }

        #expect(Self.checkResults(draft, outcome: outcome, library: library))
        let read = try outcome.get()
        #expect(read.spellings == [
            "Sources/Lib/Plain.swift:1:1 RelationalBoundary (#9223372036854775808)",
            "Sources/Lib/Plain.swift:1:9223372036854775807 RelationalBoundary"
        ])
        #expect(read.mutants.map(\.place) == [.record, .unmapped])
    }

    @Test("""
        a mutant line of a session no header opened is skipped, and only the not-covered key at 0:0 is read, \
        spelled as a key that reads back as none
        """)
    func otherSessionSkipped() throws {
        let library = try Library()
        defer { library.remove() }
        let draft = ResultsEdgeDraft(
            headerSession: 1,
            notCovered: ResultsEdgeDraft.KeyNumbers(line: 0, column: 0, occurrence: 1),
            mutantSession: 0,
            tested: ResultsEdgeDraft.KeyNumbers(line: 1, column: 1, occurrence: 0),
            exitStatus: 0,
            failedTestCount: Int.max
        )

        let outcome = ResultsOutcome {
            let data = try draft.data(fileHash: library.plainHash)
            guard case .results(let results) = try MutationResultsFile.read(data) else {
                throw MutationFailure(description: "the file holds only a stopped line")
            }
            let mutants = library.harness.mapper.mutants(of: results, run: 1, suspects: .unjudged)
            let spellings = results.mutants.map(\.key.description)
            return ReadMutants(results: results, mutants: mutants, spellings: spellings)
        }

        #expect(Self.checkResults(draft, outcome: outcome, library: library))
        #expect(try outcome.get().spellings == ["Sources/Lib/Plain.swift:0:0 RelationalBoundary (#2)"])
        #expect(try outcome.get().spellings.map(MutantKey.init(spelled:)) == [nil])
        #expect(try outcome.get().results.skippedLines == [2])
    }

    @Test("""
        the results path's check detects a planted defect: B25's 04a undone with a wrapping add, which spells the \
        largest occurrence (#-9223372036854775808)
        """)
    func resultsCheckDetectsWrappingSpelling() throws {
        let library = try Library()
        defer { library.remove() }
        let draft = Self.largestResults
        let data = try draft.data(fileHash: library.plainHash)
        guard case .results(let results) = try MutationResultsFile.read(data) else {
            Issue.record("the file holds only a stopped line")
            return
        }
        let read = ReadMutants(
            results: results,
            mutants: library.harness.mapper.mutants(of: results, run: 1, suspects: .unjudged),
            spellings: results.mutants.map(\.key.description)
        )

        PlantedDefect.expectDetected("04a undone with a wrapping add", sourceLocation: #_sourceLocation) {
            Self.checkResults(draft, outcome: .success(Self.wrappingSpellings(read)), library: library)
        }
    }
}
