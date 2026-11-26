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
//  diagnostic is its origin note.
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
    /// unparsed. The bound also keeps every time read far inside `Int`:
    /// twelve digits are under 10^14 hundredths.
    static let wholeDigits = 12
    /// The fields of an expression's timing line: time and place.
    static let expressionFields = 2
    /// The fields of a function body's timing line: time, place and
    /// declaration.
    static let functionFields = 3
    /// What lines that can't continue a message start with.
    static let linePrefixes = BuildDiagnostic.Severity.allCases.map { $0.rawValue + ": " } + ["info: "]
    /// The decorations a note's line starts with.
    static let decorations = ["`- ", "|- "]

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

    /// The value of `text` when it is one or more ASCII digits, else nil.
    static func digits(_ text: Substring) -> Int? {
        guard text.isEmpty == false, text.allSatisfy({ $0.isASCII && $0.isNumber }) else {
            return nil
        }
        return Int(text)
    }

    /// `<path>:<line>:<column>` split from the right, the path not empty
    /// and not starting with white space, else nil.
    static func splitPlace(_ text: Substring) -> BuildPlace? {
        guard let lastColon = text.lastIndex(of: ":") else {
            return nil
        }
        let head = text[..<lastColon]
        guard let middleColon = head.lastIndex(of: ":"),
              let column = digits(text[text.index(after: lastColon)...]),
              let line = digits(head[head.index(after: middleColon)...])
        else {
            return nil
        }
        let path = head[..<middleColon]
        guard let first = path.first, first.isWhitespace == false else {
            return nil
        }
        return BuildPlace(path: String(path), line: line, column: column)
    }

    /// Whether `text` can never be a diagnostic's first line: blank, a
    /// source excerpt line (digits or nothing before a `|`), a box line
    /// (`+---`) or a decorated line (`` `- `` or `|- `).
    static func isStructural(_ text: String) -> Bool {
        if text.allSatisfy(\.isWhitespace) {
            return true
        }
        if let bar = text.firstIndex(of: "|"),
           text[..<bar].allSatisfy({ $0 == " " || ($0.isASCII && $0.isNumber) }) {
            return true
        }
        return text.drop { $0 == " " }.hasPrefix("+-") || decorated(text) != nil
    }

    /// The text after a `` `- `` or `|- `` decoration at the start of
    /// `text`, spaces before it allowed; nil when it has none.
    static func decorated(_ text: String) -> Substring? {
        let trimmed = text.drop { $0 == " " }
        guard let mark = decorations.first(where: { trimmed.hasPrefix($0) }) else {
            return nil
        }
        return trimmed.dropFirst(mark.count)
    }

    /// Whether `text` is a group's footnote, `[#Group]: <https://…>`.
    static func isGroupFootnote(_ text: String) -> Bool {
        text.hasPrefix("[#") && text.contains("]: <") && text.hasSuffix(">")
    }

    /// Whether `line` can continue a diagnostic's message: it isn't blank,
    /// a timing line, a diagnostic, an excerpt, box or decorated line, a
    /// group footnote, or a line starting `warning: `, `error: `, `note: `,
    /// `remark: ` or `info: `.
    static func continues(_ line: String) -> Bool {
        !(isStructural(line)
            || timingEntry(line) != nil
            || header(line[...]) != nil
            || linePrefixes.contains { line.hasPrefix($0) }
            || isGroupFootnote(line))
    }

    /// A diagnostic's first line, read; nil when `text` is none.
    static func header(_ text: Substring) -> DiagnosticHeader? {
        var searchStart = text.startIndex
        while let separator = text.range(of: ": ", range: searchStart..<text.endIndex) {
            let rest = text[separator.upperBound...]
            let severity = BuildDiagnostic.Severity.allCases.first { severity in
                rest.hasPrefix(severity.rawValue + ": ") || rest == severity.rawValue + ":"
            }
            if let severity, let location = location(text[..<separator.lowerBound]) {
                return DiagnosticHeader(
                    location: location,
                    severity: severity,
                    message: rest.dropFirst(severity.rawValue.count + ": ".count)
                )
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
    /// expansion's, `<unknown>:<line>`, or `<path>:<line>:<column>`.
    private static func location(_ prefix: Substring) -> BuildDiagnostic.Location? {
        if prefix.hasPrefix(macroPlace) {
            guard let place = splitPlace(prefix.dropFirst(macroPlace.count)),
                  let sigil = place.path.first, sigil == "#" || sigil == "@", place.path.count > 1,
                  place.path.dropFirst().allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "." })
            else {
                return nil
            }
            return .macro(name: place.path, line: place.line, column: place.column)
        }
        if prefix.hasPrefix(unknownPlace + ":"), let line = digits(prefix.dropFirst(unknownPlace.count + 1)) {
            return .unknown(line: line)
        }
        return splitPlace(prefix).map(BuildDiagnostic.Location.file)
    }
}
