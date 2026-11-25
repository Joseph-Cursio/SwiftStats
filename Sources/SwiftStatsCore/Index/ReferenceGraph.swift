//
//  ReferenceGraph.swift
//  SwiftStatsCore
//
//  The references in the T1 build's index, counted (M7, design §4.1,
//  §4.3, §4.4). A reference is a distinct occurrence with the `reference`
//  role, implicit ones included, in a scanned file that didn't change. Its
//  container is found as `ReferenceResolver.container(of:)` says, and the
//  records it counts for as `ReferenceResolver.targets(of:roles:)` says. A reference doesn't count
//  for a record of its container record's own family. Each record's
//  referrers are its distinct counting containers, split by the
//  container's target; a family references another when a record of one
//  counts for a record of the other, both production families, directly
//  or through a requirement. Every reference to a package type or a member
//  of it (owning type by `TypeOwnership`) adds the container to the type's
//  fan-in (a test container, or the container's owning type, else the
//  container itself, the type's own members left out), a type reference
//  from a production family, and an edge from the container's owning
//  production type, unless the two are nested.
//

/// The references of a snapshot, counted per record, family and type.
struct ReferenceGraph {
    /// What the graph reads.
    struct Input {
        /// The USR join, for each record's USRs and definitions.
        let join: USRJoin
        /// The scan's records.
        let records: [FunctionRecord]
        /// The snapshot's occurrence facts.
        let facts: OccurrenceFacts
        /// The package's types and owners.
        let ownership: TypeOwnership
        /// Each file's top-level statement lines, by path.
        let topLevelLines: [String: Set<Int>]
        /// The test targets.
        let testModules: Set<String>
        /// Each read unit's main file's target, by path.
        let targetOfFile: [String: String]
    }

    /// Distinct containers counting for a record or a type, by the
    /// container's target.
    struct Referrers<Member: Hashable> {
        /// In the record's or type's own target.
        var sameModule: Set<Member> = []
        /// In other production targets.
        var otherModules: Set<Member> = []
        /// In test targets.
        var tests: Set<Member> = []
    }

    /// What tells a type's referrers apart: the owning type of a container
    /// that has one, else the container.
    enum TypeReferrer: Hashable {
        /// A container's owning type, by USR.
        case owner(String)
        /// A container with no owning type.
        case container(ReferenceContainer.Identity)
    }

    /// The rule, as the `index` collector's `references:` option states it.
    static let rule = "distinct containers (calledBy or containedBy, a local variable followed to the declaration "
        + "enclosing it; else baseOf or extendedBy; else by position: top-level statement lines, innermost record, "
        + "type, file) of non-family references, implicit included; a property's read references count for its "
        + "reading accessors and write references for its writing ones; a requirement of a package-declared protocol "
        + "counts its references for its witnesses (any occurrence with overrideOf); split by the container's "
        + "target: same production target, other production targets, test targets"

    /// The accessor kinds a reference with the `read` role counts for.
    static let readingAccessors: Set<String> = ["get", "_read", "read", "unsafeAddress"]
    /// The accessor kinds a reference with the `write` role counts for.
    static let writingAccessors: Set<String> = [
        "set", "_modify", "modify", "unsafeMutableAddress", "willSet", "didSet"
    ]

    /// Each record with a counted reference's referrers, by key.
    let referrers: [String: Referrers<ReferenceContainer.Identity>]
    /// Each record's test containers' names, by key.
    let testNames: [String: [ReferenceContainer.Identity: String]]
    /// Whether each record with a primary USR is a witness, by key.
    let witness: [String: Bool]
    /// The production families' references to each other.
    let familyReferences: Set<IndexFamilyReference>
    /// The production families' references to package types.
    let familyTypeReferences: Set<IndexFamilyTypeReference>
    /// Each production type's referrers, by USR.
    let typeReferrers: [String: Referrers<TypeReferrer>]
    /// The edges between production types, by the referring type's USR.
    let typeEdges: [String: Set<String>]

    /// The counts `input` gives.
    init(_ input: Input) {
        var counting = ReferenceCounting(input)
        for located in input.facts.references {
            counting.count(located)
        }
        referrers = counting.referrers
        testNames = counting.testNames
        familyReferences = counting.familyReferences
        familyTypeReferences = counting.familyTypeReferences
        typeReferrers = counting.typeReferrers
        typeEdges = counting.typeEdges
        witness = counting.resolver.witnesses()
    }
}
