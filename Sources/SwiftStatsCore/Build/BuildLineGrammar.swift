//
//  BuildLineGrammar.swift
//  SwiftStatsCore
//
//  The line patterns of the T1 build's output (M7, design §6.1). A timing
//  line is a time `<digits>[.<one or two digits>]ms` with at most twelve
//  whole digits, a tab, `<invalid loc>` or `<path>:<line>:<column>` (split
//  from the right, so a path may hold colons and spaces), and for a
//  function body a tab and its declaration. A diagnostic's first line is
//  its place, `: `, a severity, `: ` and the message; the place is the
//  first prefix before `: <severity>: ` that reads as one: `macro expansion
//  #name:<line>:<column>` (or `@name`), `<unknown>:<line>`, or
//  `<path>:<line>:<column>`. Source excerpt lines (digits or nothing before
//  a `|`), box lines (`+---`) and decorated lines (`` `- ``, `|- `) are
//  never a diagnostic's first line; a decorated note after a macro
//  diagnostic is its origin note. A place's colons, a header's `: `
//  separators and severity, the timing mark, a blank line's white space,
//  an excerpt's `|`, a box's `+-`, a decoration, a group footnote's
//  `]: <` and the prefixes of lines that can't continue a message are
//  found among a line's Unicode scalars (or bytes), not its Characters,
//  so a Prepend scalar or a combining mark beside one moves no field's
//  boundary (design B23, decided U13).
//

import Foundation

/// The line patterns of the build's output.
enum BuildLineGrammar {
    /// What a synthesized member's timing line has in place of a location.
    static let invalidLocation = "<invalid loc>"
    /// The place prefix of a diagnostic in a macro expansion.
    static let macroPlace = "macro expansion "
    /// The text of the note that names a macro expansion's origin.
    static let originNote = "expanded code originates here"
    /// The place of a diagnostic the compiler has no location for.
    static let unknownPlace = "<unknown>"
    /// What a timing line holds after its time.
    static let timingMark = "ms\t"
    /// What separates a place's path, line and column.
    static let colon: Unicode.Scalar = ":"
    /// What separates a diagnostic's place, severity and message, as
    /// scalars.
    static let separatorScalars = ": ".unicodeScalars
    /// What a time's unit is.
    static let unit = "ms"
    /// Hundredths of a millisecond in one.
    static let hundredthsPerMillisecond = 100
    /// Hundredths of a millisecond in a tenth.
    static let hundredthsPerTenth = 10
    /// The most fraction digits a time has.
    static let fractionDigits = 2
    /// The most whole digits a time has. Assumed, not forced: no single
    /// type-check entry reaches 10^12 ms (about 31 years), so a time with
    /// more isn't one the compiler printed, and its line is counted
    /// unparsed; like every line holding `ms<TAB>` it ends a diagnostic's
    /// message (`continues`), so it is counted there too. The bound also
    /// keeps every time read far inside `Int`: twelve digits are under
    /// 10^14 hundredths.
    static let wholeDigits = 12
    /// The fields of an expression's timing line: time and place.
    static let expressionFields = 2
    /// The fields of a function body's timing line: time, place and
    /// declaration.
    static let functionFields = 3
    /// What lines that can't continue a message start with, as scalars.
    static let linePrefixes = (BuildDiagnostic.Severity.allCases.map { $0.rawValue + ": " } + ["info: "])
        .map(\.unicodeScalars)
    /// The decorations a note's line starts with, as scalars.
    static let decorations = ["`- ", "|- "].map(\.unicodeScalars)
    /// What a box line starts with after its spaces, as scalars.
    static let boxStart = "+-".unicodeScalars
    /// What a group footnote starts with, as scalars.
    static let footnoteStart = "[#".unicodeScalars
    /// What separates a group footnote's name from its link, as scalars.
    static let footnoteSeparator = "]: <".unicodeScalars

    /// The entry a whole timing line states, or nil.
    static func timingEntry(_ text: String) -> TimingEntry? {
        let fields = text.split(separator: "\t", omittingEmptySubsequences: false)
        guard fields.count == expressionFields || fields.count == functionFields,
              let hundredths = hundredths(fields[0])
        else {
            return nil
        }
        var place: BuildPlace?
        if fields[1] != invalidLocation {
            guard let parsed = splitPlace(fields[1]) else {
                return nil
            }
            place = parsed
        }
        guard let declaration = fields.dropFirst(expressionFields).first else {
            return TimingEntry(kind: .expression, hundredths: hundredths, place: place, declaration: nil)
        }
        guard declaration.isEmpty == false else {
            return nil
        }
        return TimingEntry(kind: .function, hundredths: hundredths, place: place, declaration: String(declaration))
    }

    /// `<digits>[.<one or two digits>]ms` as hundredths of a millisecond
    /// (`4.35ms` 435, `4.3ms` 430, `4ms` 400), else nil; nil too when the
    /// whole part has more than `wholeDigits` digits.
    static func hundredths(_ field: Substring) -> Int? {
        guard field.hasSuffix(unit) else {
            return nil
        }
        let parts = field.dropLast(unit.count).split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        guard let wholeText = parts.first, wholeText.count <= wholeDigits, let whole = digits(wholeText) else {
            return nil
        }
        guard let fractionText = parts.dropFirst().first else {
            return whole * hundredthsPerMillisecond
        }
        guard fractionText.count <= fractionDigits, let fraction = digits(fractionText) else {
            return nil
        }
        let scale = fractionText.count == fractionDigits ? 1 : hundredthsPerTenth
        return whole * hundredthsPerMillisecond + fraction * scale
    }

    /// Whether `line` holds `ms<TAB>`: a timing line, read or refused (a
    /// time past `wholeDigits` whole digits, a bad place, a stray field).
    /// Such a line is never part of a diagnostic's message, and on the
    /// standard error one that states no entry is counted. The mark is
    /// found in the line's UTF-8 bytes, not its Characters, so a Prepend
    /// scalar that joins the `m` into one Character doesn't hide it
    /// (design U13), as the checker finds it.
    static func holdsTimingMark(_ line: String) -> Bool {
        line.utf8.contains(timingMark.utf8)
    }

    /// The value of `text` when it is one or more ASCII digits, else nil.
    static func digits(_ text: Substring) -> Int? {
        guard text.isEmpty == false, text.allSatisfy({ $0.isASCII && $0.isNumber }) else {
            return nil
        }
        return Int(text)
    }

    /// `<path>:<line>:<column>` split from the right at its last two
    /// colons, the path not empty and not starting with white space, else
    /// nil. The colons are found among the text's Unicode scalars, not its
    /// Characters, so a Prepend scalar just before one, which joins it into
    /// one Character, stays in the field before it and doesn't hide it
    /// (design B23, decided U13), as the checker splits on code points.
    static func splitPlace(_ text: Substring) -> BuildPlace? {
        let scalars = text.unicodeScalars
        guard let lastColon = scalars.lastIndex(of: colon) else {
            return nil
        }
        let head = scalars[..<lastColon]
        guard let middleColon = head.lastIndex(of: colon),
              let column = digits(Substring(scalars[scalars.index(after: lastColon)...])),
              let line = digits(Substring(head[head.index(after: middleColon)...]))
        else {
            return nil
        }
        let path = head[..<middleColon]
        guard let first = path.first, first.properties.isWhitespace == false else {
            return nil
        }
        return BuildPlace(path: String(Substring(path)), line: line, column: column)
    }

    /// Whether `text` can never be a diagnostic's first line: blank (every
    /// scalar white space), a source excerpt line (spaces and ASCII digits
    /// or nothing before its first `|`), a box line (`+---`) or a decorated
    /// line (`` `- `` or `|- `). Read on Unicode scalars, not Characters,
    /// so a space that a combining mark joins isn't blank, and a mark after
    /// a `|`, a `+-` or a decoration doesn't hide it (decided U13), as the
    /// checker reads code points.
    static func isStructural(_ text: String) -> Bool {
        let scalars = text.unicodeScalars
        if scalars.allSatisfy(\.properties.isWhitespace) {
            return true
        }
        if let bar = scalars.firstIndex(of: "|"),
           scalars[..<bar].allSatisfy({ $0 == " " || ("0"..."9").contains($0) }) {
            return true
        }
        return scalars.drop { $0 == " " }.starts(with: boxStart) || decorated(text) != nil
    }

    /// The text after a `` `- `` or `|- `` decoration at the start of
    /// `text`, spaces before it allowed; nil when it has none. The
    /// decoration is found among scalars, so a combining mark after its
    /// space stays in the text after it (decided U13).
    static func decorated(_ text: String) -> Substring? {
        let trimmed = text.unicodeScalars.drop { $0 == " " }
        guard let mark = decorations.first(where: { trimmed.starts(with: $0) }) else {
            return nil
        }
        return Substring(trimmed.dropFirst(mark.count))
    }

    /// Whether `text` is a group's footnote, `[#Group]: <https://…>`, its
    /// parts found among scalars (decided U13).
    static func isGroupFootnote(_ text: String) -> Bool {
        let scalars = text.unicodeScalars
        return scalars.starts(with: footnoteStart)
            && scalars.firstRange(of: footnoteSeparator) != nil
            && scalars.last == ">"
    }

    /// Whether `line` starts with `prefix`, compared scalar by scalar, so a
    /// combining mark just after the prefix doesn't hide it (decided U13).
    static func starts(_ line: String, with prefix: String.UnicodeScalarView) -> Bool {
        line.unicodeScalars.starts(with: prefix)
    }

    /// Whether `line` can continue a diagnostic's message: it isn't blank,
    /// a line holding `ms<TAB>` (a timing line, whether or not it reads as
    /// one; design B10), a diagnostic, an excerpt, box or decorated line, a
    /// group footnote, or a line starting `warning: `, `error: `, `note: `,
    /// `remark: ` or `info: `.
    static func continues(_ line: String) -> Bool {
        !(isStructural(line)
            || holdsTimingMark(line)
            || header(line[...]) != nil
            || linePrefixes.contains { starts(line, with: $0) }
            || isGroupFootnote(line))
    }

    /// A diagnostic's first line, read; nil when `text` is none. The `: `
    /// separators, the severity and where the message starts are found
    /// among the text's Unicode scalars, not its Characters, so a Prepend
    /// scalar before a separator or a combining mark after one moves no
    /// field's boundary (design B23, decided U13).
    static func header(_ text: Substring) -> DiagnosticHeader? {
        let scalars = text.unicodeScalars
        var searchStart = scalars.startIndex
        while let separator = scalars[searchStart...].firstRange(of: separatorScalars) {
            let rest = scalars[separator.upperBound...]
            let severity = BuildDiagnostic.Severity.allCases.first { severity in
                rest.starts(with: (severity.rawValue + ": ").unicodeScalars)
                    || rest.elementsEqual((severity.rawValue + ":").unicodeScalars)
            }
            if let severity, let location = location(Substring(scalars[..<separator.lowerBound])) {
                let message = Substring(rest.dropFirst(severity.rawValue.unicodeScalars.count + separatorScalars.count))
                return DiagnosticHeader(location: location, severity: severity, message: message)
            }
            searchStart = separator.upperBound
        }
        return nil
    }

    /// The place `line` names when it is a macro expansion's origin note,
    /// `` `- <path>:<line>:<column>: note: expanded code originates here``;
    /// nil otherwise.
    static func originPlace(_ line: String) -> BuildPlace? {
        guard let inner = decorated(line), let header = header(inner), header.severity == .note,
              header.message.trimmingCharacters(in: .whitespaces) == originNote,
              case .file(let place) = header.location
        else {
            return nil
        }
        return place
    }

    /// The location a diagnostic's place prefix names, else nil: a macro
    /// expansion's, `<unknown>:<line>`, or `<path>:<line>:<column>`. The
    /// forms are told apart on Unicode scalars, as `header` reads them.
    private static func location(_ prefix: Substring) -> BuildDiagnostic.Location? {
        let scalars = prefix.unicodeScalars
        let macro = macroPlace.unicodeScalars
        if scalars.starts(with: macro) {
            guard let place = splitPlace(Substring(scalars.dropFirst(macro.count))),
                  let sigil = place.path.first, sigil == "#" || sigil == "@", place.path.count > 1,
                  place.path.dropFirst().allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "." })
            else {
                return nil
            }
            return .macro(name: place.path, line: place.line, column: place.column)
        }
        let unknown = (unknownPlace + ":").unicodeScalars
        if scalars.starts(with: unknown), let line = digits(Substring(scalars.dropFirst(unknown.count))) {
            return .unknown(line: line)
        }
        return splitPlace(prefix).map(BuildDiagnostic.Location.file)
    }
}
