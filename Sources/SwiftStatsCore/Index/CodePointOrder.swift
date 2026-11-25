//
//  CodePointOrder.swift
//  SwiftStatsCore
//
//  The order the index's coupling uses wherever an order decides a result
//  (M7, design §4: the first five test referrers, the numbering of USR type
//  cycles): strings compared by their Unicode scalars, one by one, as
//  Python's `sorted()` orders the independent checker's figures. `String`'s
//  own `<` compares canonical forms, so a decomposed name would sort apart.
//

/// Code point order on strings and on lists of them.
enum CodePointOrder {
    /// Whether `lhs` comes before `rhs` in code point order.
    static func precedes(_ lhs: String, _ rhs: String) -> Bool {
        lhs.unicodeScalars.lexicographicallyPrecedes(rhs.unicodeScalars)
    }

    /// Whether `lhs` comes before `rhs`, compared element by element in
    /// code point order, a shorter prefix first.
    static func precedes(_ lhs: [String], _ rhs: [String]) -> Bool {
        lhs.lexicographicallyPrecedes(rhs) { precedes($0, $1) }
    }
}
