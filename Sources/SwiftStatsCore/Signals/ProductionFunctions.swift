//
//  ProductionFunctions.swift
//  SwiftStatsCore
//
//  The function rows M4's signals list (PRD §8): production code outside
//  generated files, read from the store's own `generated` column, so a
//  snapshot without history gives the same lists. A suggestion attaches to
//  one of them through its location's owner.
//

/// A snapshot's production function rows outside generated files.
struct ProductionFunctions {
    /// The rows, in the snapshot's order.
    let rows: [FunctionRow]
    /// The rows by key.
    private let byKey: [String: FunctionRow]

    /// The rows of `snapshot`. A row written before store v3, which
    /// doesn't say whether its file is generated, is left out.
    init(_ snapshot: StoredSnapshot) {
        rows = snapshot.functions.filter { $0.role == .production && $0.facts?.generated == false }
        byKey = Dictionary(rows.map { ($0.key, $0) }) { first, _ in first }
    }

    /// The row whose key is `key`; nil when no production row outside
    /// generated files has it.
    func row(key: String) -> FunctionRow? {
        byKey[key]
    }

    /// The row `candidate` attaches to; nil when it attaches to no
    /// function, or to one that isn't production code outside generated files.
    func row(of candidate: PropertyCandidate) -> FunctionRow? {
        guard let location = candidate.location, location.attachedTo == .function, let owner = location.owner else {
            return nil
        }
        return byKey[owner]
    }
}
