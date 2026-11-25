//
//  USRJoin+Requirements.swift
//  SwiftStatsCore
//
//  Which definitions with no record are protocol requirements, and which
//  subscripts have accessor records of their own (M7, design §3.3, §3.5,
//  as built after review C6/C33 and C8). A property or subscript
//  requirement's getters and setters are requirements though their
//  `childOf`/`accessorOf` relation names the property, not the protocol:
//  the property's own definition in the same file is the protocol's child.
//  A shorthand subscript's own accessors are its explicit ones, which the
//  scan names `subscript`; a local computed property's getter, or a local
//  type's, nested in its body has the subscript as parent but isn't one.
//

extension USRJoin {
    /// The name the scan gives a subscript's explicit accessors.
    private static let subscriptName = "subscript"

    /// The keys of `records`' subscripts that have accessor records of their
    /// own: explicit accessors, which the scan names `subscript` with the
    /// subscript as parent. A local computed property's getter, or a local
    /// type's, nested in a shorthand subscript's body has the subscript as
    /// parent too, but its property's name.
    static func subscriptsWithAccessors(_ records: [FunctionRecord]) -> Set<String> {
        Set(records.filter { $0.kind == .accessor && $0.name == subscriptName }.compactMap(\.parentKey))
    }

    /// The USRs that `occurrences` (one file's) define as children of a
    /// protocol: its requirements, properties and subscripts among them.
    static func protocolMembers(in occurrences: [IndexOccurrenceFact]) -> Set<String> {
        var members: Set<String> = []
        for occurrence in occurrences where occurrence.roles & IndexSymbolKind.Role.definition != 0 {
            let isMember = occurrence.relations.contains { relation in
                relation.roles & IndexSymbolKind.RelationRole.childOf != 0 && relation.kind == IndexSymbolKind.protocol
            }
            if isMember {
                members.insert(occurrence.usr)
            }
        }
        return members
    }

    /// Whether `occurrence`, a definition no record holds, is a protocol
    /// requirement without a body: its `childOf` relation names a protocol,
    /// or its `childOf` or `accessorOf` relation names a property or
    /// subscript among `protocolMembers` (a property or subscript
    /// requirement's getter or setter, whose relations name the property,
    /// not the protocol).
    static func isRequirement(_ occurrence: IndexOccurrenceFact, protocolMembers: Set<String>) -> Bool {
        let owner = IndexSymbolKind.RelationRole.childOf | IndexSymbolKind.RelationRole.accessorOf
        return occurrence.relations.contains { relation in
            if relation.roles & IndexSymbolKind.RelationRole.childOf != 0, relation.kind == IndexSymbolKind.protocol {
                return true
            }
            return relation.roles & owner != 0 && USRKinds.isProperty(relation.kind)
                && protocolMembers.contains(relation.usr)
        }
    }
}
