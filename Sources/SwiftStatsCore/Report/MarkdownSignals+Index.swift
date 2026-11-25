//
//  MarkdownSignals+Index.swift
//  SwiftStatsCore
//
//  The input columns of M7's signal tables (design §8, §10.1): for dead
//  but tested, after the function and its score (its mutants that ran),
//  its mutants killed of scored, with its run's coverage setting when off,
//  its killing tests, the declaration outskirts reports unused that covers
//  it with the rule, and whether it is dead with tests as roots too; for
//  test-only production code, after the function and its score, how many
//  test containers reference it with the first three named, then its
//  lines covered and function score, a dash when the snapshot holds no
//  coverage or the function has no mutants. Hidden coupling has none
//  until its plan step adds them. A cell whose payload is absent shows a
//  dash.
//

extension MarkdownSignals {
    /// Test referrers a cell names before saying how many more there are.
    static let listedReferrers = 3

    /// Test-only production code: the test referrers, then the lines
    /// covered and the function score when the snapshot holds them.
    static var testOnlyColumns: [Column] {
        [
            ("Test referrers", references(referrers)),
            ("Lines covered", coverage { tally($0.lines) }),
            ("Function score", mutation { functionScore($0.functionScore) })
        ]
    }

    /// Dead but tested: the mutants killed of scored, the killing tests,
    /// the covering declaration and whether the run with tests as roots
    /// covers the function too.
    static var deadButTestedColumns: [Column] {
        [
            ("Killed / scored", mutation(killed)),
            ("Killing tests", mutation(killingTests)),
            ("Covering declaration", dead { "`\($0.kind) \($0.name)` via \($0.via.rawValue)" }),
            ("Dead with tests as roots", dead { $0.deadWithTestsAsRoots ? "yes" : "no" })
        ]
    }

    /// The input columns of M7's signal `signal`.
    static func indexColumns(for signal: SignalName) -> [Column] {
        switch signal {
        case .deadButTested:
            deadButTestedColumns

        case .testOnlyProduction:
            testOnlyColumns

        default:
            []
        }
    }

    /// A function's mutants killed of scored (its function score), with
    /// its run's coverage setting when off.
    private static func killed(_ mutation: SignalItem.Mutation) -> String {
        functionScore(mutation.functionScore) + (mutation.coverage == .disabled ? ", coverage off" : "")
    }

    /// A cell reading an item's covering declaration with `cell`.
    private static func dead(_ cell: @escaping (SignalItem.Dead) -> String) -> (SignalItem) -> String {
        { item in item.dead.map(cell) ?? "—" }
    }

    /// How many test containers reference a function, the first three
    /// named, and how many more there are.
    private static func referrers(_ references: SignalItem.References) -> String {
        let named = references.testReferrers.prefix(listedReferrers)
        guard named.isEmpty == false else {
            return String(references.tests)
        }
        let more = references.tests - named.count
        return "\(references.tests): " + named.joined(separator: "; ") + (more > 0 ? " (+\(more) more)" : "")
    }

    /// A cell reading an item's references with `cell`.
    private static func references(_ cell: @escaping (SignalItem.References) -> String) -> (SignalItem) -> String {
        { item in item.references.map(cell) ?? "—" }
    }
}
