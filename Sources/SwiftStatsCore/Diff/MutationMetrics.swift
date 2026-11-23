//
//  MutationMetrics.swift
//  SwiftStatsCore
//
//  Each record's mutation figures on each side of a diff (M6, design §8),
//  when the SwiftMutator collector's results compare: its mutation score
//  (SwiftMutator's formula; none when nothing was scored, as for a
//  function no test ran), its function score (the signals' figure, so a
//  function no test ran reads low, not missing), its unkilled mutants and
//  its scored mutants (the function score's denominator). A record with
//  no mutant on a side has no values there: not collected, never 0.
//

/// Mutation figures of records by key.
struct MutationMetrics {
    /// The metric of a record's mutation score.
    static let score = "mutation.score.percent"
    /// The metric of a record's function score.
    static let functionScore = "mutation.functionScore.percent"
    /// The metric of a record's unkilled mutants.
    static let unkilled = "mutation.unkilled"
    /// The metric of a record's scored mutants.
    static let scored = "mutation.scored"

    /// Values in the older snapshot: record key → metric → value.
    let old: [String: [String: Double]]
    /// Values in the newer snapshot.
    let new: [String: [String: Double]]

    /// The values of `old` and `new`; empty unless `compared` holds the
    /// SwiftMutator collector.
    init(old: StoredMutation?, new: StoredMutation?, compared: Set<String>) {
        let compares = compared.contains(MutationAdapter.name)
        self.old = compares ? Self.values(of: old) : [:]
        self.new = compares ? Self.values(of: new) : [:]
    }

    /// Each record's figures in `mutation`, by key.
    private static func values(of mutation: StoredMutation?) -> [String: [String: Double]] {
        let pairs = (mutation?.report.records ?? []).map { record in
            (record.key, values(of: record))
        }
        return Dictionary(pairs) { first, _ in first }
    }

    /// `record`'s figures that have a value.
    private static func values(of record: MutationRecord) -> [String: Double] {
        let figures = MutationFigures(record.counts)
        let optional: [String: Double?] = [
            score: figures.score.percent,
            functionScore: figures.functionScore.percent,
            unkilled: Double(figures.unkilled),
            scored: Double(figures.functionScore.scored)
        ]
        return optional.compactMapValues(\.self)
    }
}
