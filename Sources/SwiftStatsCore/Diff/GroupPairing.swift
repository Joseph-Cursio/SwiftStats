//
//  GroupPairing.swift
//  SwiftStatsCore
//
//  Pairs the members of a group that share a normalised key between two
//  snapshots (PRD §6.6): first by a body hash unique within the group on
//  both sides, then, when the counts left are equal, in source order.
//

/// Pairs items within a group.
enum GroupPairing {
    /// Pairs of `old` and `new` items, and those left over on each side.
    static func pair<Item>(
        _ old: [Item],
        _ new: [Item],
        hash: (Item) -> String,
        order: (Item, Item) -> Bool
    ) -> Pairing<Item> {
        let oldByHash = Dictionary(grouping: old.indices) { hash(old[$0]) }
        let newByHash = Dictionary(grouping: new.indices) { hash(new[$0]) }
        var pairs: [(Item, Item)] = []
        var usedOld: Set<Int> = []
        var usedNew: Set<Int> = []
        for (value, oldIndices) in oldByHash.sorted(by: { $0.key < $1.key }) {
            guard oldIndices.count == 1, let newIndices = newByHash[value], newIndices.count == 1 else {
                continue
            }
            pairs.append((old[oldIndices[0]], new[newIndices[0]]))
            usedOld.insert(oldIndices[0])
            usedNew.insert(newIndices[0])
        }
        let leftOld = old.indices.filter { usedOld.contains($0) == false }.map { old[$0] }.sorted(by: order)
        let leftNew = new.indices.filter { usedNew.contains($0) == false }.map { new[$0] }.sorted(by: order)
        guard leftOld.count == leftNew.count else {
            return Pairing(pairs: pairs, unmatchedOld: leftOld, unmatchedNew: leftNew)
        }
        return Pairing(pairs: pairs + Array(zip(leftOld, leftNew)), unmatchedOld: [], unmatchedNew: [])
    }
}
