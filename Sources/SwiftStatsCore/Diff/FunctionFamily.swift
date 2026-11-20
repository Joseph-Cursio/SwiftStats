//
//  FunctionFamily.swift
//  SwiftStatsCore
//
//  A function record with its nested functions and accessors, or a computed
//  property's accessors (PRD §6.6): the unit `diff` reports changes on.
//

/// A family of function records.
struct FunctionFamily {
    /// The root's key, or the property's key without its accessor part.
    let id: String
    /// The record with no parent; nil for a computed property's accessors.
    let root: FunctionRow?
    /// Every record in the family, sorted by key, then line.
    let members: [FunctionRow]

    /// The family's file.
    var file: String {
        root?.file ?? members[0].file
    }

    /// The family's kind.
    var kind: FunctionKind {
        root?.kind ?? .accessor
    }

    /// The family's module.
    var module: String {
        members[0].module
    }

    /// The root's body hash, or the accessors' hashes together.
    var bodyHash: String {
        root?.bodyHash ?? accessors.map { "\($0.accessorKind ?? ""):\($0.bodyHash)" }.joined(separator: ",")
    }

    /// The root's body lines, or its accessors' together.
    var bodyLines: Int {
        root?.bodyLines ?? accessors.reduce(0) { $0 + $1.bodyLines }
    }

    /// The root's stripped lines, or its accessors' together.
    var strippedLines: Int {
        root?.strippedLines ?? accessors.reduce(0) { $0 + $1.strippedLines }
    }

    /// A computed property's accessors; empty for a family with a root.
    var accessors: [FunctionRow] {
        root == nil ? members.filter(Self.isPropertyAccessor) : []
    }

    /// What tells this family from any other in its snapshot: its key,
    /// file and first line.
    var identity: String {
        "\(id)\u{0}\(file)\u{0}\(startLine)"
    }

    /// Where the family starts, for ordering.
    var startLine: Int {
        root?.startLine ?? members[0].startLine
    }

    /// The families `rows` form.
    static func families(_ rows: [FunctionRow]) -> [Self] {
        let byKey = Dictionary(grouping: rows.indices) { rows[$0].key }
        var groups: [String: [Int]] = [:]
        for index in rows.indices {
            groups[group(of: index, in: rows, byKey: byKey), default: []].append(index)
        }
        return groups.values.map { indices in
            let familyMembers = indices.map { rows[$0] }.sorted { ($0.key, $0.startLine) < ($1.key, $1.startLine) }
            let familyRoot = familyMembers.first { $0.parentKey == nil && isPropertyAccessor($0) == false }
            return Self(id: familyRoot?.key ?? ownerKey(of: familyMembers[0]), root: familyRoot, members: familyMembers)
        }
        .sorted { ($0.id, $0.file, $0.startLine) < ($1.id, $1.file, $1.startLine) }
    }

    /// Whether `row` is a computed property's accessor, which has no parent record.
    static func isPropertyAccessor(_ row: FunctionRow) -> Bool {
        row.kind == .accessor && row.parentKey == nil
    }

    /// A property accessor's key without its ` { get }` part.
    static func ownerKey(of row: FunctionRow) -> String {
        guard let accessor = row.accessorKind,
              let range = row.key.range(of: " { \(accessor) }", options: .backwards) else {
            return row.key
        }
        return row.key.replacingCharacters(in: range, with: "")
    }

    /// The family `rows[index]` belongs to: its root's index, or a computed
    /// property's key and file. A missing parent makes a record its own root.
    private static func group(of index: Int, in rows: [FunctionRow], byKey: [String: [Int]]) -> String {
        var current = index
        var seen: Set<Int> = [index]
        while let parent = rows[current].parentKey,
              let parentIndex = byKey[parent]?.first,
              seen.insert(parentIndex).inserted {
            current = parentIndex
        }
        let top = rows[current]
        if isPropertyAccessor(top) {
            return "property\u{0}\(ownerKey(of: top))\u{0}\(top.file)"
        }
        return "record\u{0}\(current)"
    }
}
