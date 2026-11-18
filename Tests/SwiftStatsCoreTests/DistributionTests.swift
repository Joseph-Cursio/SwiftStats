@testable import SwiftStatsCore
import Testing

/// Nearest-rank distributions (PRD §7.2, §9).
@Suite("Distribution")
struct DistributionTests {
    @Test("nearest-rank median and 90th percentile")
    func nearestRank() {
        let distribution = Distribution(Array((1...10).reversed()))

        #expect(distribution.count == 10)
        #expect(distribution.total == 55)
        #expect(distribution.min == 1)
        #expect(distribution.median == 5)
        #expect(distribution.p90 == 9)
        #expect(distribution.max == 10)
    }

    @Test("one value, and none")
    func edges() {
        #expect(Distribution([7]).total == 7)
        #expect(Distribution([7]).median == 7)
        #expect(Distribution([7]).p90 == 7)
        #expect(Distribution([]).total == 0)
        #expect(Distribution([]).min == nil)
        #expect(Distribution([]).median == nil)
        #expect(Distribution([]).max == nil)
    }
}
