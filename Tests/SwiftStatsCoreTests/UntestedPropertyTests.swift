//
//  UntestedPropertyTests.swift
//  SwiftStatsCoreTests
//
//  Untested property (PRD §8): which suggestions are in the pool (Strong
//  or Verified, production site, not disproven or rejected), that a
//  tested one counts but isn't listed, the flags and score (a score past
//  2^53 or as large as an Int holds included), and the rule for a package
//  with no test target.
//

import Foundation
@testable import SwiftStatsCore
import Testing

@Suite("Untested property")
struct UntestedPropertyTests {
    private typealias Row = PropertyHarness.Row

    /// The library's file, as the tool writes it.
    private static let values = "@ROOT@/Sources/Core/Values.swift"

    /// A structural blocker, as JSON.
    private static let blocker = "\"private\""
    /// The subject fingerprint of the Verified row, as JSON.
    private static let verifiedPrint = "\"FB\""
    /// The subject fingerprint of the disproven row, as JSON.
    private static let disprovenPrint = "\"FF\""

    /// Suggestions of each kind the pool keeps or drops.
    private static let rows = [
        Row(identity: "0x00000000000000A1", location: "\(values):4"),
        Row(
            identity: "0x00000000000000B2",
            location: "\(values):12",
            score: 25,
            tier: "Possible",
            fingerprint: verifiedPrint
        ),
        Row(identity: "0x00000000000000C3", location: "\(values):20", score: 90, tier: "Advisory", blocker: blocker),
        Row(identity: "0x00000000000000D4", location: "@ROOT@/Tests/CoreTests/MoneyTests.swift:5", score: 85),
        Row(identity: "0x00000000000000E5", location: "\(values):16"),
        Row(identity: "0x00000000000000F6", location: "\(values):16", fingerprint: disprovenPrint),
        Row(identity: "0x00000000000000A7", location: "\(values):4", score: 95),
        Row(identity: "0x00000000000000B8", location: "\(values):4", score: 50, tier: "Likely"),
        Row(
            identity: "0x00000000000000C9",
            location: "\(values):12",
            template: "round-trip",
            function: "encoded()",
            extra: ", \"secondaryFunctionName\": \"decoded(_:)\""
        ),
        Row(identity: "0x00000000000000DA", location: "(unknown)", function: "(unknown)"),
        Row(identity: "0x00000000000000EB", location: "@ROOT@/Sources/Core/Made.swift:2")
    ]

    /// A Strong reducer invariant: an interaction row, never in the pool.
    private static let interaction = """
        {"family": "determinism", "identityHash": "0x00000000000000D1",
         "location": "@ROOT@/Sources/Core/Values.swift:29",
         "reducerQualifiedName": "reduce", "score": 80, "tier": "Strong"}
        """

    /// The package's decisions: E5 rejected, C9 accepted.
    private static let decisions = """
        {"records": [
          {"decision": "rejected", "identityHash": "00000000000000E5", "tier": "strong"},
          {"decision": "accepted", "identityHash": "00000000000000C9", "tier": "strong"}
        ], "schemaVersion": 2}
        """

    /// The package's verify evidence: B2 verified, F6 disproven, both fresh.
    private static let evidence = """
        {"records": [
          {"identityHash": "00000000000000B2", "outcome": "measured-bothPass", "subjectFingerprint": "FB"},
          {"identityHash": "00000000000000F6", "outcome": "measured-defaultFails", "subjectFingerprint": "FF"}
        ], "schemaVersion": 1}
        """

    /// A generated property test for A7.
    private static let stub = """
        // Suggestion identity: 0x00000000000000A7
        import Testing
        @testable import Core

        @Test func doubledIsIdempotent() {
            #expect(Money(cents: 1).doubled().doubled().cents == 4)
        }
        """

    /// The stub's path in the test target.
    private static let stubPath = "Generated/SwiftInfer/idempotence/DoubledTests.swift"

    /// The package, with its test target when `tests` is true, scanned and stored.
    private static func snapshot(tests: Bool) throws -> StoredSnapshot {
        var files = [
            "Sources/Core/Values.swift": PropertyHarness.values,
            "Sources/Core/Made.swift": "// DO NOT EDIT\nfunc made() -> Int {\n    1\n}\n",
            ".swiftinfer/decisions.json": decisions,
            ".swiftinfer/verify-evidence.json": evidence
        ]
        var targets = [PropertyHarness.target("Core", "library", "Sources/Core", ["Made.swift", "Values.swift"])]
        if tests {
            files["Tests/CoreTests/MoneyTests.swift"] = PropertyHarness.tests
            files["Tests/CoreTests/\(stubPath)"] = stub
            let sources = [stubPath, "MoneyTests.swift"]
            targets.append(PropertyHarness.target("CoreTests", "test", "Tests/CoreTests", sources))
        }
        let index = PropertyHarness.index(
            rows,
            interactions: [interaction],
            schemaVersion: SwiftInferIndex.schemaVersion
        )
        return try SignalHarness.stored(files, targets: targets, indexes: ["Core": index])
    }

    @Test("Strong and Verified suggestions no property test checks are listed; test-site, rejected, disproven aren't")
    func listed() throws {
        let signal = try SignalHarness.signal(.untestedProperty, of: try Self.snapshot(tests: true))

        #expect(signal.leftOut == nil)
        #expect(signal.items.map(\.property?.identity) == [
            "0x00000000000000C3", "0x00000000000000A1", "0x00000000000000C9", "0x00000000000000B2"
        ])
        // A Verified Possible row scores its 25 plus Verified's 50.
        #expect(signal.items.map(\.score) == [90, 80, 80, 75])
        #expect(signal.members.count == 4)
        #expect(signal.items.map(\.property?.verified) == [false, false, false, true])
        #expect(signal.items.map(\.property?.blocked) == [true, false, false, false])
        #expect(signal.items.map(\.subject) == [
            // A private member's key names its file.
            "Core::Money::func secret(_: Int) -> Int @ Sources/Core/Values.swift",
            "Core::Money::func doubled() -> Money",
            "Core::Money::func encoded() -> String",
            "Core::Money::func encoded() -> String"
        ])
        #expect(signal.rule == UntestedProperty.rule)
    }

    @Test("a tested candidate counts in the pool but is absent from the list")
    func tested() throws {
        let snapshot = try Self.snapshot(tests: true)
        let signal = try SignalHarness.signal(.untestedProperty, of: snapshot)
        let tested = try #require(snapshot.candidates.first { $0.identity == "0x00000000000000A7" })

        #expect(tested.testedBy == .generated)
        // A1, B2, C3, A7 and C9.
        #expect(signal.candidates == 5)
        #expect(signal.items.contains { $0.property?.identity == tested.identity } == false)
        let top = MarkdownSignals.top(signal, limit: MarkdownSignals.defaultTopLimit)
        #expect(top.contains("0x00000000000000A7") == false)
        #expect(top.contains("4 members of 4 ranked"))
    }

    @Test("the table shows the template, tier and score, Verified, the blocker flag, the partner and the decision")
    func table() throws {
        let signal = try SignalHarness.signal(.untestedProperty, of: try Self.snapshot(tests: true))

        #expect(SignalHarness.rows(signal) == [
            "| # | Function | Score | Template | Tier / score | Verified | Blocked | Partner | Decision | Member |",
            "| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |",
            "| 1 | `Money::func secret(_: Int) -> Int` (Sources/Core/Values.swift:20) | 90 | idempotence "
                + "| Advisory / 90 | no | yes | — | — | yes |",
            "| 2 | `Money::func doubled() -> Money` (Sources/Core/Values.swift:4) | 80 | idempotence | Strong / 80 "
                + "| no | no | — | — | yes |",
            "| 3 | `Money::func encoded() -> String` (Sources/Core/Values.swift:12) | 80 | round-trip | Strong / 80 "
                + "| no | no | decoded(_:) | accepted | yes |",
            "| 4 | `Money::func encoded() -> String` (Sources/Core/Values.swift:12) | 75 | idempotence | Possible / 25 "
                + "| yes | no | — | — | yes |"
        ])
    }

    @Test("a package with no test target says so in the rule")
    func noTestTarget() throws {
        let signal = try SignalHarness.signal(.untestedProperty, of: try Self.snapshot(tests: false))

        #expect(signal.rule == UntestedProperty.rule + "; the package has no test target, so no test can be found")
        // A7, scoring 95, is untested now that its stub is gone.
        #expect(signal.items.map(\.property?.identity) == [
            "0x00000000000000A7", "0x00000000000000C3", "0x00000000000000A1", "0x00000000000000C9", "0x00000000000000B2"
        ])
    }

    /// The tool's scores are far from an `Int`'s end, so this row is
    /// written by hand: Verified's 50 is added in `Double`, as the item's
    /// score is held, where it can't overflow.
    @Test("""
        a Verified suggestion whose score is the largest an Int holds is listed with Verified's 50 added \
        instead of trapping
        """)
    func largestScore() throws {
        let row = Row(
            identity: "0x00000000000000B1",
            location: "\(Self.values):4",
            score: Int.max,
            tier: "Likely",
            fingerprint: "\"FB1\""
        )
        let records = """
            {"records": [
              {"identityHash": "00000000000000B1", "outcome": "measured-bothPass", "subjectFingerprint": "FB1"}
            ], "schemaVersion": 1}
            """
        let files = ["Sources/Core/Values.swift": PropertyHarness.values, ".swiftinfer/verify-evidence.json": records]
        let targets = [PropertyHarness.target("Core", "library", "Sources/Core", ["Values.swift"])]
        let snapshot = try SignalHarness.stored(
            files,
            targets: targets,
            indexes: ["Core": PropertyHarness.index([row])]
        )
        let signal = try SignalHarness.signal(.untestedProperty, of: snapshot)

        #expect(snapshot.candidates.map(\.score) == [Int.max])
        #expect(signal.items.map(\.property?.identity) == ["0x00000000000000B1"])
        #expect(signal.items.map(\.property?.verified) == [true])
        #expect(signal.items.map(\.score) == [Double(Int.max) + Double(UntestedProperty.verifiedBonus)])
        // The sum rounds to 2^63, printed as the shortest decimal that reads back as it.
        #expect(SignalHarness.rows(signal).last == "| 1 | `Money::func doubled() -> Money` "
            + "(Sources/Core/Values.swift:4) | 9223372036854776000 | idempotence | Likely / 9223372036854775807 "
            + "| yes | no | — | — | yes |")
    }

    /// Past 2^53 a `Double` can't hold every `Int`, so Verified's 50 is
    /// added in `Int` and the sum rounded once: 2^53 + 51 rounds to
    /// 2^53 + 52, where rounding the score first would give 2^53 + 50.
    @Test("a Verified suggestion's score past 2^53 is its exact sum with Verified's 50, rounded once")
    func scorePastDoublePrecision() throws {
        let row = Row(
            identity: "0x00000000000000B1",
            location: "\(Self.values):4",
            score: 9_007_199_254_740_993,
            tier: "Likely",
            fingerprint: "\"FB1\""
        )
        let records = """
            {"records": [
              {"identityHash": "00000000000000B1", "outcome": "measured-bothPass", "subjectFingerprint": "FB1"}
            ], "schemaVersion": 1}
            """
        let files = ["Sources/Core/Values.swift": PropertyHarness.values, ".swiftinfer/verify-evidence.json": records]
        let targets = [PropertyHarness.target("Core", "library", "Sources/Core", ["Values.swift"])]
        let snapshot = try SignalHarness.stored(
            files,
            targets: targets,
            indexes: ["Core": PropertyHarness.index([row])]
        )
        let signal = try SignalHarness.signal(.untestedProperty, of: snapshot)

        #expect(snapshot.candidates.map(\.score) == [9_007_199_254_740_993])
        #expect(signal.items.map(\.property?.verified) == [true])
        #expect(signal.items.map(\.score) == [9_007_199_254_741_044])
    }
}
