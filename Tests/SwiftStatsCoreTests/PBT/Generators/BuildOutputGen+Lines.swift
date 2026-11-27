//
//  BuildOutputGen+Lines.swift
//  SwiftStatsCoreTests
//
//  The single lines both files hold. Plain text (a message line's text at
//  the top level, ignored there, taken by a header above it). Near misses:
//  a header wrong in one field (no column, a capital severity, no space
//  after the place's colon, a macro name with a space, only its sigil or
//  no sigil, an empty path, a path led by a tab or a no-break space, `<unknown>`
//  with no line), or a timing line with a space for its tab; each is plain
//  text.
//  Structure: excerpts (one may end ` [word]`, M7 C2), excerpt notes,
//  boxes and decorated notes. Stoppers: footnotes, `info:`, `error:`,
//  `note:` and `remark:` lines that are no diagnostic. Other warnings:
//  SwiftPM's and Swift Build's `warning: ` lines. Blank lines, white space
//  included. Wild lines of any inline fragments, or of bytes that aren't
//  UTF-8. And under the decided rules, a plain line with an escape just
//  before a Character that joins its last scalar (B24, read so since step
//  7c).
//

import PropertyBased
@testable import SwiftStatsCore

extension BuildOutputGen {
    /// A header wrong in one field.
    enum NearHeader: CaseIterable, Sendable {
        /// A macro name with a space.
        case badMacro
        /// A macro name that is only its sigil.
        case bareSigil
        /// The severity capitalised.
        case capitalized
        /// No path before the line and column.
        case emptyPath
        /// A path led by a no-break space.
        case noBreakLedPath
        /// No column.
        case noColumn
        /// No space after the place's last colon.
        case noSpace
        /// A macro expansion's place whose name has no sigil.
        case sigilLess
        /// A path led by a tab.
        case tabLedPath
        /// `<unknown>` with no line.
        case unknownWithoutLine

        /// The place and severity this fault writes before the message, for
        /// `place` and `severity`.
        func prefix(_ place: FilePlace, severity: BuildDiagnostic.Severity) -> String {
            switch self {
            case .badMacro:
                "macro expansion #bad name:1:2: \(severity.rawValue): "

            case .bareSigil:
                "macro expansion #:1:2: \(severity.rawValue): "

            case .capitalized:
                "\(place.text): \(severity.rawValue.capitalized): "

            case .emptyPath:
                ":\(place.place.line):\(place.place.column): \(severity.rawValue): "

            case .noBreakLedPath:
                "\u{A0}\(place.text): \(severity.rawValue): "

            case .noColumn:
                "\(place.place.path):\(place.place.line): \(severity.rawValue): "

            case .noSpace:
                "\(place.text):\(severity.rawValue): "

            case .sigilLess:
                "macro expansion expect:1:2: \(severity.rawValue): "

            case .tabLedPath:
                "\t\(place.text): \(severity.rawValue): "

            case .unknownWithoutLine:
                "<unknown>: \(severity.rawValue): "
            }
        }
    }

    /// The share of excerpt lines ending ` [word]`.
    static let excerptSuffixRate: Float = 0.3
    /// How many fragments a wild line has (assumed).
    static let wildFragments = 1...6
    /// The largest excerpt line number (assumed).
    static let largestExcerptLine = 9_999

    /// White space lines: empty, spaces, a tab, a no-break space and an
    /// ideographic space.
    static let blanks = ["", "    ", "\t", "\u{A0}", "\u{3000}"]
    /// The blank lines that aren't spaces only.
    static let otherBlanks = ["\t", "\u{A0}", "\u{3000}", " \t "]
    /// Structure lines with no text of their own.
    static let structureLines = ["   |", "   +--- macro expansion #expect ----------", "   +------------------"]
    /// How decorated notes start.
    static let decoratedStarts = ["`- note: ", "  `- warning: ", "|- note: "]
    /// How stoppers with text start.
    static let stopperStarts = ["info: ", "error: ", "note: ", "remark: "]
    /// The controls a joined escape follows.
    static let joiningControls = ["\u{0}", "\u{1C}"]
    /// Scalars that join the Character before them: combining marks and a
    /// zero-width joiner.
    static let joiningScalars = ["\u{301}", "\u{308}", "\u{200D}"]
    /// The escapes a joined escape can be, placed before the Character at
    /// a position: a CSI, an OSC-8 link ended by `ESC \`, a two-character
    /// escape.
    static let joinedEscapes: [@Sendable (Int) -> BuildLineDecoration.Escape] = [
        { .csi(start: $0, end: $0) },
        { .oscTerminated(start: $0, end: $0) },
        { .twoCharacter($0) }
    ]

    /// Plain text at the top level, maybe indented, maybe with suffixes.
    static let plain = zip(Pick.element(of: indentations), headerMessage)
        .map { indentation, message in
            let line = message.with(body: indentation + message.body)
            return BuildLineDraft(.plain(line), text: line.rendered, traits: [])
        }

    /// A near miss: a header or a timing line wrong in one field.
    static let nearMiss = Gen.frequency(
        (fileWeight, nearHeader),
        (classWeight, zip(time, timingPlace(.current)).map { time, place in
            let line = SuffixedText(time.text + "ms " + (place?.text ?? invalidLocation))
            return BuildLineDraft(.plain(line), text: line.rendered, traits: [])
        })
    )

    /// A header wrong in one field, which reads as plain text.
    static let nearHeader = zip(
        Pick.element(of: NearHeader.allCases),
        filePlace(.current),
        Pick.element(of: severities),
        headerMessage
    )
    .map { fault, place, severity, message in
        let line = message.with(body: fault.prefix(place, severity: severity) + message.body)
        return BuildLineDraft(.plain(line), text: line.rendered, traits: [.nearHeader])
    }

    /// A structure line.
    static let structural = Gen.frequency(
        (fileWeight, zip(Gen<Int>.value(in: 1...largestExcerptLine), text, word.optional(valueRate: excerptSuffixRate))
            .map { line, text, suffix in "\(line) | \(text)" + (suffix.map { " [\($0)]" } ?? "") }),
        (classWeight, zip(text, Pick.element(of: identifiers)).map { "   |     `- warning: \($0) [\($1)]" }),
        (classWeight, Pick.element(of: structureLines)),
        (classWeight, text.map { "   |1 | " + $0 }),
        (classWeight, zip(Pick.element(of: decoratedStarts), text).map { $0 + $1 })
    )
    .map { BuildLineDraft(.structural, text: $0, traits: []) }

    /// A group's footnote.
    static let footnote = zip(Pick.element(of: groups), word).map { group, slug in
        "[#\(group)]: <https://docs.swift.org/compiler/documentation/diagnostics/\(slug)>"
    }

    /// A line that ends a message and is otherwise ignored.
    static let stopper = Gen.frequency(
        (classWeight, zip(Pick.element(of: stopperStarts), text).map { $0 + $1 }),
        (classWeight, Gen.always("error: Build failed")),
        (classWeight, footnote)
    )
    .map { BuildLineDraft(.stopper, text: $0, traits: []) }

    /// A line starting `warning: ` that is no diagnostic: plain, SwiftPM's
    /// package form, or Swift Build's summary form.
    static let otherWarning = Gen.frequency(
        (classWeight, text.map { "warning: " + $0 }),
        (classWeight, zip(word, text).map { "warning: '\($0)': \($1)" }),
        (classWeight, zip(filePlace(.current), text).map { "warning: \($0.text) \($1)" })
    )
    .map { BuildLineDraft(.otherWarning, text: $0, traits: []) }

    /// A blank line.
    static let blank = Pick.element(of: blanks).map { BuildLineDraft(.blank, text: $0, traits: []) }

    /// A wild line: inline fragments, or bytes that aren't UTF-8 between
    /// two words.
    static let wild = Gen.frequency(
        (fileWeight, UnicodeGen.inlineFragment.array(of: wildFragments).map { fragments in
            BuildLineDraft(wildBytes: Array(fragments.joined().utf8))
        }),
        (classWeight, zip(word, UnicodeGen.invalidBytes, word).map { first, invalid, last in
            BuildLineDraft(wildBytes: Array(first.utf8) + invalid + Array(last.utf8))
        })
    )

    /// A plain line with an escape just before a Character that joins the
    /// escape's last scalar (B24, fixed in step 7c): a CSI, an OSC-8 link
    /// ended by `ESC \`, or a two-character escape.
    static let joinedEscape = zip(
        word,
        Pick.element(of: joiningControls),
        Pick.element(of: joiningScalars),
        word,
        Gen<Int>.value(in: joinedEscapes.indices)
    )
    .map { first, control, joining, last, kind in
        let line = SuffixedText(first + control + joining + last)
        let escape = joinedEscapes[kind]((first + control).count)
        return BuildLineDraft(.plain(line), text: line.rendered, traits: [], escape: escape)
    }
}
