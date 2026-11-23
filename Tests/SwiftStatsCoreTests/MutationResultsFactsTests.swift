import Foundation
@testable import SwiftStatsCore
import Testing

/// What a results file says beyond each mutant's verdict (M6, design §2
/// items 7 and 11), from hand-written lines: the run's workers and time
/// limit, which a resumed session with nothing left to test doesn't
/// record, and whether each mutant's `killedBy` list is whole, not
/// recorded where nothing was collected.
@Suite("Mutation results facts")
struct MutationResultsFactsTests {
    /// The library file the hand-written runs mutate.
    private static let path = "Sources/Lib/Lib.swift"
    /// Its hash in the tree.
    private static let firstHash = String(repeating: "a", count: 64)

    /// A key on `line` of the library file.
    private static func key(line: Int) -> MutantKey {
        MutantKey(path: path, operatorID: "RelationalBoundary", line: line, column: 9, occurrence: 0)
    }

    @Test("the workers and time limit are the last session's that tested a mutant, not a resume's with none left")
    func settingsOfTestingSession() throws {
        let tree = [Self.path: Self.firstHash]
        let nothingLeft = { (session: Int, discovered: Int) in
            ResultsLines.header(.init(
                session: session,
                discovered: discovered,
                delta: .init(base: tree, files: [:]),
                workers: 0,
                timeoutSeconds: nil
            ))
        }
        let firstTested = try ResultsLines.results([
            ResultsLines.header(.init(discovered: 1, tree: tree, workers: 4)),
            ResultsLines.mutant(.init(line: 3)),
            nothingLeft(2, 1),
            ResultsLines.end(.init(session: 2))
        ])
        let laterTested = try ResultsLines.results([
            ResultsLines.header(.init(discovered: 2, tree: tree, workers: 4)),
            ResultsLines.mutant(.init(line: 3)),
            ResultsLines.header(.init(
                session: 2,
                discovered: 2,
                delta: .init(base: tree, files: [:]),
                workers: 2,
                timeoutSeconds: 30
            )),
            ResultsLines.mutant(.init(line: 5, session: 2)),
            nothingLeft(3, 2),
            ResultsLines.end(.init(session: 3))
        ])

        #expect(firstTested.sessions == 2 && firstTested.complete)
        #expect(firstTested.facts.workers == 4 && firstTested.facts.timeoutSeconds == 20)
        #expect(laterTested.sessions == 3 && laterTested.complete)
        #expect(laterTested.facts.workers == 2 && laterTested.facts.timeoutSeconds == 30)
    }

    @Test("""
        a resumed file takes the facts a resume can change, discovered and dropped mutants and whether runs stop at \
        the first failure, from the last header, as SwiftMutator's own reader does, and completeness with them; the \
        build and operators from the first
        """)
    func lastHeaderFacts() throws {
        let tree = [Self.path: Self.firstHash]
        let lines = [
            ResultsLines.header(.init(
                discovered: 3,
                tree: tree,
                stopsAtFirstFailure: true,
                dropped: 1,
                operators: ["RelationalBoundary", "SwapTernary"],
                executableSHA256: "first"
            )),
            ResultsLines.mutant(.init(line: 3)),
            ResultsLines.header(.init(
                session: 2,
                discovered: 2,
                delta: .init(base: tree, files: [:]),
                stopsAtFirstFailure: false,
                dropped: 2,
                operators: ["RelationalBoundary"],
                executableSHA256: "last"
            )),
            ResultsLines.mutant(.init(line: 5, session: 2)),
            ResultsLines.end(.init(session: 2))
        ]

        let results = try ResultsLines.results(lines)

        #expect(results.sessions == 2 && results.tested == 2)
        #expect(results.facts.mutantsDiscovered == 2 && results.facts.mutantsDropped == 2)
        #expect(results.facts.stopsAtFirstFailure == false)
        #expect(results.complete && results.incompleteReason == nil)
        #expect(results.facts.operators == ["RelationalBoundary", "SwapTernary"])
        #expect(results.facts.executableSHA256 == "first")
    }

    @Test("a list's completeness is null where nothing was collected: a not-covered entry, or a line with no killedBy")
    func completenessNotCollected() throws {
        let results = try ResultsLines.results([
            ResultsLines.header(.init(discovered: 3, notCovered: [Self.key(line: 9)])),
            ResultsLines.mutant(.init(line: 3, outcome: "passed")),
            ResultsLines.mutant(.init(line: 4, outcome: "timeout", endedBy: "timedOut", failedTestCount: 0)),
            ResultsLines.mutant(.init(line: 5, killedBy: ["a()"], failedTestCount: 1)),
            ResultsLines.end(.init())
        ])

        #expect(results.mutants.map(\.key.line) == [3, 4, 5, 9])
        #expect(results.mutants.map(\.killedByComplete) == [.notRecorded, .incomplete, .complete, .notRecorded])
    }
}
