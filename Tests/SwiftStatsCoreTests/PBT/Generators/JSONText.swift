//
//  JSONText.swift
//  SwiftStatsCoreTests
//
//  A JSON value written out exactly as built, for P2.6's exports: numbers
//  keep the spelling they were given (`18446744073709551616`, `3.0`,
//  `1e2`), members keep their order, and nothing is added. Strings are
//  escaped as JSON requires (a quote, a backslash, and the control
//  characters), everything else written as UTF-8. Writing it by hand,
//  rather than through `JSONSerialization` or `JSONEncoder`, is what lets
//  a count be spelled past what a 64-bit integer holds.
//

/// A JSON value, written as built.
enum JSONText: Hashable, Sendable {
    /// An array of these values.
    case array([Self])
    /// `true` or `false`.
    case bool(Bool)
    /// A number, spelled as given.
    case number(String)
    /// An object of these members, in order.
    case object([Member])
    /// A string.
    case string(String)

    /// One member of an object.
    struct Member: Hashable, Sendable {
        /// Its key.
        let key: String
        /// Its value.
        let value: JSONText
    }

    /// The radix a control character's escape is written in.
    static let hexadecimal = 16
    /// The scalars below this are control characters, escaped.
    static let firstPrintable: UInt32 = 0x20
    /// The digits a control character's escape has.
    static let escapeDigits = 4

    /// The value written out, with no whitespace.
    var text: String {
        switch self {
        case .array(let values):
            return "[" + values.map(\.text).joined(separator: ",") + "]"

        case .bool(let value):
            return value ? "true" : "false"

        case .number(let spelling):
            return spelling

        case .object(let members):
            return "{" + members.map { Self.quoted($0.key) + ":" + $0.value.text }.joined(separator: ",") + "}"

        case .string(let value):
            return Self.quoted(value)
        }
    }

    /// An integer, spelled in decimal.
    static func integer(_ value: some BinaryInteger) -> Self {
        .number("\(value)")
    }

    /// `value` as a JSON string literal.
    static func quoted(_ value: String) -> String {
        let escaped = value.unicodeScalars.map { scalar -> String in
            switch scalar {
            case "\"":
                return "\\\""

            case "\\":
                return "\\\\"

            default:
                guard scalar.value < firstPrintable else {
                    return String(scalar)
                }
                let digits = String(scalar.value, radix: hexadecimal)
                return "\\u" + String(repeating: "0", count: escapeDigits - digits.count) + digits
            }
        }
        return "\"" + escaped.joined() + "\""
    }
}
