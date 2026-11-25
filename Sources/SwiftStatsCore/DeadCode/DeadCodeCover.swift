//
//  DeadCodeCover.swift
//  SwiftStatsCore
//
//  What one outskirts entry covers (M7, design §5.4): the rule, the
//  records, the unit beyond those records (a type or an extension) and the
//  stripped lines it spans; nothing for an entry that isn't an unused
//  production entry or that no rule maps.
//

/// The records an outskirts entry covers.
struct DeadCodeCover: Sendable {
    /// What an entry no rule maps covers.
    static let nothing = Self(via: nil, keys: [], unit: nil, lines: nil)

    /// The rule; nil when it covers nothing.
    let via: DeadCodeVia?
    /// The covered records' keys, in code point order.
    let keys: [String]
    /// A type's or an extension's unit; nil for an entry covering records
    /// by USR, accessor or position.
    let unit: DeadCodeUnit?
    /// The stripped lines it spans: its records', or its type's or
    /// extension's; nil when it covers nothing.
    let lines: Int?
}
