//
//  LawVisibilityTests.swift
//  SwiftStatsCoreTests
//
//  Which candidates a law-detection name has, and which file-scope
//  operators a conformance sees (PRD §7.11): a typealias naming a type the
//  search already found is no second candidate, nor is an alias reading
//  that names no package type; a file-scope `==` or `<` is a witness only
//  where Swift would find it, in its module and, if private, its file.
//

@testable import SwiftStatsCore
import Testing

@Suite("Law name visibility")
struct LawVisibilityTests {
    @Test("a typealias re-exporting a type from another module names that type, not a second candidate")
    func reExportedTypealias() {
        let modules: Set<String> = ["Core", "Extras", "ExtrasTests"]
        let core = LawHarness.facts(
            "public struct Money: Equatable { public var cents: Int }\n",
            file: "Sources/Core/Money.swift",
            module: "Core",
            isTest: false,
            modules: modules
        )
        let extras = LawHarness.facts(
            "import Core\npublic typealias Money = Core.Money\n",
            file: "Sources/Extras/Exports.swift",
            module: "Extras",
            isTest: false,
            modules: modules
        )
        let tests = LawHarness.facts(
            "import Extras\nfunc check() async throws { try await checkEquatablePropertyLaws(for: Money.self) }\n",
            file: "Tests/ExtrasTests/MoneyTests.swift",
            module: "ExtrasTests",
            isTest: true,
            modules: modules
        )

        let report = LawCheckCollector.detect([core, extras, tests], generatedFiles: [])

        #expect(report.checks.map(LawCheckTests.describe) == [
            "Core::Money Equatable declared synthesized run call Sources/Core/Money.swift:1"
        ])
        #expect(report.ambiguousNames.isEmpty)
    }

    @Test("a type nested in an extension written through a typealias keeps that path for checks and extensions")
    func typeNestedThroughTypealias() {
        let production = LawHarness.facts(
            """
            public struct Wallet: Equatable {}
            public typealias Cash = Wallet
            extension Cash { public struct Inner: Hashable { public var value: Int } }
            extension Cash.Inner: Comparable {
                public static func < (lhs: Self, rhs: Self) -> Bool { lhs.value < rhs.value }
            }
            """,
            file: "Sources/Core/Wallet.swift",
            module: "Core",
            isTest: false
        )
        let tests = LawHarness.facts(
            "func check() async throws { try await checkHashablePropertyLaws(for: Cash.Inner.self) }\n",
            file: "Tests/CoreTests/WalletTests.swift",
            module: "CoreTests",
            isTest: true
        )

        let report = LawCheckCollector.detect([production, tests], generatedFiles: [])

        #expect(report.checks.map(LawCheckTests.describe) == [
            "Core::Cash.Inner Comparable declared custom notRun - Sources/Core/Wallet.swift:4",
            "Core::Cash.Inner Hashable declared synthesized run call Sources/Core/Wallet.swift:3",
            "Core::Wallet Equatable declared synthesized notRun - Sources/Core/Wallet.swift:1"
        ])
        #expect(report.ambiguousNames.isEmpty)
    }

    @Test("a file-scope == counts only where the conformance can see it: its file if private, else its module")
    func operatorWitnessVisibility() {
        let modules: Set<String> = ["Core", "Extras"]
        let types = LawHarness.facts(
            """
            public struct Gauge: Equatable { var value: Int }
            public struct Meter: Equatable { var value: Int }
            public struct Dial { var value: Int }
            private struct Tag: Equatable { var value: Int }
            private func == (lhs: Tag, rhs: Tag) -> Bool { false }
            """,
            file: "Sources/Core/Types.swift",
            module: "Core",
            isTest: false,
            modules: modules
        )
        let operators = LawHarness.facts(
            "private func == (lhs: Gauge, rhs: Gauge) -> Bool { false }\n",
            file: "Sources/Core/Ops.swift",
            module: "Core",
            isTest: false,
            modules: modules
        )
        let extras = LawHarness.facts(
            """
            import Core
            public func == (lhs: Meter, rhs: Meter) -> Bool { false }
            extension Dial: Equatable {}
            public func == (lhs: Dial, rhs: Dial) -> Bool { false }
            """,
            file: "Sources/Extras/Ops.swift",
            module: "Extras",
            isTest: false,
            modules: modules
        )

        let report = LawCheckCollector.detect([types, operators, extras], generatedFiles: [])

        #expect(report.checks.map(LawCheckTests.describe) == [
            "Core::Dial Equatable declared custom notRun - Sources/Extras/Ops.swift:3",
            "Core::Gauge Equatable declared synthesized notRun - Sources/Core/Types.swift:1",
            "Core::Meter Equatable declared synthesized notRun - Sources/Core/Types.swift:2",
            "Core::Tag @ Sources/Core/Types.swift Equatable declared custom notRun - Sources/Core/Types.swift:4"
        ])
    }
}
