//
//  MarkdownSignals+Index.swift
//  SwiftStatsCore
//
//  The input columns of M7's signal tables (design §8, §10.1): for
//  test-only production code, after the function and its score, how many
//  test containers reference it with the first three named, then its
//  lines covered and function score, a dash when the snapshot holds no
//  coverage or the function has no mutants. Dead but tested and hidden
//  coupling have none until their plan steps add them. A cell whose
//  payload is absent shows a dash.
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

    /// The input columns of M7's signal `signal`.
    static func indexColumns(for signal: SignalName) -> [Column] {
        signal == .testOnlyProduction ? testOnlyColumns : []
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
