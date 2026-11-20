//
//  LawCheckTests.swift
//  SwiftStatsCoreTests
//
//  Law detection (PRD §7.11): the Laws fixture's pairs, each worked out by
//  hand from its sources (see the comments there), and the rules behind
//  them: provenance, implementation, each state, `.ownOnly`, the
//  floating-point waiver, kit-name gating, name resolution, and the
//  conformances that make no pair.
//

import Foundation
@testable import SwiftStatsCore
import Testing

@Suite("Law checks")
struct LawCheckTests {
    /// Every pair of the Laws fixture: type, protocol, provenance,
    /// implementation, state, evidence and where it is declared.
    private static let expected = [
        "Core::Bare Identifiable declared custom notRun - Sources/Extras/Extras.swift:19",
        "Core::Code RawRepresentable declared custom notRun - Sources/Core/Values.swift:19",
        "Core::Envelope Codable declared custom notRun - Sources/Core/Values.swift:35",
        "Core::Envelope.CodingKeys RawRepresentable rawType synthesized notRun - Sources/Core/Values.swift:36",
        "Core::Fixed AdditiveArithmetic declared custom waived - Sources/Core/Numbers.swift:4",
        "Core::Fixed FloatingPoint declared custom run call Sources/Core/Numbers.swift:4",
        "Core::Fixed Numeric declared custom waived - Sources/Core/Numbers.swift:4",
        "Core::Grade Equatable declared synthesized notRun - Sources/Core/Numbers.swift:19",
        "Core::Grade Hashable declared synthesized run call Sources/Core/Numbers.swift:19",
        "Core::Handle Equatable declared custom notRun - Sources/Core/Equality.swift:16",
        "Core::Handle Hashable declared custom notRun - Sources/Core/Equality.swift:16",
        "Core::Key Hashable declared custom notRun - Sources/Core/Equality.swift:21",
        "Core::Ledger.Entry Equatable declared synthesized run call Sources/Core/Nested.swift:2",
        "Core::Level CaseIterable declared custom notRun - Sources/Core/Values.swift:9",
        "Core::Level RawRepresentable rawType synthesized notRun - Sources/Core/Values.swift:9",
        "Core::Money Comparable declared custom run call Sources/Core/Money.swift:5",
        "Core::Money Hashable declared synthesized notRun - Sources/Core/Money.swift:5",
        "Core::Money Semigroup declared custom run call Sources/Core/Money.swift:13",
        "Core::Payload Codable declared custom notRun - Sources/Core/Values.swift:44",
        "Core::Pin Hashable declared custom notRun - Sources/Core/Equality.swift:29",
        "Core::Point Equatable declared custom notRun - Sources/Core/Equality.swift:2",
        "Core::Point Hashable declared custom notRun - Sources/Extras/Extras.swift:17",
        "Core::Rank Equatable declared synthesized run call Sources/Core/Numbers.swift:24",
        "Core::Rank Hashable declared synthesized run call Sources/Core/Numbers.swift:24",
        "Core::Record Codable codable synthesized notRun - Sources/Core/Values.swift:28",
        "Core::Settings Codable declared synthesized notRun - Sources/Core/Values.swift:61",
        "Core::Size Equatable declared synthesized suppressed marker Sources/Core/Equality.swift:11",
        "Core::Slot Hashable declared custom notRun - Sources/Core/Equality.swift:25",
        "Core::Status CaseIterable declared synthesized notRun - Sources/Core/Values.swift:3",
        "Core::Status Codable declared synthesized notRun - Sources/Core/Values.swift:3",
        "Core::Status RawRepresentable rawType synthesized notRun - Sources/Core/Values.swift:3",
        "Core::Tally Equatable declared synthesized notRun - Sources/Core/Algebra.swift:2",
        "Core::Tier RawRepresentable rawType synthesized notRun - Sources/Core/Nested.swift:20",
        "Core::Tone CaseIterable declared synthesized notRun - Sources/Core/Numbers.swift:10",
        "Core::Tone Codable declared synthesized notRun - Sources/Core/Numbers.swift:16",
        "Core::Tone Comparable declared synthesized run macro Sources/Core/Numbers.swift:10",
        "Core::Tone RawRepresentable rawType synthesized notRun - Sources/Core/Numbers.swift:10",
        "Core::Width Hashable declared synthesized notRun - Sources/Core/Numbers.swift:29",
        "Extras::Team Equatable declared synthesized notRun - Sources/Extras/Extras.swift:7",
        "Extras::Tier RawRepresentable rawType synthesized notRun - Sources/Extras/Extras.swift:12"
    ]

    /// One pair as a line of `expected`.
    static func describe(_ check: LawCheck) -> String {
        [
            check.type, check.protocolName, check.provenance.rawValue, check.implementation.rawValue,
            check.state.rawValue, check.evidence?.rawValue ?? "-", "\(check.file):\(check.line)"
        ].joined(separator: " ")
    }

    @Test("the Laws fixture gives each pair its provenance, implementation, state and evidence")
    func fixturePairs() throws {
        let laws = try LawHarness.scan().laws

        #expect(laws.checks.map(Self.describe) == Self.expected)
        #expect(laws.checks.allSatisfy { $0.generated == false })
    }

    @Test("unnamed and generic subjects are counted, an ambiguous name and test-only conformances attach nowhere")
    func unattached() throws {
        let laws = try LawHarness.scan().laws

        // `using: generator` names no subject, `for: T.self` is a generic
        // parameter; `checkValueSemanticPropertyLaws` isn't one of the 33
        // and a call in a string literal is no call.
        #expect(laws.unresolvedCalls == 2)
        // Core and Extras both declare a top-level `Tier`.
        #expect(laws.ambiguousNames == ["Tier"])
        // `extension Bare: Equatable` and the refactor writeout's
        // `extension Size: Semigroup`, both in the test target.
        #expect(laws.testOnlyConformances == 2)
        #expect(laws.kitDependency == false)
        let protocols = Dictionary(grouping: laws.checks, by: \.type).mapValues { $0.map(\.protocolName) }
        #expect(protocols["Core::Bare"] == ["Identifiable"])
        #expect(protocols["Core::Size"] == ["Equatable"])
        #expect(protocols["Core::Ledger"] == nil)
        #expect(protocols["Core::Profile"] == nil)
        #expect(protocols["Core::Summary"] == nil)
        #expect(laws.checks.contains { $0.type.hasPrefix("CoreTests::") } == false)
    }

    @Test("a kit algebraic protocol counts only where the kit is imported and no package protocol shares its name")
    func algebraicGating() throws {
        let laws = try LawHarness.scan().laws
        let protocols = Dictionary(grouping: laws.checks, by: \.type).mapValues { $0.map(\.protocolName) }

        // Money's file imports the kit; Tally's doesn't; Extras declares
        // its own `Group`.
        #expect(protocols["Core::Money"]?.contains("Semigroup") == true)
        #expect(protocols["Core::Tally"] == ["Equatable"])
        #expect(protocols["Extras::Team"] == ["Equatable"])
    }

    @Test("roll-ups count pairs by state on production scopes only, as swiftstats metrics; notRun is lower-is-better")
    func rollups() throws {
        let report = try LawHarness.scan()
        let byName = Dictionary(uniqueKeysWithValues: report.rollups.map { ($0.name, $0) })

        #expect(byName["Core"]?.laws?.state == ["notRun": 27, "run": 8, "suppressed": 1, "waived": 2])
        #expect(byName["Extras"]?.laws?.state == ["notRun": 2])
        #expect(byName["production"]?.laws?.state == ["notRun": 29, "run": 8, "suppressed": 1, "waived": 2])
        #expect(byName["CoreTests"].map { $0.laws == nil } == true)
        #expect(byName["tests"].map { $0.laws == nil } == true)
        let metrics = try RollupMetrics.metrics(of: try #require(byName["production"]))
        let lawMetrics = metrics.filter { $0.path.hasPrefix("laws.") }
        #expect(lawMetrics.map(\.path) == [
            "laws.state.notRun", "laws.state.run", "laws.state.suppressed", "laws.state.waived"
        ])
        #expect(lawMetrics.allSatisfy { $0.collector == SwiftStatsCollector.name })
        #expect(MetricDirection.of("laws.state.notRun") == .lowerIsBetter)
        #expect(MetricDirection.of("laws.state.run") == .neutral)
    }

    @Test("a SwiftPropertyLaws dependency in Package.swift or a pin in Package.resolved sets kitDependency")
    func kitDependency() throws {
        let declared = DescribedDependency(
            identity: "swiftpropertylaws",
            type: "sourceControl",
            location: "https://github.com/Joseph-Cursio/SwiftPropertyLaws.git",
            requirement: "4.11.0..<5.0.0"
        )
        #expect(try LawHarness.scan(dependencies: [declared]).laws.kitDependency)

        let resolved = """
        {
          "pins" : [
            {
              "identity" : "swiftpropertylaws",
              "kind" : "remoteSourceControl",
              "location" : "https://github.com/Joseph-Cursio/SwiftPropertyLaws.git",
              "state" : { "revision" : "a5ecdab", "version" : "4.11.0" }
            }
          ],
          "version" : 3
        }
        """
        let package = try TemporaryPackage([
            "Sources/Lib/Lib.swift": "public struct Value: Equatable {}\n",
            "Package.resolved": resolved
        ])
        defer { package.remove() }
        let laws = try package.scan(tools: SnapshotHarness.noTools).laws
        #expect(laws.kitDependency)
        #expect(laws.checks.map(Self.describe) == [
            "Lib::Value Equatable declared synthesized notRun - Sources/Lib/Lib.swift:1"
        ])
    }

    @Test("law detection gives the same report whatever order the files come in")
    func fileOrder() throws {
        let facts = try LawHarness.fixtureFacts()
        let generated: Set<String> = ["Tests/CoreTests/PropertyLawTests.generated.swift"]

        let forward = LawCheckCollector.detect(facts, generatedFiles: generated)
        let reversed = LawCheckCollector.detect(facts.reversed(), generatedFiles: generated)

        #expect(forward == reversed)
        #expect(forward.checks.map(Self.describe) == Self.expected)
    }

    @Test("a check means the nested type its enclosing suite or extension declares before a top-level namesake")
    func lexicalScope() {
        let production = LawHarness.facts(
            "public struct Money: Hashable {}\npublic struct Wallet { public struct Money: Hashable {} }\n",
            file: "Sources/Lib/Money.swift",
            module: "Lib",
            isTest: false
        )
        let tests = LawHarness.facts(
            """
            struct Suite {
                struct Money: Hashable {}
                func local() async throws { try await checkHashablePropertyLaws(for: Money.self) }
            }
            extension Wallet {
                func nested() async throws { try await checkHashablePropertyLaws(for: Money.self) }
            }
            """,
            file: "Tests/LibTests/Suite.swift",
            module: "LibTests",
            isTest: true
        )

        let checks = LawCheckCollector.detect([production, tests], generatedFiles: []).checks

        // The first call means `Suite.Money`, a test type; the second,
        // inside `extension Wallet` in the test module, means the production
        // `Wallet.Money` before the top-level `Money`.
        #expect(checks.map(Self.describe) == [
            "Lib::Money Hashable declared synthesized notRun - Sources/Lib/Money.swift:1",
            "Lib::Wallet.Money Hashable declared synthesized run call Sources/Lib/Money.swift:2"
        ])
    }

    @Test("the suite macro runs the most specific emittable protocols and what they inherit, from the primary alone")
    func suiteCoverage() {
        let hashableComparable = KitProtocols.coveredBySuite(inheriting: ["Hashable", "Comparable"])
        #expect(hashableComparable == ["Hashable", "Comparable", "Equatable"])
        // Strideable is never emitted but implies Comparable, which runs Equatable.
        #expect(KitProtocols.coveredBySuite(inheriting: ["Strideable"]) == ["Comparable", "Equatable"])
        #expect(KitProtocols.coveredBySuite(inheriting: ["Encodable", "Decodable", "CaseIterable"]) == ["Codable"])
        // FloatingPoint subsumes Numeric when emitting but doesn't run it.
        #expect(KitProtocols.coveredBySuite(inheriting: ["FloatingPoint", "Numeric"]) == ["FloatingPoint"])
        #expect(KitProtocols.covered(by: "SignedInteger", ownOnly: false) == [
            "SignedInteger", "BinaryInteger", "SignedNumeric", "Numeric", "AdditiveArithmetic"
        ])
        #expect(KitProtocols.covered(by: "SignedInteger", ownOnly: true) == ["SignedInteger"])
        #expect(KitProtocols.known.count == 33)
        #expect(KitProtocols.checkedProtocol(ofFunction: "checkRingPropertyLaws") == "Ring")
        #expect(KitProtocols.checkedProtocol(ofFunction: "checkValueSemanticPropertyLaws") == nil)
    }

    @Test("markers and subjects are read as written, generic arguments stripped")
    func reading() {
        let comment = "    // (checkHashablePropertyLaws for BitSet.Counted suppressed by user marker)"
        let marker = LawCallReader.marker(comment)
        #expect(marker?.protocolName == "Hashable")
        #expect(marker?.typeName == "BitSet.Counted")
        #expect(LawCallReader.marker("// property-law-suppress: hashable_Foo") == nil)
        #expect(LawCallReader.typeName("Deque< Int >") == "Deque")
        #expect(LawCallReader.typeName("Outer.Box<[String: Int]>") == "Outer.Box")
        #expect(LawCallReader.typeName("makeValue()") == nil)

        let facts = LawHarness.facts(
            """
            func check<T: Hashable>(_ value: T) async throws {
                try await checkHashablePropertyLaws(for: T.self, using: T.gen())
                try await checkHashablePropertyLaws(for: Box<Int>.self, laws: .ownOnly)
                try await checkHashablePropertyLaws(sampling: Outer.Box.gen)
                try await checkHashablePropertyLaws(overEvery: Self.gen())
            }
            """,
            file: "Tests/LibTests/Checks.swift",
            module: "LibTests",
            isTest: true
        )
        #expect(facts.calls.map { $0.typeName ?? "-" } == ["-", "Box", "Outer.Box", "-"])
        #expect(facts.calls.map(\.ownOnly) == [false, true, false, false])
    }

    @Test("type records carry their inheritance clause, normalised and sorted")
    func conformances() {
        let types = CollectorHarness.types("""
        struct Wrapped: @unchecked Sendable, Swift.Hashable, PropertyLawKit.Monoid, ~Copyable, Codable & Comparable {}
        extension Int: @retroactive Semigroup {}
        protocol Model: Equatable & Codable {}
        struct Plain {}
        """)

        #expect(types.map(\.conformances) == [
            ["Codable", "Comparable", "Hashable", "Monoid", "Sendable"],
            ["Semigroup"],
            ["Codable", "Equatable"],
            []
        ])
    }

    @Test("the Law checks section counts production pairs by state and says what didn't attach")
    func markdown() throws {
        let lines = MarkdownLaws.render(try LawHarness.scan())

        #expect(lines == [
            "Production conformances to the protocols SwiftPropertyLaws checks. "
                + "The package does not depend on SwiftPropertyLaws.",
            "",
            "| State | Pairs |",
            "| --- | --- |",
            "| suppressed | 1 |",
            "| run | 8 |",
            "| waived | 2 |",
            "| notRun | 29 |",
            "",
            "2 check calls with no subject SwiftStats can name; 1 ambiguous type name; "
                + "2 conformances only test targets declare."
        ])
    }
}
