//
//  PeripheryJSONGen.swift
//  SwiftStatsCoreTests
//
//  outskirts entries for P9.2 and locations and hints for P9.4. Paths are
//  recorded ones under the non-existent `/NoSuchPeripheryPackage` root
//  (and the fixture's `@ROOT@`), built of pieces that split or join text
//  (colons, `::`, spaces, digits, a Prepend scalar, a combining mark, a
//  line break), or any fragments, sometimes ending in a Prepend scalar or
//  text that looks like a place (`:12`, `:3:4`); nothing here touches the
//  file system. Lines and columns are small, anywhere up to `Int.max`, or
//  an edge. Hints are recorded names, ASCII words or names that aren't
//  plain letters (empty, holding a digit, a space or a parenthesis,
//  accented), usually with both parentheses, around text of recorded
//  pieces, parentheses or any fragments, sometimes starting with a
//  combining mark or ending in a Prepend scalar. An entry's parts are each
//  faulty at a fixed rate, independently, so several faults meet in one
//  entry often enough for the reader's order to show (design D14's
//  meta-test counts); values of the right type are recorded ones or any
//  fragments. A line or column of 0, or one carrying a plus sign, is drawn
//  as its own flaw class, since each is the one flaw a single check of
//  "positive number of ASCII digits" catches. No text starts with a byte
//  order mark: `JSONSerialization`, which the collector reads outskirts'
//  output with, drops one that starts a string (B29, awaiting U17, pinned
//  in `PeripheryOutputTests+Scalars`), and outskirts' strings (absolute
//  paths, Swift names, kinds, USRs, hints) never start with one (assumed).
//  Every list is ordered simplest first, so a failure shrinks toward its
//  plainest form.
//

import PropertyBased
@testable import SwiftStatsCore

/// Generators of outskirts entries, locations and hints.
enum PeripheryJSONGen {
    /// The non-existent root generated paths lie under.
    static let root = "/NoSuchPeripheryPackage/"
    /// Recorded paths: the Index fixture's, and one holding a colon and a
    /// space (`PeripheryOutputTests`).
    static let recordedPaths = [
        root + "Sources/IndexCore/Locals.swift",
        "@ROOT@/Sources/IndexCore/Accessors.swift",
        root + "Sources/a:b c.swift"
    ]
    /// Pieces a path is built of.
    static let pathPieces = [
        "a", "/", "Sources", ".swift", " ", ":", "12", "0", "::", "x y", "\u{600}", "\u{301}", "\n"
    ]
    /// What a path may end with, just before the line's colon: a Prepend
    /// scalar (B23), or text that looks like a place.
    static let pathTails = UnicodeGen.prepend + [":", ":12", ":3:4", " ", "0"]
    /// What a path is when it would be empty, after a shrink dropped all
    /// its fragments (design D7).
    static let fallbackPath = "p"
    /// The scalar no generated text starts with.
    static let byteOrderMark: Unicode.Scalar = "\u{FEFF}"
    /// What a text starts with in its place.
    static let markReplacement: Unicode.Scalar = "?"
    /// How many pieces or fragments a built path has (assumed: enough for
    /// any two classes to meet, short enough to read when shrunk).
    static let pathLength = 1...6
    /// The largest small line or column (assumed: past any real file).
    static let smallNumber = 99_999
    /// The smallest number holding a zero (forced: the radix).
    static let smallestWithZero = 10
    /// Edge lines and columns: the smallest, numbers holding a zero, and
    /// the largest.
    static let edgeNumbers = [1, smallestWithZero, smallestWithZero * smallestWithZero, Int.max]
    /// How many leading zeros a padded number has (assumed: one shows the
    /// rule, three show it isn't one digit's).
    static let paddingZeros = 1...3

    /// outskirts' hint names (PRD §7.6a).
    static let recordedHintNames = [
        "unused", "assignOnlyProperty", "redundantPublicAccessibility", "redundantConformance"
    ]
    /// The ASCII letters, both cases.
    static let asciiLetters = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")
    /// Names that aren't plain letters: empty, a digit, holding a digit, a
    /// space, an underscore or a parenthesis, accented precomposed and
    /// decomposed, and a fullwidth letter.
    static let oddHintNames = ["", "1", "a1", "a b", "a_b", "a(b", "\u{E9}t\u{E9}", "e\u{301}", "\u{FF41}"]
    /// Pieces a hint's text is built of: outskirts' recorded text, words,
    /// parentheses, quotes and separators.
    static let textPieces = ["replace with: 'A, B'", "a", " ", "(", ")", "()", "'", ":", ","]
    /// What a hint's text may start with: a combining mark, which joins
    /// the opening parenthesis into one Character, or a parenthesis.
    static let textHeads = ["\u{301}", "\u{308}", "(", ")"]
    /// What it may end with: a Prepend scalar, which joins the closing
    /// parenthesis into one Character, or a parenthesis.
    static let textTails = UnicodeGen.prepend + ["(", ")"]
    /// How many pieces or fragments a hint's text has (assumed, as above).
    static let textLength = 0...4

    /// Recorded accessibilities.
    static let accessibilities = ["internal", "public", "private", "fileprivate", "open"]
    /// Recorded kinds.
    static let kinds = ["function.free", "var.global", "var.parameter", "var.instance", "protocol", "extension"]
    /// Recorded names.
    static let names = ["f()", "unusedTotal", "unusedHelper()", "Unused", "parseLine(_:)"]
    /// Recorded attributes.
    static let attributes = ["@objc", "@discardableResult", "@MainActor"]
    /// Recorded modifiers.
    static let modifiers = ["public", "final", "static", "private(set)"]
    /// Recorded ids: USRs and outskirts' synthetic ones.
    static let ids = [
        "s:9IndexCore1fyyF", "c:objc(cs)Probe", "param-values-summarize(_:)-s:9IndexCore9summarizeySiSaySiGF",
        "import-Foundation"
    ]
    /// Recorded modules: C99 names and target names.
    static let modules = ["IndexCore", "index_kit", "IndexDepKit"]
    /// How many values a list holds.
    static let listLength = 0...3
    /// How many fragments a string of any fragments has.
    static let stringLength = 0...3
    /// How many hints a `hints` list of more than one holds.
    static let manyHints = 2...3
    /// How many members the reader doesn't read an entry holds.
    static let extraCount = 0...2
    /// The ordinals of the first entries of a run.
    static let earlyOrdinals = 1...20
    /// Edge ordinals: the first and the largest.
    static let edgeOrdinals = [1, Int.max]

    /// Values of another type than a string: numbers, Booleans, `null`, an
    /// object, and lists.
    static let notStrings: [JSONText] = [
        .number("3"), .bool(true), .null, .object([]), .array([]), .array([.string("x")]), .number("0.5")
    ]
    /// Values of another type than a list of strings: numbers, Booleans,
    /// `null`, strings, an object, and lists holding a number, `null`, a
    /// list, an object or a Boolean beside strings or alone.
    static let notStringLists: [JSONText] = [
        .number("3"), .bool(false), .null, .string("x"), .string(""), .object([]),
        .array([.string("a"), .number("1")]), .array([.null]), .array([.array([.string("a")])]),
        .array([.object([])]), .array([.string("a"), .bool(true)])
    ]
    /// Values an entry is when it isn't an object.
    static let notObjects: [JSONText] = [
        .string("unused"), .number("1"), .bool(true), .null, .array([]), .array([.string("unused")])
    ]
    /// Keys the reader doesn't read: later releases' and near misses of
    /// the nine.
    static let extraKeys = ["asset", "range", "Kind", "location ", "HINTS"]
    /// Values those keys hold.
    static let extraValues: [JSONText] = [.string("x"), .number("1"), .null, .object([]), .array([])]

    /// Weight of recorded values.
    static let recordedWeight = 3.0
    /// Weight of built values.
    static let builtWeight = 2.0
    /// Weight of each other class.
    static let classWeight = 1.0
    /// Weight of a key holding a value of its type: with a missing key and
    /// a mistyped one at `faultWeight` each, about one key in 12.5 is
    /// faulty, so about half the objects have a key fault.
    static let soundKeyWeight = 11.5
    /// Weight of a key missing, and of a key of another type.
    static let faultWeight = 0.5
    /// Weight of a `hints` list of one hint.
    static let oneHintWeight = 6.5
    /// Weight of a `hints` list of none.
    static let noHintWeight = 1.0
    /// Weight of a `hints` list of more than one.
    static let manyHintsWeight = 2.5
    /// Weight of a sound location.
    static let soundLocationWeight = 11.0
    /// Weight of a location whose number has leading zeros.
    static let paddedWeight = 1.5
    /// Weight of a location with a flawed number.
    static let numberFlawWeight = 4.0
    /// Weight of a location whose line or column is 0, beside the flawed
    /// numbers: 0 is the edge of "positive", which a reader taking `>= 0`
    /// would cross, so it is drawn often enough to be an entry's only fault
    /// in most runs (design D14's meta-test counts).
    static let zeroWeight = 4.0
    /// Weight of a location whose line or column carries a plus sign,
    /// beside the flawed numbers: `+12` is the one flaw that `Int(_:)`
    /// parses, so only the check that the number is all ASCII digits
    /// refuses it, and it is drawn often enough to be an entry's only
    /// fault in most runs (design D14's meta-test counts).
    static let signedWeight = 4.0
    /// The share of entries that aren't objects.
    static let notObjectRate: Float = 0.08
    /// The share of paths with a tail.
    static let tailRate: Float = 0.3
    /// The share of built paths under the root.
    static let rootRate: Float = 0.5
    /// The share of hints' texts with a head, and with a tail.
    static let edgeRate: Float = 0.25
    /// The share of hints with an opening parenthesis, and with a closing
    /// one.
    static let parenthesisRate: Float = 0.9

    /// A path that isn't empty: a recorded one, one built of pieces,
    /// sometimes under the root, or one of any fragments, sometimes with a
    /// tail.
    static let path = zip(
        Gen.frequency(
            (recordedWeight, Pick.element(of: recordedPaths)),
            (
                builtWeight,
                zip(Gen.bool(rootRate), Pick.element(of: pathPieces).array(of: pathLength))
                    .map { underRoot, pieces in (underRoot ? root : "") + pieces.joined() }
            ),
            (builtWeight, UnicodeGen.fragment.array(of: pathLength).map { $0.joined() })
        ),
        Pick.element(of: pathTails).optional(valueRate: tailRate)
    )
    .map { body, tail in
        let text = startingWithoutMark(body + (tail ?? ""))
        return text.isEmpty ? fallbackPath : text
    }

    /// A line or a column: small, anywhere from 1 to `Int.max`, or an edge.
    static let number = Gen.frequency(
        (recordedWeight, Gen<Int>.value(in: 1...smallNumber)),
        (classWeight, Gen<Int>.value(in: 1...Int.max)),
        (classWeight, Pick.element(of: edgeNumbers))
    )

    /// A sound location.
    static let location = zip(path, number, number)
        .map { path, line, column in LocationDraft(path: path, line: line, column: column, flaw: .sound) }

    /// A location's flaw: none, mostly; leading zeros; a flawed number,
    /// often 0 or signed; or a missing column or place or an empty path.
    static let flaw = Gen.frequency(
        (soundLocationWeight, Gen.always(LocationDraft.Flaw.sound)),
        (paddedWeight, zip(Gen<Int>.value(in: paddingZeros), Gen.bool).map(LocationDraft.Flaw.padded)),
        (
            numberFlawWeight,
            zip(Pick.element(of: LocationDraft.NumberFlaw.allCases), Gen.bool).map(LocationDraft.Flaw.number)
        ),
        (zeroWeight, Gen.bool.map { inColumn in LocationDraft.Flaw.number(.zero, inColumn: inColumn) }),
        (signedWeight, Gen.bool.map { inColumn in LocationDraft.Flaw.number(.signed, inColumn: inColumn) }),
        (classWeight, Gen.always(LocationDraft.Flaw.noColumn)),
        (classWeight, Gen.always(LocationDraft.Flaw.noPlace)),
        (classWeight, Gen.always(LocationDraft.Flaw.emptyPath))
    )

    /// A location, possibly flawed.
    static let flawedLocation = zip(location, flaw)
        .map { sound, flaw in LocationDraft(path: sound.path, line: sound.line, column: sound.column, flaw: flaw) }

    /// What comes before a hint's opening parenthesis: a recorded name, an
    /// ASCII word, or a name that isn't plain letters.
    static let hintName = Gen.frequency(
        (recordedWeight, Pick.element(of: recordedHintNames)),
        (builtWeight, UnicodeGen.word(from: asciiLetters)),
        (builtWeight, Pick.element(of: oddHintNames))
    )

    /// A hint's text: recorded pieces or any fragments, sometimes after a
    /// head and before a tail.
    static let hintText = zip(
        Pick.element(of: textHeads).optional(valueRate: edgeRate),
        Gen.frequency(
            (builtWeight, Pick.element(of: textPieces).array(of: textLength).map { $0.joined() }),
            (builtWeight, UnicodeGen.fragment.array(of: textLength).map { $0.joined() })
        ),
        Pick.element(of: textTails).optional(valueRate: edgeRate)
    )
    .map { head, body, tail in startingWithoutMark((head ?? "") + body + (tail ?? "")) }

    /// A hint.
    static let hint = zip(hintName, Gen.bool(parenthesisRate), hintText, Gen.bool(parenthesisRate))
        .map(HintDraft.init)

    /// P9.4's input: a sound location and a hint.
    static let place = zip(location, hint).map(PeripheryPlace.init)

    /// A string of any fragments.
    static let anyString = UnicodeGen.fragment.array(of: stringLength).map { startingWithoutMark($0.joined()) }

    /// A `hints` list: one hint, mostly; none; or more than one.
    static let hints = Gen.frequency(
        (oneHintWeight, hint.map { [$0.rendered] }),
        (noHintWeight, Gen.always([String]())),
        (manyHintsWeight, hint.map(\.rendered).array(of: manyHints))
    )
    .eraseToAny()

    /// What the four string keys hold: `accessibility`, `kind`, `location`
    /// and `name`.
    static let stringFields = zip(
        stringField(string(accessibilities).map(PeripheryEntryDraft.Field.string).eraseToAny()),
        stringField(string(kinds).map(PeripheryEntryDraft.Field.string).eraseToAny()),
        stringField(flawedLocation.map(PeripheryEntryDraft.Field.location).eraseToAny()),
        stringField(string(names).map(PeripheryEntryDraft.Field.string).eraseToAny())
    )

    /// What the five list keys hold: `attributes`, `hints`, `ids`,
    /// `modifiers` and `modules`.
    static let listFields = zip(
        listField(list(attributes)),
        listField(hints),
        listField(list(ids)),
        listField(list(modifiers)),
        listField(list(modules))
    )

    /// Members the reader doesn't read, each key once.
    static let extras = zip(Pick.element(of: extraKeys), Pick.element(of: extraValues))
        .map { key, value in JSONText.Member(key: key, value: value) }
        .array(of: extraCount)
        .map { members in
            members.indices
                .filter { index in members[..<index].contains { $0.key == members[index].key } == false }
                .map { members[$0] }
        }

    /// An ordinal: early in a run, anywhere, or an edge.
    static let ordinal = Gen.frequency(
        (recordedWeight, Gen<Int>.value(in: earlyOrdinals)),
        (classWeight, Gen<Int>.value(in: 1...Int.max)),
        (classWeight, Pick.element(of: edgeOrdinals))
    )

    /// P9.2's input: an entry, sometimes not an object, its parts each
    /// faulty at a fixed rate.
    static let entry = zip(
        Pick.element(of: notObjects).optional(valueRate: notObjectRate),
        stringFields,
        listFields,
        extras,
        ordinal,
        Pick.element(of: DeadCodeRun.ordered)
    )
    .map { notObject, strings, lists, extras, ordinal, run in
        PeripheryEntryDraft(
            notObject: notObject,
            fields: [strings.0, lists.0, lists.1, lists.2, strings.1, strings.2, lists.3, lists.4, strings.3],
            extras: extras,
            ordinal: ordinal,
            run: run
        )
    }
    .eraseToAny()

    /// `text` with a byte order mark that starts it written as `?`.
    static func startingWithoutMark(_ text: String) -> String {
        var scalars = text.unicodeScalars
        if scalars.first == byteOrderMark {
            scalars.replaceSubrange(scalars.startIndex...scalars.startIndex, with: [markReplacement])
        }
        return String(scalars)
    }

    /// A string value: a recorded one or any fragments.
    static func string(_ recorded: [String]) -> Generator<String, AnySequence<Any>> {
        Gen.frequency(
            (recordedWeight, Pick.element(of: recorded)),
            (classWeight, anyString)
        )
        .eraseToAny()
    }

    /// What a key whose value is a string holds, sound ones from `sound`.
    static func stringField(
        _ sound: Generator<PeripheryEntryDraft.Field, AnySequence<Any>>
    ) -> Generator<PeripheryEntryDraft.Field, AnySequence<Any>> {
        Gen.frequency(
            (soundKeyWeight, sound),
            (faultWeight, Gen.always(PeripheryEntryDraft.Field.missing)),
            (faultWeight, Pick.element(of: notStrings).map(PeripheryEntryDraft.Field.wrong))
        )
        .eraseToAny()
    }

    /// What a key whose value is a list of strings holds, sound ones from
    /// `sound`.
    static func listField(_ sound: Generator<[String], AnySequence<Any>>) -> Generator<
        PeripheryEntryDraft.Field, AnySequence<Any>
    > {
        Gen.frequency(
            (soundKeyWeight, sound.map(PeripheryEntryDraft.Field.list)),
            (faultWeight, Gen.always(PeripheryEntryDraft.Field.missing)),
            (faultWeight, Pick.element(of: notStringLists).map(PeripheryEntryDraft.Field.wrong))
        )
        .eraseToAny()
    }

    /// A list of strings: recorded ones or any fragments.
    static func list(_ recorded: [String]) -> Generator<[String], AnySequence<Any>> {
        string(recorded).array(of: listLength).eraseToAny()
    }
}
