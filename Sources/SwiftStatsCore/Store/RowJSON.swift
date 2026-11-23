//
//  RowJSON.swift
//  SwiftStatsCore
//
//  Text columns of the mutation rows (M6, design §5): lists held as a JSON
//  array in one column (a mutant's `killedBy`, whose names are user
//  strings that may hold any character, so no separator could be safe,
//  and a run's format versions and operators), and values held by name (a
//  mutant's verdict, a suspect test's reason). Reading one back throws
//  when the column doesn't read.
//

import Foundation

/// JSON and named text columns.
enum RowJSON {
    /// A column that doesn't read as what it holds.
    struct Unreadable: Error, Equatable {
        /// The column's text.
        let text: String
    }

    /// `value` as compact JSON text.
    static func text(_ value: some Encodable) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(value), let text = String(bytes: data, encoding: .utf8) else {
            return "null"
        }
        return text
    }

    /// The `type` value `text` holds; it throws when `text` doesn't read
    /// as one.
    static func decoded<Value: Decodable>(_ type: Value.Type, from text: String) throws -> Value {
        try JSONDecoder().decode(type, from: Data(text.utf8))
    }

    /// The `Value` named `text`; it throws when no value is.
    static func named<Value: RawRepresentable<String>>(_: Value.Type, from text: String) throws -> Value {
        guard let value = Value(rawValue: text) else {
            throw Unreadable(text: text)
        }
        return value
    }
}
