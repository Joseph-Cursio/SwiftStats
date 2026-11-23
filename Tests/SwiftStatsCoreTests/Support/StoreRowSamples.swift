//
//  StoreRowSamples.swift
//  SwiftStatsCoreTests
//
//  Hand-made M4 results covering every nullable column of the store's v3
//  tables, written as the scan JSON writes them, and a scan report rebuilt
//  to carry them, so the store's rows can be checked without running the
//  external tools.
//

import Foundation
@testable import SwiftStatsCore

/// M4 results for the store's v3 tables.
enum StoreRowSamples {
    /// Candidates covering each shape of location, verify join, decision
    /// and test link: none of them; a verified, decided, linked one; an
    /// interaction row whose evidence can't be judged; and one no evidence
    /// record names.
    private static let candidateJSON = """
        [
          {"identity": "0x0000000000000001", "population": "algebraic", "template": "idempotence",
           "tier": "Possible", "score": 25, "scoreBand": "Possible", "blocked": false, "function": "double(_:)",
           "unmapped": "noLocation", "generated": false, "identityCollision": false, "testKeys": []},
          {"identity": "0x00000000000000A2", "population": "algebraic", "template": "round-trip",
           "tier": "Strong", "score": 90, "scoreBand": "Strong", "blocked": true, "function": "double(_:)",
           "typeName": "Money", "site": "production", "generated": true, "identityCollision": true,
           "location": {"file": "Sources/Lib/Lib.swift", "line": 2, "attachedTo": "function",
                        "owner": "Lib::func double(_:)"},
           "partner": "halve(_:)", "partnerKey": "Lib::func halve(_:)", "decision": "accepted",
           "verification": {"outcome": "measured-bothPass",
                            "judgement": {"fresh": true, "verified": true, "disproven": false}},
           "testedBy": "handwritten", "testKeys": ["Tests::func first()", "Tests::func second()"]},
          {"identity": "0x00000000000000B3", "population": "interaction", "template": "reducer",
           "tier": "Likely", "score": 50, "scoreBand": "Likely", "blocked": false, "function": "reduce",
           "unmapped": "noLocation", "generated": false, "identityCollision": false,
           "decision": "acceptedAsConformance", "verification": {"outcome": "measured-defaultFails"},
           "testedBy": "macro", "testKeys": []},
          {"identity": "0x00000000000000C4", "population": "algebraic", "template": "idempotence",
           "tier": "Advisory", "score": 80, "scoreBand": "Strong", "blocked": true, "function": "rounded()",
           "site": "production", "unmapped": "type", "generated": false, "identityCollision": false,
           "location": {"file": "Sources/Lib/Lib.swift", "line": 9, "attachedTo": "type"},
           "verification": {"judgement": {"fresh": false, "verified": false, "disproven": false}},
           "testedBy": "generated", "testKeys": ["Tests::func stub()"]}
        ]
        """

    /// Law checks with and without evidence.
    private static let lawJSON = """
        {"checks": [
           {"type": "Lib::Money", "protocol": "Equatable", "provenance": "declared", "implementation": "custom",
            "state": "run", "evidence": "call", "file": "Sources/Lib/Lib.swift", "line": 9, "generated": false},
           {"type": "Lib::Suit", "protocol": "RawRepresentable", "provenance": "rawType",
            "implementation": "synthesized", "state": "notRun", "file": "Sources/Lib/Model.generated.swift",
            "line": 1, "generated": true}
         ],
         "unresolvedCalls": 1, "ambiguousNames": [], "testOnlyConformances": 0, "kitDependency": true}
        """

    /// An exact subtree class whose copies cover records whole, and a
    /// near-miss class with a copy no record holds.
    private static let cloneJSON = """
        {"part": "production", "fileListHash": "sha256:abc",
         "toolDuplicatedLines": {"subtree": 4, "type1": 4, "sequence": 0, "nearMiss": 3},
         "classes": [
           {"ordinal": 1, "pass": "subtree", "exact": true, "mass": 40, "lineSpan": 4, "fingerprint": "f1",
            "instances": [
              {"file": "Sources/Lib/A.swift", "strippedLines": 4, "containing": "Lib::func a()",
               "range": {"start": {"line": 1, "column": 1}, "end": {"line": 4, "column": 1}},
               "wholes": ["Lib::func a()"]},
              {"file": "Sources/Lib/B.swift", "strippedLines": 4,
               "range": {"start": {"line": 3, "column": 5}, "end": {"line": 6, "column": 5}},
               "wholes": ["Lib::func b()", "Lib::func c()"]}
            ]},
           {"ordinal": 2, "pass": "near-miss", "exact": false, "mass": 30, "similarity": 0.9012, "lineSpan": 3,
            "fingerprint": "f2",
            "instances": [
              {"file": "Sources/Lib/A.swift", "strippedLines": 3,
               "range": {"start": {"line": 6, "column": 9}, "end": {"line": 8, "column": 20}}, "wholes": []}
            ]}
         ]}
        """

    /// Effect facts with two reasons and a refutation chain.
    private static let effectJSON = """
        {"tier": "idempotent", "source": "bodyInferred", "purity": "refuted",
         "refutation": {"case": "refutingConstruction", "root": "nondeterministicCall",
                        "detail": "constructs Clock, which calls Date()"},
         "function": {"inference": "unique", "valueShaped": false,
                      "inferred": {"tier": "idempotent", "depth": 2, "anchor": "heuristic",
                                   "via": ["calls `a()`", "calls `b()`"]}}}
        """

    /// `json` decoded as a `Value`.
    private static func decoded<Value: Decodable>(_ json: String) throws -> Value {
        try JSONDecoder().decode(Value.self, from: Data(json.utf8))
    }

    /// The candidates.
    static func candidates() throws -> [PropertyCandidate] {
        try decoded(candidateJSON)
    }

    /// The law checks.
    static func laws() throws -> LawReport {
        try decoded(lawJSON)
    }

    /// The clones.
    static func clones() throws -> CloneReport {
        try decoded(cloneJSON)
    }

    /// The effect facts.
    static func effect() throws -> EffectFacts {
        try decoded(effectJSON)
    }

    /// `report` with `records`, and these samples as its candidates, clones and law checks.
    static func report(_ report: ScanReport, records: [FunctionRecord]) throws -> ScanReport {
        ScanReport(
            schemaVersion: report.schemaVersion,
            tool: report.tool,
            metrics: report.metrics,
            package: report.package,
            configuration: report.configuration,
            targets: report.targets,
            records: records,
            types: report.types,
            files: report.files,
            rollups: report.rollups,
            sitrep: report.sitrep,
            collectors: report.collectors,
            findings: report.findings,
            tests: report.tests,
            dependencies: report.dependencies,
            warnings: report.warnings,
            effects: report.effects,
            properties: PropertyReport(
                candidates: try candidates(),
                orphanDecisions: nil,
                orphanVerifyRecords: nil,
                crossTargetDuplicates: 0,
                crossTargetConflicts: 0,
                identityCollisions: 0,
                joinInputs: PropertyReport.JoinInputs(decisions: nil, interactionDecisions: nil, verifyEvidence: nil),
                seiRevision: "ba3624d"
            ),
            clones: try clones(),
            laws: try laws(),
            coverage: nil,
            mutation: nil
        )
    }
}
