import Foundation
@testable import SwiftStatsCore
import Testing

/// outskirts' JSON read on Unicode scalars (design B23, decided U13): a
/// hint's parentheses are found among scalars, so a combining mark or a
/// Prepend scalar beside one stays in the text.
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
}
