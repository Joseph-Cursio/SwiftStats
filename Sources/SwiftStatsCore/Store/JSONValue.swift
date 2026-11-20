//
//  JSONValue.swift
//  SwiftStatsCore
//
//  A decoded JSON value, for walking an encoded roll-up's numbers and
//  comparing a tool's rows field by field.
//

/// Any JSON value.
enum JSONValue: Decodable, Equatable, Sendable {
    /// An array.
    case array([Self])
    /// `true` or `false`.
    case bool(Bool)
    /// `null`.
    case null
    /// A number.
    case number(Double)
    /// An object.
    case object([String: Self])
    /// A string.
    case string(String)

    /// Decodes whichever kind of value is there; booleans are tried before
    /// numbers, since a number never decodes as a boolean.
    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let flag = try? container.decode(Bool.self) {
            self = .bool(flag)
        } else if let number = try? container.decode(Double.self) {
            self = .number(number)
        } else if let text = try? container.decode(String.self) {
            self = .string(text)
        } else if let items = try? container.decode([Self].self) {
            self = .array(items)
        } else {
            self = .object(try container.decode([String: Self].self))
        }
    }
}
