import Foundation
@testable import SwiftStatsCore
import Testing

/// How a pair's partner is found (PRD §7.11): by base name and labels in the
/// primary's file and type, a type and its extensions there being one type;
/// an ambiguous partner stays unresolved.
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

    /// A codec whose `decode` overloads differ by label: `decode(from:)` on
    /// line 4, `encode(_:)` on line 8 and `decode(_:)` on line 12.
    private static let codec = """
        struct Token {}

        struct TokenCodec {
            func decode(from bytes: [UInt8]) -> Token {
                Token()
            }

            func encode(_ token: Token) -> String {
                ""
            }

            func decode(_ text: String) -> Token {
                Token()
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

    /// Each candidate's partner key, by identity, when the library's file
    /// is `source` and the tool writes `rows` for it.
    private static func partnerKeys(_ rows: [PropertyHarness.Row], source: String) throws -> [String: String] {
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
        return Dictionary(uniqueKeysWithValues: candidates.map { ($0.identity, $0.partnerKey ?? "unresolved") })
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

    @Test("a partner resolves by its labels, not to the first overload of its base name")
    func partnerByLabels() throws {
        let rows = [
            Self.pair("0x00000000000000F1", line: 8, function: "encode(_:)", partner: "decode(_:)"),
            Self.pair("0x00000000000000F2", line: 12, function: "decode(_:)", partner: "encode(_:)")
        ]

        #expect(try Self.partnerKeys(rows, source: Self.codec) == [
            "0x00000000000000F1": "Core::TokenCodec::func decode(_: String) -> Token",
            "0x00000000000000F2": "Core::TokenCodec::func encode(_: Token) -> String"
        ])
    }

    @Test("a partner several functions match, by labels or by a bare name, is left unresolved")
    func ambiguousPartner() throws {
        let sameLabels = Self.codec.replacingOccurrences(of: "decode(from bytes:", with: "decode(_ bytes:")
        let rows = [
            Self.pair("0x00000000000000F3", line: 8, function: "encode(_:)", partner: "decode(_:)"),
            Self.pair("0x00000000000000F4", line: 8, function: "encode(_:)", partner: "decode")
        ]

        #expect(try Self.partnerKeys(rows, source: sameLabels) == [
            "0x00000000000000F3": "unresolved",
            "0x00000000000000F4": "unresolved"
        ])
    }

    @Test("a partner never resolves to its own primary, so a same-named inverse resolves to the other overload")
    func partnerIsNotPrimary() throws {
        let converter = """
            struct Celsius {}
            struct Fahrenheit {}

            struct Converter {
                func convert(_ temp: Celsius) -> Fahrenheit {
                    Fahrenheit()
                }

                func convert(_ temp: Fahrenheit) -> Celsius {
                    Celsius()
                }

                func normalized(_ temp: Celsius) -> Celsius {
                    temp
                }
            }
            """
        let rows = [
            Self.pair("0x00000000000000F5", line: 5, function: "convert(_:)", partner: "convert(_:)"),
            Self.pair("0x00000000000000F6", line: 13, function: "normalized(_:)", partner: "normalized(_:)")
        ]

        #expect(try Self.partnerKeys(rows, source: converter) == [
            "0x00000000000000F5": "Core::Converter::func convert(_: Fahrenheit) -> Celsius",
            "0x00000000000000F6": "unresolved"
        ])
    }

    @Test("a record's labels come from its key's declaration, whatever its generics, effects, suffixes or parents")
    func labelsInKeys() {
        #expect(CandidateMapper.labels(named: "decode(_:)") == "(_:)")
        #expect(CandidateMapper.labels(named: "Money.+(lhs:rhs:)") == "(lhs:rhs:)")
        #expect(CandidateMapper.labels(named: "encoded()") == "()")
        #expect(CandidateMapper.labels(named: "decode") == nil)
        let labels = { (key: String, name: String) in CandidateMapper.labels(inKey: key, name: name) }
        #expect(labels("Core::TokenCodec::func decode(from: [UInt8]) -> Token", "decode") == "(from:)")
        #expect(labels("Core::Money::static func ==(lhs: Money, rhs: Money) -> Bool", "==") == "(lhs:rhs:)")
        #expect(labels("Core::func pick<T>(_: T, or: T) -> T where T: Equatable", "pick") == "(_:or:)")
        #expect(labels("Core::func apply(_: (Int) -> Int, to: Int) async throws -> Int #2", "apply") == "(_:to:)")
        #expect(labels("Core::func flagged(_: Int) -> Int #if DEBUG", "flagged") == "(_:)")
        #expect(labels("Core::func outer(at: Int) -> Int::func inner(_: Int) -> Int", "inner") == "(_:)")
        #expect(labels("Core::Money::var count: Int { get }::func now() -> Int", "now") == "()")
        #expect(labels("Core::func decodedValue(_: Int) -> Int", "decoded") == nil)
    }
}
