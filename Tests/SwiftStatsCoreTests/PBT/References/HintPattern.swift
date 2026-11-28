//
//  HintPattern.swift
//  SwiftStatsCoreTests
//
//  The reference reading of an outskirts hint, for P9.4, written from the
//  spec rather than from `PeripheryOutput.split(_:)`: a hint is split as
//  `name(text)` exactly when the whole of it matches the checker's
//  `([A-Za-z]+)\((.*)\)` (`Scripts/index-check.py`'s `HINT_WITH_TEXT`, read
//  with `fullmatch` on code points): one or more ASCII letters, an opening
//  parenthesis, any text, and a closing parenthesis that ends the hint.
//  The letters can't hold a parenthesis, so the name is the hint's longest
//  run of leading ASCII letters, and it must be followed by the opening
//  one. It works on Unicode scalars, as the checker does and as decided
//  U13 has SwiftStats parse tool output (design B23).
//

/// The reference reading of an outskirts hint.
enum HintPattern {
    /// The opening parenthesis.
    static let opening: Unicode.Scalar = "("
    /// The closing parenthesis.
    static let closing: Unicode.Scalar = ")"
    /// How many parentheses a split hint holds besides its text's.
    static let parentheses = 2

    /// `hint` as its name and the text in its parentheses when the whole
    /// of it is ASCII letters, `(`, any text and `)`; else the hint and nil.
    static func split(_ hint: String) -> (name: String, text: String?) {
        let scalars = Array(hint.unicodeScalars)
        let letters = scalars.prefix(while: isASCIILetter).count
        // The letters and both parentheses: the fewest scalars a split hint
        // has.
        let shortest = letters + parentheses
        guard letters > 0, scalars.count >= shortest, scalars[letters] == opening, scalars.last == closing else {
            return (hint, nil)
        }
        return (text(of: scalars[..<letters]), text(of: scalars[(letters + 1)..<(scalars.count - 1)]))
    }

    /// Whether `scalar` is an ASCII letter, A to Z or a to z.
    static func isASCIILetter(_ scalar: Unicode.Scalar) -> Bool {
        ("A"..."Z").contains(scalar) || ("a"..."z").contains(scalar)
    }

    /// `scalars` as a string.
    static func text(of scalars: ArraySlice<Unicode.Scalar>) -> String {
        String(String.UnicodeScalarView(scalars))
    }
}
