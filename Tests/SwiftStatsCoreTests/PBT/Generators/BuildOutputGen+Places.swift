//
//  BuildOutputGen+Places.swift
//  SwiftStatsCoreTests
//
//  Paths and places in build output. A path is a root, up to two segments
//  and a `.swift` file name; segments hold spaces, colons (`a:b`, `a: b`,
//  `12:34`), accents in both forms, Hangul, emoji and flags, and a Prepend
//  scalar between two letters, where it joins no separator. The path ends
//  in its file name, so no prefix of a place but the whole reads as one
//  that has a line and column; it never starts with white space; and its
//  words can't spell a severity, so a `: ` inside it never starts a
//  header. Under the decided rules a Prepend scalar may end the path,
//  just before the `:` of its line (B23, read so since step 7c). A
//  header's place is a file's, a macro expansion's (`#name` or `@name`,
//  the name holding a digit, `_` or `.` too) or `<unknown>:<line>`.
//

import PropertyBased
@testable import SwiftStatsCore

extension BuildOutputGen {
    /// A path, a line and a column, as written and as read.
    struct FilePlace: Sendable {
        /// As written: `<path>:<line>:<column>`.
        let text: String
        /// As read.
        let place: BuildPlace
        /// `shapeB23` when a Prepend scalar ends the path.
        let traits: Set<BuildLineTrait>
    }

    /// A header's place, as written and as read.
    struct HeaderPlace: Sendable {
        /// As written, before `: <severity>: `.
        let text: String
        /// As read.
        let location: BuildDiagnostic.Location
        /// What the place gives the line.
        let traits: Set<BuildLineTrait>
    }

    /// Weight of a file's place among the places.
    static let fileWeight = 4.0
    /// Weight of a plain path segment.
    static let segmentWordWeight = 4.0
    /// Weight of a path that ends as written, before any Prepend scalar.
    static let plainEndWeight = 5.0
    /// How many segments a path has between its root and its file name
    /// (assumed: enough for the segment kinds to meet).
    static let pathSegments = 0...2

    /// Where paths start: absolute, the recordings' root token, one with a
    /// space, a relative one, and one with a colon.
    static let roots = ["/Users/dev/Package", "@ROOT@", "/tmp/a b", "Sources", "/Volumes/x:y"]
    /// The macros a diagnostic can be in: a name may hold a digit, `_`
    /// and `.` after its sigil.
    static let macroNames = ["#expect", "#require", "@Test", "@Observable", "#Macros.stringify", "#my_macro2"]
    /// What a timing line holds in place of a location.
    static let invalidLocation = "<invalid loc>"

    /// One path segment.
    static let segment = Gen.frequency(
        (segmentWordWeight, word),
        (classWeight, zip(word, word).map { $0 + " " + $1 }),
        (classWeight, zip(word, Pick.element(of: [":", ": "]), word).map { $0 + $1 + $2 }),
        (classWeight, zip(number, number).map { $0.text + ":" + $1.text }),
        (classWeight, zip(word, Pick.element(of: UnicodeGen.precomposed + UnicodeGen.decomposed)).map { $0 + $1 }),
        (classWeight, Pick.element(of: UnicodeGen.hangul + UnicodeGen.emoji + UnicodeGen.flags)),
        (classWeight, zip(word, Pick.element(of: UnicodeGen.prepend), word).map { $0 + $1 + $2 })
    )

    /// A path under `rules`, and `shapeB23` when a Prepend scalar ends
    /// it (decided rules only).
    static func path(_ rules: Rules) -> Generator<(text: String, traits: Set<BuildLineTrait>), AnySequence<Any>> {
        let end = Gen.frequency(
            (plainEndWeight, Gen.always("")),
            (rules == .decided ? fixedShapeWeight : neverWeight, Pick.element(of: UnicodeGen.prepend))
        )
        return zip(Pick.element(of: roots), segment.array(of: pathSegments), word, end)
            .map { root, segments, file, end in
                let text = ([root] + segments + [file + ".swift"]).joined(separator: "/") + end
                return (text: text, traits: end.isEmpty ? [] : [.shapeB23])
            }
            .eraseToAny()
    }

    /// A file's place under `rules`.
    static func filePlace(_ rules: Rules) -> Generator<FilePlace, AnySequence<Any>> {
        zip(path(rules), number, number)
            .map { path, line, column in
                FilePlace(
                    text: "\(path.text):\(line.text):\(column.text)",
                    place: BuildPlace(path: path.text, line: line.value, column: column.value),
                    traits: path.traits
                )
            }
            .eraseToAny()
    }

    /// A timing line's place under `rules`: a file's, or nil for `<invalid
    /// loc>`.
    static func timingPlace(_ rules: Rules) -> Generator<FilePlace?, AnySequence<Any>> {
        Gen.frequency(
            (classWeight, Gen.always(FilePlace?.none)),
            (fileWeight, filePlace(rules).map { FilePlace?.some($0) })
        )
        .eraseToAny()
    }

    /// A header's place under `rules`: a file's, a macro expansion's or
    /// `<unknown>:<line>`.
    static func headerPlace(_ rules: Rules) -> Generator<HeaderPlace, AnySequence<Any>> {
        Gen.frequency(
            (fileWeight, filePlace(rules).map { place in
                HeaderPlace(text: place.text, location: .file(place.place), traits: place.traits)
            }),
            (classWeight, zip(Pick.element(of: macroNames), number, number).map(macroPlace)),
            (classWeight, number.map { line in
                HeaderPlace(text: "<unknown>:\(line.text)", location: .unknown(line: line.value), traits: [])
            })
        )
        .eraseToAny()
    }

    /// The place of a diagnostic in the expansion of the macro `name`, at
    /// `line` and `column`.
    static func macroPlace(
        name: String,
        line: (text: String, value: Int),
        column: (text: String, value: Int)
    ) -> HeaderPlace {
        HeaderPlace(
            text: "macro expansion \(name):\(line.text):\(column.text)",
            location: .macro(name: name, line: line.value, column: column.value),
            traits: []
        )
    }
}
