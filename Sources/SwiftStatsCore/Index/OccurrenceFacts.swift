//
//  OccurrenceFacts.swift
//  SwiftStatsCore
//
//  One pass over the occurrences the kept and variant units' records hold
//  (M7, design §4), for the reference graph and type ownership: each
//  distinct occurrence once (variant units and shared records repeat
//  them), by file, files in order. It notes each definition's `childOf`
//  relation (an explicit definition's over an implicit one's), the targets
//  defining each USR, the explicit definitions of nominal types and every
//  extension's definition in the scanned files that didn't change, which
//  symbols override or witness which (`overrideOf`, implicit occurrences
//  included), the type each extension's head names (`extendedBy`), and the
//  reference occurrences in the scanned files that didn't change.
//

/// What the coupling reads from a snapshot's occurrences.
struct OccurrenceFacts {
    /// An occurrence with the file it was filed under.
    struct Located {
        /// The file, relative to the package root (or absolute outside it).
        let file: String
        /// The occurrence.
        let occurrence: IndexOccurrenceFact
    }

    /// The nominal type kinds: struct, class (actors too), enum, protocol.
    private static let nominalKinds: Set<Int> = [
        IndexSymbolKind.struct, IndexSymbolKind.class, IndexSymbolKind.enum, IndexSymbolKind.protocol
    ]

    /// The `childOf` relation of each USR's definition, by USR.
    private(set) var childOf: [String: IndexOccurrenceFact.Relation] = [:]
    /// The package targets whose files define each USR, by USR.
    private(set) var definitionTargets: [String: Set<String>] = [:]
    /// The explicit definitions of structs, classes, enums and protocols
    /// in the scanned files that didn't change, in file and occurrence
    /// order.
    private(set) var typeDefinitions: [Located] = []
    /// Each extension's first definition, by its USR.
    private(set) var extensionDefinitions: [String: Located] = [:]
    /// The symbols of the occurrences overriding or witnessing each USR,
    /// by the overridden USR.
    private(set) var overriding: [String: Set<String>] = [:]
    /// Every symbol of an occurrence with an `overrideOf` relation.
    private(set) var overridingSymbols: Set<String> = []
    /// The type each extension's head names, by the extension's USR.
    private(set) var extended: [String: String] = [:]
    /// The distinct reference occurrences in the scanned files that didn't
    /// change, in file and occurrence order.
    private(set) var references: [Located] = []

    /// The facts of `occurrences` (by file, as `USRJoin.occurrences(in:)`
    /// files them), each file's target in `targets` (package targets
    /// only), definitions of types and references taken only from
    /// `joinable` files (scanned, unchanged).
    init(occurrences: [String: [IndexOccurrenceFact]], targets: [String: String], joinable: Set<String>) {
        for (file, held) in occurrences.sorted(by: { CodePointOrder.precedes($0.key, $1.key) }) {
            var seen: Set<IndexOccurrenceFact> = []
            for occurrence in held where seen.insert(occurrence).inserted {
                note(Located(file: file, occurrence: occurrence), target: targets[file], joinable: joinable)
            }
        }
    }

    /// Notes what `located`, in a file of `target`, gives.
    private mutating func note(_ located: Located, target: String?, joinable: Set<String>) {
        let occurrence = located.occurrence
        let usr = occurrence.usr
        let isReference = occurrence.roles & IndexSymbolKind.Role.reference != 0
        for relation in occurrence.relations {
            if relation.roles & IndexSymbolKind.RelationRole.overrideOf != 0 {
                overriding[relation.usr, default: []].insert(usr)
                overridingSymbols.insert(usr)
            }
            let extends = relation.roles & IndexSymbolKind.RelationRole.extendedBy != 0
            if isReference, extends, extended[relation.usr] == nil {
                extended[relation.usr] = usr
            }
        }
        if occurrence.roles & IndexSymbolKind.Role.definition != 0 {
            noteDefinition(located, target: target, joinable: joinable)
        }
        if isReference, joinable.contains(located.file) {
            references.append(located)
        }
    }

    /// Notes the definition `located`, in a file of `target`.
    private mutating func noteDefinition(_ located: Located, target: String?, joinable: Set<String>) {
        let occurrence = located.occurrence
        let usr = occurrence.usr
        let isImplicit = occurrence.roles & IndexSymbolKind.Role.implicit != 0
        if let target {
            definitionTargets[usr, default: []].insert(target)
        }
        let parent = occurrence.relations.first { $0.roles & IndexSymbolKind.RelationRole.childOf != 0 }
        if let parent, childOf[usr] == nil || isImplicit == false {
            childOf[usr] = parent
        }
        if joinable.contains(located.file), Self.nominalKinds.contains(occurrence.kind), isImplicit == false {
            typeDefinitions.append(located)
        }
        if occurrence.kind == IndexSymbolKind.extension, extensionDefinitions[usr] == nil {
            extensionDefinitions[usr] = located
        }
    }
}
