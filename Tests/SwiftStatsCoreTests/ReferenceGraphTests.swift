import Foundation
@testable import SwiftStatsCore
import Testing

/// The reference graph on the Index fixture's recorded index (M7, design
/// §4.1, §4.4): a copy scanned with `--index` against its recorded build,
/// the `index` collector reading `reader.json`, some tests with an
/// occurrence edited or added. Each case's figures were checked by hand
/// against the fixture's source and agree with the independent checker's
/// (`index-check.py usr`, check u7, with `--local-containers enclosing
/// --requirements package`). Serialized, each scan on a thread of its own.
@Suite("Reference graph", .serialized)
struct ReferenceGraphTests {
    /// The test that calls what only tests call.
    private static let onlyTests = "IndexCoreTests::IndexCoreTests::func onlyTests()"
    /// The test that writes `Threshold.level`.
    private static let writesLevel = "IndexCoreTests::IndexCoreTests::func writesLevel()"
    /// `Threshold.level`'s getter.
    private static let levelGetter = "IndexCore::Threshold::var level: Int { get }"
    /// `Threshold.level`'s setter.
    private static let levelSetter = "IndexCore::Threshold::var level: Int { set }"
    /// `layout(_:)`, called from `IndexApp`'s top-level code and two tests.
    private static let layout = "IndexCore::func layout(_: Int) -> Int"
    /// `layout(_:)`'s USR.
    private static let layoutUSR = "s:9IndexCore6layoutyS2iF"

    /// Each record's coupling in `index`, by key.
    private static func coupling(_ index: IndexReport) -> [String: IndexRecordCoupling] {
        Dictionary(uniqueKeysWithValues: index.records.compactMap { record in
            record.coupling.map { (record.key, $0) }
        })
    }

    /// Referrers with no test referrer names.
    private static func production(same: Int, other: Int) -> IndexReferences {
        IndexReferences(sameModule: same, otherModules: other, tests: 0, testReferrers: [])
    }

    /// Referrers in tests only, named `names`.
    private static func tested(by names: [String]) -> IndexReferences {
        IndexReferences(sameModule: 0, otherModules: 0, tests: names.count, testReferrers: names)
    }

    @Test("""
        a function only a test calls has that test as its one referrer, in a test target, and nothing else; a \
        public function and another target's function are counted alike
        """)
    func onlyTestsCall() async throws {
        try await IndexFixtureScan().run { _, outcome in
            let coupling = Self.coupling(try #require(outcome.report.index))
            for key in [
                "IndexCore::func onlyTestsCall() -> Int", "IndexCore::func publicOnlyTests() -> Int",
                "index-kit::func kitOnlyTests() -> Int", "index-support::func parseLine(_: String) -> [String]"
            ] {
                let expected = IndexRecordCoupling(witness: false, references: Self.tested(by: [Self.onlyTests]))
                #expect(coupling[key] == expected, "\(key)")
            }
            #expect(coupling["IndexCore::func neverCalled() -> Int"]?.references == Self.production(same: 0, other: 0))
        }
    }

    @Test("""
        a production read of a computed property counts for its getter alone and a test's write for its setter \
        alone, and a reference with neither role counts for both
        """)
    func roleRouting() async throws {
        try await IndexFixtureScan().run { _, outcome in
            let coupling = Self.coupling(try #require(outcome.report.index))
            #expect(coupling[Self.levelGetter]?.references == Self.production(same: 1, other: 0))
            #expect(coupling[Self.levelSetter]?.references == Self.tested(by: [Self.writesLevel]))
        }
        var roleless = try IndexFixtureScan()
        roleless.source = { recorded in
            recorded.changingOccurrences(inFile: "Tests/IndexCoreTests/IndexCoreTests.swift", adding: []) { held in
                let isWrite = held.line == 19 && held.usr == "s:9IndexCore9ThresholdV5levelSivp"
                return isWrite ? held.removing(IndexSymbolKind.Role.write) : held
            }
        }
        try await roleless.run { _, outcome in
            let coupling = Self.coupling(try #require(outcome.report.index))
            #expect(coupling[Self.levelGetter]?.references == IndexReferences(
                sameModule: 1,
                otherModules: 0,
                tests: 1,
                testReferrers: [Self.writesLevel]
            ))
            #expect(coupling[Self.levelSetter]?.references == Self.tested(by: [Self.writesLevel]))
        }
    }

    @Test("""
        a call through a package protocol's requirement counts for its witness and for the default \
        implementation in a protocol extension, both witnesses, as requirement family references
        """)
    func requirements() async throws {
        try await IndexFixtureScan().run { _, outcome in
            let index = try #require(outcome.report.index)
            let coupling = Self.coupling(index)
            let reached = IndexRecordCoupling(witness: true, references: Self.production(same: 1, other: 0))
            #expect(coupling["IndexCore::Tile::func area() -> Int"] == reached)
            #expect(coupling["IndexCore::Greeter::func greet() -> String"] == reached)
            #expect(index.familyReferences.filter { $0.via == .requirement } == [
                IndexFamilyReference(
                    fromFamily: "IndexCore::func totalArea(_: [any Shape]) -> Int",
                    toFamily: "IndexCore::Tile::func area() -> Int",
                    via: .requirement
                ),
                IndexFamilyReference(
                    fromFamily: "IndexCore::func welcome() -> String",
                    toFamily: "IndexCore::Greeter::func greet() -> String",
                    via: .requirement
                )
            ])
            for key in [
                "IndexCore::Bike::func wheels() -> Int", "IndexCore::Bike::var description: String { get }",
                "IndexCore::Ring::subscript(_: Int) -> Int"
            ] {
                #expect(coupling[key]?.witness == true, "\(key)")
            }
            #expect(coupling["IndexCore::Vehicle::func wheels() -> Int"]?.witness == false)
        }
    }

    @Test("""
        a standard-library requirement such as Equatable's == doesn't reach the package's witnesses: comparing \
        two Pairs is no reference to Version's ==
        """)
    func standardRequirements() async throws {
        try await IndexFixtureScan().run { _, outcome in
            let index = try #require(outcome.report.index)
            let equals = "IndexCore::Version::static func ==(lhs: Version, rhs: Version) -> Bool"
            #expect(Self.coupling(index)[equals] == IndexRecordCoupling(
                witness: true,
                references: Self.production(same: 0, other: 0)
            ))
            #expect(index.familyReferences.contains { $0.toFamily == equals } == false)
            #expect(index.familyTypeReferences.contains(IndexFamilyTypeReference(
                family: "index-support::func samePair() -> Bool",
                module: "index-support",
                typePath: "Pair",
                typeFile: nil
            )))
        }
    }

    @Test("""
        a reference from the referenced record's own family doesn't count: a parent's calls of its nested \
        function and local type, a recursive call, and a nested function calling its parent
        """)
    func ownFamily() async throws {
        let nested = [
            "IndexCore::func layout(_: Int) -> Int / func padded(_: Int) -> Int",
            "IndexCore::func layout(_: Int) -> Int / Square::func area() -> Int"
        ]
        var edited = try IndexFixtureScan()
        edited.source = { recorded in
            let recursion = IndexOccurrenceFact.call(
                of: "s:9IndexCore13onlyTestsCallSiyF",
                named: "onlyTestsCall()",
                at: SourcePosition(line: 9, column: 5),
                from: .caller("s:9IndexCore13onlyTestsCallSiyF", named: "onlyTestsCall()", isLocal: false)
            )
            let parent = IndexOccurrenceFact.call(
                of: Self.layoutUSR,
                named: "layout(_:)",
                at: SourcePosition(line: 4, column: 9),
                from: .caller("s:9IndexCore6layoutyS2iF6paddedL_yS2iF", named: "padded(_:)", isLocal: true)
            )
            return recorded
                .changingOccurrences(inFile: "Sources/IndexCore/TestOnly.swift", adding: [recursion], \.self)
                .changingOccurrences(inFile: "Sources/IndexCore/Locals.swift", adding: [parent], \.self)
        }
        for scan in [try IndexFixtureScan(), edited] {
            try await scan.run { _, outcome in
                let coupling = Self.coupling(try #require(outcome.report.index))
                for key in nested {
                    #expect(coupling[key]?.references == Self.production(same: 0, other: 0), "\(key)")
                }
                let onlyTestsCall = coupling["IndexCore::func onlyTestsCall() -> Int"]
                #expect(onlyTestsCall?.references == Self.tested(by: [Self.onlyTests]))
                #expect(coupling[Self.layout]?.references == IndexReferences(
                    sameModule: 0,
                    otherModules: 1,
                    tests: 2,
                    testReferrers: [
                        "IndexCoreTests::IndexCoreTests::func needlessTry()",
                        "IndexXCTests::LayoutXCTests::func testLayout()"
                    ]
                ))
            }
        }
    }

    @Test("""
        top-level code is a referrer in its own target, an attribute argument's reference is contained by its \
        test function, and a reference in a local variable's initializer counts for the declaration enclosing it
        """)
    func positionsAndLocals() async throws {
        try await IndexFixtureScan().run { _, outcome in
            let index = try #require(outcome.report.index)
            let coupling = Self.coupling(index)
            #expect(index.familyReferences.contains(IndexFamilyReference(
                fromFamily: "IndexApp::<top-level code> @ Sources/IndexApp/main.swift",
                toFamily: Self.layout,
                via: .direct
            )))
            let banner = coupling["index-support::func banner() -> String"]
            #expect(banner?.references == Self.production(same: 0, other: 1))
            #expect(coupling["IndexCore::func cases() -> [Int]"]?.references == Self.tested(by: [
                "$s14IndexCoreTestsAAV8positive4TestfMp_25generatorad84a4ae6813c52ffMu_()",
                "IndexCoreTests::IndexCoreTests::func positive(value: Int)"
            ]))
            let nonOptional = "IndexCoreTests::IndexCoreTests::func nonOptional()"
            let count = coupling["IndexCore::Storage::var count: Int { get }"]
            #expect(count?.references == Self.tested(by: [nonOptional]))
            #expect(index.types.first { $0.typePath == "Storage" }?.referrersTests == 1)
        }
    }

    @Test("""
        a record without a primary USR has no witness flag and no referrers, and the JSON leaves both out; a \
        record with one round-trips
        """)
    func withoutUSR() async throws {
        try await IndexFixtureScan().run { _, outcome in
            let index = try #require(outcome.report.index)
            let without = index.records.filter { $0.usr == nil }
            #expect(without.count == 3 && without.allSatisfy { $0.coupling == nil })
            #expect(index.records.filter { $0.usr != nil }.allSatisfy { $0.coupling != nil })
            let encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys
            let written = try #require(String(bytes: try encoder.encode(without[0]), encoding: .utf8))
            #expect(written.contains("witness") == false && written.contains("references") == false)
            let decoded = try JSONDecoder().decode([IndexRecordUSR].self, from: try encoder.encode(index.records))
            #expect(decoded == index.records)
            let referrers = #"{"sameModule": 0, "otherModules": 0, "tests": 0, "testReferrers": []}"#
            let broken = Data(#"{"key": "k", "usr": "s:k", "references": \#(referrers)}"#.utf8)
            #expect(throws: DecodingError.self) {
                try JSONDecoder().decode(IndexRecordUSR.self, from: broken)
            }
        }
    }

    @Test("""
        every roll-up scope counts the USR type cycles with a member in it, its types in cycles and the module \
        edges starting in it, as the index collector's metrics; the options state the two rules
        """)
    func rollups() async throws {
        try await IndexFixtureScan().run { _, outcome in
            let rollups = outcome.report.rollups
            let counts = Dictionary(uniqueKeysWithValues: rollups.compactMap { rollup in
                rollup.index.map { index in
                    let scope = "\(rollup.scope.rawValue) \(rollup.name)"
                    return (scope, [index.typeCycles, index.typesInCycles, index.moduleEdges])
                }
            })
            #expect(counts == [
                "module IndexApp": [0, 0, 2], "module IndexCore": [1, 2, 1], "module IndexCoreTests": [0, 0, 3],
                "module IndexTool": [0, 0, 0], "module IndexXCTests": [0, 0, 1], "module index-kit": [0, 0, 0],
                "module index-support": [0, 0, 0], "project production": [1, 2, 3], "project tests": [0, 0, 4]
            ])
            let metrics = try rollups.flatMap(RollupMetrics.metrics(of:))
                .filter { ["index.typeCycles", "index.typesInCycles", "index.moduleEdges"].contains($0.path) }
            #expect(metrics.count == 27 && metrics.allSatisfy { $0.collector == "index" })
            #expect(IndexAdapter.options.suffix(2) == [
                "references: " + ReferenceGraph.rule, "types: " + TypeOwnership.rule
            ])
        }
    }
}
