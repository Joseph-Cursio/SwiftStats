//
//  JSONFlag.swift
//  SwiftStatsCore
//
//  A JSON boolean that SwiftMutator may leave out (M6, design §2): a
//  property of this type, optional, reads `true`, `false` or absent
//  without an optional `Bool`.
//

/// A JSON boolean.
struct JSONFlag: Decodable, Equatable, Sendable {
    /// Its value.
    let value: Bool

    /// The flag `value`.
    init(_ value: Bool) {
        self.value = value
    }

    /// Reads a JSON boolean.
    init(from decoder: any Decoder) throws {
        value = try decoder.singleValueContainer().decode(Bool.self)
    }
}
