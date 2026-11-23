//
//  PropertyTargetSamples.swift
//  SwiftStatsCoreTests
//
//  The package best property-test target's tests read (M6, design §7.3):
//  `Money`'s methods with suggestions of every tier, a round trip whose
//  partner has its own suggestion, a Verified row, a generated property
//  test, a blocked Advisory row, rejected and disproven rows, rows on a
//  test, a generated file and no function, an interaction row, files whose
//  results are unresolved and unlisted, and each function's mutants.
//

import Foundation
@testable import SwiftStatsCore

/// The best property-test target tests' package.
enum PropertyTargetSamples {
    /// The harness's rows.
    typealias Row = PropertyHarness.Row
    /// The harness.
    typealias Harness = PropertyTargetHarness

    /// The library's main file, as rows name it.
    static let values = Harness.valuesPath

    /// The key of `encoded(_:)`.
    static let encoded = Harness.key("func encoded(_: Int) -> String")
    /// The key of `decoded(_:)`.
    static let decoded = Harness.key("func decoded(_: String) -> Int")
    /// The key of `doubled(_:)`.
    static let doubled = Harness.key("func doubled(_: Int) -> Int")
    /// The key of `halved(_:)`.
    static let halved = Harness.key("func halved(_: Int) -> Int")
    /// The key of `clamped(_:)`.
    static let clamped = Harness.key("func clamped(_: Int) -> Int")
    /// The key of `hidden(_:)`, a private method: its key names its file.
    static let hidden = Harness.key("func hidden(_: Int) -> Int @ Sources/Core/Values.swift")
    /// The key of `built(_:)`.
    static let built = Harness.key("func built(_: Int) -> Int")

    /// A file whose results are unresolved.
    static let moved = "Sources/Core/Moved.swift"
    /// A file whose results are unlisted.
    static let fresh = "Sources/Core/Fresh.swift"
    /// A generated file.
    static let made = "Sources/Core/Made.swift"
    /// The generated property test checking C1.
    static let stubPath = "Tests/CoreTests/Generated/SwiftInfer/idempotence/DoubledTests.swift"

    /// A structural blocker, as JSON.
    static let blocker = "\"private\""
    /// A round trip's partner, as the row's extra field.
    static let partner = ", \"secondaryFunctionName\": \"decoded(_:)\""

    /// The score of the Likely rows that don't matter to the order.
    static let likelyScore = 45
    /// A1's score: Likely.
    static let roundTripScore = 50
    /// A2's score: Possible.
    static let secondRoundTripScore = 30
    /// B1's score: Possible, Verified by fresh evidence.
    static let verifiedScore = 35
    /// D1's score: Strong.
    static let halvedScore = 90
    /// E1's score: Strong, held at Advisory.
    static let advisoryScore = 95
    /// F2's score: Strong, disproven.
    static let disprovenScore = 85
    /// C2's score: Strong, above C1's and B1's with Verified's bonus.
    static let strongerScore = 90

    /// Suggestions of each kind the signal reads or drops. A1 and A2 are
    /// round trips of `encoded` naming `decoded`; B1 is Verified; C1 has a
    /// generated test; E1 is a blocked Advisory row; F1 is rejected and F2
    /// disproven; the last three are on a test, a generated file and no
    /// function.
    static let rows = [
        Row(
            identity: "0x00000000000000A1",
            location: at("encoded"),
            template: "round-trip",
            function: "encoded(_:)",
            score: roundTripScore,
            tier: "Likely",
            extra: partner
        ),
        Row(
            identity: "0x00000000000000A2",
            location: at("encoded"),
            template: "round-trip",
            function: "encoded(_:)",
            score: secondRoundTripScore,
            tier: "Possible",
            extra: partner
        ),
        Row(
            identity: "0x00000000000000B1",
            location: at("decoded"),
            function: "decoded(_:)",
            score: verifiedScore,
            tier: "Possible",
            fingerprint: "\"FB\""
        ),
        Row(identity: "0x00000000000000C1", location: at("doubled"), function: "doubled(_:)"),
        Row(identity: "0x00000000000000D1", location: at("halved"), function: "halved(_:)", score: halvedScore),
        Row(
            identity: "0x00000000000000E1",
            location: at("clamped"),
            function: "clamped(_:)",
            score: advisoryScore,
            tier: "Advisory",
            blocker: blocker
        ),
        Row(identity: "0x00000000000000F1", location: at("hidden"), function: "hidden(_:)"),
        Row(
            identity: "0x00000000000000F2",
            location: at("hidden"),
            function: "hidden(_:)",
            score: disprovenScore,
            fingerprint: "\"FF\""
        ),
        Row(identity: "0x00000000000000B7", location: at("built"), score: likelyScore, tier: "Likely"),
        Row(identity: "0x00000000000000B8", location: at("bare"), score: likelyScore, tier: "Likely"),
        Row(identity: "0x00000000000000B9", location: at("func", in: moved, source: movedSource), score: likelyScore),
        Row(identity: "0x00000000000000BA", location: at("func", in: fresh, source: freshSource), score: likelyScore),
        Row(
            identity: "0x00000000000000BB",
            location: at("#expect", in: "Tests/CoreTests/MoneyTests.swift", source: Harness.tests)
        ),
        Row(identity: "0x00000000000000BC", location: at("func", in: made, source: madeSource)),
        Row(identity: "0x00000000000000BD", location: "(unknown)", function: "(unknown)")
    ]

    /// A Strong reducer invariant: an interaction row, never read.
    static let interaction = """
        {"family": "determinism", "identityHash": "0x00000000000000D7",
         "location": "@ROOT@/Sources/Core/Values.swift:10",
         "reducerQualifiedName": "reduce", "score": 80, "tier": "Strong"}
        """

    /// The package's decisions: F1 rejected.
    static let decisions = """
        {"records": [{"decision": "rejected", "identityHash": "00000000000000F1", "tier": "strong"}],
         "schemaVersion": 2}
        """

    /// The package's verify evidence: B1 verified, F2 disproven, both fresh.
    static let evidence = """
        {"records": [
          {"identityHash": "00000000000000B1", "outcome": "measured-bothPass", "subjectFingerprint": "FB"},
          {"identityHash": "00000000000000F2", "outcome": "measured-defaultFails", "subjectFingerprint": "FF"}
        ], "schemaVersion": 1}
        """

    /// The package's verify evidence without B1's record: F2 disproven, B1
    /// no longer Verified.
    static let evidenceWithoutVerified = """
        {"records": [
          {"identityHash": "00000000000000F2", "outcome": "measured-defaultFails", "subjectFingerprint": "FF"}
        ], "schemaVersion": 1}
        """

    /// A second suggestion on `doubled`, outweighing C1 though its identity
    /// is larger and it is written after: it ranks first only by weight.
    static let strongerDoubled = Row(
        identity: "0x00000000000000C2",
        location: at("doubled"),
        template: "involution",
        function: "doubled(_:)",
        score: strongerScore
    )

    /// A generated property test for C1.
    static let stub = """
        // Suggestion identity: 0x00000000000000C1
        import Testing
        @testable import Core

        @Test func doubledIsIdempotent() {
            #expect(Money().doubled(Money().doubled(1)) == 4)
        }
        """

    /// The file whose results are unresolved.
    static let movedSource = "func moved(_ value: Int) -> Int {\n    value\n}\n"
    /// The file whose results are unlisted.
    static let freshSource = "func fresh(_ value: Int) -> Int {\n    value\n}\n"
    /// The generated file.
    static let madeSource = "// DO NOT EDIT\nfunc made() -> Int {\n    1\n}\n"

    /// The package's files beyond the harness's own.
    static let files = [
        moved: movedSource,
        fresh: freshSource,
        made: madeSource,
        ".swiftinfer/decisions.json": decisions,
        ".swiftinfer/verify-evidence.json": evidence,
        stubPath: stub
    ]

    /// Each function's mutants.
    static let mutants: [String: [MutationSignalHarness.Planted]] = [
        encoded: [
            .init(verdict: .killed, killedBy: ["roundTrips()"]), .init(verdict: .survived), .init(verdict: .survived)
        ],
        decoded: [.init(verdict: .survived), .init(verdict: .notCovered)],
        doubled: [.init(verdict: .timedOut), .init(verdict: .noCoverage)],
        halved: [.init(verdict: .killed), .init(verdict: .killed)],
        clamped: [.init(verdict: .survived), .init(verdict: .buildError)],
        hidden: [.init(verdict: .survived)],
        built: [.init(verdict: .buildError), .init(verdict: .buildError)]
    ]

    /// Where `function` of `Money` starts, as the tool writes it.
    static func at(_ function: String) -> String {
        Harness.location(values, SignalHarness.line(of: "func \(function)(", after: "", in: Harness.values))
    }

    /// Where `text` first is in the file at `path` of the package, as the
    /// tool writes it.
    static func at(_ text: String, in path: String, source: String) -> String {
        Harness.location(path, SignalHarness.line(of: text, after: "", in: source))
    }

    /// The package as the setup's defaults leave it.
    static func setup() -> Harness.Setup {
        Harness.Setup(
            files: files,
            rows: rows,
            interactions: [interaction],
            mutants: mutants,
            dispositions: [moved: .unresolved, fresh: .unlisted]
        )
    }

    /// The package as the setup's defaults leave it, with `change` applied.
    static func setup(_ change: (inout Harness.Setup) -> Void) -> Harness.Setup {
        var setup = Harness.Setup(
            files: files,
            rows: rows,
            interactions: [interaction],
            mutants: mutants,
            dispositions: [moved: .unresolved, fresh: .unlisted]
        )
        change(&setup)
        return setup
    }
}
