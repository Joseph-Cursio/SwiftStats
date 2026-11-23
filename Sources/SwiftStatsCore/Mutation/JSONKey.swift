//
//  JSONKey.swift
//  SwiftStatsCore
//
//  A JSON object's key by name (M6), for the decoders of SwiftMutator's
//  lines and report, whose types are nested too deep to declare their own
//  `CodingKeys`.
//

/// A JSON object's key.
struct JSONKey: CodingKey, ExpressibleByStringLiteral {
    /// The key's name.
    let stringValue: String

    /// Never an integer key.
    var intValue: Int? {
        nil
    }

    /// The key `name`.
    init(stringLiteral name: String) {
        stringValue = name
    }

    /// The key `stringValue`.
    init?(stringValue: String) {
        self.stringValue = stringValue
    }

    /// No integer keys.
    init?(intValue _: Int) {
        nil
    }
}
