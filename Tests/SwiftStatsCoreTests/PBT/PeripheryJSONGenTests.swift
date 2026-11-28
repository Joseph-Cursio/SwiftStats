import PropertyBased
@testable import SwiftStatsCore
import Testing

/// What the outskirts generator draws (design D14): from a fixed seed, a
/// thousand entries reach each antecedent of P9.2 an exact number of times
/// (an entry that reads, one that isn't an object, a key missing or of
/// another type, a list holding a non-string, a hints list without one
/// hint, a location that doesn't read, a line or column of 0 alone, a
/// signed one alone, and the faults meeting: two keys, a key and the hints,
/// a key and the location, the hints and the location alone), and a
/// thousand places reach each antecedent of P9.4 (paths holding a colon or
/// a space, ending in a Prepend scalar or in digits after a colon, the
/// largest line or column; hints that split, with text starting with a
/// mark, ending in a Prepend scalar or holding a parenthesis, and hints
/// with both parentheses that read whole). The counts hold under this
/// engine's generator code and this standard library; a change to either,
/// or to a weight or list in `PeripheryJSONGen`, redraws them. Hand-worked
/// examples pin the generator's rendering and the reference, `HintPattern`.
@Suite("outskirts generator")
struct PeripheryJSONGenTests {
    /// The draws each meta-test makes.
    static let draws = 1_000
    /// The attempts allowed per draw: only scalars reject a value (a
    /// surrogate), so a few are always enough at this seed.
    static let attempts = 10
    /// The fixed seed the meta-tests draw from.
    static let seeded = Xoshiro(seed: (1, 2, 3, 4))

    @Test("a thousand entries reach each antecedent of P9.2 an exact number of times")
    func entryClasses() throws {
        var random = Self.seeded
        var counts: [String: Int] = [:]
        for _ in 0..<Self.draws {
            let draft = try PeripheryJSONGen.entry.run(using: &random, limit: Self.attempts)
            for label in PeripheryOutputPBT.entryLabels(of: draft) {
                counts[label, default: 0] += 1
            }
        }

        #expect(counts == [
            "a hints fault beside a location fault, every key sound": 82,
            "a hints list without one hint": 287,
            "a key fault beside a hints fault": 145,
            "a key fault beside a location fault": 219,
            "a key missing": 263,
            "a line or column of 0, the entry's only fault": 34,
            "a list holding something other than a string": 90,
            "a location that doesn't read": 447,
            "a location that reads through leading zeros": 18,
            "a signed line or column, the entry's only fault": 51,
            "a string key of another type": 146,
            "an entry that isn't an object": 97,
            "an entry that reads": 137,
            "two keys faulty": 149
        ])
    }

    @Test("a thousand places reach each antecedent of P9.4 an exact number of times")
    func placeClasses() throws {
        var random = Self.seeded
        var counts: [String: Int] = [:]
        for _ in 0..<Self.draws {
            let place = try PeripheryJSONGen.place.run(using: &random, limit: Self.attempts)
            for label in PeripheryOutputPBT.placeLabels(of: place) {
                counts[label, default: 0] += 1
            }
        }

        #expect(counts == [
            "a hint that splits": 623,
            "a hint with both parentheses that reads whole": 214,
            "a path ending in a Prepend scalar": 189,
            "a path ending in digits after a colon": 48,
            "a path holding a colon": 351,
            "a path holding a space": 296,
            "split text ending in a Prepend scalar": 135,
            "split text holding a parenthesis": 248,
            "split text starting with a combining mark": 81,
            "the largest line or column": 96
        ])
    }

    @Test("""
        a flawed location renders its flaw in the line or the column, and one missing its column or place \
        writes its path's colons as underscores
        """)
    func flawsRender() {
        let flaws: [(LocationDraft.Flaw, String)] = [
            (.sound, "a:1:12:345"),
            (.padded(zeros: 3, inColumn: true), "a:1:12:000345"),
            (.number(.empty, inColumn: false), "a:1::345"),
            (.number(.fullwidth, inColumn: true), "a:1:12:\u{FF13}\u{FF14}\u{FF15}"),
            (.number(.marked, inColumn: false), "a:1:12\u{301}:345"),
            (.number(.negative, inColumn: true), "a:1:12:-345"),
            (.number(.pastInt, inColumn: false), "a:1:120000000000000000000:345"),
            (.number(.signed, inColumn: false), "a:1:+12:345"),
            (.number(.spaced, inColumn: true), "a:1:12: 345"),
            (.number(.word, inColumn: false), "a:1:12x:345"),
            (.number(.zero, inColumn: true), "a:1:12:0"),
            (.noColumn, "a_1:12"),
            (.noPlace, "a_1"),
            (.emptyPath, ":12:345")
        ]

        for (flaw, text) in flaws {
            let draft = LocationDraft(path: "a:1", line: 12, column: 345, flaw: flaw)

            #expect(draft.rendered == text)
        }
    }

    @Test("""
        the hint reference splits ASCII letters, an opening parenthesis, any text and a closing one ending the \
        hint, on scalars, and reads anything else whole
        """)
    func hintReference() {
        let splits = [
            ("redundantConformance(replace with: 'A, B')", "redundantConformance", "replace with: 'A, B'"),
            ("a()", "a", ""),
            ("a(\u{301}x\u{600})", "a", "\u{301}x\u{600}"),
            ("a((b))", "a", "(b)")
        ]
        let whole = ["unused", "a(b", "a)", "(x)", "a1(x)", "\u{E9}(x)", "a(x)\u{301}", ")"]

        for (hint, name, text) in splits {
            let split = HintPattern.split(hint)

            #expect(PeripheryOutputPBT.sameScalars(split.name, name))
            #expect(PeripheryOutputPBT.sameScalars(split.text, text))
        }
        for hint in whole {
            let split = HintPattern.split(hint)

            #expect(PeripheryOutputPBT.sameScalars(split.name, hint))
            #expect(split.text == nil)
        }
    }
}
