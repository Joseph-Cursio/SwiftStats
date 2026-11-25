//
//  DeadCodeIndex.swift
//  SwiftStatsCore
//
//  What the dead-code mapping takes from the `index` collector's read
//  (M7, design §5.4): the records holding each USR as their primary or
//  secondary USR, each property's accessor records (`accessorOf`, as the
//  reference graph routes a property's references), the package types by
//  USR with the type record each is placed on and its identity, each
//  record's owning package type by its primary USR, and the package type
//  owning each extension record (`TypeOwnership`). Absent when the index
//  didn't run, and the mapping then goes by position.
//

/// The index facts the dead-code mapping reads.
struct DeadCodeIndex: Sendable {
    /// The records holding each USR as their primary or secondary USR, by
    /// USR.
    let recordsByUSR: [String: Set<String>]
    /// Each property's accessor records, by the property's USR.
    let accessorsByProperty: [String: Set<String>]
    /// The scan's type record each package type is placed on, by the
    /// type's USR.
    let typeRecords: [String: Int]
    /// Each package type's identity, by USR.
    let identities: [String: TypeIdentity]
    /// The records with a primary USR.
    let joined: Set<String>
    /// The owning package type of each record with a primary USR that has
    /// one, by key.
    let owners: [String: String]
    /// The owning package type of each extension record that has one, by
    /// the record's index among the scan's type records.
    let extensionOwners: [Int: String]

    /// The facts `join` and `ownership` give for `records`, the scan's
    /// records.
    init(join: USRJoin, records: [FunctionRecord], ownership: TypeOwnership) {
        var holders: [String: Set<String>] = [:]
        for (key, usr) in join.primary {
            holders[usr, default: []].insert(key)
        }
        for (key, usr) in join.secondary {
            holders[usr, default: []].insert(key)
        }
        recordsByUSR = holders
        var accessors: [String: Set<String>] = [:]
        for record in records where record.kind == .accessor {
            guard let definition = join.primaryDefinitions[record.key] else {
                continue
            }
            for relation in definition.occurrence.relations
            where relation.roles & IndexSymbolKind.RelationRole.accessorOf != 0 {
                accessors[relation.usr, default: []].insert(record.key)
            }
        }
        accessorsByProperty = accessors
        typeRecords = ownership.types.mapValues(\.record)
        identities = ownership.types.mapValues(\.identity)
        joined = Set(join.primary.keys)
        owners = join.primary.compactMapValues(ownership.owner(of:))
        var extensions: [Int: String] = [:]
        for (index, type) in ownership.records.enumerated() where type.kind == .extensionDeclaration {
            extensions[index] = ownership.owner(ofRecord: index)
        }
        extensionOwners = extensions
    }
}
