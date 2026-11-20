import Foundation
@testable import SwiftStatsCore
import Testing

/// The `@CheckProperty` link (PRD §7.11): the macro expands into a test of
/// one law, so it links only a suggestion of that law's template.
@Suite("Property macro links")
struct PropertyMacroLinkTests {
    private typealias Row = PropertyHarness.Row

    /// The library's file: a codec whose partner carries `.idempotent`, a
    /// bag with `.idempotent`, `.preservesInvariant` and an argument the
    /// macro rejects, and two codecs with `.roundTrip` on either side.
    private static let source = """
        public struct Token: Equatable {}

        public struct TokenCodec {
            public func encode(_ token: Token) -> String {
                ""
            }

            @CheckProperty(.idempotent)
            public func decode(_ text: String) -> Token {
                Token()
            }
        }

        public struct Bag: Equatable {
            @CheckProperty(.idempotent)
            public func merge(_ other: Bag) -> Bag {
                self
            }

            @CheckProperty(.preservesInvariant(\\.isValid))
            public func clamped(_ other: Bag) -> Bag {
                self
            }

            @CheckProperty(.idempotent())
            public func trimmed(_ other: Bag) -> Bag {
                self
            }
        }

        public struct Codec {
            @CheckProperty(.roundTrip(pairedWith: "decode"))
            public func encode(_ value: Int) -> String {
                String(value)
            }

            public func decode(_ text: String) -> Int {
                Int(text) ?? 0
            }
        }

        public struct Wire {
            public func encode(_ value: Int) -> String {
                String(value)
            }

            @CheckProperty(.roundTrip(pairedWith: "encode"))
            public func decode(_ text: String) -> Int {
                Int(text) ?? 0
            }
        }
        """

    /// A row of `template` on `function(_:)` in `type`, paired with
    /// `partner(_:)` when one is given.
    private static func row(
        _ identity: String,
        _ template: String,
        _ function: String,
        in type: String,
        partner: String? = nil
    ) -> Row {
        let line = SignalHarness.line(of: "func \(function)(", after: "struct \(type)", in: source)
        return Row(
            identity: identity,
            location: "@ROOT@/Sources/Core/Values.swift:\(line)",
            template: template,
            function: "\(function)(_:)",
            extra: partner.map { ", \"secondaryFunctionName\": \"\($0)(_:)\"" } ?? ""
        )
    }

    /// How each candidate the tool writes as `rows` for the library's file
    /// is tested, by identity; every one must attach to a function.
    private static func testedBy(_ rows: [Row]) throws -> [String: String] {
        let package = try PropertyHarness.package(["Sources/Core/Values.swift": source])
        defer { package.remove() }
        let tool = try FakeTool.makeIndexer(
            indexes: [
                "Core": PropertyHarness.index(rows),
                "Macros": PropertyHarness.emptyIndex,
                "Tool": PropertyHarness.emptyIndex
            ],
            errors: [:],
            statuses: [:],
            delays: [:]
        )
        defer { PropertyHarness.remove(tool) }
        let candidates = try #require(try package.scan(tools: PropertyHarness.locator(tool)).properties).candidates
        try #require(candidates.allSatisfy { $0.location?.attachedTo == .function })
        return Dictionary(uniqueKeysWithValues: candidates.map { ($0.identity, $0.testedBy?.rawValue ?? "none") })
    }

    @Test("""
        a @CheckProperty links only a suggestion of the law it checks: idempotence for .idempotent, invariant \
        preservation for .preservesInvariant, and a round trip for .roundTrip paired with the other function, \
        on either one; an argument the macro rejects links nothing
        """)
    func macroLinksItsOwnLaw() throws {
        let rows = [
            Self.row("0x00000000000000F1", "round-trip", "encode", in: "TokenCodec", partner: "decode"),
            Self.row("0x00000000000000F2", "commutativity", "merge", in: "Bag"),
            Self.row("0x00000000000000F3", "idempotence", "merge", in: "Bag"),
            Self.row("0x00000000000000F4", "invariant-preservation", "clamped", in: "Bag"),
            Self.row("0x00000000000000F5", "idempotence", "clamped", in: "Bag"),
            Self.row("0x00000000000000F6", "idempotence", "trimmed", in: "Bag"),
            Self.row("0x00000000000000F7", "round-trip", "encode", in: "Codec", partner: "decode"),
            Self.row("0x00000000000000F8", "round-trip", "decode", in: "Codec", partner: "encode"),
            Self.row("0x00000000000000F9", "round-trip", "encode", in: "Wire", partner: "decode"),
            Self.row("0x00000000000000FA", "idempotence", "decode", in: "Wire")
        ]

        #expect(try Self.testedBy(rows) == [
            // `.idempotent` on the partner checks no round trip.
            "0x00000000000000F1": "none",
            "0x00000000000000F2": "none",
            "0x00000000000000F3": "macro",
            "0x00000000000000F4": "macro",
            "0x00000000000000F5": "none",
            // `.idempotent()` is no case the macro reads.
            "0x00000000000000F6": "none",
            "0x00000000000000F7": "macro",
            "0x00000000000000F8": "macro",
            "0x00000000000000F9": "macro",
            "0x00000000000000FA": "none"
        ])
    }
}
