//
//  TimeFieldGen.swift
//  SwiftStatsCoreTests
//
//  Time fields of build-output timing lines, for P1.3: whole digits of
//  short lengths, of lengths either side of the reader's twelve-digit
//  bound (B1), and of lengths past what an `Int` holds (19 digits and
//  more), a leading zero as often as any first digit; no fraction, or a
//  point with zero to three fraction digits; then `ms`. A share of fields
//  takes one fault at a drawn position: an ASCII digit replaced by its
//  fullwidth or Arabic-Indic form (digits Swift calls numbers, but not
//  ASCII), a combining mark after a scalar, a Prepend scalar (it joins
//  the scalar after it into one Character, B23), a point or a space
//  inserted, a sign, no whole digits, no unit, or another unit; its
//  fraction, if any, has one or two digits, so the fault is its only one.
//  A fault may leave a valid time (a point inserted into whole digits),
//  so the generator states no reading: P1.3's oracle reads each field
//  (`DecimalHundredths`). Every list is ordered simplest first, and the
//  engine shrinks a field by dropping digits, toward zeros, and toward no
//  fault.
//

import PropertyBased
import Testing

/// Generators of build-output time fields, weighted toward the digit
/// bound's edges.
enum TimeFieldGen {
    /// A generated time field, P1.3's input.
    struct Field: Sendable, CustomTestStringConvertible {
        /// The field as written.
        let text: String
        /// The fault it took, if any.
        let fault: Fault?

        /// The field as a Swift literal, each scalar past ASCII also named
        /// by its code point, and its fault.
        var testDescription: String {
            let named = text.unicodeScalars.filter { $0.isASCII == false }
                .map { "U+" + String($0.value, radix: TimeFieldGen.hexadecimal, uppercase: true) }
            let scalars = named.isEmpty ? "" : " (" + named.joined(separator: " ") + ")"
            return text.debugDescription + scalars + ", fault: " + (fault.map { "\($0)" } ?? "none")
        }
    }

    /// A fault in a time field.
    enum Fault: CaseIterable, Sendable {
        /// An ASCII digit replaced by its Arabic-Indic form.
        case arabicIndicDigit
        /// A combining acute accent after a scalar.
        case combiningMark
        /// No whole digits.
        case emptyWhole
        /// An ASCII digit replaced by its fullwidth form.
        case fullwidthDigit
        /// A point inserted.
        case insertedPoint
        /// A space inserted.
        case insertedSpace
        /// No unit.
        case missingUnit
        /// A Prepend scalar inserted.
        case prependScalar
        /// A sign before the field.
        case signed
        /// Another unit in place of `ms`.
        case wrongUnit

        /// `scalars` with `scalar` inserted at `position`, modulo the
        /// places between and around them.
        static func inserting(
            _ scalar: Unicode.Scalar,
            into scalars: [Unicode.Scalar],
            at position: Int
        ) -> [Unicode.Scalar] {
            var inserted = scalars
            inserted.insert(scalar, at: position % (scalars.count + 1))
            return inserted
        }

        /// `scalars` with the ASCII digit at `position`, modulo their
        /// count, written in the digits whose zero is `zero`; unchanged
        /// when it has none.
        static func replacingDigit(
            in scalars: [Unicode.Scalar],
            at position: Int,
            zero: Unicode.Scalar
        ) -> [Unicode.Scalar] {
            let digits = scalars.indices.filter { DecimalHundredths.isDigit(scalars[$0]) }
            guard digits.isEmpty == false else {
                return scalars
            }
            let index = digits[position % digits.count]
            let value = scalars[index].value - DecimalHundredths.zero.value
            var replaced = scalars
            replaced[index] = Unicode.Scalar(zero.value + value) ?? scalars[index]
            return replaced
        }

        /// `scalars`, a field with its unit, with this fault at `position`
        /// (taken modulo the places it can go).
        func applied(to scalars: [Unicode.Scalar], at position: Int) -> [Unicode.Scalar] {
            switch self {
            case .arabicIndicDigit:
                Self.replacingDigit(in: scalars, at: position, zero: TimeFieldGen.arabicIndicZero)

            case .combiningMark:
                Self.inserting(TimeFieldGen.combiningAcute, into: scalars, at: position % scalars.count + 1)

            case .emptyWhole:
                Array(scalars.drop { DecimalHundredths.isDigit($0) })

            case .fullwidthDigit:
                Self.replacingDigit(in: scalars, at: position, zero: TimeFieldGen.fullwidthZero)

            case .insertedPoint:
                Self.inserting(DecimalHundredths.point, into: scalars, at: position)

            case .insertedSpace:
                Self.inserting(" ", into: scalars, at: position)

            case .missingUnit:
                Array(scalars.dropLast(DecimalHundredths.unit.count))

            case .prependScalar:
                Self.inserting(TimeFieldGen.prepend, into: scalars, at: position)

            case .signed:
                [TimeFieldGen.signs[position % TimeFieldGen.signs.count]] + scalars

            case .wrongUnit:
                Array(scalars.dropLast(DecimalHundredths.unit.count))
                    + TimeFieldGen.wrongUnits[position % TimeFieldGen.wrongUnits.count]
            }
        }
    }

    /// Weight of short whole parts, the most common in a real build.
    static let shortWeight = 3.0
    /// Weight of whole parts either side of the bound.
    static let boundWeight = 4.0
    /// Weight of whole parts far past the bound.
    static let longWeight = 2.0
    /// The share of fields with a point.
    static let pointRate: Float = 0.6
    /// The share of fields with a fault: half, so each fault comes up in
    /// about one field in twenty.
    static let faultRate: Float = 0.5

    /// The lengths of a short whole part (assumed: most type-check times
    /// are under ten seconds).
    static let shortLengths = 1...4
    /// The lengths either side of the bound (forced: twelve, B1's bound,
    /// with one digit less and one more).
    static let boundLengths = 11...13
    /// The lengths far past the bound (forced: from one past the bound's
    /// neighbour to 21, two past the 19 digits of `Int.max`).
    static let longLengths = 14...21
    /// How many fraction digits follow a point (forced: none and three,
    /// one each side of the one or two a time has).
    static let fractionLengths = 0...3
    /// The largest fault position, taken modulo a field's places (assumed:
    /// past the longest field's length, so positions spread over it).
    static let positionBound = 30
    /// The radix a code point is named in.
    static let hexadecimal = 16

    /// The Arabic-Indic zero, U+0660: `Character.isNumber`, not ASCII.
    static let arabicIndicZero: Unicode.Scalar = "\u{660}"
    /// The fullwidth zero, U+FF10: `Character.isNumber`, not ASCII.
    static let fullwidthZero: Unicode.Scalar = "\u{FF10}"
    /// A combining acute accent, which joins the scalar before it.
    static let combiningAcute: Unicode.Scalar = "\u{301}"
    /// A Prepend scalar, U+0600, which joins the scalar after it.
    static let prepend: Unicode.Scalar = "\u{600}"
    /// The signs a field may take.
    static let signs: [Unicode.Scalar] = ["-", "+"]
    /// Units a time doesn't have.
    static let wrongUnits: [[Unicode.Scalar]] = [["s"], ["M", "S"], ["\u{B5}", "s"], ["m", "s", " "]]

    /// A whole part: short, either side of the bound, or far past it.
    static let whole = Gen.frequency(
        (shortWeight, NumberGen.digitString(lengths: shortLengths)),
        (boundWeight, NumberGen.digitString(lengths: boundLengths)),
        (longWeight, NumberGen.digitString(lengths: longLengths))
    )

    /// A fraction's digits after a point, or nil for no point.
    static let fraction = NumberGen.digitString(lengths: fractionLengths).optional(valueRate: pointRate)

    /// A fault and where it goes, or nil for none.
    static let fault = zip(Pick.element(of: Fault.allCases), Gen<Int>.value(in: 0...positionBound))
        .map { (fault: $0, position: $1) }
        .optional(valueRate: faultRate)

    /// A time field.
    static let field = zip(whole, fraction, fault)
        .map { whole, drawn, fault in
            let digits = fault == nil ? drawn : drawn.map(faultless)
            let written = whole + (digits.map { String(DecimalHundredths.point) + $0 } ?? "") + "ms"
            let scalars = Array(written.unicodeScalars)
            let faulted = fault.map { $0.fault.applied(to: scalars, at: $0.position) } ?? scalars
            return Field(text: String(String.UnicodeScalarView(faulted)), fault: fault?.fault)
        }

    /// The fraction digits a faulted field has a point before: one or two,
    /// so the fault is the field's only one. An empty fraction becomes
    /// `5`, and a third digit is dropped.
    static func faultless(_ fraction: String) -> String {
        fraction.isEmpty ? "5" : String(fraction.prefix(DecimalHundredths.hundredthsDigits))
    }
}
