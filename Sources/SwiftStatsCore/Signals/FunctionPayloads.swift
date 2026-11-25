//
//  FunctionPayloads.swift
//  SwiftStatsCore
//
//  The coverage and mutation payloads an M7 signal adds to a function's
//  item when the snapshot holds those results (design §8): its coverage,
//  as M5's signals give it, whenever the snapshot holds coverage rows, and
//  its mutation results in M6's weak-tests shape when it has mutants.
//

/// The coverage and mutation payloads of a snapshot's functions.
struct FunctionPayloads {
    /// Whether the snapshot holds coverage.
    private let holdsCoverage: Bool
    /// The coverage of each production record, by key.
    private let coverage: [String: CoverageRecord]
    /// The judge of the snapshot's mutation results; nil when it holds
    /// none.
    private let judge: MutationJudge?

    /// The payloads of `snapshot`'s functions.
    init(_ snapshot: StoredSnapshot) {
        let held = snapshot.coverage?.report
        holdsCoverage = held != nil
        coverage = Dictionary((held?.records ?? []).map { ($0.key, $0) }) { first, _ in first }
        judge = snapshot.mutation.map { MutationJudge(snapshot, mutation: $0.report, coverage: held) }
    }

    /// `row`'s coverage: its lines and regions, either nil when nothing of
    /// it has coverage data; nil when the snapshot holds no coverage.
    func coverage(of row: FunctionRow) -> SignalItem.Coverage? {
        guard holdsCoverage else {
            return nil
        }
        let record = coverage[row.key]
        return SignalItem.Coverage(lines: record?.lines, regions: record?.regions)
    }

    /// `row`'s mutation results; nil when it has no mutants, or the
    /// snapshot holds no mutation results.
    func mutation(of row: FunctionRow) -> SignalItem.Mutation? {
        guard let judge, let counts = judge.counts(of: row) else {
            return nil
        }
        return judge.payload(of: row, counts: counts)
    }
}
