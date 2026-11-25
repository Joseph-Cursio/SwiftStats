//
//  PercentLimit.swift
//  SwiftStatsCore
//
//  Whether a count is at least a configured percent of another, compared
//  exactly (M7, design §8.1's `support × 100 ≥ confidence × min(changes)`):
//  the limit is the decimal its configuration wrote, the shortest one
//  reading back as its `Double` (as reports print it), not the binary
//  value nearest it, so a share equal to a limit such as 64.4 reaches it.
//  The share's decimal digits come from long division in integers, one at
//  a time, against the limit's.
//

/// An exact comparison of a share with a percent limit.
enum PercentLimit {
    /// One percent's whole.
    private static let wholePercent = 100
    /// The decimal base.
    private static let base = 10

    /// Whether `part` is at least `limit` percent of `whole`: `part × 100
    /// ≥ limit × whole`, with `limit` read as the shortest decimal giving
    /// its `Double`. Any part reaches a limit of zero or a `whole` of
    /// zero, and no negative part reaches anything; a limit that isn't a
    /// plain decimal, or counts too large for integers, compare in
    /// floating point.
    static func reaches(_ part: Int, of whole: Int, limit: Double) -> Bool {
        guard part >= 0 else {
            return false
        }
        guard whole > 0, limit > 0 else {
            return true
        }
        let approximate = Double(part) * Double(wholePercent) >= limit * Double(whole)
        let text = MarkdownNumber.exact(limit)
        let point = text.firstIndex(of: ".") ?? text.endIndex
        let fraction = text[point...].dropFirst()
        let digits = fraction.compactMap(\.wholeNumberValue)
        guard digits.count == fraction.count, let integral = Int(text[..<point]) else {
            return approximate
        }
        let (scaled, overflow) = part.multipliedReportingOverflow(by: wholePercent)
        guard overflow == false else {
            return approximate
        }
        var quotient = scaled / whole
        var remainder = scaled % whole
        if quotient != integral {
            return quotient > integral
        }
        for digit in digits {
            let (next, carried) = remainder.multipliedReportingOverflow(by: base)
            guard carried == false else {
                return approximate
            }
            quotient = next / whole
            remainder = next % whole
            if quotient != digit {
                return quotient > digit
            }
        }
        return true
    }
}
