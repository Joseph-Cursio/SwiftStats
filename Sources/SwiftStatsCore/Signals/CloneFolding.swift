//
//  CloneFolding.swift
//  SwiftStatsCore
//
//  Folding nested clone classes (PRD §8), shared by divergent clones (M4)
//  and uneven clone testing (M5): a listed class that another listed class
//  holds folds into one maximal class, so one finding is listed once. What
//  "holds" means is the signal's; it must be transitive. Classes holding
//  each other stand as one: the most specific class (subtree, sequence,
//  near-miss), then the larger mass, then the lowest ordinal. A class held
//  by several maximal ones that don't hold each other folds into the one
//  with the largest mass, then the stronger kind (exact, renamed, sequence,
//  near-miss), then the lowest ordinal.
//

/// Folds nested clone classes into the classes holding them.
enum CloneFolding {
    /// The members of `members` that no other holds, each with the
    /// ordinals of the members folded into it, sorted, in ordinal order.
    /// `cloneClass` gives a member's class; `holds(lhs, rhs)` says whether
    /// `lhs` holds all of `rhs`.
    static func folded<Member>(
        _ members: [Member],
        cloneClass: (Member) -> CloneClass,
        holds: (Member, Member) -> Bool
    ) -> [(member: Member, folded: [Int])] {
        let ordered = members.sorted { cloneClass($0).ordinal < cloneClass($1).ordinal }
        // Members holding each other: the most specific, then largest, stands for them.
        var groups: [[Member]] = []
        for member in ordered {
            if let index = groups.firstIndex(where: { holds($0[0], member) && holds(member, $0[0]) }) {
                groups[index].append(member)
            } else {
                groups.append([member])
            }
        }
        var foldedInto: [Int: [Int]] = [:]
        let representatives = groups.compactMap { group -> Member? in
            let standing = group.min { lhs, rhs in
                let (left, right) = (cloneClass(lhs), cloneClass(rhs))
                return (left.pass.specificity, -left.mass, left.ordinal)
                    < (right.pass.specificity, -right.mass, right.ordinal)
            }
            if let standing {
                let ordinal = cloneClass(standing).ordinal
                foldedInto[ordinal, default: []] += group.map { cloneClass($0).ordinal }.filter { $0 != ordinal }
            }
            return standing
        }
        func strictlyHolds(_ lhs: Member, _ rhs: Member) -> Bool {
            holds(lhs, rhs) && holds(rhs, lhs) == false
        }
        let maximal = representatives.filter { candidate in
            representatives.contains { strictlyHolds($0, candidate) } == false
        }
        let maximalOrdinals = Set(maximal.map { cloneClass($0).ordinal })
        let held = representatives.filter { maximalOrdinals.contains(cloneClass($0).ordinal) == false }
        for representative in held {
            let holder = maximal.filter { strictlyHolds($0, representative) }.min { lhs, rhs in
                let (left, right) = (cloneClass(lhs), cloneClass(rhs))
                return (-left.mass, kindRank(left), left.ordinal) < (-right.mass, kindRank(right), right.ordinal)
            }
            guard let holder else {
                continue
            }
            let ordinal = cloneClass(representative).ordinal
            foldedInto[cloneClass(holder).ordinal, default: []] += [ordinal] + (foldedInto[ordinal] ?? [])
        }
        return maximal.map { ($0, (foldedInto[cloneClass($0).ordinal] ?? []).sorted()) }
    }

    /// Where `cloneClass`'s kind sorts among the strongest claims.
    private static func kindRank(_ cloneClass: CloneClass) -> Int {
        CloneKind(pass: cloneClass.pass, exact: cloneClass.exact).rank
    }
}
