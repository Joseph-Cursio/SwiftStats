import Foundation
@testable import SwiftStatsCore
import Testing

/// How reports print the thresholds they used (PRD §8, M6 design §7):
/// in full, the shortest decimal that reads back as the number compared,
/// never rounded, never in exponent form, and never trapping on a value
/// too large for an `Int`; and how they print a value, which never traps
/// either: a whole one past what an `Int` holds prints in full, as the
/// shortest decimal that reads back as it, and infinities and NaN print as
/// `inf`, `-inf` and `nan`.
@Suite("Markdown numbers")
struct MarkdownNumberTests {
    @Test(
        "a threshold prints in full as the shortest decimal that reads back as it",
        arguments: [
            (80.0, "80"),
            (0.0, "0"),
            (-0.0, "0"),
            (49.5, "49.5"),
            (33.333, "33.333"),
            (0.125, "0.125"),
            (0.004, "0.004"),
            (0.00001, "0.00001"),
            (1.5e-7, "0.00000015"),
            (1e16, "10000000000000000"),
            (1.25e20, "125000000000000000000"),
            (1e19, "10000000000000000000")
        ]
    )
    func exact(value: Double, text: String) {
        #expect(MarkdownNumber.exact(value) == text)
        #expect(Double(MarkdownNumber.exact(value)) == value)
    }

    @Test(
        "a value prints whole without a fraction, else to two places, and never traps outside what an Int holds",
        arguments: [
            (20.0, "20"),
            (-0.0, "0"),
            (2.5, "2.50"),
            (-9_223_372_036_854_775_808.0, "-9223372036854775808"),
            (9_223_372_036_854_775_808.0, "9223372036854776000"),
            (1e19, "10000000000000000000"),
            (-1e19, "-10000000000000000000"),
            (1e300, "1" + String(repeating: "0", count: 300)),
            (Double.infinity, "inf"),
            (-Double.infinity, "-inf"),
            (Double.nan, "nan")
        ]
    )
    func value(value: Double, text: String) {
        #expect(MarkdownNumber.value(value) == text)
    }
}
