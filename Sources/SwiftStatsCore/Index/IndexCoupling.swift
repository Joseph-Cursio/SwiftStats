//
//  IndexCoupling.swift
//  SwiftStatsCore
//
//  The index side of coupling for one scan (M7, design §4, D5): the
//  occurrence facts, the package's types and owners (`TypeOwnership`), the
//  counted references (`ReferenceGraph`), the module edges
//  (`ModuleEdges`) and the USR type cycles (`TypeCycles`), assembled as
//  the scan JSON's `index` block writes them: each record's witness flag
//  and referrers (records with a primary USR only), the edges, the
//  production types with their fan-in and cycle number, and the family
//  references, each list in a fixed order; and the facts the dead-code
//  mapping reads from the same join and ownership (`DeadCodeIndex`).
//

/// The coupling the T1 build's index gives a scan.
struct IndexCoupling {
    /// How many test referrer names a record keeps.
    static let testReferrersKept = 5

    /// Each record's witness flag and referrers, by key; records without a
    /// primary USR are absent.
    let records: [String: IndexRecordCoupling]
    /// The module edges, by source, then destination.
    let moduleEdges: [IndexModuleEdge]
    /// The production types, by identity, then USR.
    let types: [IndexTypeRow]
    /// The production families' references to each other, by source,
    /// destination, then how.
    let familyReferences: [IndexFamilyReference]
    /// The production families' references to package types, by family,
    /// then type.
    let familyTypeReferences: [IndexFamilyTypeReference]
    /// What the dead-code mapping reads from the index: the records by
    /// USR, the properties' accessor records and the types' ownership.
    let deadCode: DeadCodeIndex

    /// The coupling of `snapshot` for `scan`, its records joined by
    /// `join`, references and types read only from `joinable` files
    /// (scanned, unchanged), the package's targets named `packageTargets`.
    init(
        snapshot: IndexSnapshot,
        join: USRJoin,
        scan: IndexAdapter.Scan,
        joinable: Set<String>,
        packageTargets: Set<String>
    ) {
        let input = Self.input(snapshot: snapshot, join: join, scan: scan, joinable: joinable)
        let graph = ReferenceGraph(input)
        deadCode = DeadCodeIndex(join: join, records: scan.records, ownership: input.ownership)
        records = Self.records(graph, join: join)
        moduleEdges = ModuleEdges.edges(
            of: snapshot,
            facts: input.facts,
            targets: input.targetOfFile,
            packageTargets: packageTargets
        )
        types = Self.types(graph, ownership: input.ownership)
        familyReferences = graph.familyReferences.sorted { lhs, rhs in
            CodePointOrder.precedes(
                [lhs.fromFamily, lhs.toFamily, lhs.via.rawValue],
                [rhs.fromFamily, rhs.toFamily, rhs.via.rawValue]
            )
        }
        familyTypeReferences = graph.familyTypeReferences.sorted { lhs, rhs in
            CodePointOrder.precedes(
                [lhs.family, lhs.module, lhs.typePath, lhs.typeFile ?? ""],
                [rhs.family, rhs.module, rhs.typePath, rhs.typeFile ?? ""]
            )
        }
    }

    /// What the reference graph reads for `scan` from `snapshot`, its
    /// records joined by `join` (built from the same snapshot, whose filed
    /// occurrences it keeps): each read unit's main file's target (the
    /// first unit's, by name), the occurrence facts, and the types and
    /// owners, references and types read only from `joinable` files.
    static func input(
        snapshot: IndexSnapshot,
        join: USRJoin,
        scan: IndexAdapter.Scan,
        joinable: Set<String>
    ) -> ReferenceGraph.Input {
        var targetOfFile: [String: String] = [:]
        for unit in snapshot.readUnits where unit.isPackageModule && targetOfFile[unit.path] == nil {
            targetOfFile[unit.path] = unit.module
        }
        let testModules = Set(scan.targets.filter(\.isTest).map(\.name))
        let facts = OccurrenceFacts(
            occurrences: join.filedOccurrences,
            targets: targetOfFile,
            joinable: joinable
        )
        let ownership = TypeOwnership(
            facts: facts,
            records: scan.types,
            fileScopedTypes: scan.fileScopedTypes,
            testModules: testModules,
            joinable: joinable
        )
        return ReferenceGraph.Input(
            join: join,
            records: scan.records,
            facts: facts,
            ownership: ownership,
            topLevelLines: scan.topLevelLines,
            testModules: testModules,
            targetOfFile: targetOfFile
        )
    }

    /// Each record with a primary USR's witness flag and referrers in
    /// `graph`, by key.
    private static func records(_ graph: ReferenceGraph, join: USRJoin) -> [String: IndexRecordCoupling] {
        var coupled: [String: IndexRecordCoupling] = [:]
        for key in join.primary.keys {
            let referrers = graph.referrers[key] ?? .init()
            let names = (graph.testNames[key] ?? [:]).values.sorted(by: CodePointOrder.precedes)
            coupled[key] = IndexRecordCoupling(
                witness: graph.witness[key] ?? false,
                references: IndexReferences(
                    sameModule: referrers.sameModule.count,
                    otherModules: referrers.otherModules.count,
                    tests: referrers.tests.count,
                    testReferrers: Array(names.prefix(testReferrersKept))
                )
            )
        }
        return coupled
    }

    /// The production types of `ownership` with their fan-in in `graph`
    /// and their cycle numbers, by identity, then USR.
    private static func types(_ graph: ReferenceGraph, ownership: TypeOwnership) -> [IndexTypeRow] {
        let production = ownership.types.values.filter(\.isProduction)
        let cycles = TypeCycles(nodes: production.map(\.usr), edges: graph.typeEdges) { usr in
            ownership.types[usr]?.identity ?? TypeIdentity.unknown
        }
        return production
            .sorted { CodePointOrder.precedes($0.identity.parts + [$0.usr], $1.identity.parts + [$1.usr]) }
            .map { type in
                let referrers = graph.typeReferrers[type.usr] ?? .init()
                return IndexTypeRow(
                    module: type.identity.module,
                    typePath: type.identity.typePath,
                    typeFile: type.identity.writtenFile,
                    usr: type.usr,
                    referrersSameModule: referrers.sameModule.count,
                    referrersOtherModules: referrers.otherModules.count,
                    referrersTests: referrers.tests.count,
                    cycle: cycles.numbers[type.usr]
                )
            }
    }
}
