//
//  NumberGen.swift
//  SwiftStatsCoreTests
//
//  Numbers for properties of code that formats or reads them. A uniform
//  `Double` in a range almost never lands on the values formatting gets
//  wrong (a subnormal, a whole number past what an `Int` holds, a value
//  Swift prints with an exponent, an infinity), so each generator mixes
//  branches: every binade alike, drawn as sign, exponent and significand
//  bit patterns; the named edges; whole numbers from the full `Int` range;
//  and short decimals like the thresholds a configuration states. Digit
//  strings, for fields read as numbers, draw each digit alone. Every
//  branch is total (no filter, so nothing is rejected), and the engine
//  shrinks within the branch it drew: the drawn branches toward zero, a
//  list of named edges toward its first edge, which is zero in the finite
//  and integer lists (the non-finite list has none, and starts with
//  infinity). Raw edges go only into subjects that are total over them:
//  arithmetic subjects draw from named bounds instead.
//

import Foundation
import PropertyBased

/// Generators of `Double` and `Int` values, weighted toward their edges.
enum NumberGen {
    /// Weight of the binade branch: most draws, so every magnitude from the
    /// subnormals to the largest finite value comes up.
    static let binadeWeight = 5.0
    /// Weight of the named edges.
    static let edgeWeight = 1.0
    /// Weight of whole numbers from the full `Int` range.
    static let wholeWeight = 2.0
    /// Weight of short decimals.
    static let decimalWeight = 2.0
    /// Weight of the finite values in `anyDouble`.
    static let finiteWeight = 9.0
    /// Weight of the infinities and NaNs in `anyDouble`.
    static let nonFiniteWeight = 1.0
    /// Weight of the full `Int` range in `int`.
    static let fullIntWeight = 2.0
    /// Weight of small integers in `int`.
    static let smallIntWeight = 2.0

    /// The largest exponent bit pattern of a finite `Double` (forced: one
    /// below the all-ones pattern of the infinities and NaNs).
    static let largestFiniteExponent = Double.infinity.exponentBitPattern - 1
    /// The largest significand bit pattern (forced: every significand bit set).
    static let largestSignificand = Double.greatestFiniteMagnitude.significandBitPattern
    /// The largest mantissa of a short decimal, in magnitude (assumed: a
    /// configured threshold has at most six digits before its point moves).
    static let decimalMantissaBound = 1_000_000
    /// The most places a short decimal moves its point (assumed, as above).
    static let decimalPlaces = 9
    /// The largest small integer in magnitude (assumed: counts and line
    /// totals a real report prints).
    static let smallIntBound = 10_000
    /// The smallest magnitude Swift's `description` writes without an
    /// exponent (forced, as measured on Swift 6.4: its next value down
    /// prints as `9.999999999999999e-05`).
    static let smallestPlainFraction = 1e-4
    /// The base short decimals move their point in.
    static let decimalBase = 10.0
    /// The magnitudes where Swift's `description` switches to exponent form,
    /// each drawn with its neighbours: 2⁵³, the largest value it writes
    /// without an exponent (forced, as measured on Swift 6.4: its next value
    /// up prints with one), and the smallest plain fraction.
    static let exponentFormEdges = [Double(1 << (Double.significandBitCount + 1)), smallestPlainFraction]

    /// The finite edges, zero first, so a failure drawn here shrinks to it:
    /// zeros, the subnormal and normal limits, the largest magnitudes, ones,
    /// where fractions end (2⁵²), what an `Int` holds and the first values
    /// past it, and either side of where Swift's description switches to
    /// exponent form.
    static let finiteEdges: [Double] = [
        0,
        -0.0,
        .leastNonzeroMagnitude,
        -.leastNonzeroMagnitude,
        .leastNormalMagnitude,
        .greatestFiniteMagnitude,
        -.greatestFiniteMagnitude,
        1,
        -1,
        .ulpOfOne,
        Double(1 << Double.significandBitCount),
        Double(Int.max).nextDown,
        Double(Int.max),
        Double(Int.min),
        Double(Int.min).nextDown
    ] + exponentFormEdges + exponentFormEdges.map(\.nextDown) + exponentFormEdges.map(\.nextUp)

    /// The infinities and NaNs, a negative and a signalling one included.
    static let nonFiniteEdges: [Double] = [.infinity, -.infinity, .nan, -.nan, .signalingNaN]

    /// The ASCII digits, zero first, so a drawn digit shrinks toward it.
    static let asciiDigits = Array("0123456789")

    /// The integer edges: zero first, so a failure drawn here shrinks to it,
    /// then its neighbours, and `Int`'s limits and theirs.
    static let intEdges = [0, -1, 1, Int.min, Int.min + 1, Int.max - 1, Int.max]

    /// Every finite binade alike: sign, exponent and significand drawn
    /// apart, so a subnormal is as likely as a value near 1.
    static let binade = zip(
        Gen.bool,
        Gen<UInt>.value(in: 0...largestFiniteExponent),
        Gen<UInt64>.value(in: 0...largestSignificand)
    )
    .map { isNegative, exponent, significand in
        Double(sign: isNegative ? .minus : .plus, exponentBitPattern: exponent, significandBitPattern: significand)
    }

    /// A whole number from the full `Int` range, as a `Double`: near the
    /// limits it rounds to 2⁶³, past what an `Int` holds.
    static let wholeFromInt = Gen<Int>.value().map(Double.init)

    /// A short decimal, `mantissa / 10^places`.
    static let decimal = zip(
        Gen<Int>.value(in: -decimalMantissaBound...decimalMantissaBound),
        Gen<Int>.value(in: 0...decimalPlaces)
    )
    .map { mantissa, places in
        Double(mantissa) / pow(decimalBase, Double(places))
    }

    /// Any finite `Double`, from every branch.
    static let finiteDouble = Gen.frequency(
        (binadeWeight, binade),
        (edgeWeight, element(of: finiteEdges)),
        (wholeWeight, wholeFromInt),
        (decimalWeight, decimal)
    )

    /// Any `Double`: the finite ones, the infinities and NaNs.
    static let anyDouble = Gen.frequency(
        (finiteWeight, finiteDouble),
        (nonFiniteWeight, element(of: nonFiniteEdges))
    )

    /// Any `Int`: the full range, small values and the edges.
    static let int = Gen.frequency(
        (fullIntWeight, Gen<Int>.value()),
        (smallIntWeight, Gen<Int>.value(in: -smallIntBound...smallIntBound)),
        (edgeWeight, element(of: intEdges))
    )

    /// A string of ASCII digits, as many as `lengths` allows, each digit
    /// drawn alone, so a leading zero comes up as often as any other first
    /// digit: a field the code reads as a number (a time in build output,
    /// P1.3). It shrinks by dropping digits and toward zeros.
    static func digitString(lengths: ClosedRange<Int>) -> Generator<String, AnySequence<Any>> {
        element(of: asciiDigits).array(of: lengths).map { String($0) }.eraseToAny()
    }

    /// An element of `values`, which must not be empty, drawn by index so
    /// it shrinks toward the first.
    static func element<Value: Sendable>(of values: [Value]) -> Generator<Value, Shrink.Integer<Int>> {
        Gen<Int>.value(in: values.indices).map { values[$0] }
    }
}
