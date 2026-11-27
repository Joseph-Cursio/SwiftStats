//
//  BuildOutputGen+Text.swift
//  SwiftStatsCoreTests
//
//  The text build-output lines are made of. A text is a word, then pieces
//  of a gap and a word, so it starts and ends with a word: it is never
//  blank, never starts like structure or a prefix the reader looks for,
//  and never ends in white space or `]`. Words leave out `n` and `r`, so
//  no text spells a severity, `info` or `macro expansion`, and a line is a
//  header only where a block wrote one. Gaps are spaces, any inline
//  fragment of `UnicodeGen` (accents, Hangul, emoji, Prepend scalars,
//  controls, any scalar but a line break, tab or escape), a lone carriage
//  return, which a word always follows, or a bar (` | `, `||`, `|=`),
//  which a word always comes before, so the line is no excerpt: its first
//  `|` has text before it that isn't spaces and digits. A continuation
//  line may start with digits that aren't ASCII and a bar, which isn't an
//  excerpt's gutter either. Suffix parts are a well-formed or malformed ID
//  or group; continuation lines draw them rarely, so a long message often
//  runs past the limit without completing. A message line sometimes ends
//  in white space after its parts, which only the end of a whole message
//  drops.
//

import PropertyBased
@testable import SwiftStatsCore

extension BuildOutputGen {
    /// Weight of a space among the gaps between words.
    static let spaceWeight = 6.0
    /// Weight of a vocabulary word among the words.
    static let vocabularyWeight = 4.0
    /// Weight of no suffix part on a header's message line.
    static let headerNoPartWeight = 3.0
    /// Weight of no suffix part on a continuation line.
    static let continuationNoPartWeight = 12.0
    /// Weight of no group part.
    static let noGroupWeight = 6.0
    /// Weight of no trailing white space on a message line.
    static let noTrailingWeight = 6.0
    /// The share of numbers written with a leading zero.
    static let paddedRate: Float = 0.2

    /// How many gap-and-word pieces follow a text's first word (assumed:
    /// enough for each fragment class to meet a neighbour).
    static let textPieces = 0...4
    /// The largest line or column number (assumed: past any real file).
    static let largestNumber = 99_999

    /// Letters for words: no `n` and no `r`, so no word spells a severity,
    /// `info` or `macro expansion`.
    static let safeLetters = Array("abcdefghijklmopqstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")
    /// Words of safe letters, the shortest first.
    static let vocabulary = [
        "x", "be", "it", "to", "OK", "let", "may", "the", "Box", "Kit", "Map", "Set", "Baz", "Foo", "self", "this",
        "used", "type", "Bool", "Data", "JSON", "UUID", "check", "value", "await", "swift", "Cache", "Model", "macOS",
        "Tests", "Double", "Sample"
    ]
    /// The characters of a diagnostic ID.
    static let identifierCharacters = Array("abcdefghijklmnopqrstuvwxyz0123456789_")
    /// The characters of a diagnostic group.
    static let groupCharacters = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
    /// Real diagnostic IDs.
    static let identifiers = ["pbd_never_used", "unreachable_code_after_stmt", "bridged_warning", "no_throw_in_try"]
    /// Real diagnostic groups.
    static let groups = ["NoUsage", "DeprecatedDeclaration", "UnnecessaryEffectMarker"]
    /// ID parts no suffix reads: capitals, a space, nothing, a dash.
    static let malformedIdentifiers = [" [Bad]", " [has space]", " []", " [dash-ed]"]
    /// Group parts no suffix reads: a dash, nothing, a space.
    static let malformedGroups = [" [#Bad-Group]", " [#]", " [#No Usage]"]
    /// What a continuation line may start with: nothing, spaces, a tab, or
    /// Arabic-Indic or fullwidth digits and a bar, which aren't an
    /// excerpt's gutter (only spaces and ASCII digits are).
    static let indentations = ["", "    ", "        ", "\t", "\u{661}\u{662} | ", "  \u{FF13}| "]
    /// The gaps that hold a bar, a word always before them.
    static let barGaps = [" | ", "||", "|="]
    /// The white space a message line may end in: spaces, a no-break and
    /// an ideographic space (no tab: after a word ending `ms`, it would
    /// make a timing mark).
    static let trailings = [" ", "   ", "\u{A0}", "\u{3000}"]

    /// A word: mostly one of `vocabulary`, sometimes drawn letter by letter
    /// from `safeLetters` (one draw against several, for speed).
    static let word = Gen.frequency(
        (vocabularyWeight, Pick.element(of: vocabulary)),
        (classWeight, UnicodeGen.word(from: safeLetters))
    )

    /// What goes between two words.
    static let gap = Gen.frequency(
        (spaceWeight, Gen.always(" ")),
        (classWeight, UnicodeGen.inlineFragment),
        (classWeight, Gen.always("\r")),
        (classWeight, Pick.element(of: barGaps))
    )

    /// What a message line ends in after its parts: mostly nothing,
    /// sometimes white space.
    static let trailing = Gen.frequency(
        (noTrailingWeight, Gen.always("")),
        (classWeight, Pick.element(of: trailings))
    )

    /// A text that starts and ends with a word.
    static let text = zip(word, zip(gap, word).map { $0 + $1 }.array(of: textPieces))
        .map { $0 + $1.joined() }

    /// A line or column number, as written and as read.
    static let number = zip(Gen<Int>.value(in: 0...largestNumber), Gen.bool(paddedRate))
        .map { value, padded in (text: (padded ? "0" : "") + String(value), value: value) }

    /// A header's message line: a text, often with an ID, sometimes a group,
    /// sometimes trailing white space.
    static let headerMessage = zip(text, identifierPart(noPartWeight: headerNoPartWeight), groupPart, trailing)
        .map { SuffixedText(body: $0, identifier: $1, group: $2, trailing: $3) }

    /// A continuation line's text: indented or not, rarely with a suffix,
    /// sometimes trailing white space.
    static let continuationText = zip(
        Pick.element(of: indentations),
        text,
        identifierPart(noPartWeight: continuationNoPartWeight),
        groupPart,
        trailing
    )
    .map { SuffixedText(body: $0 + $1, identifier: $2, group: $3, trailing: $4) }

    /// A group part: mostly none, sometimes well formed or malformed.
    static let groupPart = Gen.frequency(
        (noGroupWeight, Gen.always(SuffixedText.Part.absent)),
        (classWeight, Pick.element(of: groups).map { SuffixedText.Part.valid($0) }),
        (classWeight, UnicodeGen.word(from: groupCharacters).map { SuffixedText.Part.valid($0) }),
        (classWeight, Pick.element(of: malformedGroups).map { SuffixedText.Part.malformed($0) })
    )

    /// An ID part: none (weighted `noPartWeight`), a real or drawn ID, or a
    /// malformed one.
    static func identifierPart(noPartWeight: Double) -> Generator<SuffixedText.Part, AnySequence<Any>> {
        Gen.frequency(
            (noPartWeight, Gen.always(SuffixedText.Part.absent)),
            (classWeight, Pick.element(of: identifiers).map { SuffixedText.Part.valid($0) }),
            (classWeight, UnicodeGen.word(from: identifierCharacters).map { SuffixedText.Part.valid($0) }),
            (classWeight, Pick.element(of: malformedIdentifiers).map { SuffixedText.Part.malformed($0) })
        )
        .eraseToAny()
    }
}
