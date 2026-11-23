//
//  UnevenMutationMember.swift
//  SwiftStatsCore
//
//  A clone class whose copies the tests kill unevenly (M6, uneven clone
//  testing, mutation part, design §7.4): its measured copies and those at
//  most the low limit killed, before nested members fold into the ones
//  holding them.
//

/// A clone class with a well tested and a poorly tested copy.
struct UnevenMutationMember {
    /// The class.
    let cloneClass: CloneClass
    /// Its measured copies, in the class's order.
    let copies: [MutationCopy]
    /// Those at most the low limit killed.
    let poor: [MutationCopy]

    /// The unkilled mutants of its poorly tested copies, each once (copies
    /// may overlap): what its score counts.
    var unkilled: [Mutant] {
        var seen: Set<MutantKey> = []
        return poor.flatMap(\.unkilled).filter { seen.insert($0.key).inserted }
    }

    /// Whether a mutant of its poorly tested copies ran and no test checked
    /// it (survived or timed out), rather than all of them lying in code no
    /// test ran.
    var ranUnchecked: Bool {
        poor.contains { $0.figures.runButUnchecked > 0 }
    }

    /// Its least killed copy: the lowest function score (cross-multiplied),
    /// then the most unkilled mutants, then file, then first line. A member
    /// has a poorly tested copy, so there is one.
    var leastKilled: MutationCopy {
        let sorted = poor.sorted { lhs, rhs in
            let (left, right) = (lhs.score, rhs.score)
            let (leftShare, rightShare) = (left.killed * right.scored, right.killed * left.scored)
            if leftShare != rightShare {
                return leftShare < rightShare
            }
            return (-lhs.figures.unkilled, lhs.file, lhs.start) < (-rhs.figures.unkilled, rhs.file, rhs.start)
        }
        return sorted[0]
    }

    /// Whether every poorly tested copy of `other` lies inside one of this
    /// member's poorly tested copies.
    func holds(_ other: Self) -> Bool {
        other.poor.allSatisfy { copy in poor.contains { copy.lies(inside: $0) } }
    }
}
