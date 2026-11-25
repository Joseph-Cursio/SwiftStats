//
//  ReferenceCounting.swift
//  SwiftStatsCore
//
//  The counting pass of `ReferenceGraph` (M7, design §4.1, §4.3, §4.4):
//  one reference at a time, its container found and the records it counts
//  for, the family exclusion applied, each record's referrers, test
//  referrer names and family references gathered, then the reference's
//  package type (the referenced type, or the referenced member's owner)
//  for its fan-in, a family's type reference and the edges between
//  production types. Families are `FunctionFamily`'s, named by their ids;
//  a production family is one whose every member is production code.
//

/// Gathers the counts of `ReferenceGraph`, one reference at a time.
struct ReferenceCounting {
    /// Finds containers and targets.
    let resolver: ReferenceResolver
    /// Each record's family id, by key.
    private let familyOf: [String: String]
    /// Whether each family is a production family, by id.
    private let isProductionFamily: [String: Bool]
    /// Each record with a counted reference's referrers, by key.
    private(set) var referrers: [String: ReferenceGraph.Referrers<ReferenceContainer.Identity>] = [:]
    /// Each record's test containers' names, by key.
    private(set) var testNames: [String: [ReferenceContainer.Identity: String]] = [:]
    /// The production families' references to each other.
    private(set) var familyReferences: Set<IndexFamilyReference> = []
    /// The production families' references to package types.
    private(set) var familyTypeReferences: Set<IndexFamilyTypeReference> = []
    /// Each production type's referrers, by USR.
    private(set) var typeReferrers: [String: ReferenceGraph.Referrers<ReferenceGraph.TypeReferrer>] = [:]
    /// The edges between production types, by the referring type's USR.
    private(set) var typeEdges: [String: Set<String>] = [:]

    /// A pass over `input`'s references.
    init(_ input: ReferenceGraph.Input) {
        resolver = ReferenceResolver(input)
        var families: [String: String] = [:]
        for family in FunctionFamily.families(input.records.map { FunctionRow($0, snapshotId: 0) }) {
            for member in family.members where families[member.key] == nil {
                families[member.key] = family.id
            }
        }
        var production: [String: Bool] = [:]
        for record in input.records {
            let family = families[record.key] ?? record.key
            production[family] = (production[family] ?? true) && record.role == .production
        }
        familyOf = families
        isProductionFamily = production
    }

    /// Counts the reference `located`.
    mutating func count(_ located: OccurrenceFacts.Located) {
        let usr = located.occurrence.usr
        let container = resolver.container(of: located)
        let isTest = container.target.map(resolver.input.testModules.contains) ?? false
        let sourceFamily = container.recordKey.map(family(of:))
        for target in resolver.targets(of: usr, roles: located.occurrence.roles) {
            let destination = family(of: target.key)
            guard sourceFamily != destination else {
                continue
            }
            let module = resolver.recordsByKey[target.key]?.module
            if isTest {
                referrers[target.key, default: .init()].tests.insert(container.identity)
                testNames[target.key, default: [:]][container.identity] = container.name
            } else if container.target == module {
                referrers[target.key, default: .init()].sameModule.insert(container.identity)
            } else {
                referrers[target.key, default: .init()].otherModules.insert(container.identity)
            }
            if let sourceFamily, isProduction(sourceFamily), isProduction(destination) {
                familyReferences.insert(
                    IndexFamilyReference(fromFamily: sourceFamily, toFamily: destination, via: target.via)
                )
            }
        }
        countType(usr, container: container, isTest: isTest, sourceFamily: sourceFamily)
    }

    /// Counts a reference to `usr` from `container` (in a test target when
    /// `isTest`, of `sourceFamily` when a record) against the package type
    /// it names or whose member it names.
    private mutating func countType(
        _ usr: String,
        container: ReferenceContainer,
        isTest: Bool,
        sourceFamily: String?
    ) {
        let ownership = resolver.input.ownership
        guard let referenced = ownership.types[usr] != nil ? usr : ownership.owner(of: usr),
              let type = ownership.types[referenced] else {
            return
        }
        if let sourceFamily, isProduction(sourceFamily) {
            familyTypeReferences.insert(IndexFamilyTypeReference(
                family: sourceFamily,
                module: type.identity.module,
                typePath: type.identity.typePath,
                typeFile: type.identity.writtenFile
            ))
        }
        if type.isProduction {
            if isTest {
                typeReferrers[referenced, default: .init()].tests.insert(.container(container.identity))
            } else if container.owner != referenced {
                let referrer: ReferenceGraph.TypeReferrer = container.owner.map { .owner($0) }
                    ?? .container(container.identity)
                if container.target == type.module {
                    typeReferrers[referenced, default: .init()].sameModule.insert(referrer)
                } else {
                    typeReferrers[referenced, default: .init()].otherModules.insert(referrer)
                }
            }
        }
        if let owner = container.owner, owner != referenced, isTest == false,
           ownership.types[owner]?.isProduction == true, type.isProduction,
           ownership.isNested(owner, referenced) == false {
            typeEdges[owner, default: []].insert(referenced)
        }
    }

    /// The family id of the record `key`.
    private func family(of key: String) -> String {
        familyOf[key] ?? key
    }

    /// Whether the family `family` is a production family.
    private func isProduction(_ family: String) -> Bool {
        isProductionFamily[family] ?? false
    }
}
