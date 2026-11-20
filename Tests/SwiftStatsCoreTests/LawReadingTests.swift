//
//  LawReadingTests.swift
//  SwiftStatsCoreTests
//
//  How law detection reads source (PRD §7.11): a check on a type local to
//  the test names no production type, only a coder-typed `init(from:)` or
//  `encode(to:)` is a Codable witness, and `@PropertyLawSuite` reads the
//  primary's inheritance clause exactly as written, as the macro does.
//

@testable import SwiftStatsCore
import Testing

@Suite("Law check reading")
struct LawReadingTests {
    @Test("a check on a type local to the test attaches nowhere, though a production type shares its name")
    func localTypes() {
        let production = LawHarness.facts(
            "public struct Money: Hashable {}\npublic struct Pin: Hashable {}\npublic struct Tag: Hashable {}\n",
            file: "Sources/Lib/Values.swift",
            module: "Lib",
            isTest: false
        )
        let tests = LawHarness.facts(
            """
            struct Suite {
                func local() async throws {
                    struct Money: Hashable {}
                    try await checkHashablePropertyLaws(for: Money.self)
                    let run = {
                        typealias Pin = Money
                        try await checkHashablePropertyLaws(for: Pin.self)
                    }
                    try await run()
                }
                func nested() async throws {
                    struct Outer {
                        struct Tag: Hashable {}
                        func check() async throws { try await checkHashablePropertyLaws(for: Tag.self) }
                    }
                    try await checkHashablePropertyLaws(for: Money.self)
                }
            }
            """,
            file: "Tests/LibTests/Suite.swift",
            module: "LibTests",
            isTest: true
        )

        // Only the last call, outside the body declaring the local `Money`,
        // means Lib's `Money`; none is unresolved.
        #expect(tests.calls.map(\.namesLocalType) == [true, true, true, false])
        let report = LawCheckCollector.detect([production, tests], generatedFiles: [])
        #expect(report.checks.map(LawCheckTests.describe) == [
            "Lib::Money Hashable declared synthesized run call Sources/Lib/Values.swift:1",
            "Lib::Pin Hashable declared synthesized notRun - Sources/Lib/Values.swift:2",
            "Lib::Tag Hashable declared synthesized notRun - Sources/Lib/Values.swift:3"
        ])
        #expect(report.unresolvedCalls == 0)
    }

    @Test("only init(from:) and encode(to:) taking just a Decoder or Encoder are Codable witnesses")
    func codableWitnesses() {
        let facts = LawHarness.facts(
            """
            struct Plain: Codable {
                init(from decoder: Decoder) throws {}
                func encode(to encoder: any Swift.Encoder) throws {}
            }
            struct Opaque: Codable {
                init(from decoder: some Decoder) throws {}
            }
            struct Converting: Codable {
                init(from other: Plain) {}
                init(from decoder: Decoder, strict: Bool) throws {}
                func encode(to sink: inout [String]) {}
            }
            """,
            file: "Sources/Lib/Coding.swift",
            module: "Lib",
            isTest: false
        )

        #expect(facts.declarations.map(\.witnesses) == [[.initFrom, .encodeTo], [.initFrom], []])
    }

    @Test("the suite macro reads the primary's inheritance as written, so a qualified or composed name runs nothing")
    func suiteReadsWrittenNames() {
        let facts = LawHarness.facts(
            """
            @PropertyLawSuite
            public struct Qualified: Swift.Hashable {}
            @PropertyLawSuite
            public struct Composed: Equatable & Codable {}
            @PropertyLawSuite
            public struct Plain: Hashable {}
            """,
            file: "Sources/Lib/Suites.swift",
            module: "Lib",
            isTest: false
        )

        #expect(facts.declarations.map(\.writtenInherited) == [
            ["Swift.Hashable"], ["Equatable & Codable"], ["Hashable"]
        ])
        #expect(LawCheckCollector.detect([facts], generatedFiles: []).checks.map(LawCheckTests.describe) == [
            "Lib::Composed Codable declared synthesized notRun - Sources/Lib/Suites.swift:3",
            "Lib::Composed Equatable declared synthesized notRun - Sources/Lib/Suites.swift:3",
            "Lib::Plain Hashable declared synthesized run macro Sources/Lib/Suites.swift:5",
            "Lib::Qualified Hashable declared synthesized notRun - Sources/Lib/Suites.swift:1"
        ])
    }
}
