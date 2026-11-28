//
//  YAMLText.swift
//  SwiftStatsCoreTests
//
//  How a configuration draft's scalars are written (YAML 1.2, as libyaml
//  reads it, which Yams wraps). A plain scalar is written only when YAML
//  reads it back as the same text in block and in flow context: not empty,
//  no space at either end, only printable scalars and no tab, no flow
//  indicator (`,[]{}`), no `: ` or ` #`, no `:` at the end, not starting
//  with a document marker or an indicator (`-` only before a character
//  that isn't a space, as in `-1`). A single-quoted scalar doubles its
//  quotes and holds no line break, tab or unprintable scalar. A
//  double-quoted scalar escapes the backslash, the quote, the tab and
//  every scalar libyaml doesn't count printable (the controls, DEL, the C1
//  controls, U+FEFF, U+FFFE and U+FFFF), and next line, the line and
//  paragraph separators, so any text can be written double-quoted.
//

/// The rules a draft's scalars are written by.
enum YAMLText {
    /// The characters a plain scalar may not start with.
    static let indicators: Set<Unicode.Scalar> = [
        "-", "?", ":", ",", "[", "]", "{", "}", "#", "&", "*", "!", "|", ">", "'", "\"", "%", "@", "`"
    ]
    /// The flow indicators, which a plain scalar in flow context may not hold.
    static let flowIndicators: Set<Unicode.Scalar> = [",", "[", "]", "{", "}"]
    /// Document markers, which a plain scalar may not start with.
    static let documentMarkers = ["---", "..."]
    /// The scalars that break a line in YAML or as Unicode: line feed,
    /// carriage return, next line, line separator, paragraph separator.
    static let lineBreaks: Set<Unicode.Scalar> = ["\n", "\r", "\u{85}", "\u{2028}", "\u{2029}"]
    /// The radix a double-quoted escape is written in.
    static let hexadecimal = 16
    /// The digits of a `\u` escape.
    static let shortEscapeDigits = 4
    /// The digits of a `\U` escape.
    static let longEscapeDigits = 8
    /// The first scalar a `\u` escape can't hold.
    static let firstAstral: UInt32 = 0x1_0000
    /// The printable ASCII scalars (space to tilde).
    static let printableASCII: ClosedRange<UInt32> = 0x20...0x7E
    /// Printable scalars from no-break space to the last before the surrogates.
    static let printableLow: ClosedRange<UInt32> = 0xA0...0xD7FF
    /// Printable scalars after the surrogates, up to U+FFFD.
    static let printableHigh: ClosedRange<UInt32> = 0xE000...0xFFFD
    /// The byte order mark, which libyaml doesn't count printable.
    static let byteOrderMark: UInt32 = 0xFEFF

    /// Whether libyaml counts `scalar` printable inside a scalar, line
    /// breaks and the tab aside.
    static func isPrintable(_ scalar: Unicode.Scalar) -> Bool {
        let value = scalar.value
        return printableASCII.contains(value)
            || (printableLow.contains(value) && lineBreaks.contains(scalar) == false)
            || (printableHigh.contains(value) && value != byteOrderMark)
            || value >= firstAstral
    }

    /// Whether `text` written plain reads back as itself in block and in
    /// flow context. Checked on scalars, as libyaml reads it (a combining
    /// mark after `#` doesn't hide the comment), in one pass.
    static func isPlainSafe(_ text: String) -> Bool {
        var first: Unicode.Scalar?
        var second: Unicode.Scalar?
        var previous: Unicode.Scalar?
        for scalar in text.unicodeScalars {
            guard isPrintable(scalar), flowIndicators.contains(scalar) == false,
                  (previous == ":" && scalar == " ") == false, (previous == " " && scalar == "#") == false else {
                return false
            }
            if first == nil {
                first = scalar
            } else if second == nil {
                second = scalar
            }
            previous = scalar
        }
        guard let first, let last = previous, first != " ", last != " ", last != ":",
              documentMarkers.contains(where: text.hasPrefix) == false else {
            return false
        }
        guard indicators.contains(first) else {
            return true
        }
        return first == "-" && second != nil && second != " "
    }

    /// Whether `text` can be written single-quoted.
    static func isSingleSafe(_ text: String) -> Bool {
        text.unicodeScalars.allSatisfy(isPrintable)
    }

    /// `text` between single quotes, each quote doubled.
    static func singleQuoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "''") + "'"
    }

    /// `text` between double quotes, escaped.
    static func doubleQuoted(_ text: String) -> String {
        let escaped = text.unicodeScalars.map { scalar -> String in
            switch scalar {
            case "\\":
                return "\\\\"

            case "\"":
                return "\\\""

            case "\t":
                return "\\t"

            default:
                guard isPrintable(scalar) == false else {
                    return String(scalar)
                }
                return escape(scalar)
            }
        }
        return "\"" + escaped.joined() + "\""
    }

    /// `scalar` as a `\u` or `\U` escape.
    static func escape(_ scalar: Unicode.Scalar) -> String {
        let digits = String(scalar.value, radix: hexadecimal, uppercase: true)
        let (prefix, width) = scalar.value < firstAstral ? ("\\u", shortEscapeDigits) : ("\\U", longEscapeDigits)
        return prefix + String(repeating: "0", count: width - digits.count) + digits
    }
}
