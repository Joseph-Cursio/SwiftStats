//
//  CloneKind.swift
//  SwiftStatsCore
//
//  How a report names a clone class: exact or renamed subtree copies, a
//  sequence, or near-miss copies, in that order from the strongest claim.
//

/// The kind of a clone class, as reports name and order it.
enum CloneKind: String, Hashable, Sendable {
    /// A copied subtree, token for token.
    case exact
    /// Copies alike in shape, not identical.
    case nearMiss = "near-miss"
    /// A copied subtree whose identifiers or literals differ.
    case renamed
    /// A run of identical statements or members.
    case sequence

    /// The kinds from the strongest claim to the weakest.
    static let order: [Self] = [.exact, .renamed, .sequence, .nearMiss]

    /// Where the kind sorts: exact, renamed, sequence, near-miss.
    var rank: Int {
        Self.order.firstIndex(of: self) ?? Self.order.count
    }

    /// The kind of a class found by `pass`, exact or not.
    init(pass: CloneClass.Pass, exact: Bool) {
        switch pass {
        case .nearMiss:
            self = .nearMiss

        case .sequence:
            self = .sequence

        case .subtree:
            self = exact ? .exact : .renamed
        }
    }
}
