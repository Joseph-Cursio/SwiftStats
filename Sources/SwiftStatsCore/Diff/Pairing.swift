//
//  Pairing.swift
//  SwiftStatsCore
//
//  Items paired between two snapshots, and those left on each side.
//

/// Paired items and the leftovers.
struct Pairing<Item> {
    /// Each older item with its newer counterpart.
    var pairs: [(Item, Item)]
    /// Older items with no counterpart.
    var unmatchedOld: [Item]
    /// Newer items with no counterpart.
    var unmatchedNew: [Item]
}
