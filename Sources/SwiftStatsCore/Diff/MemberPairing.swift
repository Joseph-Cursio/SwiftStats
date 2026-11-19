//
//  MemberPairing.swift
//  SwiftStatsCore
//
//  Pairs the records of two matched families (PRD §6.6). The anchors pair
//  first: root with root, or a computed property's accessors by accessor
//  kind. Nested records then pair by key, once the old anchor's key at the
//  front of each is replaced with its new counterpart's, then by key without
//  sibling numbers and file parts, so a renumbered ` #2` still pairs with
//  its own body.
//

/// Pairs records within a matched family.
enum MemberPairing {
    /// The paired records, and those only in the older or newer family.
    static func pair(_ old: FunctionFamily, _ new: FunctionFamily) -> Pairing<FunctionRow> {
        let anchors: Pairing<FunctionRow>
        if let oldRoot = old.root, let newRoot = new.root {
            anchors = Pairing(pairs: [(oldRoot, newRoot)], unmatchedOld: [], unmatchedNew: [])
        } else {
            anchors = GroupPairing.pair(old.accessors, new.accessors, hash: { $0.accessorKind ?? "" }, order: byLine)
        }
        let anchorKeys = Set(old.accessors.map(\.key) + [old.root?.key].compactMap(\.self))
        let newAnchorKeys = Set(new.accessors.map(\.key) + [new.root?.key].compactMap(\.self))
        let rewrites = anchors.pairs.map { (old: $0.0.key, new: $0.1.key) }
        let rewrite: (FunctionRow) -> String = { row in
            guard let anchor = rewrites.first(where: { row.key.hasPrefix($0.old + " / ") }) else {
                return row.key
            }
            return anchor.new + row.key.dropFirst(anchor.old.count)
        }
        let file = new.file
        let form: (String) -> String = { KeyForm.withoutOrdinals(KeyForm.withoutFile($0, file: file)) }
        let oldChildren = old.members.filter { anchorKeys.contains($0.key) == false }
        let newChildren = new.members.filter { newAnchorKeys.contains($0.key) == false }
        let oldGroups = Dictionary(grouping: oldChildren) { form(rewrite($0)) }
        let newGroups = Dictionary(grouping: newChildren) { form($0.key) }
        var result = anchors
        result.unmatchedNew += newGroups.filter { oldGroups[$0.key] == nil }.values.flatMap(\.self)
        for (key, group) in oldGroups {
            let paired = GroupPairing.pair(group, newGroups[key] ?? [], hash: \.bodyHash, order: byLine)
            result.pairs += paired.pairs
            result.unmatchedOld += paired.unmatchedOld
            result.unmatchedNew += paired.unmatchedNew
        }
        return result
    }

    /// Orders records by line, then key.
    private static func byLine(_ lhs: FunctionRow, _ rhs: FunctionRow) -> Bool {
        (lhs.startLine, lhs.key) < (rhs.startLine, rhs.key)
    }
}
