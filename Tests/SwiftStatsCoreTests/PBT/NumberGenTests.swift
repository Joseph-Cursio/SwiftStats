import PropertyBased
import Testing

/// What the number generators draw (design D14): from a fixed seed, a
/// thousand draws reach each class a property's laws depend on an exact
/// number of times (zeros, subnormals, fractions, whole values within and
/// past what an `Int` holds, values Swift prints with an exponent, NaN and
/// the infinities, and `Int`'s limits), so a generator that stops reaching
/// one fails here, deterministically, rather than leaving a random
/// property to pass without checking it. The counts hold under this
/// engine's generator code and this standard library; a change to either
/// redraws them.
@Suite("Number generators")
struct NumberGenTests {
    /// The draws each meta-test makes.
    static let draws = 1_000
    /// The attempts allowed per draw: the generators never reject a value,
    /// so one is enough, and a filter added later fails here instead of
    /// hanging.
    static let attempts = 1
    /// The fixed seed every meta-test draws from.
    static let seeded = Xoshiro(seed: (1, 2, 3, 4))

    /// The classes `value` falls in: exactly one of NaN, infinite, zero,
    /// subnormal, fraction, whole within an `Int` and whole past one; and
    /// also negative, and printed with an exponent, when it is.
    static func labels(of value: Double) -> [String] {
        let kind = if value.isNaN {
            "nan"
        } else if value.isInfinite {
            "infinite"
        } else if value == 0 {
            "zero"
        } else if value.isSubnormal {
            "subnormal"
        } else if value.rounded() != value {
            "fraction"
        } else if Int(exactly: value) == nil {
            "whole past Int"
        } else {
            "whole within Int"
        }
        let negative = value.sign == .minus && value.isNaN == false ? ["negative"] : []
        let exponent = value.isFinite && value.description.contains("e") ? ["exponent form"] : []
        return [kind] + negative + exponent
    }

    /// The classes `value` falls in: exactly one of `Int`'s limits, small
    /// (within `NumberGen.smallIntBound` of zero) and large; and also
    /// negative, and zero, when it is.
    static func labels(of value: Int) -> [String] {
        let kind = if value == .min || value == .max {
            "limit"
        } else if (-NumberGen.smallIntBound...NumberGen.smallIntBound).contains(value) {
            "small"
        } else {
            "large"
        }
        let sign = value < 0 ? ["negative"] : value == 0 ? ["zero"] : []
        return [kind] + sign
    }

    /// How often each label of `labels` comes up over `draws` draws from
    /// `generator`, starting from `seeded`.
    static func counts<Value>(
        _ generator: Generator<Value, some Sequence>,
        labels: (Value) -> [String]
    ) throws -> [String: Int] {
        var random = seeded
        var counts: [String: Int] = [:]
        for _ in 0..<draws {
            for label in labels(try generator.run(using: &random, limit: attempts)) {
                counts[label, default: 0] += 1
            }
        }
        return counts
    }

    @Test("finite doubles reach every finite class, and never NaN or an infinity")
    func finiteDoubles() throws {
        let counts = try Self.counts(NumberGen.finiteDouble, labels: Self.labels(of:))

        #expect(
            counts == [
                "exponent form": 760,
                "fraction": 437,
                "negative": 471,
                "subnormal": 4,
                "whole past Int": 250,
                "whole within Int": 304,
                "zero": 5
            ]
        )
    }

    @Test("any double reaches every class, NaN and the infinities included")
    func anyDoubles() throws {
        let counts = try Self.counts(NumberGen.anyDouble, labels: Self.labels(of:))

        #expect(
            counts == [
                "exponent form": 696,
                "fraction": 424,
                "infinite": 33,
                "nan": 48,
                "negative": 432,
                "subnormal": 9,
                "whole past Int": 236,
                "whole within Int": 248,
                "zero": 2
            ]
        )
    }

    @Test("integers reach the limits, small and large values, both signs and zero")
    func integers() throws {
        let counts = try Self.counts(NumberGen.int, labels: Self.labels(of:))

        #expect(counts == ["large": 451, "limit": 54, "negative": 506, "small": 495, "zero": 33])
    }
}
