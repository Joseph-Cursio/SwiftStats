//
//  MutantKeyGen+Spelling.swift
//  SwiftStatsCoreTests
//
//  Strings near the spellings of mutant keys, for P3.3. A spelling is a
//  key's (`MutantKeyGen`), written part by part as SwiftMutator spells it
//  (`path:line:column Operator`, plus ` (#k)` for occurrence k − 1 > 0), with
//  up to two flaws, each replacing one part: a number with a sign, a
//  leading zero, a digit outside ASCII or a value past `Int` (one that
//  wraps negative, or one that wraps to a valid number); a colon or the
//  space missing or doubled; an empty path or operator; a repeat of 1, 0,
//  or malformed. Or it is a run of the pieces keys are made of, joined at
//  random. The flaws are weighted so that each refusal branch a planted
//  defect can drop comes in a few percent of draws.
//

import PropertyBased
@testable import SwiftStatsCore
import Testing

/// Strings near the spellings of keys in P3.1's domain, P3.3's input.
extension MutantKeyGen {
    /// A part of a key's spelling.
    enum Part: Sendable, CaseIterable {
        /// The column.
        case column
        /// The colon before the column.
        case columnColon
        /// The line.
        case line
        /// The colon before the line.
        case lineColon
        /// The operator.
        case operatorID
        /// The path.
        case path
        /// ` (#k)`, or nothing for occurrence 0.
        case repeatSuffix
        /// The space before the operator.
        case space
    }

    /// One way to spell a number other than as SwiftMutator prints it.
    enum NumberFlaw: Sendable, CaseIterable {
        /// Its digits as Arabic-Indic digits.
        case arabicIndic
        /// No digits at all.
        case empty
        /// Its digits as fullwidth digits.
        case fullwidth
        /// A `0` before it.
        case leadingZero
        /// A `-` before it.
        case minus
        /// `Int.max` plus it, past what an `Int` holds.
        case overflow
        /// A `+` before it.
        case plus
        /// A space before it.
        case spaced
        /// Its digits as superscript digits.
        case superscript
        /// 2^64 plus it: past what an `Int` holds, and read with wrapping
        /// arithmetic, itself.
        case wrapped
        /// `0`.
        case zero

        /// What the flaw writes before the digits, when that is all it
        /// does; empty otherwise.
        var prefix: String {
            switch self {
            case .leadingZero:
                "0"
            case .minus:
                "-"
            case .plus:
                "+"
            case .spaced:
                " "
            default:
                ""
            }
        }
    }

    /// One part of a key's spelling written otherwise.
    struct Flaw: Sendable, CustomTestStringConvertible {
        /// The part.
        let part: Part
        /// What is written in its place.
        let text: String

        /// The part and its text, in ASCII.
        var testDescription: String {
            PBTTrace.ascii("\(part) as \(text.debugDescription)")
        }
    }

    /// Where a spelling came from.
    enum Source: Sendable {
        /// A key's spelling with these flaws, none when empty.
        case key(MutantKey, flaws: [Flaw])
        /// Pieces joined at random.
        case pieces
    }

    /// A string near a key's spelling, P3.3's input.
    struct Spelling: Sendable, CustomTestStringConvertible {
        /// The string.
        let text: String
        /// Where it came from.
        let source: Source

        /// The string and its source, in ASCII.
        var testDescription: String {
            switch source {
            case let .key(key, flaws):
                let flawText = flaws.isEmpty ? "no flaw" : flaws.map(\.testDescription).joined(separator: ", ")
                let origin = "from " + MutantKeyGen.parts(of: key) + " with \(flawText)"
                return PBTTrace.ascii("\(text.debugDescription), \(origin)")
            case .pieces:
                return PBTTrace.ascii("\(text.debugDescription), from pieces")
            }
        }
    }

    /// The parts in the order a spelling writes them.
    static let order: [Part] = [.path, .lineColon, .line, .columnColon, .column, .space, .operatorID, .repeatSuffix]
    /// The number flaws, simplest first.
    static let numberFlaws: [NumberFlaw] = [
        .empty, .zero, .plus, .minus, .leadingZero, .spaced, .overflow, .wrapped, .fullwidth, .arabicIndic,
        .superscript
    ]
    /// The number flaws decided U11 added: a sign and a leading zero, which
    /// `Int(_:)` alone reads.
    static let signFlaws: [NumberFlaw] = [.plus, .leadingZero]
    /// What a flawed colon is: none, two, a space, a fullwidth colon or a
    /// semicolon.
    static let colonFlaws = ["", "::", " ", "\u{FF1A}", ";"]
    /// What a flawed space is: none, two, a tab or a no-break space.
    static let spaceFlaws = ["", "  ", "\t", "\u{A0}"]
    /// What a flawed operator is, besides empty: one holding a space,
    /// a space, and one ending in `)` (which reads as itself when no
    /// ` (#` comes before it).
    static let operatorFlaws = ["a b", " ", "Op ", " Op", "x)"]
    /// A repeat of 1, which SwiftMutator never spells: occurrence 0 has no
    /// repeat.
    static let lowRepeat = " (#1)"
    /// A repeat of 0, malformed repeats, and the two either side of the
    /// largest.
    static let repeatFlaws = [
        " (#0)",
        " (#)",
        ")",
        " (#x)",
        " (#2",
        " #2)",
        "(#2)",
        " (# 2)",
        " (#2)x",
        " (#2) (#3)",
        " (#9223372036854775807)",
        " (#9223372036854775808)",
        " (#99999999999999999999)"
    ]
    /// Pieces a spelling of pieces is joined from, simplest first.
    static let spellingPieces = [
        "a", ":", " ", "1", "0", "2", "9", " (#", ")", "#", "(", "+", "-", "Op", "/", ".swift", "12",
        "\u{600}", "\u{301}", "\u{FF11}", "9223372036854775807", "9223372036854775808"
    ]
    /// How many pieces a spelling of pieces has (assumed: enough for two
    /// places and a repeat).
    static let pieceCount = 0...16
    /// The code point of Arabic-Indic digit zero.
    static let arabicIndicZero: UInt32 = 0x660
    /// The code point of fullwidth digit zero.
    static let fullwidthZero: UInt32 = 0xFF10
    /// The superscript digits 0 to 9.
    static let superscripts: [Unicode.Scalar] = [
        "\u{2070}", "\u{B9}", "\u{B2}", "\u{B3}", "\u{2074}", "\u{2075}", "\u{2076}", "\u{2077}", "\u{2078}", "\u{2079}"
    ]
    /// The code point of ASCII `0`.
    static let asciiZero = Unicode.Scalar("0").value
    /// 2^64's digits but its last six (forced: 2^64 is 18446744073709551616).
    static let wrapHead = "18446744073709"
    /// 2^64's last six digits; any number up to `smallNumber` added to them
    /// stays six digits, so 2^64 + n is `wrapHead` then `wrapTail + n`.
    static let wrapTail = 551_616

    /// Weight of a flaw in a line or a column, each.
    static let numberPartWeight = 2.0
    /// Weight of a flaw in the repeat.
    static let repeatPartWeight = 3.0
    /// Weight of a flaw in the path or the operator, each.
    static let textPartWeight = 2.0
    /// Weight of a sign or leading zero among the number flaws (decided
    /// U11's flaws, which a defect undoing U11 accepts).
    static let signWeight = 4.0
    /// Weight of a number that wraps to itself (`.wrapped`) among the number
    /// flaws: a reader folding digits with wrapping arithmetic accepts it
    /// even when it refuses a negative, which `.overflow` wraps to.
    static let wrappedWeight = 4.0
    /// Weight of the other number flaws.
    static let otherNumberWeight = 8.0
    /// Weight of an empty operator among the operator flaws.
    static let emptyOperatorWeight = 3.0
    /// Weight of a repeat of 1 among the repeat flaws.
    static let lowRepeatWeight = 3.0
    /// Weight of a flawed number in a repeat, and of a malformed repeat.
    static let repeatClassWeight = 2.0
    /// Weight of keys' spellings among the spellings.
    static let keySpellingWeight = 8.0
    /// The share of spellings with a first flaw.
    static let firstFlawRate: Float = 0.6
    /// The share of spellings with a second flaw.
    static let secondFlawRate: Float = 0.1

    /// A number spelled otherwise: one of the number flaws applied to a
    /// small number.
    static let flawedNumber = zip(
        Gen.frequency(
            (signWeight, Pick.element(of: signFlaws)),
            (wrappedWeight, Gen.always(NumberFlaw.wrapped)),
            (otherNumberWeight, Pick.element(of: numberFlaws))
        ),
        Gen<Int>.value(in: 1...smallNumber)
    )
    .map { flaw, value in flawed(value, by: flaw) }

    /// A repeat spelled otherwise: 1, a flawed number, or malformed.
    static let flawedRepeat = Gen.frequency(
        (lowRepeatWeight, Gen.always(lowRepeat)),
        (repeatClassWeight, flawedNumber.map { " (#\($0))" }),
        (repeatClassWeight, Pick.element(of: repeatFlaws))
    )

    /// One part of a spelling written otherwise.
    static let flaw = Gen.frequency(
        (numberPartWeight, flawedNumber.map { Flaw(part: .line, text: $0) }),
        (numberPartWeight, flawedNumber.map { Flaw(part: .column, text: $0) }),
        (repeatPartWeight, flawedRepeat.map { Flaw(part: .repeatSuffix, text: $0) }),
        (classWeight, Pick.element(of: colonFlaws).map { Flaw(part: .lineColon, text: $0) }),
        (classWeight, Pick.element(of: colonFlaws).map { Flaw(part: .columnColon, text: $0) }),
        (classWeight, Pick.element(of: spaceFlaws).map { Flaw(part: .space, text: $0) }),
        (
            textPartWeight,
            Gen.frequency(
                (emptyOperatorWeight, Gen.always("")),
                (classWeight, Pick.element(of: operatorFlaws))
            )
            .map { Flaw(part: .operatorID, text: $0) }
        ),
        (textPartWeight, Gen.always(Flaw(part: .path, text: "")))
    )

    /// A key's spelling with up to two flaws.
    static let flawedSpelling = zip(
        key,
        flaw.optional(valueRate: firstFlawRate),
        flaw.optional(valueRate: secondFlawRate)
    )
    .map { key, first, second in
        let flaws = [first, second].compactMap(\.self)
        return Spelling(text: written(key, flaws: flaws), source: .key(key, flaws: flaws))
    }

    /// Pieces of keys joined at random.
    static let pieceSpelling = Pick.element(of: spellingPieces)
        .array(of: pieceCount)
        .map { Spelling(text: $0.joined(), source: .pieces) }

    /// A string near a key's spelling, P3.3's input.
    static let spelling = Gen.frequency(
        (keySpellingWeight, flawedSpelling),
        (classWeight, pieceSpelling)
    )

    /// `key` written part by part as the format states, with each of
    /// `flaws` in place of its part, a later flaw of the same part winning.
    static func written(_ key: MutantKey, flaws: [Flaw]) -> String {
        var parts: [Part: String] = [
            .path: key.path,
            .lineColon: ":",
            .line: String(key.line),
            .columnColon: ":",
            .column: String(key.column),
            .space: " ",
            .operatorID: key.operatorID,
            .repeatSuffix: key.occurrence > 0 ? " (#\(key.occurrence + 1))" : ""
        ]
        for change in flaws {
            parts[change.part] = change.text
        }
        return order.map { parts[$0] ?? "" }.joined()
    }

    /// `value`, a positive number up to `smallNumber`, spelled with
    /// `flaw`.
    static func flawed(_ value: Int, by flaw: NumberFlaw) -> String {
        let digits = String(value)
        switch flaw {
        case .arabicIndic:
            return shifted(digits, to: arabicIndicZero)
        case .empty:
            return ""
        case .fullwidth:
            return shifted(digits, to: fullwidthZero)
        case .leadingZero, .minus, .plus, .spaced:
            return flaw.prefix + digits
        case .overflow:
            return String(UInt(Int.max) + UInt(value))
        case .superscript:
            return String(String.UnicodeScalarView(digits.unicodeScalars.map { superscripts[digit($0)] }))
        case .wrapped:
            return wrapHead + String(wrapTail + value)
        case .zero:
            return "0"
        }
    }

    /// `digits`, ASCII digits, with each written as the digit of the block
    /// whose zero is `zero`.
    static func shifted(_ digits: String, to zero: UInt32) -> String {
        String(String.UnicodeScalarView(digits.unicodeScalars.compactMap { Unicode.Scalar(zero + UInt32(digit($0))) }))
    }

    /// The value of `scalar`, an ASCII digit.
    static func digit(_ scalar: Unicode.Scalar) -> Int {
        Int(scalar.value - asciiZero)
    }
}
