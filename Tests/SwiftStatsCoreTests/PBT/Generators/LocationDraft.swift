//
//  LocationDraft.swift
//  SwiftStatsCoreTests
//
//  An outskirts location as decisions, for P9.2 and P9.4: a path that
//  isn't empty, of any scalars, a line and a column from 1 to `Int.max`,
//  and at most one flaw. `PeripheryFields.Location`'s doc comment is the
//  spec: the text is read from the right as `path:line:column`, its colons
//  found among Unicode scalars (design B23, decided U13), with a path that
//  isn't empty and a line and a column that are positive numbers of ASCII
//  decimal digits. So a sound location, rendered, reads back as itself,
//  whatever colons, spaces or Prepend scalars its path holds; one whose
//  number is padded with leading zeros reads as that number, since the
//  digits still spell it; and a flaw in a number (empty, zero, signed,
//  negative, past `Int`, a fullwidth digit, a combining mark or a space
//  beside the digits, a letter after them), a missing column or place, or
//  an empty path makes it read as no location. A location missing its
//  column or place has its path's colons written as `_`, since a path
//  ending in `:12` would otherwise supply the missing number.
//

@testable import SwiftStatsCore

/// An outskirts location as decisions.
struct LocationDraft: Hashable, Sendable {
    /// What is wrong with the location, if anything.
    enum Flaw: Hashable, Sendable {
        /// The path is empty.
        case emptyPath
        /// The column and its colon are missing.
        case noColumn
        /// The line, the column and their colons are missing.
        case noPlace
        /// The line's number, or the column's when `inColumn`, is written
        /// with this flaw.
        case number(NumberFlaw, inColumn: Bool)
        /// The line's number, or the column's when `inColumn`, has this
        /// many leading zeros.
        case padded(zeros: Int, inColumn: Bool)
        /// Nothing.
        case sound
    }

    /// How a flawed number is written.
    enum NumberFlaw: String, CaseIterable, Hashable, Sendable {
        /// Not at all.
        case empty
        /// In fullwidth digits.
        case fullwidth
        /// With a combining mark after its last digit.
        case marked
        /// With a minus sign.
        case negative
        /// With nineteen zeros after it, past `Int.max`.
        case pastInt
        /// With a plus sign.
        case signed
        /// With a space before it.
        case spaced
        /// With a letter after it.
        case word
        /// As 0.
        case zero
    }

    /// The scalar a flawed number's combining mark is (forced: an acute
    /// accent joins the digit before it into one Character).
    static let combiningMark = "\u{301}"
    /// How many zeros a number past `Int.max` appends (forced: any
    /// positive number times 10^19 is past `Int.max`, about 9.2 * 10^18).
    static let pastIntZeroCount = 19
    /// What a number past `Int.max` appends.
    static let pastIntZeros = String(repeating: "0", count: pastIntZeroCount)
    /// The fullwidth digit zero; the others follow it (forced: Unicode's
    /// Halfwidth and Fullwidth Forms block).
    static let fullwidthZero: UInt32 = 0xFF10
    /// What a path's colons become when the location has no column or
    /// place.
    static let colonReplacement = "_"

    /// The path, as outskirts wrote it.
    let path: String
    /// The 1-based line.
    let line: Int
    /// The 1-based column.
    let column: Int
    /// What is wrong, if anything.
    let flaw: Flaw

    /// The location as text.
    var rendered: String {
        switch flaw {
        case .emptyPath:
            return ":\(line):\(column)"

        case .noColumn:
            return colonless + ":\(line)"

        case .noPlace:
            return colonless

        case let .number(numberFlaw, inColumn):
            let written = Self.written(inColumn ? column : line, numberFlaw)
            return inColumn ? "\(path):\(line):\(written)" : "\(path):\(written):\(column)"

        case let .padded(zeros, inColumn):
            let padding = String(repeating: "0", count: zeros)
            return inColumn ? "\(path):\(line):\(padding)\(column)" : "\(path):\(padding)\(line):\(column)"

        case .sound:
            return "\(path):\(line):\(column)"
        }
    }

    /// What the text should read as: the drafted place when it is sound
    /// or only padded, else no location.
    var expected: PeripheryFields.Location? {
        switch flaw {
        case .padded, .sound:
            return PeripheryFields.Location(path: path, line: line, column: column)

        case .emptyPath, .noColumn, .noPlace, .number:
            return nil
        }
    }

    /// The path with every colon written as `_`.
    var colonless: String {
        String(String.UnicodeScalarView(path.unicodeScalars.flatMap { scalar in
            scalar == ":" ? Array(Self.colonReplacement.unicodeScalars) : [scalar]
        }))
    }

    /// `number` written with `flaw`.
    static func written(_ number: Int, _ flaw: NumberFlaw) -> String {
        switch flaw {
        case .empty:
            return ""

        case .fullwidth:
            let scalars = String(number).unicodeScalars.compactMap { digit in
                Unicode.Scalar(fullwidthZero + digit.value - ("0" as Unicode.Scalar).value)
            }
            return String(String.UnicodeScalarView(scalars))

        case .marked:
            return "\(number)" + combiningMark

        case .negative:
            return "-\(number)"

        case .pastInt:
            return "\(number)" + pastIntZeros

        case .signed:
            return "+\(number)"

        case .spaced:
            return " \(number)"

        case .word:
            return "\(number)x"

        case .zero:
            return "0"
        }
    }
}
