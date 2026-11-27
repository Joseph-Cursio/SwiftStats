import Foundation
import PropertyBased
@testable import SwiftStatsCore
import Testing

/// Properties of the number formats reports print (PRD §8, M6 design §7,
/// `MarkdownNumber`'s doc comments), over drawn numbers: a threshold prints
/// in full as the shortest decimal that reads back as it (P7.1), and no
/// format traps on any number, each printing in the shape its doc comment
/// states (P7.2, which guards B2). `MarkdownNumberTests` holds the fixed
/// examples; each property here has its own, calling its shared check, and
/// meta-tests that feed a planted defect's output to that check.
@Suite("Markdown numbers: properties", .tags(.pbt))
struct MarkdownNumberPBT {
    /// The numbers P7.2 prints: one for `value`, and the counts
    /// `perThousand` and `seconds` take.
    struct FormatInput: Sendable, CustomTestStringConvertible {
        /// The number `value` prints.
        let value: Double
        /// The count `perThousand` divides.
        let count: Int
        /// The lines `perThousand` divides by.
        let lines: Int
        /// The milliseconds `seconds` prints.
        let milliseconds: Int

        /// The four numbers, named, as a failure report shows them.
        var testDescription: String {
            "value \(value), count \(count), lines \(lines), milliseconds \(milliseconds)"
        }
    }

    /// P7.1's base runs, over the engine's 100: one `exact` call costs
    /// microseconds, and the domain is flat (every binade alike, plus the
    /// edges), so more draws cost nothing and reach more binades.
    static let exactRuns = 300
    /// P7.2's base runs: the engine's default.
    static let formatRuns = 100
    /// Half the last place `perThousand` and `seconds` print (one decimal).
    static let halfTenth = 0.05
    /// Half the last place `value` prints a fraction to (two decimals).
    static let halfHundredth = 0.005
    /// Relative slack for the floating-point steps between a format's
    /// exact quotient and the one it prints: a few units in the last place
    /// of a `Double` (2⁻⁵² is about 2.2 × 10⁻¹⁶), with room to spare.
    static let relativeSlack = 1e-9
    /// Lines per thousand, as `perThousand` scales its count.
    static let linesPerThousand = 1_000.0
    /// Milliseconds per second, as `seconds` divides.
    static let millisecondsPerSecond = 1_000.0
    /// The significant digits `%.Ne` prints beyond its precision `N`: the
    /// one before the point.
    static let digitBeforePoint = 1
    /// The fraction digits `value` prints for a value that isn't whole.
    static let valueFractionDigits = 2

    /// P7.2's input: any `Double`, and three `Int`s.
    static let formatInput = zip(NumberGen.anyDouble, NumberGen.int, NumberGen.int, NumberGen.int)
        .map { value, count, lines, milliseconds in
            FormatInput(value: value, count: count, lines: lines, milliseconds: milliseconds)
        }

    /// Whether `printed`, `MarkdownNumber.exact(value)` for a finite
    /// `value`, holds every law `exact`'s doc comment states: it reads back
    /// as `value`; it is a plain decimal, with no exponent; a whole value
    /// has no point; zero has no sign, and any other value its own; and it
    /// is the shortest decimal: no zero pads it (its fraction doesn't end in
    /// one, and its whole part is `0` or doesn't start with one), and no
    /// decimal one significant digit shorter reads back as `value`. Records
    /// an issue for each law that fails.
    static func checkExact(_ value: Double, printed: String) -> Bool {
        let digits = significantDigits(printed)
        let shorter = String(format: "%.*e", Int32(digits - digitBeforePoint - 1), value)
        let laws: [(holds: Bool, law: String)] = [
            (Double(printed) == value, "reads back as \(value)"),
            (isDecimal(printed, fractionDigits: 0...Int.max), "is a plain decimal with no exponent"),
            (value.rounded() != value || printed.contains(".") == false, "has no point on a whole value"),
            (value != 0 || printed == "0", "is 0 for a zero"),
            (printed.hasPrefix("-") == (value < 0), "carries the value's sign"),
            (isUnpadded(printed), "has no zero padding its fraction's end or its whole part's start"),
            (digits <= 1 || Double(shorter) != value, "is shortest: \(shorter) reads back too")
        ]
        return holds(laws, printed: printed)
    }

    /// Whether `value`, `perThousand` and `seconds` are what
    /// `MarkdownNumber` prints for `input`'s numbers in the shapes its doc
    /// comments state. Checks all three, recording an issue for each law
    /// that fails.
    static func checkFormats(_ input: FormatInput, value: String, perThousand: String, seconds: String) -> Bool {
        [
            checkValue(input.value, printed: value),
            checkPerThousand(input.count, lines: input.lines, printed: perThousand),
            checkSeconds(input.milliseconds, printed: seconds)
        ]
        .allSatisfy(\.self)
    }

    /// Whether `printed` is what `value` must print as: `nan` for any NaN,
    /// `inf` or `-inf` for an infinity; for a whole value, digits with no
    /// point that read back as it (`0` for a zero); for any other, its
    /// sign and digits to exactly two places, within half the last place.
    static func checkValue(_ value: Double, printed: String) -> Bool {
        if value.isNaN {
            return holds([(printed == "nan", "is nan")], printed: printed)
        }
        if value.isInfinite {
            return holds([(printed == (value < 0 ? "-inf" : "inf"), "is \(value)")], printed: printed)
        }
        if value.rounded() == value {
            return holds(
                [
                    (isDecimal(printed, fractionDigits: 0...0), "is whole digits"),
                    (Double(printed) == value, "reads back as \(value)"),
                    (value != 0 || printed == "0", "is 0 for a zero")
                ],
                printed: printed
            )
        }
        let distance = Double(printed).map { abs($0 - value) } ?? .infinity
        return holds(
            [
                (isDecimal(printed, fractionDigits: valueFractionDigits...valueFractionDigits), "has two places"),
                (printed.hasPrefix("-") == (value < 0), "carries the value's sign"),
                (distance <= halfHundredth + value.ulp, "is within half a hundredth of \(value)")
            ],
            printed: printed
        )
    }

    /// Whether `printed` is `count` per thousand `lines`: a dash for no
    /// lines; else the sign of `count` and digits to one place, within
    /// half the last place of the exact quotient.
    static func checkPerThousand(_ count: Int, lines: Int, printed: String) -> Bool {
        guard lines > 0 else {
            return holds([(printed == "—", "is a dash with no lines")], printed: printed)
        }
        return checkTenths(printed, numerator: Double(count) * linesPerThousand, denominator: Double(lines))
    }

    /// Whether `printed` is `milliseconds` in seconds: the sign and digits
    /// to one place, within half the last place, then ` s`.
    static func checkSeconds(_ milliseconds: Int, printed: String) -> Bool {
        guard printed.hasSuffix(" s") else {
            return holds([(false, "ends in \" s\"")], printed: printed)
        }
        return checkTenths(
            String(printed.dropLast(" s".count)),
            numerator: Double(milliseconds),
            denominator: millisecondsPerSecond
        )
    }

    /// Whether `printed` is `numerator / denominator` (a positive
    /// denominator) to one decimal place: the numerator's sign, digits to
    /// one place, and within half a tenth of the exact quotient, which is
    /// checked multiplied out (`printed × denominator` against `numerator`)
    /// rather than by the division the subject does.
    static func checkTenths(_ printed: String, numerator: Double, denominator: Double) -> Bool {
        let product = Double(printed).map { $0 * denominator } ?? .infinity
        let bound = halfTenth * denominator + abs(numerator) * relativeSlack
        return holds(
            [
                (isDecimal(printed, fractionDigits: 1...1), "has one place"),
                (printed.hasPrefix("-") == (numerator < 0), "carries the sign of \(numerator)"),
                (abs(product - numerator) <= bound * (1 + relativeSlack), "is within half a tenth of the quotient")
            ],
            printed: printed
        )
    }

    /// Records an issue naming `printed` for each law in `laws` that fails;
    /// whether all hold.
    static func holds(_ laws: [(holds: Bool, law: String)], printed: String) -> Bool {
        for law in laws where law.holds == false {
            Issue.record("\"\(printed)\" fails: it \(law.law)")
        }
        return laws.allSatisfy(\.holds)
    }

    /// Whether `text` is a plain decimal: an optional `-`, at least one
    /// ASCII digit, then, when `fractionDigits` allows any, an optional
    /// point followed by a count of ASCII digits it contains.
    static func isDecimal(_ text: String, fractionDigits: ClosedRange<Int>) -> Bool {
        let unsigned = text.hasPrefix("-") ? text.dropFirst() : Substring(text)
        let parts = unsigned.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        guard let whole = parts.first, whole.isEmpty == false, whole.allSatisfy(isDigit) else {
            return false
        }
        guard parts.count > 1 else {
            return fractionDigits.contains(0)
        }
        let fraction = parts[1]
        return fraction.isEmpty == false && fraction.allSatisfy(isDigit) && fractionDigits.contains(fraction.count)
    }

    /// Whether a plain decimal has no padding zero: its fraction, if any,
    /// doesn't end in `0`, and its whole part is `0` or doesn't start with
    /// `0`.
    static func isUnpadded(_ text: String) -> Bool {
        let unsigned = text.hasPrefix("-") ? text.dropFirst() : Substring(text)
        let parts = unsigned.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        let whole = parts.first ?? ""
        let fraction = parts.count > 1 ? parts[1] : ""
        return fraction.hasSuffix("0") == false && (whole == "0" || whole.hasPrefix("0") == false)
    }

    /// The significant digits of a plain decimal: its digits without the
    /// leading zeros, and without the trailing ones, which a whole number
    /// past 10¹⁶ pads with.
    static func significantDigits(_ text: String) -> Int {
        let digits = Array(text.filter(isDigit).drop { $0 == "0" })
        return digits.reversed().drop { $0 == "0" }.count
    }

    /// Whether `character` is an ASCII digit.
    static func isDigit(_ character: Character) -> Bool {
        ("0"..."9").contains(character)
    }

    // MARK: P7.1

    /// Invariant: every finite `Double` prints through `exact` as the
    /// shortest decimal that reads back as it, with no exponent, no point on
    /// a whole value, no sign on zero and its own sign otherwise.
    /// Why it holds: `MarkdownNumber.exact`'s doc comment states each law,
    /// so a report prints the number it compared (PRD §8, M6 design §7).
    /// Why it might not: infinities and NaN are outside (they print as Swift
    /// writes them, pinned in `MarkdownNumberTests`); "shortest" is checked
    /// one significant digit down only, a necessary condition.
    /// Oracle: round trip through `Double(_:)`, plus postconditions, with
    /// "shortest" checked against Foundation's `%.*e`, not the Swift
    /// `description` `exact` starts from; planted defects: one zero dropped
    /// after the point for a value below 0.0001, and a `0` appended to every
    /// fraction, both detected.
    /// Tier: Strict (stop-ship).
    @Test(
        "every finite double prints in full as the shortest decimal that reads back as it",
        .timeLimit(PBTBudget.timeLimit)
    )
    func exactReadsBack() async {
        let latch = FirstFailureLatch()
        await propertyCheck(count: PBTBudget.runs(Self.exactRuns), input: NumberGen.finiteDouble) { value in
            PBTTrace.note(value)
            if Self.checkExact(value, printed: MarkdownNumber.exact(value)) == false {
                PBTTrace.firstFailure(value, latch: latch)
            }
        }
    }

    @Test("the smallest subnormal prints all 324 places of its fraction")
    func smallestSubnormal() {
        let printed = MarkdownNumber.exact(.leastNonzeroMagnitude)

        #expect(Self.checkExact(.leastNonzeroMagnitude, printed: printed))
        #expect(printed == "0." + String(repeating: "0", count: 323) + "5")
    }

    @Test("the largest finite double prints all 309 of its digits")
    func largestFinite() {
        let printed = MarkdownNumber.exact(.greatestFiniteMagnitude)

        #expect(Self.checkExact(.greatestFiniteMagnitude, printed: printed))
        #expect(printed == "17976931348623157" + String(repeating: "0", count: 292))
    }

    @Test(
        "values either side of where Swift switches to an exponent print in full",
        arguments: [9_007_199_254_740_994.0, 0.00009999999999999999]
    )
    func exponentEdges(value: Double) {
        #expect(Self.checkExact(value, printed: MarkdownNumber.exact(value)))
    }

    @Test(
        "a planted defect's output for exact fails the law",
        arguments: [
            (0.00001, "1e-05"),
            (80, "80.0"),
            (0.1, "0.10000000000000001"),
            (-0.0, "-0"),
            (0.000015, "0.00015"),
            (0.5, "0.50"),
            (0.1, "00.1"),
            (120, "0120")
        ]
    )
    func exactDefectsDetected(value: Double, printed: String) {
        PlantedDefect.expectDetected("exact printing \(value) as \(printed)", sourceLocation: #_sourceLocation) {
            Self.checkExact(value, printed: printed)
        }
    }

    // MARK: P7.2

    /// Invariant: no `Double` traps `value` and no `Int`s trap `perThousand`
    /// or `seconds`, and each prints in the shape its doc comment states.
    /// Why it holds: `value`'s doc comment ("no `Double` traps": whole
    /// values without a fraction, others to two places, infinities and NaN
    /// as `inf`, `-inf` and `nan`) and the one-decimal formats of
    /// `perThousand` and `seconds`, which convert to `Double` before
    /// dividing, so no `Int` overflows.
    /// Why it might not: a whole value past what an `Int` holds prints
    /// through `exact` (B2's fix), which P7.1 covers; a fraction is checked
    /// within half its last place, not digit by digit.
    /// Oracle: postconditions, with each quotient checked multiplied out,
    /// not by the subject's division; planted defect: B2's
    /// `String(Int(value))`, detected as a trap (the trace names the input),
    /// and `seconds` dividing by 100, detected.
    /// Tier: Strict (stop-ship).
    @Test(
        "no number traps a format, and each prints in the shape its doc comment states",
        .timeLimit(PBTBudget.timeLimit)
    )
    func formatsAreTotal() async {
        let latch = FirstFailureLatch()
        await propertyCheck(count: PBTBudget.runs(Self.formatRuns), input: Self.formatInput) { input in
            PBTTrace.note(input)
            let passed = Self.checkFormats(
                input,
                value: MarkdownNumber.value(input.value),
                perThousand: MarkdownNumber.perThousand(input.count, lines: input.lines),
                seconds: MarkdownNumber.seconds(input.milliseconds)
            )
            if passed == false {
                PBTTrace.firstFailure(input, latch: latch)
            }
        }
    }

    @Test("B2: a timeout of 1e300 seconds prints in full, and a count over no lines prints a dash")
    func hugeTimeout() {
        let input = FormatInput(value: 1e300, count: 3, lines: 0, milliseconds: 1_500)
        let value = MarkdownNumber.value(input.value)
        let perThousand = MarkdownNumber.perThousand(input.count, lines: input.lines)
        let seconds = MarkdownNumber.seconds(input.milliseconds)

        #expect(Self.checkFormats(input, value: value, perThousand: perThousand, seconds: seconds))
        #expect(value == "1" + String(repeating: "0", count: 300))
        #expect(perThousand == "—")
        #expect(seconds == "1.5 s")
    }

    @Test("the limits of an Int print in every format")
    func intLimits() {
        let input = FormatInput(value: Double(Int.max), count: Int.min, lines: Int.max, milliseconds: Int.min)

        #expect(
            Self.checkFormats(
                input,
                value: MarkdownNumber.value(input.value),
                perThousand: MarkdownNumber.perThousand(input.count, lines: input.lines),
                seconds: MarkdownNumber.seconds(input.milliseconds)
            )
        )
    }

    @Test("a negative infinity, a zero count and a fraction print as stated")
    func infinityAndFraction() {
        let input = FormatInput(value: -.infinity, count: 0, lines: 1, milliseconds: -49)
        let value = MarkdownNumber.value(input.value)
        let perThousand = MarkdownNumber.perThousand(input.count, lines: input.lines)
        let seconds = MarkdownNumber.seconds(input.milliseconds)

        #expect(Self.checkFormats(input, value: value, perThousand: perThousand, seconds: seconds))
        #expect([value, perThousand, seconds] == ["-inf", "0.0", "-0.0 s"])
    }

    @Test("a planted defect's output for any format fails the law")
    func formatDefectsDetected() {
        let input = FormatInput(value: 20, count: 3, lines: 2_000, milliseconds: 1_500)
        let value = MarkdownNumber.value(input.value)
        let perThousand = MarkdownNumber.perThousand(input.count, lines: input.lines)
        let seconds = MarkdownNumber.seconds(input.milliseconds)

        PlantedDefect.expectDetected("value printing a whole number to two places", sourceLocation: #_sourceLocation) {
            Self.checkFormats(input, value: "20.00", perThousand: perThousand, seconds: seconds)
        }
        PlantedDefect.expectDetected("perThousand not scaling by a thousand", sourceLocation: #_sourceLocation) {
            Self.checkFormats(input, value: value, perThousand: "0.0", seconds: seconds)
        }
        PlantedDefect.expectDetected("seconds dividing by a hundred", sourceLocation: #_sourceLocation) {
            Self.checkFormats(input, value: value, perThousand: perThousand, seconds: "15.0 s")
        }
    }
}
