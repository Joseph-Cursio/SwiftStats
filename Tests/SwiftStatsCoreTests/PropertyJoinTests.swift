import Foundation
@testable import SwiftStatsCore
import Testing

/// SwiftInferProperties' suggestions joined to the package's own decisions
/// and verify evidence (PRD §7.11): which evidence verifies or disproves,
/// the interaction file's spelling, what an absent or unreadable file
/// leaves, and an export, which has none of the files, compared with the
/// working tree, which has them.
@Suite("Property joins", .serialized)
struct PropertyJoinTests {
    private typealias Row = PropertyHarness.Row

    /// The library's file, as the tool writes it; `doubled()` is on line 4.
    private static let values = "@ROOT@/Sources/Core/Values.swift:4"

    /// Rows on `doubled()`, each with the fingerprint its case needs.
    private static let rows = [
        Row(identity: "0x0000000000000001", location: values, score: 25, tier: "Possible", fingerprint: "\"F1\""),
        Row(identity: "0x0000000000000002", location: values, score: 20, tier: "Possible", fingerprint: "\"F2\""),
        Row(identity: "0x0000000000000003", location: values, score: 40, tier: "Likely", fingerprint: "\"F3\""),
        Row(
            identity: "0x0000000000000004",
            location: values,
            tier: "Advisory",
            blocker: "\"private\"",
            fingerprint: "\"F4\""
        ),
        Row(identity: "0x0000000000000005", location: values),
        Row(identity: "0x0000000000000006", location: values, fingerprint: "\"F6\""),
        Row(identity: "0x0000000000000007", location: values, score: 50, tier: "Likely", fingerprint: "\"F7\""),
        Row(identity: "0x0000000000000008", location: values, score: 50, tier: "Likely", fingerprint: "\"F8\""),
        Row(identity: "0x0000000000000009", location: values, score: 50, tier: "Likely", fingerprint: "\"F9\""),
        // The index's own decision, from a run that found one, is not what
        // SwiftStats joins.
        Row(
            identity: "0x000000000000000A",
            location: values,
            fingerprint: "\"FA\"",
            extra: ", \"decision\": \"rejected\""
        )
    ]

    /// A reducer invariant on `reduce(_:_:)`, line 29.
    private static let interaction = """
        {"family": "determinism", "identityHash": "0x00000000000000D1",
         "location": "@ROOT@/Sources/Core/Values.swift:29",
         "reducerQualifiedName": "reduce", "score": 30, "tier": "Possible"}
        """

    /// `decisions.json`: four rows decided, the first twice, and one orphan.
    private static let decisions = """
        {"records": [
          {"decision": "accepted", "identityHash": "0000000000000001", "tier": "possible"},
          {"decision": "rejected", "identityHash": "0000000000000001", "tier": "possible"},
          {"decision": "rejected", "identityHash": "0000000000000002", "tier": "possible"},
          {"decision": "skipped", "identityHash": "0000000000000003", "tier": "likely"},
          {"decision": "acceptedAsConformance", "identityHash": "000000000000000A", "tier": "strong"},
          {"decision": "accepted", "identityHash": "DEADBEEF00000000", "tier": "strong"}
        ], "schemaVersion": 2}
        """

    /// `interaction-decisions.json`: the reducer row, hyphenated, a hash no
    /// interaction row has, and an algebraic row's hash.
    private static let interactionDecisions = """
        {"records": [
          {"decision": "accepted-as-conformance", "identityHash": "00000000000000D1", "family": "determinism"},
          {"decision": "skipped", "identityHash": "00000000000000D9", "family": "determinism"},
          {"decision": "accepted", "identityHash": "0000000000000001", "family": "determinism"}
        ], "schemaVersion": 1}
        """

    /// `verify-evidence.json`: one record per case, and one orphan.
    private static let evidence = """
        {"records": [
          {"identityHash": "0000000000000001", "outcome": "measured-bothPass", "subjectFingerprint": "F1"},
          {"identityHash": "0000000000000002", "outcome": "measured-bothPass", "subjectFingerprint": "F2"},
          {"identityHash": "0000000000000003", "outcome": "measured-bothPass", "subjectFingerprint": "OLD"},
          {"identityHash": "0000000000000004", "outcome": "measured-bothPass", "subjectFingerprint": "F4"},
          {"identityHash": "0000000000000005", "outcome": "measured-bothPass", "subjectFingerprint": "F5"},
          {"identityHash": "0000000000000006", "outcome": "measured-bothPass"},
          {"identityHash": "0000000000000007", "outcome": "measured-defaultFails", "subjectFingerprint": "F7"},
          {"identityHash": "0000000000000008", "outcome": "measured-defaultFails", "subjectFingerprint": "OLD"},
          {"identityHash": "0000000000000009", "outcome": "measured-edgeCaseAdvisory", "subjectFingerprint": "F9"},
          {"identityHash": "00000000000000D1", "outcome": "measured-bothPass", "subjectFingerprint": "FD"},
          {"identityHash": "0000000000000E01", "outcome": "measured-error"}
        ], "schemaVersion": 1}
        """

    /// The harness package with `extra` files, scanned with a fake indexer
    /// giving the library the rows and the reducer invariant.
    private static func scan(_ extra: [String: String]) throws -> ScanReport {
        let package = try PropertyHarness.package(extra)
        defer { package.remove() }
        let tool = try FakeTool.makeIndexer(
            indexes: [
                "Core": PropertyHarness.index(
                    rows,
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

    /// A repository whose first commit has `doubled(_:)`, whose second adds
    /// `tripled(_:)` in another file, and whose working tree adds an
    /// ignored `decisions.json` deciding the suggestion on `doubled(_:)`;
    /// with the first commit's hash.
    private static func twoCommits() throws -> (HistoryRepository, String) {
        let repository = try HistoryRepository()
        try repository.write([
            ".gitignore": ".swiftinfer/\n.swiftstats/\n",
            "Sources/Core/Values.swift": "public func doubled(_ value: Int) -> Int {\n    value * 2\n}\n"
        ])
        let older = try repository.commit("one", day: 1)
        let tripled = "public func tripled(_ value: Int) -> Int {\n    value * 3\n}\n"
        try repository.write(["Sources/Core/More.swift": tripled])
        try repository.commit("two", day: 2)
        let decided = """
            {"records": [{"decision": "accepted", "identityHash": "00000000000000A1"}], "schemaVersion": 2}
            """
        try repository.write([".swiftinfer/decisions.json": decided])
        return (repository, older)
    }

    /// `text`'s hash as the joins record it.
    private static func hash(_ text: String) -> String {
        "sha256:" + ContentHash.sha256(Data(text.utf8))
    }

    /// Each candidate's verify join as `outcome fresh verified disproven`,
    /// `none` for a nil outcome and `undecided` for a nil judgement.
    private static func verification(_ candidate: PropertyCandidate) -> String {
        guard let joined = candidate.verification else {
            return "nil"
        }
        let outcome = joined.outcome?.rawValue ?? "none"
        guard let judgement = joined.judgement else {
            return "\(outcome) undecided"
        }
        return "\(outcome) \(judgement.fresh) \(judgement.verified) \(judgement.disproven)"
    }

    @Test("""
        fresh bothPass evidence verifies a row not Advisory whose score reaches Strong with 50 added, and \
        fresh defaultFails evidence disproves; stale or missing fingerprints verify nothing, and evidence on \
        an interaction row, which has no fingerprint to compare, leaves freshness undecided
        """)
    func verified() throws {
        let report = try Self.scan([
            ".swiftinfer/decisions.json": Self.decisions,
            ".swiftinfer/interaction-decisions.json": Self.interactionDecisions,
            ".swiftinfer/verify-evidence.json": Self.evidence
        ])
        let properties = try #require(report.properties)
        let byIdentity = Dictionary(uniqueKeysWithValues: properties.candidates.map { ($0.identity, $0) })

        #expect(byIdentity.mapValues(Self.verification) == [
            "0x0000000000000001": "measured-bothPass true true false",
            "0x0000000000000002": "measured-bothPass true false false",
            "0x0000000000000003": "measured-bothPass false false false",
            "0x0000000000000004": "measured-bothPass true false false",
            "0x0000000000000005": "measured-bothPass false false false",
            "0x0000000000000006": "measured-bothPass false false false",
            "0x0000000000000007": "measured-defaultFails true false true",
            "0x0000000000000008": "measured-defaultFails false false false",
            "0x0000000000000009": "measured-edgeCaseAdvisory true false false",
            "0x000000000000000A": "none false false false",
            // Interaction rows carry no fingerprint in the index, so freshness is undecided.
            "0x00000000000000D1": "measured-bothPass undecided"
        ])
        #expect(byIdentity.compactMapValues(\.decision) == [
            "0x0000000000000001": .accepted, "0x0000000000000002": .rejected, "0x0000000000000003": .skipped,
            "0x000000000000000A": .asConformance, "0x00000000000000D1": .asConformance
        ])
        // One decisions.json orphan; two interaction records name no interaction row.
        #expect(properties.orphanDecisions == 3)
        #expect(properties.orphanVerifyRecords == 1)
        #expect(properties.joinInputs == PropertyReport.JoinInputs(
            decisions: Self.hash(Self.decisions),
            interactionDecisions: Self.hash(Self.interactionDecisions),
            verifyEvidence: Self.hash(Self.evidence)
        ))
        #expect(report.warnings.isEmpty)
    }

    @Test("with none of the package's files, every join is nil and nothing is counted")
    func absent() throws {
        let report = try Self.scan([:])
        let properties = try #require(report.properties)

        #expect(properties.candidates.count == Self.rows.count + 1)
        #expect(properties.candidates.allSatisfy { $0.decision == nil && $0.verification == nil })
        #expect(properties.orphanDecisions == nil)
        #expect(properties.orphanVerifyRecords == nil)
        #expect(properties.joinInputs == PropertyReport.JoinInputs(
            decisions: nil,
            interactionDecisions: nil,
            verifyEvidence: nil
        ))
    }

    @Test("an unreadable file joins nothing and says so; a file read beside it still joins")
    func unreadable() throws {
        let unknownOutcome = """
            {"records": [{"identityHash": "0000000000000001", "outcome": "measured-maybe"}], "schemaVersion": 1}
            """
        let report = try Self.scan([
            ".swiftinfer/decisions.json": "{",
            ".swiftinfer/interaction-decisions.json": Self.interactionDecisions,
            ".swiftinfer/verify-evidence.json": unknownOutcome
        ])
        let properties = try #require(report.properties)
        let warnings = report.warnings.filter { $0.file?.hasPrefix(".swiftinfer/") == true }

        #expect(warnings.map(\.file) == [".swiftinfer/decisions.json", ".swiftinfer/verify-evidence.json"])
        #expect(warnings.allSatisfy { warning in
            warning.message.hasPrefix("not readable, so SwiftInferProperties' suggestions aren't joined to it: ")
        })
        #expect(properties.candidates.allSatisfy { $0.verification == nil })
        let decided = properties.candidates.filter { $0.decision != nil }.map(\.identity)
        #expect(decided == ["0x00000000000000D1"])
        #expect(properties.orphanDecisions == 2)
        #expect(properties.orphanVerifyRecords == nil)
        #expect(properties.joinInputs.decisions == nil)
        #expect(properties.joinInputs.interactionDecisions == Self.hash(Self.interactionDecisions))
        #expect(properties.joinInputs.verifyEvidence == nil)
    }

    @Test("""
        an exported revision, which has no decisions, and the working tree, which has them, compare as \
        compared and show the properties roll-up's deltas
        """)
    func exportComparesWithWorkingTree() throws {
        let (repository, older) = try Self.twoCommits()
        defer { repository.remove() }
        let exportRows = [
            Row(identity: "0x00000000000000A1", location: "@ROOT@/Sources/Core/Values.swift:1"),
            Row(identity: "0x00000000000000A2", location: "@ROOT@/Sources/Core/More.swift:1")
        ]
        let tool = try FakeTool.makeIndexer(
            indexes: ["Core": PropertyHarness.index(exportRows)],
            errors: [:],
            statuses: [:],
            delays: [:]
        )
        defer { PropertyHarness.remove(tool) }
        let workspace = try SnapshotWorkspace(
            packageRoot: repository.root,
            configurationFile: nil,
            storeOverride: nil,
            build: SnapshotHarness.build,
            describer: HistoryRepository.DiskDescriber(),
            tools: PropertyHarness.locator(tool)
        )

        let ids = try workspace.diffSnapshotIDs(older: older, newer: nil, includeDirty: false, rescan: false)
        let before = try workspace.store.load(id: ids.older)
        let after = try workspace.store.load(id: ids.newer)
        let diff = SnapshotDiff.diff(before, after)

        let outcome = diff.collectors.first { $0.name == SwiftInferPropertiesAdapter.name }?.outcome
        #expect(outcome == .compared)
        let deltas = diff.rollups.filter { $0.delta.metric.hasPrefix("properties.") }
            .map { "\($0.name) \($0.delta.metric) \($0.delta.before ?? -1) \($0.delta.after ?? -1)" }
        #expect(deltas == [
            "Core properties.mapped 1.0 2.0", "Core properties.tier.Strong 1.0 2.0",
            "production properties.mapped 1.0 2.0", "production properties.unmapped 1.0 0.0"
        ])
        let joins = try [ids.older, ids.newer].map { id in
            try workspace.store.report(id: id).properties.map { properties in
                (properties.joinInputs.decisions != nil, properties.candidates.compactMap(\.decision))
            }
        }
        #expect(joins[0]?.0 == false && joins[0]?.1.isEmpty == true)
        #expect(joins[1]?.0 == true && joins[1]?.1 == [.accepted])
    }
}
