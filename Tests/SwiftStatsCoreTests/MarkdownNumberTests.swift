import Foundation
@testable import SwiftStatsCore
import Testing

/// How reports print the thresholds they used (PRD §8, M6 design §7):
/// in full, the shortest decimal that reads back as the number compared,
/// never rounded, never in exponent form, and never trapping on a value
/// too large for an `Int`.
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
}
