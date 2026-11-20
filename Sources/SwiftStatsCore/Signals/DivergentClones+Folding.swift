//
//  DivergentClones+Folding.swift
//  SwiftStatsCore
//
//  Folding nested divergent classes (PRD §8): a member whose changed and
//  unchanged families are both within another member's folds into one
//  maximal member, so one divergence is listed once. Members with equal
//  sets keep the most specific class (subtree, sequence, near-miss), then
//  the larger mass; a member within several maximal ones that don't hold
//  each other folds into the one with the largest mass, then the stronger
//  kind, then the lowest earlier ordinal.
//

extension DivergentClones {
    /// The members of `members` that no other holds, each with the
    /// earlier ordinals of the members folded into it, sorted.
    static func folded(_ members: [DivergentMember]) -> [(member: DivergentMember, folded: [Int])] {
        // Members with equal sets: the most specific, then largest, stands for them.
        let groups = Dictionary(grouping: members) { member in
            [member.changedFamilies, member.unchangedFamilies]
        }
        let representatives = groups.values.compactMap { group in
            group.min { lhs, rhs in
                (lhs.cloneClass.pass.specificity, -lhs.cloneClass.mass, lhs.cloneClass.ordinal)
                    < (rhs.cloneClass.pass.specificity, -rhs.cloneClass.mass, rhs.cloneClass.ordinal)
            }
        }
        var foldedInto: [Int: [Int]] = [:]
        for representative in representatives {
            let own = groups[[representative.changedFamilies, representative.unchangedFamilies]] ?? []
            foldedInto[representative.cloneClass.ordinal, default: []] += own
                .map(\.cloneClass.ordinal)
                .filter { $0 != representative.cloneClass.ordinal }
        }
        let maximal = representatives.filter { candidate in
            representatives.contains { $0.strictlyHolds(candidate) } == false
        }
        for representative in representatives where maximal.contains(where: { isSame($0, representative) }) == false {
            let holder = maximal.filter { $0.strictlyHolds(representative) }.min { lhs, rhs in
                (-lhs.cloneClass.mass, lhs.kind.rank, lhs.cloneClass.ordinal)
                    < (-rhs.cloneClass.mass, rhs.kind.rank, rhs.cloneClass.ordinal)
            }
            guard let holder else {
                continue
            }
            let moved = [representative.cloneClass.ordinal] + (foldedInto[representative.cloneClass.ordinal] ?? [])
            foldedInto[holder.cloneClass.ordinal, default: []] += moved
        }
        return maximal
            .sorted { $0.cloneClass.ordinal < $1.cloneClass.ordinal }
            .map { ($0, (foldedInto[$0.cloneClass.ordinal] ?? []).sorted()) }
    }

    /// Whether `lhs` and `rhs` are the same earlier class.
    private static func isSame(_ lhs: DivergentMember, _ rhs: DivergentMember) -> Bool {
        lhs.cloneClass.ordinal == rhs.cloneClass.ordinal
    }
}
