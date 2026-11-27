import Foundation
import PropertyBased
import Testing

/// What the Unicode generators draw (design D14): from a fixed seed, a
/// thousand draws reach each fragment class an exact number of times, an
/// inline fragment never holds a line break, tab or escape, a scalar draw
/// that lands on a surrogate is rejected rather than trapping the process
/// (the engine's own scalar range generator traps, D10), the invalid byte
/// sequences are never UTF-8, and an NFC/NFD pair is two spellings of one
/// text. The counts hold under this engine's generator code and this
/// standard library; a change to either redraws them.
@Suite("Unicode generators")
struct UnicodeGenTests {
    /// The draws each count makes.
    static let draws = 1_000
    /// The single-attempt scalar draws the surrogate test makes: enough to
    /// land on the surrogates (one draw in 544) many times.
    static let scalarDraws = 100_000
    /// The attempts allowed per draw: only the scalar generator rejects a
    /// value, so a few are always enough at this seed, and a filter added
    /// later that rejects more fails here instead of hanging.
    static let attempts = 10
    /// The fixed seed every meta-test draws from.
    static let seeded = Xoshiro(seed: (1, 2, 3, 4))
    /// The surrogate code points, which are no scalars.
    static let surrogates: ClosedRange<UInt32> = 0xD800...0xDFFF
    /// The first scalar past the Basic Multilingual Plane.
    static let firstAstral: UInt32 = 0x10000

    /// The class `fragment` belongs to, compared scalar by scalar (Swift's
    /// `==` would count an NFC fragment equal to its NFD twin).
    static func label(of fragment: String) -> String {
        func isAny(of list: [String]) -> Bool {
            list.contains { $0.unicodeScalars.elementsEqual(fragment.unicodeScalars) }
        }
        let classes: [(String, [String])] = [
            ("line break", UnicodeGen.lineBreaks),
            ("tab", [UnicodeGen.tab]),
            ("byte order mark", [UnicodeGen.byteOrderMark]),
            ("control", UnicodeGen.controls),
            ("Prepend", UnicodeGen.prepend),
            ("mark after punctuation", UnicodeGen.marksAfterPunctuation),
            ("flag", UnicodeGen.flags),
            ("emoji", UnicodeGen.emoji),
            ("Hangul", UnicodeGen.hangul),
            ("precomposed", UnicodeGen.precomposed),
            ("decomposed", UnicodeGen.decomposed)
        ]
        if let match = classes.first(where: { isAny(of: $0.1) }) {
            return match.0
        }
        return fragment.allSatisfy(UnicodeGen.lowercaseLetters.contains) ? "word" : "scalar"
    }

    /// How often each label of `labels` comes up over `draws` draws from
    /// `generator`, starting from `seeded`.
    static func counts<Value>(
        _ generator: Generator<Value, some Sequence>,
        labels: (Value) -> [String]
    ) throws -> [String: Int] {
        var random = seeded
        var counts: [String: Int] = [:]
        for _ in 0..<draws {
            for label in labels(try generator.run(using: &random, limit: attempts)) {
                counts[label, default: 0] += 1
            }
        }
        return counts
    }

    @Test("inline fragments reach every class, and never hold a line break, tab or escape")
    func inlineFragments() throws {
        let counts = try Self.counts(UnicodeGen.inlineFragment) { fragment in
            let breaks = fragment.unicodeScalars.contains(where: UnicodeGen.notInline.contains)
            return [Self.label(of: fragment)] + (breaks ? ["holds a line break, tab or escape"] : [])
        }

        #expect(
            counts == [
                "Hangul": 76,
                "Prepend": 71,
                "byte order mark": 68,
                "control": 68,
                "decomposed": 76,
                "emoji": 80,
                "flag": 83,
                "mark after punctuation": 74,
                "precomposed": 65,
                "scalar": 65,
                "word": 274
            ]
        )
    }

    @Test("fragments add line breaks and tabs to the inline classes")
    func fragments() throws {
        let counts = try Self.counts(UnicodeGen.fragment) { [Self.label(of: $0)] }

        #expect(
            counts == [
                "Hangul": 52,
                "Prepend": 59,
                "byte order mark": 50,
                "control": 58,
                "decomposed": 59,
                "emoji": 74,
                "flag": 71,
                "line break": 81,
                "mark after punctuation": 59,
                "precomposed": 51,
                "scalar": 52,
                "tab": 107,
                "word": 227
            ]
        )
    }

    @Test("a scalar draw on a surrogate is rejected, never trapped, and every scalar drawn is valid")
    func scalars() {
        var random = Self.seeded
        var counts: [String: Int] = [:]
        for _ in 0..<Self.scalarDraws {
            do {
                let scalar = try UnicodeGen.scalar.run(using: &random, limit: 0)
                let plane = scalar.value < Self.firstAstral ? "Basic Multilingual Plane" : "astral"
                counts[Self.surrogates.contains(scalar.value) ? "surrogate" : plane, default: 0] += 1
            } catch {
                counts["rejected", default: 0] += 1
            }
        }

        #expect(
            counts == [
                "Basic Multilingual Plane": 5_729,
                "astral": 94_046,
                "rejected": 225
            ]
        )
    }

    @Test("an inline scalar is any scalar but a line break, tab or escape, which read as a question mark")
    func inlineScalars() throws {
        let counts = try Self.counts(UnicodeGen.inlineScalar) { fragment in
            let breaks = fragment.unicodeScalars.contains(where: UnicodeGen.notInline.contains)
            return [fragment.unicodeScalars.count == 1 ? "one scalar" : "several scalars"]
                + (breaks ? ["holds a line break, tab or escape"] : [])
        }

        #expect(counts == ["one scalar": Self.draws])
    }

    @Test("no invalid byte sequence is UTF-8, and each is drawn")
    func invalidBytes() throws {
        let decoded = UnicodeGen.invalidUTF8.filter { String(bytes: $0, encoding: .utf8) != nil }
        let counts = try Self.counts(UnicodeGen.invalidBytes) { bytes in
            [bytes.map { String(format: "%02X", $0) }.joined(separator: " ")]
        }

        #expect(decoded.isEmpty)
        #expect(
            counts == [
                "80": 174,
                "C0 80": 153,
                "E2 82": 183,
                "ED A0 80": 150,
                "F4 90 80 80": 180,
                "FF": 160
            ]
        )
    }

    @Test("an NFC/NFD pair is one text in two spellings, often different scalar by scalar")
    func normalizationPairs() throws {
        let counts = try Self.counts(UnicodeGen.nfcPair) { pair in
            let spelledApart = pair.nfc.unicodeScalars.elementsEqual(pair.nfd.unicodeScalars) == false
            let recomposed = pair.nfd.precomposedStringWithCanonicalMapping
            let composed = pair.nfc.unicodeScalars.elementsEqual(recomposed.unicodeScalars)
            return [
                pair.nfc == pair.nfd ? "canonically equal" : "different texts",
                spelledApart ? "spelled apart" : "spelled alike",
                composed ? "NFC is the NFD's composition" : "NFC is not the NFD's composition"
            ]
        }

        #expect(
            counts == [
                "NFC is the NFD's composition": 1_000,
                "canonically equal": 1_000,
                "spelled alike": 243,
                "spelled apart": 757
            ]
        )
    }
}
