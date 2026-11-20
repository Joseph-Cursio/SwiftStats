//
//  CandidateMerge.swift
//  SwiftStatsCore
//
//  Merges the rows each target's `swift-infer index` wrote (PRD §7.11).
//  The identity hash names no module or file, so two targets can write the
//  same identity: a test lifted for both, or two modules declaring the same
//  signature. Rows group by population and identity, then by location; at
//  one location, rows equal but for timestamps are duplicates, and rows
//  that differ keep the one with a structural blocker, then a type shape,
//  then the lower score, then the first target's name; an identity found
//  at several locations keeps one candidate per location, flagged. The
//  result doesn't depend on the order the rows arrive in.
//

/// Merges per-target suggestions.
enum CandidateMerge {
    /// `rows`, from any targets in any order, merged.
    static func merge(_ rows: [SwiftInferRow]) -> MergedCandidates {
        let byKey = Dictionary(grouping: rows) { "\($0.population.rawValue) \($0.identity)" }
        var kept: [MergedCandidates.Row] = []
        var duplicates = 0
        var conflicts = 0
        var collisions = 0
        for (_, sameIdentity) in byKey.sorted(by: { $0.key < $1.key }) {
            let byLocation = Dictionary(grouping: sameIdentity, by: \.location)
            let collides = byLocation.count > 1
            if collides {
                collisions += 1
            }
            for (_, group) in byLocation.sorted(by: { $0.key < $1.key }) {
                var distinct: [SwiftInferRow] = []
                for row in group.sorted(by: { $0.target < $1.target }) {
                    if distinct.contains(where: { $0.fields == row.fields }) {
                        duplicates += 1
                    } else {
                        distinct.append(row)
                    }
                }
                conflicts += distinct.count - 1
                if let winner = distinct.min(by: isKept(_:over:)) {
                    kept.append(MergedCandidates.Row(row: winner, identityCollision: collides))
                }
            }
        }
        return MergedCandidates(rows: kept, duplicates: duplicates, conflicts: conflicts, collisions: collisions)
    }

    /// Whether `lhs` is kept over `rhs`, two rows of one identity at one
    /// location that differ: a structural blocker first, then a type
    /// shape, then the lower score, then the first target's name.
    private static func isKept(_ lhs: SwiftInferRow, over rhs: SwiftInferRow) -> Bool {
        if (lhs.blocker == nil) != (rhs.blocker == nil) {
            return lhs.blocker != nil
        }
        if lhs.hasTypeShape != rhs.hasTypeShape {
            return lhs.hasTypeShape
        }
        if lhs.score != rhs.score {
            return lhs.score < rhs.score
        }
        return lhs.target < rhs.target
    }
}
