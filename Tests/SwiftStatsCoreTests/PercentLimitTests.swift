//
//  PercentLimitTests.swift
//  SwiftStatsCoreTests
//
//  The exact share-against-percent comparison (M7, design §8.1): a limit
//  read as the decimal it was written as, equal shares reaching it,
//  repeating shares compared digit by digit, the zero and negative edges,
//  and the floating-point fallback for counts too large for integers.
//

@testable import SwiftStatsCore
import Testing

/// The exact percent comparison.
@Suite("Percent limit")
struct PercentLimitTests {
    @Test("a share equal to a decimal limit reaches it, and the next decimal up doesn't")
    func equalShares() {
        #expect(PercentLimit.reaches(161, of: 250, limit: 64.4))
        #expect(PercentLimit.reaches(161, of: 250, limit: 64.4000001) == false)
        #expect(PercentLimit.reaches(7, of: 625, limit: 1.12))
        #expect(PercentLimit.reaches(3, of: 6, limit: 50))
        #expect(PercentLimit.reaches(3, of: 6, limit: 50.5) == false)
        #expect(PercentLimit.reaches(6, of: 6, limit: 100))
        #expect(PercentLimit.reaches(5, of: 6, limit: 100) == false)
        #expect(PercentLimit.reaches(1, of: 100_000_000, limit: 0.000001))
        #expect(PercentLimit.reaches(1, of: 100_000_001, limit: 0.000001) == false)
    }

    @Test("a repeating share compares digit by digit with every digit the limit writes")
    func repeatingShares() {
        #expect(PercentLimit.reaches(1, of: 3, limit: 33.33333))
        #expect(PercentLimit.reaches(1, of: 3, limit: 100.0 / 3) == false)
        #expect(PercentLimit.reaches(2, of: 3, limit: 66.66666666666666))
        #expect(PercentLimit.reaches(2, of: 3, limit: 66.67) == false)
    }

    @Test("a limit of zero and a whole of zero are reached by any part, and a negative part reaches nothing")
    func edges() {
        #expect(PercentLimit.reaches(0, of: 5, limit: 0))
        #expect(PercentLimit.reaches(0, of: 0, limit: 50))
        #expect(PercentLimit.reaches(0, of: 5, limit: 0.1) == false)
        #expect(PercentLimit.reaches(-1, of: 5, limit: 0) == false)
    }

    @Test("counts too large for integers compare in floating point")
    func fallback() {
        #expect(PercentLimit.reaches(Int.max, of: Int.max, limit: 100))
        #expect(PercentLimit.reaches(Int.max / 2, of: Int.max, limit: 60) == false)
    }
}
