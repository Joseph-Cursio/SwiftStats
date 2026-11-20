//
//  SignalSortKey.swift
//  SwiftStatsCore
//
//  The order a signal lists its items in: fields compared in turn, the
//  first that differs deciding. Most signals list by score, highest first,
//  then by subject, file and line; a signal with its own order states it.
//

/// Where an item sorts in its signal.
struct SignalSortKey: Comparable, Hashable, Sendable {
    /// One field of a key.
    enum Field: Comparable, Hashable, Sendable {
        /// A number, lowest first.
        case number(Double)
        /// Text, in `String`'s order.
        case text(String)
    }

    /// The fields, compared in turn.
    let fields: [Field]

    /// A key of `fields`.
    init(_ fields: [Field]) {
        self.fields = fields
    }

    /// The default order: score, highest first, then subject, file and line.
    static func standard(score: Double, subject: String, file: String, line: Int) -> Self {
        Self([.number(-score), .text(subject), .text(file), .number(Double(line))])
    }

    /// Whether `lhs` sorts before `rhs`.
    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.fields.lexicographicallyPrecedes(rhs.fields)
    }
}
