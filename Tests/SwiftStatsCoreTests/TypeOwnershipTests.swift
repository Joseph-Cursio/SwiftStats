@testable import SwiftStatsCore
import Testing

/// Type ownership, containers, module edges, USR type cycles and family
/// references on the Index fixture's recorded index (M7, design §4.1–§4.4),
/// built straight from `reader.json` and a measured copy of the fixture
/// (`CouplingHarness`). The figures were checked by hand against the
/// fixture's source and agree with the independent checker's check u7.
@Suite("Type ownership and coupling")
struct TypeOwnershipTests {
    /// `Alpha`'s USR.
    private static let alpha = "s:9IndexCore5AlphaV"
    /// `Beta`'s USR.
    private static let beta = "s:9IndexCore4BetaV"
    /// `Ledger`'s USR.
    private static let ledger = "s:9IndexCore6LedgerV"
    /// `Ledger.Index`'s USR.
    private static let ledgerIndex = "s:9IndexCore6LedgerV0A0V"
    /// `Bike`'s USR.
    private static let bike = "s:9IndexCore4BikeC"
    /// The file holding the inheritance clause and the extension adding a
    /// conformance.
    private static let references = "Sources/IndexCore/References.swift"

    /// A package edge of one importing file with `references`.
    private static func edge(_ from: String, _ destination: String, references: Int) -> IndexModuleEdge {
        IndexModuleEdge(fromModule: from, toModule: destination, kind: .package, references: references, files: 1)
    }

    /// A type row's same-module, other-module and test referrers.
    private static func fanIn(_ row: IndexTypeRow) -> [Int] {
        [row.referrersSameModule, row.referrersOtherModules, row.referrersTests]
    }

    @Test("""
        an extension member belongs to the package type its extension extends, a member of an extension of \
        Array to no type, and a nested type's member to the nested type
        """)
    func ownership() throws {
        let harness = try CouplingHarness()
        defer { harness.remove() }
        let ownership = harness.input.ownership
        #expect(ownership.owner(of: try harness.usr(of: "IndexCore::Alpha::func partner() -> Beta")) == Self.alpha)
        #expect(ownership.owner(of: "s:e:s:9IndexCore5AlphaV7partnerAA4BetaVyF") == Self.alpha)
        #expect(ownership.owner(of: "s:e:s:9IndexCore4BikeC11descriptionSSvp") == Self.bike)
        let doubled = try harness.usr(of: "IndexCore::Array where Element == Int::func doubledAll() -> [Int]")
        #expect(ownership.owner(of: doubled) == nil)
        #expect(ownership.owner(of: try harness.usr(of: "IndexCore::Array::func secondItem() -> Element?")) == nil)
        let entry = try harness.usr(of: "IndexCore::Ledger.Index::func entry(in: Ledger) -> Int")
        #expect(ownership.owner(of: entry) == Self.ledgerIndex)
        let index = try harness.usr(of: "IndexCore::Ledger::func index(at: Int) -> Index")
        #expect(ownership.owner(of: index) == Self.ledger)
        #expect(ownership.types.count == 26 && ownership.types.values.count(where: \.isProduction) == 24)
        #expect(ownership.unplaced.isEmpty)
        #expect(ownership.types[Self.ledgerIndex]?.identity == TypeIdentity(
            module: "IndexCore",
            typePath: "Ledger.Index",
            typeFile: ""
        ))
        #expect(ownership.isNested(Self.ledger, Self.ledgerIndex) && ownership.isNested(Self.ledgerIndex, Self.ledger))
        #expect(ownership.isNested(Self.alpha, Self.beta) == false)
    }

    @Test("""
        an inheritance clause's reference is contained by the subtype, an extension head's by the extension, an \
        attribute argument's by its test function, and a top-level call's by the top-level code record
        """)
    func containers() throws {
        let harness = try CouplingHarness()
        defer { harness.remove() }
        let resolver = harness.resolver
        let vehicle = try harness.reference(to: "s:9IndexCore7VehicleC", in: Self.references, at: 13, 26)
        let base = resolver.container(of: vehicle)
        #expect(base.identity == .symbol(Self.bike) && base.owner == Self.bike && base.target == "IndexCore")
        let head = resolver.container(of: try harness.reference(to: Self.bike, in: Self.references, at: 20, 11))
        #expect(head.identity == .symbol("s:e:s:9IndexCore4BikeC11descriptionSSvp") && head.owner == Self.bike)
        let argument = resolver.container(of: try harness.reference(
            to: "s:9IndexCore5casesSaySiGyF",
            in: "Tests/IndexCoreTests/IndexCoreTests.swift",
            at: 45,
            32
        ))
        #expect(argument.recordKey == "IndexCoreTests::IndexCoreTests::func positive(value: Int)")
        #expect(argument.target == "IndexCoreTests")
        let topLevel = resolver.container(of: try harness.reference(
            to: "s:9IndexCore6layoutyS2iF",
            in: "Sources/IndexApp/main.swift",
            at: 7,
            17
        ))
        #expect(topLevel.recordKey == "IndexApp::<top-level code> @ Sources/IndexApp/main.swift")
        #expect(topLevel.owner == nil && topLevel.target == "IndexApp")
    }

    @Test("""
        a reference with no container relation outside every record is contained by the innermost type record \
        holding it, owned by that type, which gives a type edge and a fan-in referrer by owner; outside every \
        type record too, by the file, with no owner, which gives no edge and a fan-in referrer by container
        """)
    func positionalContainers() throws {
        let harness = try CouplingHarness()
        defer { harness.remove() }
        let input = harness.input
        let file = "Sources/IndexCore/Types.swift"
        let reference = { (line: Int, column: Int) in
            OccurrenceFacts.Located(file: file, occurrence: IndexOccurrenceFact(
                line: line,
                column: column,
                roles: IndexSymbolKind.Role.reference,
                usr: Self.alpha,
                name: "Alpha",
                kind: IndexSymbolKind.struct,
                subkind: IndexSymbolKind.Subkind.plain,
                properties: 0,
                relations: []
            ))
        }
        // `var entries: [Int]` in `Ledger`, a stored property: no record
        // holds it; and the blank line between `Alpha` and `Beta`.
        let inLedger = reference(26, 20)
        let between = reference(7, 1)

        let typed = harness.resolver.container(of: inLedger)
        #expect(typed.identity == .type(TypeIdentity(module: "IndexCore", typePath: "Ledger", typeFile: "")))
        #expect(typed.owner == Self.ledger && typed.target == "IndexCore" && typed.name == "Ledger")
        let filed = harness.resolver.container(of: between)
        #expect(filed.identity == .file(file) && filed.owner == nil && filed.target == "IndexCore")

        var occurrences = input.join.filedOccurrences
        occurrences[file, default: []] += [inLedger.occurrence, between.occurrence]
        let facts = OccurrenceFacts(
            occurrences: occurrences,
            targets: input.targetOfFile,
            joinable: Set(harness.fixture.measured.files.map(\.path))
        )
        let graph = ReferenceGraph(ReferenceGraph.Input(
            join: input.join,
            records: input.records,
            facts: facts,
            ownership: input.ownership,
            topLevelLines: input.topLevelLines,
            testModules: input.testModules,
            targetOfFile: input.targetOfFile
        ))
        #expect(harness.graph.typeEdges[Self.ledger]?.contains(Self.alpha) != true)
        #expect(graph.typeEdges[Self.ledger]?.contains(Self.alpha) == true)
        let referrers = graph.typeReferrers[Self.alpha]?.sameModule ?? []
        let before = harness.graph.typeReferrers[Self.alpha]?.sameModule ?? []
        #expect(referrers.subtracting(before) == [.owner(Self.ledger), .container(.file(file))])
    }

    @Test("""
        a package edge counts the references and importing files, a dependency edge to IndexDepKit its files \
        with no references, and nothing names the target itself
        """)
    func moduleEdges() throws {
        let harness = try CouplingHarness()
        defer { harness.remove() }
        #expect(harness.coupling.moduleEdges == [
            Self.edge("IndexApp", "IndexCore", references: 1),
            Self.edge("IndexApp", "index-support", references: 1),
            IndexModuleEdge(
                fromModule: "IndexCore",
                toModule: "IndexDepKit",
                kind: .dependency,
                references: nil,
                files: 1
            ),
            Self.edge("IndexCoreTests", "IndexCore", references: 26),
            Self.edge("IndexCoreTests", "index-kit", references: 2),
            Self.edge("IndexCoreTests", "index-support", references: 2),
            Self.edge("IndexXCTests", "IndexCore", references: 1)
        ])
    }

    @Test("""
        Alpha and Beta form a USR type cycle through a method in Alpha's extension, Ledger and its nested Index \
        reference each other with no edge, and a type's own extension isn't in its fan-in
        """)
    func cycles() throws {
        let harness = try CouplingHarness()
        defer { harness.remove() }
        let edges = harness.graph.typeEdges
        #expect(edges[Self.alpha] == [Self.beta] && edges[Self.beta] == [Self.alpha])
        #expect(edges[Self.ledger] == nil && edges[Self.ledgerIndex] == nil)
        let types = Dictionary(uniqueKeysWithValues: harness.coupling.types.map { ($0.typePath, $0) })
        #expect(types.values.filter { $0.cycle != nil }.map(\.typePath).sorted() == ["Alpha", "Beta"])
        #expect(types["Alpha"]?.cycle == 1 && types["Beta"]?.cycle == 1)
        #expect(types["Vehicle"].map(Self.fanIn) == [1, 0, 0])
        #expect(types["Bike"].map(Self.fanIn) == [0, 0, 0])
        #expect(types["Threshold"].map { [$0.referrersSameModule, $0.referrersTests] } == [1, 1])
        #expect(types["Shape"]?.referrersSameModule == 3)
        #expect(types["Tool"]?.module == "IndexTool")
        #expect(types.count == 24 && types["IndexCoreTests"] == nil)
    }

    @Test("""
        production families reference each other directly or through a requirement, and reference package \
        types or their members; an extension of Array is no package type
        """)
    func familyReferences() throws {
        let harness = try CouplingHarness()
        defer { harness.remove() }
        let coupling = harness.coupling
        #expect(coupling.familyReferences.count == 20)
        #expect(coupling.familyReferences.count { $0.via == .requirement } == 2)
        #expect(coupling.familyReferences.contains(IndexFamilyReference(
            fromFamily: "IndexCore::func currentLevel() -> Int",
            toFamily: "IndexCore::Threshold::var level: Int",
            via: .direct
        )))
        #expect(coupling.familyReferences.contains { $0.fromFamily.hasPrefix("IndexCoreTests::") } == false)
        let typesOf: (String) -> [String] = { family in
            coupling.familyTypeReferences.filter { $0.family == family }.map(\.typePath)
        }
        #expect(coupling.familyTypeReferences.count == 41)
        #expect(typesOf("IndexCore::Storage::subscript(doubled: Int) -> Int") == ["Offset", "Storage"])
        #expect(typesOf("IndexCore::func cycle() -> Int") == ["Alpha", "Beta"])
        #expect(typesOf("IndexCore::Ledger.Index::func entry(in: Ledger) -> Int") == ["Ledger", "Ledger.Index"])
        #expect(typesOf("IndexCore::func arrayUse() -> Int").isEmpty)
        #expect(typesOf("IndexCore::func layout(_: Int) -> Int") == ["Square"])
    }
}
