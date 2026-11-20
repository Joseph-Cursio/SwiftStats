import Foundation
@testable import SwiftStatsCore
import Testing

/// SwiftInferProperties' suggestions attached to records (PRD §7.11): each
/// kind of row the index holds, the roll-ups that count them, the report
/// section that lists the unmapped ones, and the merge on its own.
@Suite("Property candidates")
struct PropertyCandidateTests {
    private typealias Row = PropertyHarness.Row

    /// The library's file, as the tool writes it.
    private static let values = "@ROOT@/Sources/Core/Values.swift"

    /// Rows that attach to a function: a plain one, a blocked one, a
    /// computed property, a pair and a test site.
    private static let attached = [
        Row(identity: "0x00000000000000A1", location: "\(values):4"),
        Row(
            identity: "0x00000000000000A2",
            location: "\(values):20",
            template: "predicate",
            function: "secret(_:)",
            tier: "Advisory",
            blocker: "\"no test can name the subject: it is `private`\""
        ),
        Row(
            identity: "0x00000000000000A3",
            location: "\(values):8",
            template: "measure-non-negativity",
            function: "isEmpty()",
            score: 35,
            tier: "Possible",
            computed: true
        ),
        Row(
            identity: "0x00000000000000A4",
            location: "\(values):12",
            template: "round-trip",
            function: "encoded()",
            score: 25,
            tier: "Possible",
            extra: ", \"secondaryFunctionName\": \"decoded(_:)\""
        ),
        Row(
            identity: "0x00000000000000A5",
            location: "@ROOT@/Tests/CoreTests/MoneyTests.swift:5",
            template: "differential-equivalence"
        )
    ]

    /// Rows that attach to no function: three with no usable location, one
    /// on a protocol requirement, one between types and one in a file the
    /// scan didn't cover.
    private static let unattached = [
        Row(identity: "0x00000000000000B1", location: "<corpus>:0", function: "merge(_:)", score: 20, tier: "Advisory"),
        Row(identity: "0x00000000000000B2", location: "(unknown)", function: "(unknown)", score: 20, tier: "Possible"),
        Row(identity: "0x00000000000000B3", location: "/elsewhere/Other.swift:3", score: 20, tier: "Possible"),
        Row(identity: "0x00000000000000C1", location: "\(values):26", function: "area()", score: 20, tier: "Possible"),
        Row(identity: "0x00000000000000C2", location: "\(values):24", score: 20, tier: "Possible"),
        Row(
            identity: "0x00000000000000C3",
            location: "@ROOT@/Sources/Unlisted/Extra.swift:1",
            score: 20,
            tier: "Possible"
        )
    ]

    /// A reducer invariant on `reduce(_:_:)`.
    private static let interaction = """
        {"actionTypeName": "Int", "family": "determinism", "firstSeenAt": "2026-11-19T00:00:00Z",
         "identityHash": "0x00000000000000D1", "lastSeenAt": "2026-11-19T00:00:00Z",
         "location": "\(values):29", "predicate": "reduce(s, a) == reduce(s, a)",
         "reducerQualifiedName": "reduce", "score": 30, "stateTypeName": "Int", "tier": "Possible"}
        """

    /// The package scanned with a fake indexer giving the library every
    /// row and the interaction row.
    private static func scan() throws -> ScanReport {
        let package = try PropertyHarness.package([:])
        defer { package.remove() }
        let tool = try FakeTool.makeIndexer(
            indexes: [
                "Core": PropertyHarness.index(
                    attached + unattached,
                    interactions: [interaction],
                    schemaVersion: SwiftInferIndex.schemaVersion
                ),
                "Macros": PropertyHarness.emptyIndex,
                "Tool": PropertyHarness.emptyIndex
            ],
            errors: [:],
            statuses: [:],
            delays: [:]
        )
        defer { PropertyHarness.remove(tool) }
        return try package.scan(tools: PropertyHarness.locator(tool))
    }

    /// The key of the record called `name` of `kind` in `report`.
    private static func key(_ name: String, _ kind: FunctionKind, in report: ScanReport) throws -> String {
        try #require(report.records.first { $0.name == name && $0.kind == kind }).key
    }

    @Test("""
        rows attach to the function at their line, a computed property to its getter, a test site to its \
        test and a partner by name; rows with no usable location, or outside any function, are kept unmapped
        """)
    func mapping() throws {
        let report = try Self.scan()
        let properties = try #require(report.properties)
        let candidates = properties.candidates

        #expect(candidates.map(\.identity) == [
            "0x00000000000000B1", "0x00000000000000B2", "0x00000000000000B3", "0x00000000000000A1",
            "0x00000000000000A3", "0x00000000000000A4", "0x00000000000000A2", "0x00000000000000C2",
            "0x00000000000000C1", "0x00000000000000D1", "0x00000000000000C3", "0x00000000000000A5"
        ])
        let byIdentity = Dictionary(uniqueKeysWithValues: candidates.map { ($0.identity, $0) })
        let owners = byIdentity.mapValues { $0.location?.owner ?? "-" }
        #expect(owners["0x00000000000000A1"] == (try Self.key("doubled", .function, in: report)))
        #expect(owners["0x00000000000000A2"] == (try Self.key("secret", .function, in: report)))
        #expect(owners["0x00000000000000A3"] == (try Self.key("isEmpty", .accessor, in: report)))
        #expect(owners["0x00000000000000A5"] == (try Self.key("doubling", .function, in: report)))
        #expect(owners["0x00000000000000D1"] == (try Self.key("reduce", .function, in: report)))
        #expect(owners["0x00000000000000C1"] == "Core::Shape")
        #expect(byIdentity["0x00000000000000A4"]?.partner == "decoded(_:)")
        #expect(byIdentity["0x00000000000000A4"]?.partnerKey == (try Self.key("decoded", .function, in: report)))
        #expect(byIdentity["0x00000000000000A1"]?.partnerKey == nil)
        let unmapped = byIdentity.compactMapValues(\.unmapped)
        #expect(unmapped == [
            "0x00000000000000B1": .missingLocation, "0x00000000000000B2": .missingLocation,
            "0x00000000000000B3": .missingLocation, "0x00000000000000C1": .type,
            "0x00000000000000C2": .file, "0x00000000000000C3": .unscanned
        ])
        let testSites = byIdentity.compactMapValues(\.site).filter { $0.value == .test }.keys
        #expect(testSites.sorted() == ["0x00000000000000A5"])
        #expect(byIdentity.filter { $0.value.site == nil }.keys.sorted() == [
            "0x00000000000000B1", "0x00000000000000B2", "0x00000000000000B3", "0x00000000000000C3"
        ])
        let blocked = try #require(byIdentity["0x00000000000000A2"])
        #expect((blocked.blocked, blocked.tier, blocked.scoreBand) == (true, "Advisory", .strong))
        let reducer = try #require(byIdentity["0x00000000000000D1"])
        #expect((reducer.population, reducer.template, reducer.function) == (.interaction, "determinism", "reduce"))
        #expect(byIdentity["0x00000000000000A3"]?.scoreBand == .possible)
        #expect(byIdentity["0x00000000000000B3"]?.location == nil)
        #expect(byIdentity["0x00000000000000A1"]?.typeName == "Money")
        #expect(candidates.allSatisfy { $0.generated == false && $0.identityCollision == false })
        #expect((properties.crossTargetDuplicates, properties.crossTargetConflicts, properties.identityCollisions)
            == (0, 0, 0))
        #expect(properties.seiRevision == nil)
    }

    @Test("""
        roll-ups count candidates by the file holding them, the production part also those placed in no \
        scanned file; the report lists every unmapped candidate
        """)
    func rollupsAndReport() throws {
        let report = try Self.scan()
        let rollups = Dictionary(uniqueKeysWithValues: report.rollups.map { ($0.name, $0.properties) })

        #expect(rollups["Core"]??.tier == ["Strong": 1, "Advisory": 1, "Possible": 5])
        #expect(rollups["Core"]??.mapped == 5)
        #expect(rollups["Core"]??.unmapped == 2)
        #expect(rollups["CoreTests"]??.tier == ["Strong": 1])
        #expect(rollups["production"]??.tier == ["Strong": 1, "Advisory": 2, "Possible": 8])
        #expect(rollups["production"]??.mapped == 5)
        #expect(rollups["production"]??.unmapped == 6)
        #expect(rollups["tests"]??.mapped == 1)
        for empty in ["Macros", "Plug", "Tool"] {
            #expect(rollups[empty].map { $0 == nil } == true)
        }
        let production = try #require(report.rollups.first { $0.name == "production" })
        let metrics = try RollupMetrics.metrics(of: production)
        #expect(metrics.first { $0.path == "properties.tier.Strong" }?.collector == "swiftinferproperties")
        #expect(MetricDirection.of("properties.unmapped") == .neutral)

        let lines = MarkdownProperties.render(report)
        #expect(lines[0].contains("12 candidates, 6 attached to a function and 6 not."))
        #expect(lines[0].contains("0 duplicates and 0 conflicting rows; 0 identities at more than one location."))
        #expect(lines[1]
            == "swift-infer's SwiftEffectInference: unknown (the binary isn't in a SwiftPM build directory).")
        #expect(lines.contains("| Strong | 1 | 1 |"))
        #expect(lines.contains("| Likely | 0 | 0 |"))
        #expect(lines.contains("| Possible | 8 | 0 |"))
        #expect(lines.contains("| Advisory | 2 | 0 |"))
        #expect(lines.contains(
            "| 0x00000000000000B1 | idempotence | Advisory | merge(_:) | none | no location in the package |"
        ))
        #expect(lines.contains(
            "| 0x00000000000000C1 | idempotence | Possible | area() | Sources/Core/Values.swift:26 | "
                + "inside a type, outside any function |"
        ))
        #expect(lines.filter { $0.hasPrefix("| 0x") }.count == 6)
    }

    @Test("the merge gives the same rows and counts whatever order the targets' rows arrive in")
    func mergeIsOrderFree() {
        let row = { (identity: String, location: String, target: String, blocker: String?) in
            SwiftInferRow(
                population: .algebraic,
                identity: identity,
                template: "idempotence",
                tier: "Strong",
                score: 80,
                function: "f()",
                typeName: nil,
                location: location,
                isComputedProperty: false,
                partner: nil,
                blocker: blocker,
                subjectFingerprint: nil,
                hasTypeShape: false,
                fields: .object(["blocker": blocker.map(JSONValue.string) ?? .null]),
                target: target
            )
        }
        let arriving = [
            row("0x01", "A.swift:1", "Core", nil), row("0x01", "A.swift:1", "Tool", "private"),
            row("0x02", "A.swift:1", "Core", nil), row("0x02", "B.swift:1", "Tool", nil),
            row("0x03", "A.swift:1", "Core", nil), row("0x03", "A.swift:1", "Tool", nil)
        ]

        let forward = CandidateMerge.merge(arriving)
        let backward = CandidateMerge.merge(arriving.reversed())

        let describe = { (merged: MergedCandidates) in
            merged.rows.map { "\($0.row.identity) \($0.row.location) \($0.row.target) \($0.identityCollision)" }
        }
        #expect(describe(forward) == describe(backward))
        #expect(describe(forward) == [
            "0x01 A.swift:1 Tool false", "0x02 A.swift:1 Core true", "0x02 B.swift:1 Tool true",
            "0x03 A.swift:1 Core false"
        ])
        #expect((forward.duplicates, forward.conflicts, forward.collisions) == (1, 1, 1))
    }

    @Test("the SwiftEffectInference revision comes from the build directory holding the binary, else nil")
    func buildRevision() throws {
        let directory = try SnapshotHarness.temporaryDirectory("Build")
        defer { try? FileManager.default.removeItem(at: directory) }
        let release = directory.appendingPathComponent(".build/release")
        try FileManager.default.createDirectory(at: release, withIntermediateDirectories: true)
        let binary = release.appendingPathComponent("swift-infer")
        try Data().write(to: binary)
        let state = """
            {"object": {"dependencies": [
              {"packageRef": {"identity": "swift-syntax"}, "state": {"checkoutState": {"revision": "aaa"}}},
              {"packageRef": {"identity": "swifteffectinference"}, "state": {"checkoutState": {"revision": "bbb"}}}
            ]}, "version": 7}
            """
        try Data(state.utf8).write(to: directory.appendingPathComponent(".build/workspace-state.json"))

        #expect(SwiftInferBuildState.effectInferenceRevision(of: binary) == "bbb")
        #expect(SwiftInferBuildState.effectInferenceRevision(of: directory.appendingPathComponent("tool")) == nil)
    }
}
