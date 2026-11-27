import Foundation
import Testing

/// How many inputs a property draws and how long it may take (design D4,
/// D5): `SWIFTSTATS_PBT_SCALE` multiplies every base count, reads as 1 when
/// unset, not a whole number or below 1, and is bounded above, even past
/// what an `Int` holds; the time limit is a minute per unit of scale and
/// never less than a minute.
@Suite("Property test budget")
struct PBTBudgetTests {
    @Test(
        "an unset, unreadable or non-positive scale reads as 1",
        arguments: [
            [:],
            ["SWIFTSTATS_PBT_SCALE": ""],
            ["SWIFTSTATS_PBT_SCALE": "lots"],
            ["SWIFTSTATS_PBT_SCALE": "0"],
            ["SWIFTSTATS_PBT_SCALE": "-5"],
            ["SWIFTSTATS_PBT_SCALE": "-99999999999999999999"],
            ["SWIFTSTATS_PBT_SCALE": "+"],
            ["SWIFTSTATS_PBT_SCALE": "2.5"],
            ["SWIFTSTATS_PBT_SCALE": " 10"],
            ["OTHER_SCALE": "10"]
        ]
    )
    func defaultScale(environment: [String: String]) {
        #expect(PBTBudget.scale(from: environment) == 1)
    }

    @Test("a whole-number scale multiplies every base count")
    func multiplies() {
        let scale = PBTBudget.scale(from: ["SWIFTSTATS_PBT_SCALE": "10"])

        #expect(scale == 10)
        #expect(PBTBudget.runs(100, scale: scale) == 1_000)
        #expect(PBTBudget.runs(25, scale: scale) == 250)
        #expect(PBTBudget.runs(300, scale: 1) == 300)
    }

    @Test("a scale past the bound reads as the bound")
    func bounded() {
        #expect(PBTBudget.scale(from: ["SWIFTSTATS_PBT_SCALE": "10000"]) == 10_000)
        #expect(PBTBudget.scale(from: ["SWIFTSTATS_PBT_SCALE": "10001"]) == PBTBudget.maximumScale)
        #expect(PBTBudget.scale(from: ["SWIFTSTATS_PBT_SCALE": "\(Int.max)"]) == PBTBudget.maximumScale)
        #expect(PBTBudget.scale(from: ["SWIFTSTATS_PBT_SCALE": "99999999999999999999"]) == PBTBudget.maximumScale)
        #expect(PBTBudget.scale(from: ["SWIFTSTATS_PBT_SCALE": "+99999999999999999999"]) == PBTBudget.maximumScale)
    }

    @Test("a run count that would overflow saturates")
    func saturates() {
        #expect(PBTBudget.runs(Int.max, scale: 2) == Int.max)
        #expect(PBTBudget.runs(Int.max / 2, scale: 2) == Int.max - 1)
    }

    @Test(
        "the time limit is a minute per unit of scale, and never less than a minute",
        arguments: [
            (0, Duration.seconds(60)),
            (1, Duration.seconds(60)),
            (10, Duration.seconds(600)),
            (100, Duration.seconds(6_000)),
            (10_000, Duration.seconds(600_000))
        ]
    )
    func timeLimit(scale: Int, limit: Duration) {
        let trait: TimeLimitTrait = .timeLimit(PBTBudget.timeLimit(scale: scale))

        #expect(trait.timeLimit == limit)
    }

    @Test("this process's budget is what its own environment reads")
    func processBudget() {
        let scale = PBTBudget.scale(from: ProcessInfo.processInfo.environment)
        let trait: TimeLimitTrait = .timeLimit(PBTBudget.timeLimit)

        #expect(PBTBudget.scale == scale)
        #expect(PBTBudget.runs(100) == 100 * scale)
        #expect(trait.timeLimit == .seconds(60 * scale))
    }
}
