import Foundation
@testable import SwiftStatsCore
import Testing

/// How a pair's partner is found (PRD §7.11): by base name in the primary's
/// file and type, a type and its extensions there being one type.
@Suite("Property partners")
struct PropertyPartnerTests {
    /// The library's file: `decoded(_:)` in another type, then `Money`
    /// with `encoded()` and an extension of it with `decoded(_:)`. Line
    /// numbers matter: rows name them.
    private static let source = """
        struct Other {
            static func decoded(_ text: String) -> Other {
                Other()
            }
        }

        struct Money {
            var cents: Int

            func encoded() -> String {
                String(cents)
            }
        }

        extension Money {
            static func decoded(_ text: String) -> Money {
                Money(cents: Int(text) ?? 0)
            }
        }
        """

    /// A round-trip row on `function` at `line` of the library's file,
    /// paired with `partner`.
    private static func pair(_ identity: String, line: Int, function: String, partner: String) -> PropertyHarness.Row {
        PropertyHarness.Row(
            identity: identity,
            location: "@ROOT@/Sources/Core/Values.swift:\(line)",
            template: "round-trip",
            function: function,
            extra: ", \"secondaryFunctionName\": \"\(partner)\""
        )
    }

    @Test("""
        a partner in an extension of the primary's type in its file is found, either way round, and one \
        of the same name in another type is not
        """)
    func partnerInExtension() throws {
        let rows = [
            Self.pair("0x00000000000000E1", line: 10, function: "encoded()", partner: "decoded(_:)"),
            Self.pair("0x00000000000000E2", line: 16, function: "decoded(_:)", partner: "encoded()")
        ]
        let package = try PropertyHarness.package(["Sources/Core/Values.swift": Self.source])
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

        let report = try package.scan(tools: PropertyHarness.locator(tool))

        let candidates = try #require(report.properties).candidates
        let key = { (name: String, line: Int) in
            report.records.first { $0.name == name && $0.range.start.line == line }?.key
        }
        let decoded = try #require(key("decoded", 16))
        let encoded = try #require(key("encoded", 10))
        #expect(candidates.map(\.location?.owner) == [encoded, decoded])
        #expect(candidates.map(\.partnerKey) == [decoded, encoded])
    }
}
