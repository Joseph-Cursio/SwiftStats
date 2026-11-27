import PropertyBased
import Testing

/// What the time-field generator draws (design D14): from a fixed seed, a
/// thousand fields reach each class P1.3's law depends on an exact number
/// of times: times within the twelve-digit bound and past it, twelve and
/// thirteen whole digits, a leading zero, 19 or more whole digits, one
/// and two fraction digits, other shapes, a fullwidth digit, and each
/// fault. A field is classed by the reference (`DecimalHundredths`), not
/// by the reader. The counts hold under this engine's generator code and
/// this standard library; a change to either, or to a weight or list in
/// `TimeFieldGen`, redraws them.
@Suite("Time field generator")
struct TimeFieldGenTests {
    /// The draws the meta-test makes.
    static let draws = 1_000
    /// The attempts allowed per draw: the generator never rejects a value.
    static let attempts = 1
    /// The fixed seed the meta-test draws from.
    static let seeded = Xoshiro(seed: (1, 2, 3, 4))
    /// The whole digits of `Int.max`: a time with as many or more is past
    /// what an `Int` holds, or close to it.
    static let intDigits = 19
    /// How many digits a script has, from its zero.
    static let digitCount: UInt32 = 10

    /// The classes `field` falls in: exactly one of `within the bound`,
    /// `past the bound` and `another shape`; for a time, its whole digits
    /// when twelve or thirteen, `19 or more whole digits`, `leading zero`,
    /// and `one fraction digit` or `two fraction digits` when it has some;
    /// `fullwidth digit` when it holds one; and its fault, if any.
    static func labels(of field: TimeFieldGen.Field) -> [String] {
        let fault = field.fault.map { ["fault \($0)"] } ?? []
        let fullwidth = field.text.unicodeScalars.contains { scalar in
            (TimeFieldGen.fullwidthZero.value..<TimeFieldGen.fullwidthZero.value + digitCount).contains(scalar.value)
        }
        let digits = fault + (fullwidth ? ["fullwidth digit"] : [])
        guard let reading = DecimalHundredths.reading(of: field.text) else {
            return ["another shape"] + digits
        }
        let kind = reading.wholeDigits <= DecimalHundredths.wholeDigitBound ? "within the bound" : "past the bound"
        let length = switch reading.wholeDigits {
        case DecimalHundredths.wholeDigitBound:
            ["twelve whole digits"]

        case DecimalHundredths.wholeDigitBound + 1:
            ["thirteen whole digits"]

        case intDigits...:
            ["19 or more whole digits"]

        default:
            [String]()
        }
        let zero = reading.wholeDigits > 1 && field.text.hasPrefix("0") ? ["leading zero"] : []
        let fraction = switch reading.fractionDigits {
        case 0:
            [String]()

        case 1:
            ["one fraction digit"]

        default:
            ["two fraction digits"]
        }
        return [kind] + length + zero + fraction + digits
    }

    @Test("time fields reach each class around the digit bound, each fault, and other shapes")
    func fields() throws {
        var random = Self.seeded
        var counts: [String: Int] = [:]
        for _ in 0..<Self.draws {
            for label in Self.labels(of: try TimeFieldGen.field.run(using: &random, limit: Self.attempts)) {
                counts[label, default: 0] += 1
            }
        }

        #expect(
            counts == [
                "19 or more whole digits": 28,
                "another shape": 657,
                "fault arabicIndicDigit": 50,
                "fault combiningMark": 52,
                "fault emptyWhole": 62,
                "fault fullwidthDigit": 44,
                "fault insertedPoint": 54,
                "fault insertedSpace": 46,
                "fault missingUnit": 59,
                "fault prependScalar": 47,
                "fault signed": 59,
                "fault wrongUnit": 48,
                "fullwidth digit": 44,
                "leading zero": 33,
                "one fraction digit": 70,
                "past the bound": 135,
                "thirteen whole digits": 54,
                "twelve whole digits": 42,
                "two fraction digits": 79,
                "within the bound": 208
            ]
        )
    }
}
