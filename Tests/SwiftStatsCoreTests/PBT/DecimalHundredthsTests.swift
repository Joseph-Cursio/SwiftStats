import Testing

/// The reference P1.3 compares the reader's times with (design D12: a
/// reference has examples of its own), each expectation worked out by hand
/// from the time grammar: the value in hundredths as decimal digits at any
/// length, the whole digits counted with their leading zeros, and every
/// other shape read as none.
@Suite("Decimal hundredths reference")
struct DecimalHundredthsTests {
    @Test(
        "a time reads as its value in hundredths, with two fraction digits, one or none",
        arguments: [
            ("4.35ms", "435"),
            ("4.3ms", "430"),
            ("4ms", "400"),
            ("0.01ms", "1"),
            ("0ms", "0"),
            ("007.5ms", "750")
        ]
    )
    func times(field: String, hundredths: String) {
        #expect(DecimalHundredths.reading(of: field)?.hundredths == hundredths)
        #expect(DecimalHundredths.expected(for: field) == hundredths)
    }

    @Test("a time past what an Int holds reads exactly, and is expected as none past twelve whole digits")
    func longTimes() {
        let reading = DecimalHundredths.reading(of: "92233720368547758.08ms")

        #expect(reading?.wholeDigits == 17)
        #expect(reading?.fractionDigits == 2)
        #expect(reading?.hundredths == "9223372036854775808")
        #expect(DecimalHundredths.expected(for: "92233720368547758.08ms") == nil)
        #expect(DecimalHundredths.expected(for: "999999999999.99ms") == "99999999999999")
    }

    @Test("leading zeros count as whole digits")
    func leadingZeros() {
        #expect(DecimalHundredths.reading(of: "0000000000001ms")?.wholeDigits == 13)
        #expect(DecimalHundredths.expected(for: "0000000000001ms") == nil)
        #expect(DecimalHundredths.expected(for: "000000000001ms") == "100")
    }

    @Test(
        "a field of another shape reads as none",
        arguments: [
            "ms", ".5ms", "4.ms", "4.355ms", "4", "4.3", "+4ms", "-4ms", "4 ms", "4.3.2ms",
            "\u{FF14}ms", "4.\u{FF15}ms", "\u{664}ms", "4\u{301}ms", "4\u{600}ms", "4MS", "4ms "
        ]
    )
    func otherShapes(field: String) {
        #expect(DecimalHundredths.reading(of: field) == nil)
    }
}
