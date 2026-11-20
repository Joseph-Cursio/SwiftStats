//
//  DivergentMember.swift
//  SwiftStatsCore
//
//  A clone class of an earlier snapshot whose copies diverged since (PRD
//  §8): its diverging slots' units, changed and unchanged, and its score,
//  before nested members are folded into the ones holding them.
//

/// An earlier clone class with diverging slots.
struct DivergentMember {
    /// The class, in the earlier snapshot.
    let cloneClass: CloneClass
    /// Its copies with a production, non-generated family now.
    let copies: Int
    /// The stripped lines of the units in its diverging slots.
    let lines: Int
    /// The units in diverging slots that changed, one per family, in copy order.
    let changed: [CopyUnit]
    /// The units in diverging slots that didn't, one per family, in copy order.
    let unchanged: [CopyUnit]

    /// The diverging lines per copy beyond the first.
    var score: Double {
        Double(lines) / Double(max(copies - 1, 1))
    }

    /// Where the class sorts among the strongest claims.
    var kind: CloneKind {
        CloneKind(pass: cloneClass.pass, exact: cloneClass.exact)
    }

    /// The families now of the changed units.
    var changedFamilies: Set<FamilyRef> {
        Set(changed.map(\.ref))
    }

    /// The families now of the unchanged units.
    var unchangedFamilies: Set<FamilyRef> {
        Set(unchanged.map(\.ref))
    }

    /// Whether this member's changed and unchanged families hold all of
    /// `other`'s, and more.
    func strictlyHolds(_ other: Self) -> Bool {
        let (changedOwn, unchangedOwn) = (changedFamilies, unchangedFamilies)
        let (changedOther, unchangedOther) = (other.changedFamilies, other.unchangedFamilies)
        return changedOther.isSubset(of: changedOwn) && unchangedOther.isSubset(of: unchangedOwn)
            && (changedOther != changedOwn || unchangedOther != unchangedOwn)
    }
}
