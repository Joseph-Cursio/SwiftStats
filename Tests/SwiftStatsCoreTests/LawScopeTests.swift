//
//  LawScopeTests.swift
//  SwiftStatsCoreTests
//
//  Which type a law-detection name means (PRD §7.11): a file-private type
//  is its own subject per file, a type nested in a module-qualified or
//  bound generic extension takes the extended type's path, a generic
//  parameter or associated type named in an extension or protocol names
//  no package type, a check reads through typealiases, and a file-scope
//  `==` or `<` is its parameters' type's witness.
//

@testable import SwiftStatsCore
import Testing

@Suite("Law name scope")
struct LawScopeTests {
    /// The checks law detection gives for production `sources` of module
    /// Core, each a file path and its text.
    private static func checks(_ sources: [(String, String)]) -> [String] {
        let facts = sources.map { file, text in
            LawHarness.facts(text, file: file, module: "Core", isTest: false)
        }
        return LawCheckCollector.detect(facts, generatedFiles: []).checks.map(LawCheckTests.describe)
    }

    @Test("same-named file-private types in two files are separate subjects, each with its own kind and witnesses")
    func fileScopedNamesakes() {
        let checks = Self.checks([
            (
                "Sources/Core/A.swift",
                """
                private struct Key: Hashable {
                    var value: Int
                    static func == (lhs: Key, rhs: Key) -> Bool { true }
                }
                """
            ),
            ("Sources/Core/B.swift", "private struct Key: Hashable { var value: Int }\n"),
            ("Sources/Core/C.swift", "private struct Entry: Equatable { var value: Int }\n"),
            ("Sources/Core/D.swift", "private final class Entry: Codable { var value = 0 }\n")
        ])

        #expect(checks == [
            "Core::Entry @ Sources/Core/C.swift Equatable declared synthesized notRun - Sources/Core/C.swift:1",
            "Core::Entry @ Sources/Core/D.swift Codable declared synthesized notRun - Sources/Core/D.swift:1",
            "Core::Key @ Sources/Core/A.swift Hashable declared custom notRun - Sources/Core/A.swift:1",
            "Core::Key @ Sources/Core/B.swift Hashable declared synthesized notRun - Sources/Core/B.swift:1"
        ])
    }

    @Test("an extension reaches its own file's private type, and #if twins in one file stay one subject")
    func fileScopedExtensions() {
        let checks = Self.checks([
            ("Sources/Core/A.swift", "private struct Key: Hashable { var value: Int }\n"),
            (
                "Sources/Core/B.swift",
                """
                fileprivate struct Key: Hashable { var value: Int }
                extension Key { static func == (lhs: Key, rhs: Key) -> Bool { true } }
                extension Key: Comparable { static func < (lhs: Key, rhs: Key) -> Bool { true } }
                """
            ),
            (
                "Sources/Core/C.swift",
                "#if DEBUG\nprivate struct Twin: Equatable {}\n#else\nprivate final class Twin: Equatable {}\n#endif\n"
            )
        ])

        #expect(checks == [
            "Core::Key @ Sources/Core/A.swift Hashable declared synthesized notRun - Sources/Core/A.swift:1",
            "Core::Key @ Sources/Core/B.swift Comparable declared custom notRun - Sources/Core/B.swift:3",
            "Core::Key @ Sources/Core/B.swift Hashable declared custom notRun - Sources/Core/B.swift:1",
            "Core::Twin @ Sources/Core/C.swift Equatable declared custom notRun - Sources/Core/C.swift:2"
        ])
    }

    @Test("a type nested in a module-qualified extension takes the extended type's path, so checks on it attach")
    func moduleQualifiedExtension() {
        let modules: Set<String> = ["Core", "Extras", "CoreTests"]
        let core = LawHarness.facts(
            "public struct Money {}\nextension Core.Money { public enum Currency: String, Equatable { case usd } }\n",
            file: "Sources/Core/Money.swift",
            module: "Core",
            isTest: false,
            modules: modules
        )
        let extras = LawHarness.facts(
            "import Core\nextension Core.Money { public struct Rate: Equatable { public var value: Int } }\n",
            file: "Sources/Extras/Rate.swift",
            module: "Extras",
            isTest: false,
            modules: modules
        )
        let tests = LawHarness.facts(
            """
            func checks() async throws {
                try await checkEquatablePropertyLaws(for: Money.Currency.self)
                try await checkEquatablePropertyLaws(for: Money.Rate.self)
            }
            """,
            file: "Tests/CoreTests/LawTests.swift",
            module: "CoreTests",
            isTest: true,
            modules: modules
        )

        let report = LawCheckCollector.detect([core, extras, tests], generatedFiles: [])

        #expect(report.checks.map(LawCheckTests.describe) == [
            "Core::Money.Currency Equatable declared synthesized run call Sources/Core/Money.swift:2",
            "Core::Money.Currency RawRepresentable rawType synthesized notRun - Sources/Core/Money.swift:2",
            "Extras::Money.Rate Equatable declared synthesized run call Sources/Extras/Rate.swift:2"
        ])
        #expect(report.unresolvedCalls == 0)
    }

    @Test("an extension written with generic arguments extends the generic type, and what it nests is under it")
    func boundGenericExtension() {
        let production = LawHarness.facts(
            """
            public struct Wrap<Value> { var value: Value }
            extension Wrap<Int>: Equatable {}
            extension Wrap<Int> { public struct Inner: Hashable {} }
            """,
            file: "Sources/Lib/Wrap.swift",
            module: "Lib",
            isTest: false
        )
        let tests = LawHarness.facts(
            "func check() async throws { try await checkEquatablePropertyLaws(for: Wrap<Int>.self) }\n",
            file: "Tests/LibTests/WrapTests.swift",
            module: "LibTests",
            isTest: true
        )

        let checks = LawCheckCollector.detect([production, tests], generatedFiles: []).checks
        #expect(checks.map(LawCheckTests.describe) == [
            "Lib::Wrap Equatable declared synthesized run call Sources/Lib/Wrap.swift:2",
            "Lib::Wrap.Inner Hashable declared synthesized notRun - Sources/Lib/Wrap.swift:3"
        ])
    }

    @Test("a generic parameter or associated type an extension or protocol binds names no package type")
    func boundNames() {
        let production = LawHarness.facts(
            "public struct Element: Hashable {}\npublic struct Value: Hashable {}\npublic struct Other: Hashable {}\n",
            file: "Sources/Lib/Types.swift",
            module: "Lib",
            isTest: false
        )
        let tests = LawHarness.facts(
            """
            extension Array where Element: Hashable {
                func check() async throws {
                    try await checkHashablePropertyLaws(for: Element.self)
                    try await checkHashablePropertyLaws(for: Other.self)
                }
            }
            protocol LawSuite { associatedtype Value: Hashable }
            extension LawSuite {
                func run() async throws { try await checkHashablePropertyLaws(for: Value.self) }
            }
            protocol Sized {
                #if DEBUG
                associatedtype Value: Hashable
                #endif
            }
            extension Sized {
                func run() async throws { try await checkHashablePropertyLaws(using: Value.gen()) }
            }
            """,
            file: "Tests/LibTests/Suites.swift",
            module: "LibTests",
            isTest: true
        )

        let report = LawCheckCollector.detect([production, tests], generatedFiles: [])

        #expect(report.checks.map(LawCheckTests.describe) == [
            "Lib::Element Hashable declared synthesized notRun - Sources/Lib/Types.swift:1",
            "Lib::Other Hashable declared synthesized run call Sources/Lib/Types.swift:3",
            "Lib::Value Hashable declared synthesized notRun - Sources/Lib/Types.swift:2"
        ])
        #expect(report.unresolvedCalls == 3)
    }

    @Test("a check reads through typealiases to the type they name, and one naming no plain type is unresolved")
    func typealiases() {
        let production = LawHarness.facts(
            """
            public struct Tagged: Equatable {}
            public struct Money: Equatable {}
            public struct Pin: Hashable {}
            public struct Wallet: Equatable {}
            public typealias Cash = Wallet
            """,
            file: "Sources/Core/Values.swift",
            module: "Core",
            isTest: false
        )
        let tests = LawHarness.facts(
            """
            private typealias SUT = Tagged
            private typealias Both = (Tagged, Tagged)
            struct AliasTests {
                func tagged() async throws { try await checkEquatablePropertyLaws(for: SUT.self, using: SUT.gen()) }
                func money() async throws {
                    typealias Money = Core.Money
                    try await checkEquatablePropertyLaws(for: Money.self, using: Money.gen())
                }
                func pin() async throws {
                    struct Pin: Hashable {}
                    typealias Local = Pin
                    try await checkHashablePropertyLaws(for: Local.self, using: Local.gen())
                }
                func cash() async throws { try await checkEquatablePropertyLaws(for: Cash.self) }
                func both() async throws { try await checkEquatablePropertyLaws(for: Both.self) }
            }
            """,
            file: "Tests/CoreTests/AliasTests.swift",
            module: "CoreTests",
            isTest: true
        )

        let report = LawCheckCollector.detect([production, tests], generatedFiles: [])

        #expect(report.checks.map(LawCheckTests.describe) == [
            "Core::Money Equatable declared synthesized run call Sources/Core/Values.swift:2",
            "Core::Pin Hashable declared synthesized notRun - Sources/Core/Values.swift:3",
            "Core::Tagged Equatable declared synthesized run call Sources/Core/Values.swift:1",
            "Core::Wallet Equatable declared synthesized run call Sources/Core/Values.swift:4"
        ])
        #expect(report.unresolvedCalls == 1)
    }

    @Test("a file-scope == or < taking two of a type is its witness, in any file of the module")
    func operatorWitnesses() {
        let checks = Self.checks([
            (
                "Sources/Core/Types.swift",
                """
                public struct Gauge: Equatable { var value: Int }
                public func == (lhs: Gauge, rhs: Gauge) -> Bool { lhs.value == rhs.value }
                public struct Height: Comparable { var value: Int }
                public struct Plain: Equatable { var value: Int }
                public struct Other: Equatable { var value: Int }
                public func == (lhs: Plain, rhs: Other) -> Bool { false }
                """
            ),
            ("Sources/Core/Order.swift", "public func < (lhs: Height, rhs: Height) -> Bool { lhs.value < rhs.value }\n")
        ])

        #expect(checks == [
            "Core::Gauge Equatable declared custom notRun - Sources/Core/Types.swift:1",
            "Core::Height Comparable declared custom notRun - Sources/Core/Types.swift:3",
            "Core::Other Equatable declared synthesized notRun - Sources/Core/Types.swift:5",
            "Core::Plain Equatable declared synthesized notRun - Sources/Core/Types.swift:4"
        ])
    }
}
