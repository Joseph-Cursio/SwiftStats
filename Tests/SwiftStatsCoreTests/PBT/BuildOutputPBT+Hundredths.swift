//
//  BuildOutputPBT+Hundredths.swift
//  SwiftStatsCoreTests
//
//  P1.3: a timing line's time field reads as its exact value in hundredths
//  of a millisecond when its whole part has at most twelve digits (PR 1's
//  bound, B1), and as none otherwise, checked against a reference that
//  works on the decimal digits as text (`DecimalHundredths`), over drawn
//  fields (`TimeFieldGen`) and a walk over the edge numerals: twelve and
//  thirteen whole digits, 19 to 21, and fullwidth digits.
//

import PropertyBased
@testable import SwiftStatsCore
import Testing

/// P1.3 and its walk over edge numerals.
extension BuildOutputPBT {
    /// P1.3's base runs, over the engine's 100: one `hundredths` call costs
    /// microseconds and the domain is flat, so more draws cost nothing and
    /// reach each length around the bound more often.
    static let hundredthsRuns = 300

    /// Whether `read`, what `hundredths` returned for `field`, is the
    /// reference's value: the field's exact value in hundredths, compared
    /// as decimal digits, when it is a time with at most twelve whole
    /// digits; nil otherwise. Records an issue when it isn't.
    static func checkHundredths(_ field: String, read: Int?) -> Bool {
        let expected = DecimalHundredths.expected(for: field)
        let printed = read.map(String.init)
        guard printed == expected else {
            Issue.record("\(field.debugDescription) reads as \(printed ?? "none"), expected \(expected ?? "none")")
            return false
        }
        return true
    }

    // MARK: P1.3

    /// Invariant: a time field reads as its exact value in hundredths of a
    /// millisecond when it is `<digits>[.<1-2 digits>]ms` with at most
    /// twelve whole digits, and as none when the whole part has more or
    /// the shape is wrong.
    /// Why it holds: `BuildLineGrammar.hundredths`'s doc comment (`4.35ms`
    /// 435, `4.3ms` 430, `4ms` 400; nil past `wholeDigits`), and
    /// `wholeDigits`' (twelve, PR 1's bound for B1); digits are ASCII
    /// (`digits(_:)`).
    /// Why it might not: leading zeros count as whole digits, so
    /// `0000000000001ms` reads as none, as the code counts them; fields
    /// are at most 21 digits long (assumed: past `Int.max`'s 19).
    /// Oracle: reference (`DecimalHundredths`: decimal-string arithmetic on
    /// the scalars, no wider integer); planted defects: the bound one digit
    /// longer, a one-digit fraction read unscaled, a sign accepted, and the
    /// bound refusing twelve digits, each detected.
    /// Tier: Strict (stop-ship).
    @Test(
        "a time field reads as its exact hundredths with at most twelve whole digits, and as none otherwise",
        .timeLimit(PBTBudget.timeLimit)
    )
    func hundredthsAreExact() async {
        let latch = FirstFailureLatch()
        await propertyCheck(count: PBTBudget.runs(Self.hundredthsRuns), input: TimeFieldGen.field) { field in
            PBTTrace.note(field)
            if Self.checkHundredths(field.text, read: BuildLineGrammar.hundredths(field.text[...])) == false {
                PBTTrace.firstFailure(field, latch: latch)
            }
        }
    }

    @Test("the recorded builds' times read exactly", arguments: ["0.01ms", "0.14ms", "1.23ms", "0.02ms"])
    func recordedTimes(field: String) {
        #expect(Self.checkHundredths(field, read: BuildLineGrammar.hundredths(field[...])))
    }

    @Test(
        "B1: a time past what an Int holds reads as none",
        arguments: [
            CorpusEntry(input: "92233720368547759ms", pins: "B1: whole times 100 overflowed and trapped"),
            CorpusEntry(input: "92233720368547758.08ms", pins: "B1: a time past Int.max hundredths trapped")
        ]
    )
    func timePastAnInt(entry: CorpusEntry<String>) {
        let read = BuildLineGrammar.hundredths(entry.input[...])

        #expect(Self.checkHundredths(entry.input, read: read))
        #expect(read == nil)
    }

    @Test(
        "every edge numeral reads as its stated hundredths: twelve and thirteen whole digits, 19 to 21, fullwidth",
        arguments: [
            ("999999999999ms", 99_999_999_999_900),
            ("999999999999.99ms", 99_999_999_999_999),
            ("999999999999.9ms", 99_999_999_999_990),
            ("100000000000.05ms", 10_000_000_000_005),
            ("000000000001ms", 100),
            ("000000000000.01ms", 1),
            ("1000000000000ms", nil),
            ("0000000000001ms", nil),
            ("9999999999999.99ms", nil),
            ("9223372036854775807ms", nil),
            ("9223372036854775808ms", nil),
            ("0000000000000000001ms", nil),
            ("92233720368547758.07ms", nil),
            ("18446744073709551615ms", nil),
            ("92233720368547758070ms", nil),
            ("100000000000000000000ms", nil),
            ("999999999999999999999.99ms", nil),
            ("\u{FF11}\u{FF12}ms", nil),
            ("\u{FF11}\u{FF12}.\u{FF15}ms", nil),
            ("1\u{FF12}ms", nil),
            ("12.\u{FF15}ms", nil),
            ("\u{FF14}.35ms", nil),
            ("12\u{FF4D}\u{FF53}", nil),
            (String(repeating: "\u{FF19}", count: 12) + "ms", nil)
        ] as [(String, Int?)]
    )
    func edgeNumeral(field: String, hundredths: Int?) {
        let read = BuildLineGrammar.hundredths(field[...])

        #expect(Self.checkHundredths(field, read: read))
        #expect(read == hundredths)
    }

    @Test(
        "a planted defect's time fails P1.3's law",
        arguments: [
            ("1000000000000ms", 100_000_000_000_000),
            ("4.3ms", 403),
            ("+5ms", 500),
            ("-5ms", -500),
            ("999999999999ms", nil)
        ] as [(String, Int?)]
    )
    func hundredthsDefectsDetected(field: String, read: Int?) {
        let defect = "\(field) reading as \(read.map(String.init) ?? "none")"
        PlantedDefect.expectCaught(defect, sourceLocation: #_sourceLocation) {
            Self.checkHundredths(field, read: read)
        }
    }
}
