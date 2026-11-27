//
//  DecimalHundredths.swift
//  SwiftStatsCoreTests
//
//  The reference P1.3 compares `BuildLineGrammar.hundredths` with, written
//  from the time grammar the grammar's doc comments state (M7 design §6.1,
//  and PR 1's bound), not from its code: a time field is
//  `<digits>[.<one or two digits>]ms`, its digits are the ASCII `0` to
//  `9`, and its value is in hundredths of a millisecond (`4.35ms` 435,
//  `4.3ms` 430, `4ms` 400). The value is worked out on the digits as text:
//  the whole part's digits, then the fraction's padded to two, leading
//  zeros dropped. So it is exact at any length, past what an `Int` holds
//  included, and needs no wider integer (`Int128` doesn't exist on macOS
//  14, the package's floor; design D12). The field is read as Unicode
//  scalars, not Characters, so a scalar that joins a digit, the point or
//  the unit into one Character can't hide a fault from it.
//

/// The value of a build-output time field in hundredths of a millisecond,
/// worked out on its decimal digits as text.
enum DecimalHundredths {
    /// A time field as the grammar reads it, whatever its length.
    struct Reading: Hashable, Sendable {
        /// How many whole digits the field has, leading zeros included.
        let wholeDigits: Int
        /// How many fraction digits it has: none, one or two.
        let fractionDigits: Int
        /// Its value in hundredths of a millisecond, as decimal digits
        /// with no leading zero (`0` for zero).
        let hundredths: String
    }

    /// The most whole digits a time the reader takes has. Stated here
    /// from `BuildLineGrammar.wholeDigits`'s doc comment, not read from
    /// it, so a changed bound fails P1.3: twelve, since no single
    /// type-check entry reaches 10^12 ms.
    static let wholeDigitBound = 12
    /// The most fraction digits a time has; a value in hundredths has as
    /// many.
    static let hundredthsDigits = 2
    /// A time's unit, as scalars.
    static let unit: [Unicode.Scalar] = ["m", "s"]
    /// What separates a time's whole part from its fraction.
    static let point: Unicode.Scalar = "."
    /// The ASCII zero.
    static let zero: Unicode.Scalar = "0"
    /// The ASCII nine.
    static let nine: Unicode.Scalar = "9"

    /// `field` read as `<digits>[.<one or two digits>]ms`, whatever the
    /// number of whole digits; nil when it has another shape: no unit, no
    /// whole digit, a point with no fraction digit or with more than two,
    /// or any scalar but an ASCII digit in a number.
    static func reading(of field: some StringProtocol) -> Reading? {
        let scalars = Array(field.unicodeScalars)
        guard scalars.count > unit.count, Array(scalars.suffix(unit.count)) == unit else {
            return nil
        }
        let number = scalars.dropLast(unit.count)
        let whole = Array(number.prefix { $0 != point })
        let rest = number.dropFirst(whole.count)
        let fraction = Array(rest.dropFirst())
        guard whole.isEmpty == false, whole.allSatisfy(isDigit) else {
            return nil
        }
        if rest.isEmpty == false {
            guard (1...hundredthsDigits).contains(fraction.count), fraction.allSatisfy(isDigit) else {
                return nil
            }
        }
        let padded = fraction + Array(repeating: zero, count: hundredthsDigits - fraction.count)
        let digits = (whole + padded).drop { $0 == zero }
        return Reading(
            wholeDigits: whole.count,
            fractionDigits: fraction.count,
            hundredths: digits.isEmpty ? String(zero) : String(String.UnicodeScalarView(digits))
        )
    }

    /// What `BuildLineGrammar.hundredths` should return for `field`, as
    /// decimal digits: the field's value when it is a time whose whole
    /// part has at most `wholeDigitBound` digits; nil for any other field.
    static func expected(for field: some StringProtocol) -> String? {
        guard let reading = reading(of: field), reading.wholeDigits <= wholeDigitBound else {
            return nil
        }
        return reading.hundredths
    }

    /// Whether `scalar` is an ASCII digit.
    static func isDigit(_ scalar: Unicode.Scalar) -> Bool {
        (zero...nine).contains(scalar)
    }
}
