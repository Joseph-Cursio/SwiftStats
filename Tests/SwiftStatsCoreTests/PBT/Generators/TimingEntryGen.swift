//
//  TimingEntryGen.swift
//  SwiftStatsCoreTests
//
//  Timing entries the grammar can state, each written as its line by
//  `BuildLineRenderer` in a drawn style, for P1.4. The grammar states an
//  entry whose time has at most twelve whole digits (hundredths below
//  10^14), whose place is `<invalid loc>` or a path that isn't empty,
//  doesn't start with white space and holds no tab, with a line and a
//  column from 0 to `Int.max`, and whose declaration, a function body's,
//  isn't empty and holds no tab (an expression has none). Paths come from
//  the build-output generator (spaces, colons, accents in both forms,
//  emoji, a Prepend scalar before the line's colon) or are any scalars but
//  a tab, the first not white space; so a path can hold a line break, an
//  escape or `:<digits>:<digits>`, all of which the grammar keeps in the
//  path (it reads a whole line, split on tabs, from the right).
//  Declarations come from the build-output generator or are any scalars
//  but a tab. Times, lines and columns are small, anywhere up to the
//  bound, or an edge.
//

import PropertyBased
@testable import SwiftStatsCore
import Testing

/// Generators of timing entries the grammar can state, written as lines.
enum TimingEntryGen {
    /// An entry and its line, P1.4's input.
    struct Line: Sendable, CustomTestStringConvertible {
        /// The entry.
        let entry: TimingEntry
        /// How it is written.
        let style: BuildLineRenderer.Style

        /// The entry written in its style.
        var text: String {
            BuildLineRenderer.line(entry, style: style)
        }

        /// The line, the entry and the style, in ASCII (`PBTTrace.ascii`),
        /// so a failure's seed reaches the console.
        var testDescription: String {
            PBTTrace.ascii("\(text.debugDescription) for \(entry), written \(style)")
        }
    }

    /// The largest time the grammar states, in hundredths (forced: twelve
    /// whole digits and two fraction digits).
    static let largestHundredths = 99_999_999_999_999
    /// The largest small time, in hundredths (assumed: most type-check
    /// times are under a second).
    static let smallHundredths = 99_999
    /// The largest small line or column (assumed: past any real file).
    static let smallNumber = 99_999
    /// Edge times, in hundredths: none, the smallest, a whole millisecond
    /// and the hundredth below it, a whole tenth, and the largest
    /// whole-millisecond and largest times.
    static let edgeHundredths = [
        0,
        1,
        BuildLineRenderer.hundredthsPerMillisecond - 1,
        BuildLineRenderer.hundredthsPerMillisecond,
        BuildLineRenderer.hundredthsPerTenth,
        largestHundredths + 1 - BuildLineRenderer.hundredthsPerMillisecond,
        largestHundredths
    ]
    /// Edge lines and columns.
    static let edgeNumbers = [0, 1, Int.max]
    /// How many scalars a wide path or declaration has after its first
    /// (assumed: enough for any two classes of scalar to meet).
    static let wideLength = 0...12
    /// The largest number of leading zeros drawn before a time's whole
    /// digits (forced: the twelve the grammar takes).
    static let largestPadding = BuildLineRenderer.wholeDigits
    /// What a wide path or declaration holds in place of a tab, and what a
    /// wide path starts with in place of white space.
    static let replacement = "?"
    /// Scalars the codespace rarely gives, which split or end text in
    /// other readers: the separators of a place and a path, white space,
    /// line breaks, an escape, a combining mark, a Prepend scalar and a
    /// byte order mark.
    static let specialScalars = [":", "/", " ", "\n", "\r", "\u{1B}", "\u{301}", "\u{600}", "\u{FEFF}"]

    /// Weight of small values among the times and numbers.
    static let smallWeight = 3.0
    /// Weight of each other class.
    static let classWeight = 1.0
    /// The share of entries with a place.
    static let placeRate: Float = 0.8
    /// The share of entries with a declaration (function bodies).
    static let declarationRate: Float = 0.5
    /// The share of styles with leading zeros before the time.
    static let paddingRate: Float = 0.2
    /// The share of styles with a leading zero before the line and column.
    static let paddedNumberRate: Float = 0.2

    /// A time the grammar states, in hundredths: small, anywhere up to the
    /// largest, or an edge.
    static let hundredths = Gen.frequency(
        (smallWeight, Gen<Int>.value(in: 0...smallHundredths)),
        (classWeight, Gen<Int>.value(in: 0...largestHundredths)),
        (classWeight, Pick.element(of: edgeHundredths))
    )

    /// A line or column: small, anywhere up to `Int.max`, or an edge.
    static let number = Gen.frequency(
        (smallWeight, Gen<Int>.value(in: 0...smallNumber)),
        (classWeight, Gen<Int>.value(in: 0...Int.max)),
        (classWeight, Pick.element(of: edgeNumbers))
    )

    /// Any scalar but a tab, as text: drawn from the whole codespace, or
    /// one that splits or ends text elsewhere.
    static let untabbed = Gen.frequency(
        (classWeight, UnicodeGen.scalar.map { $0 == "\t" ? replacement : String($0) }),
        (classWeight, Pick.element(of: specialScalars))
    )

    /// Any scalars but a tab, at least one, the first not white space.
    static let widePath = zip(UnicodeGen.scalar, untabbed.array(of: wideLength))
        .map { first, rest in
            (first.properties.isWhitespace ? replacement : String(first)) + rest.joined()
        }

    /// A path: the build-output generator's, or any scalars but a tab.
    static let path = Gen.frequency(
        (classWeight, BuildOutputGen.path(.decided).map(\.text)),
        (classWeight, widePath)
    )

    /// A place the grammar states.
    static let place = zip(path, number, number).map { BuildPlace(path: $0, line: $1, column: $2) }

    /// A declaration: the build-output generator's, or one or more of any
    /// scalars but a tab.
    static let declaration = Gen.frequency(
        (classWeight, BuildOutputGen.declaration),
        (classWeight, zip(untabbed, untabbed.array(of: wideLength)).map { $0 + $1.joined() })
    )

    /// An entry the grammar states: a function body's when it has a
    /// declaration, an expression's otherwise.
    static let entry = zip(
        hundredths,
        place.optional(valueRate: placeRate),
        declaration.optional(valueRate: declarationRate)
    )
        .map { hundredths, place, declaration in
            TimingEntry(
                kind: declaration == nil ? .expression : .function,
                hundredths: hundredths,
                place: place,
                declaration: declaration
            )
        }

    /// A style to write an entry in.
    static let style = zip(
        Pick.element(of: BuildLineRenderer.TimeForm.allCases),
        Gen<Int>.value(in: 1...largestPadding).optional(valueRate: paddingRate),
        Gen.bool(paddedNumberRate)
    )
    .map { BuildLineRenderer.Style(form: $0, padding: $1 ?? 0, paddedNumbers: $2) }

    /// An entry the grammar states, written in a drawn style.
    static let line = zip(entry, style).map { Line(entry: $0, style: $1) }
}
