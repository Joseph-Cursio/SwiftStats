//
//  UnicodeGen.swift
//  SwiftStatsCoreTests
//
//  Text fragments for the generators of tool output. A uniform scalar
//  almost never lands on what text handling gets wrong, so each fragment
//  is drawn from a named class: ASCII words, accents precomposed and
//  decomposed, Hangul, emoji joined by ZWJ or a modifier, a flag, a
//  combining mark after `[` or `: `, Prepend scalars (they join the
//  scalar after them into one Character, B23), controls (NUL and U+001C to
//  U+001F, which Swift doesn't count as white space, B9), a byte order
//  mark, line breaks, a tab, and any scalar at all. `scalar` is the only
//  way to draw a scalar from the whole codespace: the engine's own scalar
//  range generator force-unwraps and traps the test process on a
//  surrogate (design D10), so the surrogates are filtered out here. A
//  surrogate shrunk into is dropped from an array the same way, so nothing
//  may depend on a fragment count surviving a shrink (D7). Invalid UTF-8
//  is bytes, never a `String`, for inputs read as `Data`. Every list is
//  ordered simplest first, so a failure shrinks toward its plainest form.
//

import Foundation
import PropertyBased

/// Generators of text fragments, weighted toward the classes text handling
/// gets wrong.
enum UnicodeGen {
    /// The largest scalar value (forced: the top of Unicode's codespace).
    static let largestScalar: UInt32 = 0x10FFFF
    /// How many letters a word has (assumed: enough to spell a field,
    /// short enough that a shrunk word reads at a glance).
    static let wordLengths = 1...8
    /// How many fragments an NFC/NFD pair's text has (assumed, as above).
    static let pairFragments = 1...4

    /// Weight of ASCII words among the inline fragments: most of real tool
    /// output is ASCII.
    static let wordWeight = 4.0
    /// Weight of each other class of inline fragment.
    static let classWeight = 1.0
    /// Weight of inline fragments among all fragments.
    static let inlineWeight = 8.0

    /// The lowercase ASCII letters.
    static let lowercaseLetters = Array("abcdefghijklmnopqrstuvwxyz")
    /// Accented letters, each in its precomposed (NFC) form.
    static let precomposed = ["é", "ñ", "Å", "ü", "ç", "ǖ"]
    /// The same letters decomposed (NFD): a base letter and combining marks.
    static let decomposed = precomposed.map(\.decomposedStringWithCanonicalMapping)
    /// Hangul: precomposed syllables, and one syllable as conjoining jamo.
    static let hangul = ["한", "글", "\u{1112}\u{1161}\u{11AB}"]
    /// Emoji of several scalars: a ZWJ sequence, a family, a skin tone.
    static let emoji = [
        "\u{1F469}\u{200D}\u{1F4BB}",
        "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}",
        "\u{1F44D}\u{1F3FD}"
    ]
    /// Flags, two regional indicators each.
    static let flags = ["\u{1F1EF}\u{1F1F5}", "\u{1F1EB}\u{1F1F7}"]
    /// A combining mark after `[` and after `: `, which joins the mark to
    /// the punctuation in one Character.
    static let marksAfterPunctuation = ["[\u{301}", ": \u{308}"]
    /// The Prepend scalars of the Arabic block: each joins the scalar after
    /// it into one Character (B23).
    static let prepend = ["\u{600}", "\u{601}", "\u{602}", "\u{603}", "\u{604}", "\u{605}", "\u{6DD}"]
    /// NUL and the information separators U+001C to U+001F: controls, and
    /// not white space to Swift (B9).
    static let controls = ["\u{0}", "\u{1C}", "\u{1D}", "\u{1E}", "\u{1F}"]
    /// A byte order mark, as a fragment inside text.
    static let byteOrderMark = "\u{FEFF}"
    /// The line breaks: LF, CRLF and a lone CR.
    static let lineBreaks = ["\n", "\r\n", "\r"]
    /// A tab.
    static let tab = "\t"
    /// The scalars an inline fragment never holds: the line breaks, the tab
    /// and the escape, which start structure in line-oriented output.
    static let notInline: Set<Unicode.Scalar> = ["\n", "\r", "\t", "\u{1B}"]
    /// What an inline fragment holds in place of a scalar it never holds.
    static let replacement = "?"
    /// Byte sequences that aren't UTF-8: a lone continuation byte, an
    /// overlong NUL, an encoded surrogate, a truncated three-byte sequence,
    /// a byte UTF-8 never uses, and a scalar past U+10FFFF. Each is written
    /// as the Latin-1 characters of its bytes.
    static let invalidUTF8 = [
        "\u{80}",
        "\u{C0}\u{80}",
        "\u{ED}\u{A0}\u{80}",
        "\u{E2}\u{82}",
        "\u{FF}",
        "\u{F4}\u{90}\u{80}\u{80}"
    ]
    .map { latin1 in latin1.unicodeScalars.map { UInt8(truncatingIfNeeded: $0.value) } }

    /// Any scalar of the codespace, the surrogates excluded: the
    /// surrogate-safe form design D10 requires.
    static let scalar = Gen<UInt32>.value(in: 0...largestScalar).compactMap(Unicode.Scalar.init)

    /// Any scalar as a fragment, a line break, tab or escape replaced.
    static let inlineScalar = scalar.map { notInline.contains($0) ? replacement : String($0) }

    /// A lowercase ASCII word.
    static let lowercaseWord = word(from: lowercaseLetters)

    /// One fragment that holds no line break, tab or escape, from every
    /// class.
    static let inlineFragment = Gen.frequency(
        (wordWeight, lowercaseWord),
        (classWeight, Pick.element(of: precomposed)),
        (classWeight, Pick.element(of: decomposed)),
        (classWeight, Pick.element(of: hangul)),
        (classWeight, Pick.element(of: emoji)),
        (classWeight, Pick.element(of: flags)),
        (classWeight, Pick.element(of: marksAfterPunctuation)),
        (classWeight, Pick.element(of: prepend)),
        (classWeight, Pick.element(of: controls)),
        (classWeight, Gen.always(byteOrderMark)),
        (classWeight, inlineScalar)
    )

    /// One fragment of any class: an inline one, a line break or a tab.
    static let fragment = Gen.frequency(
        (inlineWeight, inlineFragment),
        (classWeight, Pick.element(of: lineBreaks)),
        (classWeight, Gen.always(tab))
    )

    /// A byte sequence that isn't UTF-8.
    static let invalidBytes = Pick.element(of: invalidUTF8)

    /// A text of words and accented letters in its NFC form and its NFD
    /// twin, by Foundation's canonical mappings: equal as Swift strings,
    /// different scalar by scalar.
    static let nfcPair = Gen.frequency(
        (classWeight, lowercaseWord),
        (classWeight, Pick.element(of: precomposed))
    )
    .array(of: pairFragments)
    .map { fragments in
        let text = fragments.joined()
        return (nfc: text.precomposedStringWithCanonicalMapping, nfd: text.decomposedStringWithCanonicalMapping)
    }

    /// A word of letters from `alphabet`, which must not be empty.
    static func word(from alphabet: [Character]) -> Generator<String, AnySequence<Any>> {
        Pick.element(of: alphabet).array(of: wordLengths).map { String($0) }.eraseToAny()
    }
}
