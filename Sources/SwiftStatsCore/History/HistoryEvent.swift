//
//  HistoryEvent.swift
//  SwiftStatsCore
//
//  What one commit did to one function family: changed, moved, added or removed.
//

/// What a commit did to one family.
struct HistoryEvent: Hashable, Sendable {
    /// The family before the commit; nil when the commit added it.
    let old: FamilyRef?
    /// The family after the commit; nil when the commit removed it.
    let new: FamilyRef?
    /// Whether the commit changed it, not only moved it.
    let changed: Bool
    /// How old and new were matched; nil when one side is missing.
    let method: MatchMethod?
}
