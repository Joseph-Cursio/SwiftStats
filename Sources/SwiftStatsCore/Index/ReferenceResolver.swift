//
//  ReferenceResolver.swift
//  SwiftStatsCore
//
//  Where a reference comes from and which records it counts for (M7,
//  design §4.1). Its container, the first that applies: the symbol of its
//  `calledBy` relation, else of its `containedBy` relation, else of its
//  `baseOf` or `extendedBy` relation (an inheritance clause or an
//  extension's head); a local variable that isn't a record is followed up
//  its `childOf` chain to the declaration enclosing it, since with locals
//  indexed a reference in `let x = …` names `x`. A symbol that is a record
//  (by primary or secondary USR) is that record; any other is kept as a
//  symbol in the referencing file's target. With no such relation, by
//  position: the file's top-level code record when the reference lies on
//  one of its statement lines, else the innermost record holding it, else
//  the innermost type record, else the file. The records a reference to a
//  USR counts for: the record holding the USR as its primary or secondary
//  USR; a property's accessor records by role (a read for reading
//  accessors, a write for writing ones, neither for all); and for a
//  requirement of a protocol the package declares, the same for every
//  symbol witnessing it. A record witnesses when its USR, its secondary
//  USR or its property's is the symbol of an occurrence with an
//  `overrideOf` relation.
//

/// Finds a reference's container and the records it counts for.
struct ReferenceResolver {
    /// A record a reference counts for, and how it reaches it.
    struct Target: Hashable {
        /// The record's key.
        let key: String
        /// How the reference reaches it.
        let via: IndexFamilyReference.Via
    }

    /// What the graph reads.
    let input: ReferenceGraph.Input
    /// The record holding each USR as its primary, else secondary, USR.
    private let recordByUSR: [String: String]
    /// Each property's accessor records with their accessor kinds, by the
    /// property's USR, in record order.
    private let accessorsOf: [String: [(key: String, accessor: String)]]
    /// Each accessor record's property USR, by key.
    private let propertyOf: [String: String]
    /// The overridden USRs that are requirements of package protocols.
    private let requirements: Set<String>
    /// Each file's records.
    private let recordsByFile: [String: [FunctionRecord]]
    /// Each record, by key.
    let recordsByKey: [String: FunctionRecord]

    /// A resolver over `input`.
    init(_ input: ReferenceGraph.Input) {
        self.input = input
        let join = input.join
        var holders: [String: String] = [:]
        for (key, usr) in join.primary {
            holders[usr] = key
        }
        for (key, usr) in join.secondary where holders[usr] == nil {
            holders[usr] = key
        }
        recordByUSR = holders
        var accessors: [String: [(key: String, accessor: String)]] = [:]
        var properties: [String: String] = [:]
        for record in input.records where record.kind == .accessor {
            guard let definition = join.primaryDefinitions[record.key] else {
                continue
            }
            for relation in definition.occurrence.relations
            where relation.roles & IndexSymbolKind.RelationRole.accessorOf != 0 {
                accessors[relation.usr, default: []].append((record.key, record.accessorKind ?? "get"))
                if properties[record.key] == nil {
                    properties[record.key] = relation.usr
                }
            }
        }
        accessorsOf = accessors
        propertyOf = properties
        requirements = Set(input.facts.overriding.keys.filter { usr in
            input.facts.childOf[usr]?.kind == IndexSymbolKind.protocol
        })
        recordsByFile = Dictionary(grouping: input.records, by: \.file)
        recordsByKey = Dictionary(input.records.map { ($0.key, $0) }) { _, last in last }
    }

    /// Whether each record with a primary USR is a witness, by key.
    func witnesses() -> [String: Bool] {
        let join = input.join
        var witnesses: [String: Bool] = [:]
        for record in input.records {
            guard let usr = join.primary[record.key] else {
                continue
            }
            let usrs = [usr, join.secondary[record.key], propertyOf[record.key]].compactMap(\.self)
            witnesses[record.key] = usrs.contains(where: input.facts.overridingSymbols.contains)
        }
        return witnesses
    }

    /// The records a reference to `usr` with `roles` counts for.
    func targets(of usr: String, roles: UInt64) -> Set<Target> {
        var targets: Set<Target> = []
        add(usr, via: .direct, roles: roles, to: &targets)
        if requirements.contains(usr) {
            for witness in input.facts.overriding[usr, default: []].sorted(by: CodePointOrder.precedes) {
                add(witness, via: .requirement, roles: roles, to: &targets)
            }
        }
        return targets
    }

    /// The container of the reference `located`.
    func container(of located: OccurrenceFacts.Located) -> ReferenceContainer {
        let occurrence = located.occurrence
        let relations = occurrence.relations
        let named = relations.first { $0.roles & IndexSymbolKind.RelationRole.calledBy != 0 }
            ?? relations.first { $0.roles & IndexSymbolKind.RelationRole.containedBy != 0 }
            ?? relations.first { relation in
                relation.roles & (IndexSymbolKind.RelationRole.baseOf | IndexSymbolKind.RelationRole.extendedBy) != 0
            }
        let fileTarget = input.targetOfFile[located.file]
        if let named {
            let symbol = enclosing(named)
            if let key = recordByUSR[symbol.usr] {
                return recordContainer(key)
            }
            return ReferenceContainer(
                identity: .symbol(symbol.usr),
                name: symbol.name,
                target: fileTarget,
                owner: input.ownership.owner(of: symbol.usr)
            )
        }
        return positionalContainer(
            in: located.file,
            at: SourcePosition(line: occurrence.line, column: occurrence.column),
            target: fileTarget
        )
    }

    /// The container `key` names, a record: its key, target and owning
    /// type (its USR's, else the type record holding its start).
    func recordContainer(_ key: String) -> ReferenceContainer {
        let record = recordsByKey[key]
        let owner: String?
        if let usr = input.join.primary[key] {
            owner = input.ownership.owner(of: usr)
        } else if let record, let index = input.ownership.innermostRecord(in: record.file, at: record.range.start) {
            owner = input.ownership.owner(ofRecord: index)
        } else {
            owner = nil
        }
        return ReferenceContainer(identity: .record(key), name: key, target: record?.module, owner: owner)
    }

    /// `relation`'s symbol, or, for a local symbol that isn't a record, the
    /// first declaration up its `childOf` chain that is a record or isn't
    /// local.
    private func enclosing(_ relation: IndexOccurrenceFact.Relation) -> (usr: String, name: String) {
        var (usr, name, properties) = (relation.usr, relation.name, relation.properties)
        var walked: Set<String> = []
        while recordByUSR[usr] == nil, properties & IndexSymbolKind.Property.local != 0, walked.insert(usr).inserted {
            guard let parent = input.facts.childOf[usr] else {
                break
            }
            (usr, name, properties) = (parent.usr, parent.name, parent.properties)
        }
        return (usr, name)
    }

    /// The container of a reference at `position` in `file` (of `target`)
    /// that names none: the top-level code record on whose statement lines
    /// it lies, else the innermost record holding it, else the innermost
    /// type record, else the file.
    private func positionalContainer(
        in file: String,
        at position: SourcePosition,
        target: String?
    ) -> ReferenceContainer {
        let statements = input.topLevelLines[file] ?? []
        let holding = recordsByFile[file, default: []].filter { record in
            record.range.contains(position)
                && (record.kind != .topLevelCode || statements.contains(position.line))
        }
        let topLevel = holding.filter { $0.kind == .topLevelCode }
        if let record = USRJoin.innermost(of: topLevel, holding: position) ?? USRJoin.innermost(
            of: holding,
            holding: position
        ) {
            return recordContainer(record.key)
        }
        if let index = input.ownership.innermostRecord(in: file, at: position) {
            return ReferenceContainer(
                identity: .type(input.ownership.identity(ofRecord: index)),
                name: input.ownership.records[index].name,
                target: target,
                owner: input.ownership.owner(ofRecord: index)
            )
        }
        return ReferenceContainer(identity: .file(file), name: file, target: target, owner: nil)
    }

    /// Adds to `targets` what a reference to `symbol` with `roles` reaches
    /// `via`: the record holding it, and its accessor records by role.
    private func add(_ symbol: String, via: IndexFamilyReference.Via, roles: UInt64, to targets: inout Set<Target>) {
        if let key = recordByUSR[symbol] {
            targets.insert(Target(key: key, via: via))
        }
        let reads = roles & IndexSymbolKind.Role.read != 0
        let writes = roles & IndexSymbolKind.Role.write != 0
        for (key, accessor) in accessorsOf[symbol, default: []]
        where (reads == false && writes == false)
            || (reads && ReferenceGraph.readingAccessors.contains(accessor))
            || (writes && ReferenceGraph.writingAccessors.contains(accessor)) {
            targets.insert(Target(key: key, via: via))
        }
    }
}
