import Foundation
@testable import SwiftStatsCore
import Testing

/// outskirts' JSON read on Unicode scalars and through `JSONSerialization`
/// (design B23, decided U13): a hint's parentheses are found among
/// scalars, so a combining mark or a Prepend scalar beside one stays in
/// the text; and a string's leading byte order mark is lost as
/// `JSONSerialization` reads the output, where JSON (RFC 8259) and the
/// checker's `json.loads` keep it (B29, awaiting U17: pinned as a known
/// issue).
extension PeripheryOutputTests {
    /// An entry's JSON object at `location`, of `kind`, holding `hints`,
    /// its other fields sound.
    static func scalarEntry(location: String, kind: String, hints: [String]) -> [String: Any] {
        [
            "accessibility": "internal", "attributes": [String](), "hints": hints, "ids": ["s:9IndexCore1fyyF"],
            "kind": kind, "location": location, "modifiers": [String](), "modules": ["IndexCore"], "name": "f()"
        ]
    }

    @Test(
        """
        a hint written name(text) splits on scalars, so text starting with a combining mark, which joins the \
        opening parenthesis into one Character, or ending in a Prepend scalar, which joins the closing one, stays \
        the text (design B23, decided U13)
        """,
        arguments: [
            ("redundantConformance(\u{301}A)", "redundantConformance", "\u{301}A"),
            ("unused(x\u{600})", "unused", "x\u{600}"),
            ("unused(\u{308}(a)\u{6DD})", "unused", "\u{308}(a)\u{6DD}")
        ]
    )
    func hintSplitsOnScalars(hint: String, name: String, text: String) throws {
        let entries = try PeripheryOutput.decode(
            try Self.json([
                Self.scalarEntry(location: "/NoSuchPeripheryPackage/a.swift:1:1", kind: "function.free", hints: [hint])
            ]),
            run: .roots,
            context: try Self.plainContext()
        )
        let entry = try #require(entries.first)

        #expect(entry.hint.unicodeScalars.elementsEqual(name.unicodeScalars))
        #expect(entry.hintText.map { $0.unicodeScalars.elementsEqual(text.unicodeScalars) } == true)
    }

    @Test("""
        a string value starting with a byte order mark loses it as JSONSerialization reads the output, where \
        JSON and the checker keep it (B29, awaiting U17: a known issue), and one later in a string stays
        """)
    func leadingByteOrderMark() throws {
        let entries = try PeripheryOutput.decode(
            try Self.json([
                Self.scalarEntry(
                    location: "/NoSuchPeripheryPackage/a.swift:1:1",
                    kind: "\u{FEFF}var.global",
                    hints: ["\u{FEFF}"]
                ),
                Self.scalarEntry(
                    location: "/NoSuchPeripheryPackage/a\u{FEFF}.swift:1:1",
                    kind: "function.free",
                    hints: ["unused"]
                )
            ]),
            run: .roots,
            context: try Self.plainContext()
        )
        let path = "/NoSuchPeripheryPackage/a\u{FEFF}.swift"

        #expect(entries.count == 2)
        #expect(entries.last?.path.unicodeScalars.elementsEqual(path.unicodeScalars) == true)
        #expect(entries.last?.kind == "function.free")
        withKnownIssue("B29: awaiting U17 (JSONSerialization drops a string's leading U+FEFF)") {
            #expect(entries.first?.kind.unicodeScalars.elementsEqual("\u{FEFF}var.global".unicodeScalars) == true)
            #expect(entries.first?.hint.unicodeScalars.elementsEqual("\u{FEFF}".unicodeScalars) == true)
        }
    }
}
